# Interactive bash setup for the normal user. Sourced from the managed block
# install.sh adds to ~/.bashrc; the files below live next to this one, in
# ~/.config/shell/.
[[ $- != *i* ]] && return

DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DOTS/aliases"
source "$DOTS/integrations"
