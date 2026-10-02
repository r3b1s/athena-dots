# qutebrowser entry point. Keeps settings made with :set (autoconfig.yml) and
# loads the pinkrot colours from pinkrot.py (linked alongside by install.sh).
config.load_autoconfig()
config.source('pinkrot.py')
# Vimium-style shortcuts and search keywords, mirrored from
# firefox/vimium-options.json. See that file for the conversion notes.
config.source('vimium.py')
