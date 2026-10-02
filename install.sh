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
    alacritty                        # default terminal ($terminal in i3/config)
    chromium                         # browser that follows the system colour scheme
    mise nix                         # package / language managers

    # No display manager: the X server is started per session with `startx`
    # (i3-wm does not depend on either of these). See AGENTS.md, "Starting i3".
    xorg-server                     # the X server itself
    xorg-xinit                      # startx / xinit
    xorg-xrandr                     # monitor size, set by bin/x11-monitor
    xorg-xauth                      # X authentication (ly and startx)
    ly                              # display manager; runs i3 (see AGENTS.md)
)

# What the config calls at runtime.
PKGS+=(
    jq                               # x11-ws-app
    eza zoxide fzf bat               # shell integrations (shell/); bat previews fzf's ff
    bash-completion
    maim xclip xcolor                # screenshots, clipboard, colour picker
    feh                              # wallpaper, set by bin/x11-wallpaper
    numlockx
    libnotify                        # notify-send, for convenience in scripts
    curl                             # fetches the seeded wallpaper

    # System-wide dark mode. There is no desktop here, so dconf is the system
    # theme: GTK4/libadwaita read it directly, and the portal reads it for
    # everything sandboxed (see setup_dark_theme and xdg-portal.conf).
    gsettings-desktop-schemas        # without this the color-scheme key does not exist
    dconf                            # the store gsettings writes to
    xdg-desktop-portal               # org.freedesktop.portal.Settings
    xdg-desktop-portal-gtk           # its backend; the one that implements Settings
    adwaita-icon-theme               # provides Adwaita-dark
    pipewire-pulse                   # pactl, used by x11-volume
    ttf-jetbrains-mono-nerd          # font used by the terminals / i3 / bar
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

# Wallpapers live in ~/.config/wallpapers, which is yours: drop anything in and
# bin/x11-wallpaper picks from it at random. One image is seeded on first run so
# the desktop is not bare, and an existing one is never overwritten.
WALLPAPER_URL="https://raw.githubusercontent.com/r3b1s/wallpapers/refs/heads/main/red/bleach_0.png"
WALLPAPER_FILE="bleach_0.png"

setup_wallpapers() {
    local dir="$1" dest="$1/$WALLPAPER_FILE"

    if [ "$dry" = 1 ]; then
        echo "+ ensure $dir exists"
        [ -e "$dest" ] || echo "+ download $WALLPAPER_FILE into $dir"
        return
    fi

    [ -d "$dir" ] || { run mkdir -p "$dir"; echo "created $dir"; }

    if [ -e "$dest" ]; then
        echo "wallpaper: $WALLPAPER_FILE already present"
        return
    fi

    say "Fetching a wallpaper"
    # Download to a temporary name and move it into place, so an interrupted or
    # failed fetch can never leave a truncated image that --bg-fill would choke on.
    local tmp="$dir/.$WALLPAPER_FILE.part.$$"
    local ok=0
    if command -v curl >/dev/null; then
        curl -fsSL --max-time 120 -o "$tmp" "$WALLPAPER_URL" && ok=1
    elif command -v wget >/dev/null; then
        wget -q -T 120 -O "$tmp" "$WALLPAPER_URL" && ok=1
    else
        warn "neither curl nor wget is available; not fetching a wallpaper"
    fi

    if [ "$ok" = 1 ] && [ -s "$tmp" ]; then
        mv "$tmp" "$dest"
        echo "wallpaper: saved $dest ($(du -h "$dest" | cut -f1))"
    else
        rm -f "$tmp"
        warn "could not download $WALLPAPER_URL (offline?)"
        warn "the desktop will stay unset; drop any image into $dir by hand"
    fi
}

# ly's pinkrot theme.
#
# ly reads exactly one config file, /etc/ly/config.ini - the path is compiled in,
# and there is no ~/.config/ly/config.ini fallback - so the theme has to be merged
# into that file. Merging rather than replacing keeps every setting we do not care
# about at its packaged value, and keeps working across upgrades that add keys.
#
# The original is kept once as config.ini.athena-orig; re-running restores from it
# first, so the merge is idempotent instead of accumulating.
install_ly_theme() {
    # LY_CONFIG exists so this can be pointed elsewhere for testing; normal use
    # is the system path.
    local target="${LY_CONFIG:-/etc/ly/config.ini}"
    local src="$REPO/ly/pinkrot.ini"
    local pristine="$target.athena-orig"

    [ -r "$src" ] || return 0
    if [ ! -f "$target" ]; then
        warn "$target not found; skipping the ly theme (is the 'ly' package installed?)"
        return
    fi

    say "Applying the pinkrot ly theme"
    local merged
    merged=$(mktemp)

    if [ -f "$pristine" ]; then
        cat "$pristine" > "$merged"
    else
        cat "$target" > "$merged"
        run $SUDO cp -a "$target" "$pristine"
        echo "saved pristine copy as $pristine"
    fi

    # Replace each key we theme in place; append any key the packaged file lacks.
    # Operating on the pristine copy means re-running never stacks duplicates.
    awk -v overlay="$src" '
        function keyof(s) { k = s; sub(/=.*/, "", k); gsub(/[[:space:]]/, "", k); return k }
        function valof(s) {
            v = substr(s, index(s, "=") + 1)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            return v
        }
        BEGIN {
            while ((getline line < overlay) > 0) {
                if (line ~ /^[a-z_]+[[:space:]]*=/) {
                    k = keyof(line)
                    if (!(k in val)) order[++n] = k
                    val[k] = valof(line)
                }
            }
            close(overlay)
        }
        {
            if ($0 ~ /^[a-z_]+[[:space:]]*=/) {
                k = keyof($0)
                if (k in val) { print k " = " val[k]; done_[k] = 1; next }
            }
            print
        }
        END {
            for (i = 1; i <= n; i++)
                if (!(order[i] in done_)) print order[i] " = " val[order[i]]
        }
    ' "$merged" > "$merged.new" && mv "$merged.new" "$merged"

    if cmp -s "$merged" "$target"; then
        echo "ly theme: already up to date"
    else
        run $SUDO install -m 644 "$merged" "$target"
        echo "ly theme: written to $target"
    fi
    rm -f "$merged"

    # Not worth a reboot request: log out of the session and back in.
    echo "ly theme: log out and back in to see it"
}

# Make the session read as dark.
#
# Two halves, and both are needed:
#   * dconf. color-scheme is what GTK4 and libadwaita read directly; gtk-theme
#     is what GTK3 reads, since GTK3 has no notion of color-scheme.
#   * the portal. Sandboxed apps and Qt6 (qutebrowser) ask
#     org.freedesktop.portal.Settings instead of reading dconf, and that only
#     works if the backend is running - see xdg-portal.conf for why it needs
#     XDG_CURRENT_DESKTOP=GNOME.
#
# Best run from inside the desktop session, since both halves need the session
# bus. Run from a bare tty and it explains what to do instead.
setup_dark_theme() {
    command -v gsettings >/dev/null || { warn "gsettings not installed; skipping dark mode"; return; }

    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        warn "no session bus: cannot set the system colour scheme from here."
        warn "Run these inside the i3 session to finish:"
        warn "  gsettings set org.gnome.desktop.interface color-scheme prefer-dark"
        warn "  gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark"
        warn "  systemctl --user enable --now xdg-desktop-portal.service xdg-desktop-portal-gtk.service"
        return
    fi

    say "Setting the system colour scheme to dark"
    run gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    run gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark

    if command -v systemctl >/dev/null; then
        # The gtk portal backend is gated on XDG_CURRENT_DESKTOP; i3/config sets
        # it for everything i3 spawns, this covers the user services.
        XDG_CURRENT_DESKTOP=GNOME run dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP
        run systemctl --user enable --now xdg-desktop-portal.service xdg-desktop-portal-gtk.service \
            || warn "could not start the xdg-desktop-portal user services"
    fi
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

    setup_wallpapers "$cfg/wallpapers"

    local pair
    for pair in \
        "qutebrowser/config.py:qutebrowser/config.py" \
        "qutebrowser/pinkrot.py:qutebrowser/pinkrot.py" \
        "btop/btop.conf:btop/btop.conf" \
        "btop/themes/pinkrot.theme:btop/themes/pinkrot.theme" \
        "nvim/colors/pinkrot.lua:nvim/colors/pinkrot.lua" \
        "starship/starship.toml:starship.toml"
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
    install_ly_theme
    enable_services
    enable_nix
    setup_dark_theme
fi
[ "$do_links" = 1 ] && install_links

echo
if [ "$FAILED" = 1 ]; then
    warn "finished with errors: qutebrowser-git was not installed (see above)"
    exit 1
fi
echo "Done. Log into the i3 session, or reload with \$mod+Shift+Ctrl+Mod1+c (i3-msg reload)."
