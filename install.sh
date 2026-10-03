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
    firefox                          # second browser; themed and preconfigured by policy
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
    libnotify                        # dunstify links against it (dunst's optdep); the OSDs use it
    curl                             # fetches the seeded wallpaper

    # System-wide dark mode. There is no desktop here, so dconf is the system
    # theme: GTK4/libadwaita read it directly, and the portal reads it for
    # everything sandboxed (see setup_dark_theme).
    gsettings-desktop-schemas        # without this the color-scheme key does not exist
    dconf                            # the store gsettings writes to
    xdg-desktop-portal               # org.freedesktop.portal.Settings
    xdg-desktop-portal-gtk           # its backend; the one that implements Settings
    adwaita-icon-theme               # the base icon theme pinkrot inherits from
    pipewire-pulse                   # pactl, used by x11-volume
    ttf-jetbrains-mono-nerd          # font used by the terminals / i3 / bar
    starship                         # shell prompt (config in starship/)
    tmux                             # terminal multiplexer (config in tmux/)
    rclone                           # cloud storage sync
)

# Extra shells and desktop apps (TODO.md). Bash stays the default login shell:
# nothing here calls chsh; fish/xonsh are launched explicitly when wanted.
PKGS+=(
    fish                             # vanilla fish from extra, not the Athena flavour
    xonsh                            # extra/xonsh
    obsidian                         # notes (extra/obsidian)
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

# Neovim is a LazyVim tree in this repo (init.lua, lua/config, lua/plugins,
# colors). install_links() calls link_nvim_tree() to link each file
# individually, so runtime state (lazyvim.json, lazy-lock.json, :Mason, spell,
# shada) stays out of the repo. setup_nvim() reconciles the reverse: if the
# user already had a LazyVim setup, any init.lua managed block from the old
# colourscheme-only days is removed now that init.lua itself is linked.
link_nvim_tree() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local rel
    ( cd "$REPO/nvim" && find . -type f | sed 's|^\./||' ) | while IFS= read -r rel; do
        link "$REPO/nvim/$rel" "$cfg/nvim/$rel"
    done
}
setup_nvim() {
    local init="${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua"
    local open="-- >>> athena-dots >>>"

    # Retire the old managed block: init.lua is a symlink into the repo now,
    # so a leftover block means the link was replaced by a real file.
    if [ -f "$init" ] && [ ! -L "$init" ] && grep -qF -e "$open" "$init"; then
        if [ "$dry" = 1 ]; then
            echo "+ remove the managed colourscheme block from $init (init.lua is linked now)"
        else
            local tmp
            tmp="$(mktemp)" || return 0
            awk -v open="$open" -v close="-- <<< athena-dots <<<" '
                $0 == open { skip = 1; prev_blank = 0; next }
                skip && $0 == close { skip = 0; next }
                skip { next }
                { print }
            ' "$init" > "$tmp" && run mv "$tmp" "$init" && echo "nvim: retired the managed colourscheme block in $init"
            rm -f "$tmp"
        fi
    fi
}

# Firefox: the Flame theme and Vimium, via enterprise policy.
#
# /etc/firefox/policies/policies.json is the documented system-wide location on
# Linux (the install-directory alternative under /usr/lib/firefox would be
# clobbered by package upgrades). The policy installs both add-ons from AMO at
# startup, so this needs network on first run, and activates the theme through
# the pref its manifest declares.
#
# Vimium's options cannot be installed this way: its settings live in the
# extension's own browser storage, the only import path is the Restore control
# on chrome-extension://<id>/options.html, and no policy can write extension
# storage. Load firefox/vimium-options.json from the repo there once by hand.
# qutebrowser gets the same settings by config in qutebrowser/vimium.py, which
# needs no such step.
setup_firefox() {
    local target="/etc/firefox/policies/policies.json"
    local src="$REPO/firefox/policies.json"

    if [ -r "$src" ] && command -v pacman >/dev/null && pacman -Qq firefox >/dev/null 2>&1; then
        say "Installing the Firefox policy"
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $target"
        elif [ -f "$target" ] && cmp -s "$src" "$target"; then
            echo "firefox policy: already up to date"
        else
            [ -f "$target" ] && run $SUDO cp -a "$target" "$target.bak.$(date +%s)"
            run $SUDO install -D -m 644 "$src" "$target"
            echo "firefox policy: $target (Flame theme, Vimium from AMO, Brave default search)"
        fi
    fi

}

