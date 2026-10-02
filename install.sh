#!/usr/bin/env bash
# athena-dots installer for AthenaOS (Arch-based).
#
#   1. installs any missing packages (pacman; sudo is used when not root)
#   2. enables the guest-agent services
#   3. symlinks the dots into ~/.config and ~/.local/bin
#   4. validates the i3 config
#
# Safe to re-run: installed packages are skipped, existing non-symlink targets
# are backed up, existing symlinks are replaced.
#
# Usage: ./install.sh [--packages-only | --links-only] [-n|--dry-run]
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

do_packages=1
do_links=1
dry=0
for arg in "$@"; do
    case "$arg" in
        --packages-only) do_links=0 ;;
        --links-only)    do_packages=0 ;;
        -n|--dry-run)    dry=1 ;;
        -h|--help)       sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

# ── packages ──────────────────────────────────────────────────────────────

# Core stack (see AGENTS.md).
PKGS=(
    i3-wm i3status-rust autotiling   # window manager, bar, auto-split
    rofi dunst kitty neovim btop     # launcher, notifications, terminal, editor, monitor
    alacritty                        # secondary terminal; kitty is the default
    mise nix                         # package / language managers

    # No display manager: the X server is started per session with `startx`
    # (i3-wm does not depend on either of these). See AGENTS.md, "Starting i3".
    xorg-server                     # the X server itself
    xorg-xinit                      # startx / xinit
    xorg-xrandr                     # monitor size, set by bin/x11-monitor
    xorg-xauth                      # X authentication (ly and startx)
    xorg-xsetroot                   # unset the wallpaper, used by bin/x11-wallpaper
    ly                              # display manager; runs i3 (see AGENTS.md)
)

# What the config calls at runtime.
PKGS+=(
    jq                               # x11-ws-app
    eza zoxide fzf bat               # shell integrations (shell/); bat previews fzf's ff
    bash-completion
    xdotool                          # x11-terminal-here
    maim xclip xcolor                # screenshots, clipboard, colour picker
    feh                              # wallpaper, set by bin/x11-wallpaper
    numlockx
    libnotify                        # notify-send, for convenience in scripts
    pipewire-pulse                   # pactl, used by x11-volume
    ttf-jetbrains-mono-nerd          # font used by kitty / i3 / bar
    starship                         # shell prompt (config in starship/)
)

# Session helpers and VM guest integration.
PKGS+=(
    polkit-gnome                     # polkit authentication agent
    network-manager-applet           # nm-applet
    spice-vdagent                    # shared clipboard + display resize
    qemu-guest-agent                 # host <-> guest control channel
)

# Set when something required could not be installed; reported at the end.
FAILED=0

install_packages() {
    command -v pacman >/dev/null || { warn "pacman not found; skipping package install"; return; }

    say "Checking packages"
    local missing=() p
    for p in "${PKGS[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        echo "all packages already installed"
        return
    fi

    say "Installing: ${missing[*]}"
    run $SUDO pacman -S --needed --noconfirm "${missing[@]}"
}

# qutebrowser comes from chaotic-aur ONLY (qutebrowser-git, per AGENTS.md); there
# is deliberately no fallback to extra's `qutebrowser`. The two conflict, so a
# plain `qutebrowser` already on the system is removed first.
install_qutebrowser() {
    command -v pacman >/dev/null || return 0
    pacman -Qq qutebrowser-git >/dev/null 2>&1 && return 0

    say "Checking qutebrowser-git (chaotic-aur)"
    if ! pacman -Si chaotic-aur/qutebrowser-git >/dev/null 2>&1; then
        warn "chaotic-aur/qutebrowser-git is unavailable (is chaotic-aur enabled and synced?)."
        warn "Not installing qutebrowser from any other repo. Fix chaotic-aur and re-run."
        FAILED=1
        return 0
    fi
    if pacman -Qq qutebrowser >/dev/null 2>&1; then
        warn "replacing non-chaotic qutebrowser with qutebrowser-git"
        run $SUDO pacman -Rns --noconfirm qutebrowser
    fi
    run $SUDO pacman -S --needed --noconfirm chaotic-aur/qutebrowser-git
}

# nix is for project-specific environments only: the daemon is enabled so
# `nix-shell` / `nix develop` work for the user, and nothing else is configured
# (no channels, no flakes settings).
enable_nix() {
    pacman -Qq nix >/dev/null 2>&1 || return 0
    command -v systemctl >/dev/null || return 0

    say "Enabling nix-daemon"
    run $SUDO systemctl enable --now nix-daemon.socket \
        || warn "could not enable nix-daemon.socket"

    # Multi-user nix: membership of nix-users (when the package ships it) is
    # what lets a normal user talk to the daemon. Applies at next login.
    local user="${SUDO_USER:-${USER:-}}"
    if [ -n "$user" ] && [ "$user" != root ] && getent group nix-users >/dev/null; then
        if ! id -nG "$user" | tr ' ' '\n' | grep -qx nix-users; then
            run $SUDO usermod -aG nix-users "$user"
            echo "added $user to nix-users (log out and back in for it to apply)"
        fi
    fi
}

