#!/usr/bin/env bash
# Install the dots for the ROOT user (/root). Opt-in: nothing else in this repo
# runs it. Run it yourself, as root:
#
#   sudo ./root/install.sh [-n|--dry-run]
#
# Files are COPIED, not symlinked. /root must never read files that a normal
# user can modify, so there is deliberately no link back into this repo; re-run
# the script after editing anything under root/.
#
#   shell/bash/appendrc    -> /root/.bashrc
#   shell/bash/inputrc     -> /root/.inputrc
#   starship/starship.toml -> /root/.config/starship.toml
#
# An existing, different file is backed up to <file>.bak.<timestamp> first.
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_HOME=/root

dry=0
case "${1:-}" in
    -n|--dry-run) dry=1 ;;
    -h|--help)    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
esac

if [ "$dry" = 0 ] && [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root (try: sudo $0)" >&2
    exit 1
fi

put() {
    local src="$1" dst="$2" mode="$3"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        echo "unchanged $dst"
        return
    fi
    if [ "$dry" = 1 ]; then echo "+ install $src -> $dst"; return; fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        local backup
        backup="$dst.bak.$(date +%s)"
        mv "$dst" "$backup"
        echo "backed up $dst -> $backup"
    fi
    install -D -m "$mode" "$src" "$dst"
    echo "installed $dst"
}

[ "$dry" = 1 ] || install -d -m 700 "$ROOT_HOME/.config"

put "$HERE/shell/bash/appendrc"      "$ROOT_HOME/.bashrc"                 644
put "$HERE/shell/bash/inputrc"       "$ROOT_HOME/.inputrc"                644
put "$HERE/starship/starship.toml"   "$ROOT_HOME/.config/starship.toml"   644

echo "Root user configs installed."