# Chromium: Brave default search via enterprise policy. The built-in "Rose"
# theme cannot be set by policy (no theme-selection policy exists), so it is
# seeded into the user profile's Preferences instead — see seed_chromium_rose()
# below. Policy files live in /etc/chromium/policies/managed/ and apply on
# next launch; managed (not recommended/) so the user can still change search
# back in settings if wanted... actually managed LOCKS it. That is the only
# level that sets a default engine: recommended/ merely suggests.
setup_chromium() {
    local src="$REPO/chromium/policies/managed/brave-search.json"
    local target="/etc/chromium/policies/managed/brave-search.json"

    if [ -r "$src" ] && command -v pacman >/dev/null && pacman -Qq chromium >/dev/null 2>&1; then
        say "Installing the Chromium policy"
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $target"
        elif [ -f "$target" ] && cmp -s "$src" "$target"; then
            echo "chromium policy: already up to date"
        else
            [ -f "$target" ] && run $SUDO cp -a "$target" "$target.bak.$(date +%s)"
            run $SUDO install -D -m 644 "$src" "$target"
            echo "chromium policy: $target (Brave default search)"
        fi
    fi

    seed_chromium_rose
}

# Seed the built-in "Rose" theme into the default Chromium profile. Chromium
# exposes no policy for theme selection; the theme choice lives in the
# profile's Preferences (browser.theme.color_scheme + extensions.theme). Rose
# is the built-in pink user-color theme. Only writes when no theme choice
# exists yet, so a user-picked theme is never overwritten. Takes effect on
# next Chromium launch.
seed_chromium_rose() {
    local prefs="${XDG_CONFIG_HOME:-$HOME/.config}/chromium/Default/Preferences"
    [ -r "$prefs" ] || return 0
    command -v python3 >/dev/null || return 0
    python3 - "$prefs" <<'EOF' || warn "could not seed the Chromium Rose theme"
import json, sys
p = sys.argv[1]
try:
    with open(p) as f:
        d = json.load(f)
except (OSError, ValueError) as e:
    print(f"chromium Rose theme: skipping ({e})")
    sys.exit(0)
theme = d.setdefault("browser", {}).setdefault("theme", {})
# color_scheme 2 = Rose (built-in pink); only seed when unset.
if "color_scheme" not in theme and "color_scheme2" not in theme:
    theme["color_scheme"] = 2
    with open(p, "w") as f:
        json.dump(d, f)
    print("chromium Rose theme: seeded into Default/Preferences")
else:
    print("chromium Rose theme: already chosen, leaving it alone")
EOF
}

