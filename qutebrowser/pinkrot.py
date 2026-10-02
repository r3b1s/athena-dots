# pinkrot theme for qutebrowser — dracula draw.py format
# Source this file in qutebrowser config.py via config.source()

bg = "#050007"
fg = "#f17e97"
accent = "#d40d40"
muted = "#a85869"
dark = "#1a0014"
bright_fg = "#ffffff"

# Completion
c.colors.completion.fg = fg
c.colors.completion.odd.bg = bg
c.colors.completion.even.bg = dark
c.colors.completion.category.fg = accent
c.colors.completion.category.bg = bg
c.colors.completion.category.border.top = accent
c.colors.completion.category.border.bottom = accent
c.colors.completion.item.selected.fg = bright_fg
c.colors.completion.item.selected.bg = accent
c.colors.completion.item.selected.border.top = accent
c.colors.completion.item.selected.border.bottom = accent
c.colors.completion.item.selected.match.fg = bright_fg
c.colors.completion.match.fg = accent
c.colors.completion.scrollbar.fg = fg
c.colors.completion.scrollbar.bg = bg

# Downloads
c.colors.downloads.bar.bg = bg
c.colors.downloads.start.fg = bg
c.colors.downloads.start.bg = accent
c.colors.downloads.stop.fg = bg
c.colors.downloads.stop.bg = fg
c.colors.downloads.error.fg = accent

# Hints
c.colors.hints.fg = bg
c.colors.hints.bg = accent
c.colors.hints.match.fg = fg

# Keyhint
c.colors.keyhint.fg = fg
c.colors.keyhint.suffix.fg = accent
c.colors.keyhint.bg = bg

# Messages
c.colors.messages.error.fg = bright_fg
c.colors.messages.error.bg = accent
c.colors.messages.error.border = accent
c.colors.messages.warning.fg = bright_fg
c.colors.messages.warning.bg = muted
c.colors.messages.warning.border = muted
c.colors.messages.info.fg = fg
c.colors.messages.info.bg = bg
c.colors.messages.info.border = bg

# Prompts
c.colors.prompts.fg = fg
c.colors.prompts.border = accent
c.colors.prompts.bg = bg
c.colors.prompts.selected.fg = bright_fg
c.colors.prompts.selected.bg = accent

# Statusbar
c.colors.statusbar.normal.fg = fg
c.colors.statusbar.normal.bg = bg
c.colors.statusbar.insert.fg = bg
c.colors.statusbar.insert.bg = accent
c.colors.statusbar.passthrough.fg = bg
c.colors.statusbar.passthrough.bg = muted
c.colors.statusbar.private.fg = bg
c.colors.statusbar.private.bg = dark
c.colors.statusbar.command.fg = fg
c.colors.statusbar.command.bg = bg
c.colors.statusbar.command.private.fg = fg
c.colors.statusbar.command.private.bg = bg
c.colors.statusbar.caret.fg = bg
c.colors.statusbar.caret.bg = accent
c.colors.statusbar.caret.selection.fg = bg
c.colors.statusbar.caret.selection.bg = fg
c.colors.statusbar.progress.bg = accent
c.colors.statusbar.url.fg = fg
c.colors.statusbar.url.error.fg = accent
c.colors.statusbar.url.hover.fg = bright_fg
c.colors.statusbar.url.success.http.fg = muted
c.colors.statusbar.url.success.https.fg = fg
c.colors.statusbar.url.warn.fg = accent

# Tabs
c.colors.tabs.bar.bg = bg
c.colors.tabs.indicator.start = accent
c.colors.tabs.indicator.stop = fg
c.colors.tabs.indicator.error = accent
c.colors.tabs.odd.fg = muted
c.colors.tabs.odd.bg = bg
c.colors.tabs.even.fg = muted
c.colors.tabs.even.bg = dark
c.colors.tabs.pinned.even.fg = fg
c.colors.tabs.pinned.even.bg = dark
c.colors.tabs.pinned.odd.fg = fg
c.colors.tabs.pinned.odd.bg = bg
c.colors.tabs.pinned.selected.even.fg = bright_fg
c.colors.tabs.pinned.selected.even.bg = accent
c.colors.tabs.pinned.selected.odd.fg = bright_fg
c.colors.tabs.pinned.selected.odd.bg = accent
c.colors.tabs.selected.even.fg = bright_fg
c.colors.tabs.selected.even.bg = accent
c.colors.tabs.selected.odd.fg = bright_fg
c.colors.tabs.selected.odd.bg = accent
