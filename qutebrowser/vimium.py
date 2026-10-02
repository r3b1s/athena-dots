# Vimium parity: the same keyboard shortcuts and search keywords as
# firefox/vimium-options.json, expressed in qutebrowser's syntax.
#
# Sourced from config.py. Two syntax differences from Vimium:
#   * Vimium writes `map <key> <command>` lines; qutebrowser takes
#     config.bind(key, command).
#   * Vimium writes search engines as `keyword: URL Description` with a %s
#     placeholder; qutebrowser takes a dict with a {} placeholder and has no
#     room for the description.

# Vimium's scrollPageDown/scrollPageUp move by *half* a viewport (see
# ScrollPageDown in its mode_normal.js), not a whole one. Half a page is also
# qutebrowser's own default for these keys, and J/K already default to
# next/previous tab, so all four lines below only pin behaviour that coincides;
# they are written out to keep the parity explicit.
config.bind("J", "tab-next")                 # vimium: map J nextTab
config.bind("K", "tab-prev")                 # vimium: map K previousTab
config.bind("<Ctrl+d>", "scroll-page 0 0.5")  # vimium: map <c-d> scrollPageDown
config.bind("<Ctrl+u>", "scroll-page 0 -0.5") # vimium: map <c-u> scrollPageUp

# qutebrowser requires a DEFAULT entry and the vimium file has none, so Brave
# becomes it, matching the `b` keyword. The source file defined `b` twice, for
# Brave and then Bing; the duplicate is resolved by keeping Brave in both files
# rather than by depending on parse order.
c.url.searchengines = {
    "DEFAULT": "https://search.brave.com/search?q={}",
    "m": "https://leta.mullvad.net/search?q={}&engine=google",
    "mb": "https://leta.mullvad.net/search?q={}&engine=brave",
    "g": "https://www.google.com/search?q={}",
    "gm": "https://www.google.com/maps?q={}",
    "yt": "https://www.youtube.com/results?search_query={}",
    "b": "https://search.brave.com/search?q={}",
    "d": "https://duckduckgo.com/?q={}",
    "q": "https://www.qwant.com/?q={}",
    "wp": "https://www.wikipedia.org/w/index.php?title=Special:Search&search={}",
    "aw": "https://wiki.archlinux.org/index.php?search={}",
    "nw": "https://wiki.nixos.org/w/index.php?search={}",
    "arch": "https://archlinux.org/packages/?sort=&q={}&maintainer=&flagged=",
    "aur": "https://aur.archlinux.org/packages?O=0&K={}",
    "dnf": "https://packages.fedoraproject.org/search?query={}",
    "pip": "https://pypi.org/search/?q={}",
    "gh": "https://github.com/search?q={}&type=repositories",
    "npm": "https://www.npmjs.com/search?q={}",
    "fh": "https://flathub.org/en/apps/search?q={}",
    "pi": "https://pi.dev/packages?name={}",
    "qubes": "https://search.brave.com/search?q={}+site%3Ahttps%3A%2F%2Fqubes-os.org&source=web",
    "mise": "https://search.brave.com/search?q={}+site%3Ahttps%3A%2F%2Fmise.jdx.dev&source=web",
    "ansible": "https://docs.ansible.com/projects/ansible/latest/search.html?q={}&check_keywords=yes&area=default",
}