enable_services() {
    command -v systemctl >/dev/null || return 0
    say "Enabling guest services"

    # ly is the display manager: `ly@.service` is a template, so the instance is
    # named for the tty it takes over. It Conflicts= getty@tty1, which systemd
    # resolves automatically.
    if pacman -Qq ly >/dev/null 2>&1; then
        run $SUDO systemctl enable ly@tty1.service \
            || warn "could not enable ly@tty1.service"
        if systemctl is-enabled --quiet "${DISPLAY_MANAGER:-lightdm}.service" 2>/dev/null; then
            warn "another display manager (${DISPLAY_MANAGER}) is enabled; disable it or ly will not start"
        fi
    fi
    # spice-vdagentd is socket-activated; qemu-guest-agent is started by udev
    # when the virtio channel appears, so it has nothing to enable.
    run $SUDO systemctl enable --now spice-vdagentd.socket \
        || warn "could not enable spice-vdagentd.socket"
}

# ── links ─────────────────────────────────────────────────────────────────

link() {
    local src="$1" dst="$2"
    run mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        local backup
        backup="$dst.bak.$(date +%s)"
        run mv "$dst" "$backup"
        echo "backed up $dst -> $backup"
    fi
    run ln -sfn "$src" "$dst"
    echo "linked $dst -> $src"
}

# Idempotent managed block in ~/.bashrc that loads shell/ (~/.config/shell).
# Everything else in .bashrc is left alone. Remove the block to undo.
install_bashrc_block() {
    local bashrc="$HOME/.bashrc"
    local open="# >>> athena-dots >>>"
    if [ -f "$bashrc" ] && grep -qF "$open" "$bashrc"; then
        echo "bashrc: athena-dots block already present"
    elif [ "$dry" = 1 ]; then
        echo "+ append athena-dots block to $bashrc"
    else
        touch "$bashrc"
        {
            echo
            echo "$open"
            # shellcheck disable=SC2016  # written literally: expands in .bashrc, not here
            echo '[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/shell/init.sh" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/init.sh"'
            echo "# <<< athena-dots <<<"
        } >> "$bashrc"
        echo "bashrc: appended athena-dots block"
    fi
    case "$(basename "${SHELL:-}")" in
        bash) ;;
        *) warn "login shell is ${SHELL:-unknown}, not bash; shell/ is only loaded by bash" ;;
    esac
}

# Whole directories are linked where the app never writes into its config dir.
# Where it does (qutebrowser, btop, nvim, starship's shared ~/.config) individual
# files are linked, so runtime state stays out of the repo.
install_links() {
    say "Linking dots"
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

    local d
    for d in i3 kitty alacritty rofi dunst i3status-rust shell; do
        link "$REPO/$d" "$cfg/$d"
    done

    # Wallpapers are yours, not this repo's: the folder is created if absent and
    # left otherwise, so dropping images in is all it takes.
    if [ "$dry" = 1 ]; then
        echo "+ ensure $cfg/wallpapers exists"
    elif [ ! -d "$cfg/wallpapers" ]; then
        run mkdir -p "$cfg/wallpapers"
        echo "created $cfg/wallpapers (add images to set a wallpaper)"
    else
        echo "wallpapers: $cfg/wallpapers left alone ($(find "$cfg/wallpapers" -maxdepth 1 -type f -not -name '.*' | wc -l) file(s))"
    fi

    local pair
    for pair in \
        "qutebrowser/config.py:qutebrowser/config.py" \
        "qutebrowser/pinkrot.py:qutebrowser/pinkrot.py" \
        "btop/btop.conf:btop/btop.conf" \
        "btop/themes/pinkrot.theme:btop/themes/pinkrot.theme" \
        "nvim/colors/pinkrot.lua:nvim/colors/pinkrot.lua" \
        "starship/starship.toml:starship.toml" \
        "ly/config.ini:ly/config.ini"
    do
        link "$REPO/${pair%%:*}" "$cfg/${pair#*:}"
    done

    # The nvim plugin spec only means something to a LazyVim setup.
    if [ -d "$cfg/nvim/lua/plugins" ]; then
        link "$REPO/nvim/lua/plugins/pinkrot-theme.lua" "$cfg/nvim/lua/plugins/pinkrot-theme.lua"
    else
        echo "no LazyVim plugins dir; select the colorscheme with :colorscheme pinkrot"
    fi

    install_bashrc_block

    local script
    for script in "$REPO"/bin/*; do
        link "$script" "$HOME/.local/bin/$(basename "$script")"
    done

    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) warn "$HOME/.local/bin is not on PATH; i3 binds use it directly but rofi/shells will not" ;;
    esac

    if [ "$dry" = 0 ] && command -v i3 >/dev/null; then
        say "Validating i3 config"
        i3 -C -c "$cfg/i3/config" && echo "i3 config OK"
    fi
}

if [ "$do_packages" = 1 ]; then
    install_packages
    install_qutebrowser
    enable_services
    enable_nix
fi
[ "$do_links" = 1 ] && install_links

echo
if [ "$FAILED" = 1 ]; then
    warn "finished with errors: qutebrowser-git was not installed (see above)"
    exit 1
fi
echo "Done. Log into the i3 session, or reload with \$mod+Shift+Ctrl+Mod1+c (i3-msg reload)."