# Set a key in an INI file, creating the file and its [Settings] section as
# needed. Used for the GTK settings files, which are plain INI and may already
# exist with the user's own keys.
ini_set() {
    local file="$1" key="$2" value="$3"
    [ "$dry" = 1 ] && { echo "+ set $key=$value in $file"; return; }
    mkdir -p "$(dirname "$file")"
    if [ ! -f "$file" ]; then
        printf '[Settings]\n%s=%s\n' "$key" "$value" > "$file"
        return
    fi
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "$file"
    elif grep -qE "^\[Settings\]" "$file"; then
        # insert directly after the [Settings] header, not at the end of the
        # file, so a later section cannot claim the key
        awk -v k="$key" -v v="$value" '
            { print }
            /^\[Settings\]/ && !done { print k "=" v; done = 1 }
        ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    else
        printf '\n[Settings]\n%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# GTK theme and icon theme.
#
# GTK does not read org.gnome.desktop.interface for either of these. It reads the
# XSETTINGS protocol, which a desktop session publishes via a settings daemon.
# There is none here, so the gsettings values that setup_dark_theme() writes are
# ignored by GTK and it falls back to Adwaita light and the hicolor icons.
# Confirmed on the VM with Gtk.IconTheme: nm-device-wired resolved to
# /usr/share/icons/hicolor/... however gsettings was set. GTK does read
# ~/.config/gtk-{3,4}.0/settings.ini directly, which fixes it, and is also what
# finally makes GTK3 apps dark.
#
# The icon theme is generated from the symbolic NetworkManager icons shipped by
# the package, recoloured to pinkrot, so no icon files live in this repo. Each
# one is written under both the plain and the "-symbolic" name: nm-applet asks
# for the plain name (it never references "-symbolic"), and that is what replaces
# its pastel hardware illustration in the i3bar tray with a pinkrot glyph.
PINKROT_FG="#f17e97"
PINKROT_ICON_SRC="${PINKROT_ICON_SRC:-/usr/share/icons/hicolor/scalable/apps}"

setup_gtk() {
    local icons="$HOME/.local/share/icons/pinkrot"
    local f base count=0

    if [ -d "$PINKROT_ICON_SRC" ]; then
        if [ "$dry" = 0 ]; then mkdir -p "$icons/scalable/apps"; fi
        for f in "$PINKROT_ICON_SRC"/nm-*-symbolic.svg; do
            [ -e "$f" ] || continue
            base=$(basename "$f" -symbolic.svg)
            count=$((count + 1))
            # Skip the work entirely under --dry-run: a redirection is performed
            # by the shell before run() is called, so it cannot be intercepted.
            [ "$dry" = 1 ] && continue
            sed -e "s/fill=\"#474747\"/fill=\"$PINKROT_FG\"/" \
                -e "s/fill=\"#bebebe\"/fill=\"$PINKROT_FG\"/" "$f" \
                > "$icons/scalable/apps/$base.svg"
            cp "$icons/scalable/apps/$base.svg" "$icons/scalable/apps/$base-symbolic.svg"
        done
        if [ "$dry" = 1 ]; then
            echo "+ write $icons/index.theme ($count icons)"
        else
            printf '[Icon Theme]\nName=pinkrot\nComment=NetworkManager icons recoloured for pinkrot\nInherits=Adwaita,hicolor\nDirectories=scalable/apps\n\n[scalable/apps]\nSize=16\nType=Scalable\n' > "$icons/index.theme"
            gtk-update-icon-cache -q -t -f "$icons" 2>/dev/null || true
            echo "icon theme: $count NetworkManager icons -> $icons"
        fi
    else
        warn "no $PINKROT_ICON_SRC; skipping the pinkrot icon theme"
    fi

    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local dir
    for dir in gtk-3.0 gtk-4.0; do
        # "Adwaita" plus prefer-dark, NOT "Adwaita-dark": there is no theme by
        # that name in GTK3, and naming one that does not exist makes GTK fall
        # back to *light* Adwaita without a word. Verified on the VM: the menu
        # background was #F6F5F4 with Adwaita-dark and #353535 with Adwaita +
        # gtk-application-prefer-dark-theme=1.
        ini_set "$cfg/$dir/settings.ini" gtk-theme-name Adwaita
        ini_set "$cfg/$dir/settings.ini" gtk-icon-theme-name pinkrot
        ini_set "$cfg/$dir/settings.ini" gtk-application-prefer-dark-theme 1
    done
    [ "$dry" = 1 ] || echo "gtk: Adwaita (dark), icon theme pinkrot ($cfg/gtk-{3,4}.0/settings.ini)"
}

# Make the session read as dark.
#
# Two halves, and neither is what GTK itself uses - GTK reads XSETTINGS, which
# nothing publishes here. See setup_gtk() for that; this is for everything else:
#   * dconf. color-scheme is what GTK4/libadwaita and Qt consult, and what a
#     desktop would normally republish over XSETTINGS.
#   * the portal. Sandboxed apps and Qt6 (qutebrowser) ask
#     org.freedesktop.portal.Settings instead of reading dconf, and that only
#     works if the backend is running, which needs XDG_CURRENT_DESKTOP to name a
#     desktop the backend is registered for: gtk.portal declares UseIn=gnome.
#     Check it with:
#       busctl --user call org.freedesktop.portal.Desktop \
#         /org/freedesktop/portal/desktop org.freedesktop.portal.Settings \
#         ReadOne ss org.gnome.desktop.interface color-scheme
#
# Best run from inside the desktop session, since both halves need the session
# bus. Run from a bare tty and it explains what to do instead.
setup_dark_theme() {
    command -v gsettings >/dev/null || { warn "gsettings not installed; skipping dark mode"; return; }

    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        warn "no session bus: cannot set the system colour scheme from here."
        warn "Run these inside the i3 session to finish:"
        warn "  gsettings set org.gnome.desktop.interface color-scheme prefer-dark"
        warn "  gsettings set org.gnome.desktop.interface gtk-theme Adwaita"
        warn "  systemctl --user enable --now xdg-desktop-portal.service xdg-desktop-portal-gtk.service"
        return
    fi

    say "Setting the system colour scheme to dark"
    run gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    run gsettings set org.gnome.desktop.interface gtk-theme Adwaita
    # GTK itself ignores this (see setup_gtk), but other consumers read it.
    run gsettings set org.gnome.desktop.interface icon-theme pinkrot

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

# Safe sshd config for the day it is ever enabled. Deliberately does NOT
# enable sshd: `systemctl is-enabled sshd` must stay disabled. Installs a
# drop-in (pubkey only, no passwords/interactive, no root) and the deploy key
# into ~/.ssh/authorized_keys, then validates with sshd -t.
setup_sshd() {
    local src="$REPO/ssh/sshd_config.d/10-athena-safe.conf"
    local target="/etc/ssh/sshd_config.d/10-athena-safe.conf"
    local key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGeIuM1WNYaQp75xua3Fh/DgPdFdEqGIVN748bbO5Sis athena0'

    if [ -r "$src" ]; then
        say "Installing the sshd hardening drop-in (service stays disabled)"
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $target"
        elif [ -f "$target" ] && cmp -s "$src" "$target"; then
            echo "sshd config: already up to date"
        else
            [ -f "$target" ] && run $SUDO cp -a "$target" "$target.bak.$(date +%s)"
            run $SUDO install -D -m 644 "$src" "$target"
            echo "sshd config: $target (pubkey only, no root)"
        fi
        if [ "$dry" = 0 ] && command -v sshd >/dev/null; then
            run $SUDO sshd -t && echo "sshd config OK"
        fi
    fi

    local auth="$HOME/.ssh/authorized_keys"
    if [ "$dry" = 1 ]; then
        echo "+ ensure the athena0 key is in $auth"
    else
        mkdir -p "$(dirname "$auth")"
        touch "$auth"
        chmod 700 "$(dirname "$auth")"
        chmod 600 "$auth"
        if grep -qF "$key" "$auth" 2>/dev/null; then
            echo "authorized_keys: athena0 key already present"
        else
            printf '%s\n' "$key" >> "$auth"
            echo "authorized_keys: added the athena0 key"
        fi
    fi

    # Never enable: a stray `systemctl enable sshd` would undo the intent.
    if command -v systemctl >/dev/null && systemctl is-enabled --quiet sshd 2>/dev/null; then
        warn "sshd.service is ENABLED; TODO.md says it must stay disabled (systemctl disable sshd)"
    fi
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

    for pair in \
        "qutebrowser/config.py:qutebrowser/config.py" \
        "qutebrowser/pinkrot.py:qutebrowser/pinkrot.py" \
        "qutebrowser/vimium.py:qutebrowser/vimium.py" \
        "qutebrowser/startpage.html:qutebrowser/startpage.html" \
        "btop/btop.conf:btop/btop.conf" \
        "btop/themes/pinkrot.theme:btop/themes/pinkrot.theme" \
        "tmux/tmux.conf:tmux/tmux.conf" \
        "fish/conf.d/vi_mode.fish:fish/conf.d/vi_mode.fish" \
        "fish/conf.d/svim.fish:fish/conf.d/svim.fish" \
        "xonsh/rc.xsh:xonsh/rc.xsh" \
        "starship/starship.toml:starship.toml"
    do
        link "$REPO/${pair%%:*}" "$cfg/${pair#*:}"
    done

    # Neovim is a LazyVim tree (init.lua + lua/config + colors). Individual
    # files are linked so runtime state (lazyvim.json, lazy-lock.json, :Mason,
    # spell, shada) stays out of the repo. setup_nvim() reconciles below.
    link_nvim_tree


    install_bashrc_block

    # ~/.xprofile is sourced by the session start-up (ly runs /etc/ly/setup.sh,
    # which reads it before exec'ing the session), so this is how XDG_CURRENT_DESKTOP
    # reaches everything i3 spawns. It lives in $HOME, not in ~/.config, hence the
    # separate link rather than one of the pair mappings above.
    link "$REPO/shell/xprofile" "$HOME/.xprofile"

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
    setup_gtk
    setup_firefox
    setup_chromium
    setup_sshd
    setup_nvim
fi
[ "$do_links" = 1 ] && install_links

echo
if [ "$FAILED" = 1 ]; then
    warn "finished with errors: qutebrowser-git was not installed (see above)"
    exit 1
fi
echo "Done. Log into the i3 session, or reload with \$mod+Shift+Ctrl+Mod1+c (i3-msg reload)."
