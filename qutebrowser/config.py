# qutebrowser entry point. Keeps settings made with :set (autoconfig.yml) and
# loads the pinkrot colours from pinkrot.py (linked alongside by install.sh).
config.load_autoconfig()
config.source('pinkrot.py')
