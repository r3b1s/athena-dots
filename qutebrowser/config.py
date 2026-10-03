# qutebrowser entry point. config.py is the source of truth; :set changes land
# in autoconfig.yml via config.load_autoconfig() and are kept.
# Colours come from pinkrot.py, Vimium parity from vimium.py (both linked
# alongside by install.sh).
config.load_autoconfig()
config.source('pinkrot.py')
# Vimium-style shortcuts and search keywords, mirrored from
# firefox/vimium-options.json. See that file for the conversion notes.
config.source('vimium.py')

# ── behaviour (TODO.md) ─────────────────────────────────────────────────────
# Kept here instead of autoconfig.yml so a fresh clone behaves the same.
c.colors.webpage.darkmode.enabled = True
c.content.autoplay = False
c.content.geolocation = False
c.content.pdfjs = True

# Custom startpage: linked to ~/.config/qutebrowser/startpage.html.
c.url.start_pages = ["~/.config/qutebrowser/startpage.html"]
c.url.default_page = "~/.config/qutebrowser/startpage.html"
