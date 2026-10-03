# fish secure secrets editor + aliases mirroring shell/aliases.
# svim: no viminfo, no swap/backup/undo files, no plugins.
alias svim "nvim -u NONE -i NONE -n -c 'set number' -c 'set nowritebackup nobackup noundofile noswapfile'"
set -gx SOPS_EDITOR "nvim -u NONE -i NONE -n -c 'set number' -c 'set nowritebackup nobackup noundofile noswapfile'"

# directory shortcuts (mirror shell/aliases)
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'
