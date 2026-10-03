# xonsh vi mode + svim alias. Linked to ~/.config/xonsh/rc.xsh by install.sh.
# Bash stays the default login shell; xonsh is launched explicitly.
$VI_MODE = True

import os
$SOPS_EDITOR = "nvim -u NONE -i NONE -n -c 'set number' -c 'set nowritebackup nobackup noundofile noswapfile'"
aliases["svim"] = "nvim -u NONE -i NONE -n -c 'set number' -c 'set nowritebackup nobackup noundofile noswapfile'"
