These dotfiles are intended to set up a custom [AthenaOS](https://athenaos.org/) desktop in a VM. Intended as a CTF / Engagement environment.

AthenaOS is downstream of arch linux and has access to all official Arch repos. It also has access to the blackarch repos and chaotic-aur repos.

## packages

`install.sh` is the source of truth; this is what it installs, and why.

| Area | Packages |
| --- | --- |
| Window manager and layout | `i3-wm`, `i3status-rust` (bar), `autotiling` |
| Launcher, notifications | `rofi`, `dunst`, `libnotify` |
| Terminals, editor, monitors | `alacritty` (default), `kitty`, `neovim`, `btop` |
| Browsers | `chromium`, `qutebrowser-git`, `firefox` |
| X and the session | `xorg-server`, `xorg-xinit`, `xorg-xauth`, `xorg-xrandr`, `ly` |
| Shell and prompt | `starship`, `eza`, `zoxide`, `fzf`, `bat`, `bash-completion` |
| Package managers | `mise`, `nix` |
| Helpers | `jq`, `maim`, `xclip`, `xcolor`, `feh`, `numlockx`, `curl` |
| VM guest and session services | `spice-vdagent`, `qemu-guest-agent`, `polkit-gnome`, `network-manager-applet`, `pipewire-pulse` |
| Dark mode | `gsettings-desktop-schemas`, `dconf`, `xdg-desktop-portal`, `xdg-desktop-portal-gtk`, `adwaita-icon-theme` |
| Font | `ttf-jetbrains-mono-nerd` |

Notes on particular entries:

- **`qutebrowser-git` is chaotic-aur only**, with no fallback. `install.sh` checks
  `pacman -Si chaotic-aur/qutebrowser-git`, and if that fails it warns, finishes the rest, and exits
  non-zero rather than substituting extra's `qutebrowser`. If a conflicting `qutebrowser` is installed it is
  removed first.
- **`nix` is installed, nothing more.** `install.sh` enables `nix-daemon.socket` and adds the user to
  `nix-users` when that group exists. No channels, no flakes config: project-specific environments only.
- **`libnotify` is load-bearing**, not a convenience: `dunst` lists it as an optdep for `dunstify`, and every
  OSD in `bin/` calls `dunstify`.
- **`xorg-server` and `xorg-xinit` are explicit** because `i3-wm` does not depend on either. They are what
  `startx` needs, and what `ly` runs against.
- **`chromium`** is installed alongside `qutebrowser-git` because both follow the system colour scheme.
- **`firefox`** is configured by enterprise policy, not by copying profile files; see below.
- **`ttf-jetbrains-mono-nerd`** is the font named by kitty, alacritty, i3, ly and the bar.

## Starting i3

The VM has no desktop environment. `ly` is the display manager: install.sh enables `ly@tty1.service`, and
at boot you get a login prompt on the virtual console. Pick `i3` as the session; it comes from i3-wm's
`/usr/share/xsessions/i3.desktop`, which ly reads, so no extra session file is needed.

ly reads exactly one config file, `/etc/ly/config.ini`. The path is compiled into it and there is **no**
`~/.config/ly/config.ini` fallback, so a per-user config does nothing. `install_ly_theme()` therefore merges
`ly/pinkrot.ini` into that system file, keeping the packaged original at `/etc/ly/config.ini.athena-orig` and
always re-merging from it, so repeat runs are idempotent. A `pacman -Syu` that upgrades ly restores the
packaged file (or leaves a `.pacnew`); re-run the installer to put the theme back.
Autologin is deliberately not enabled: log in interactively.

`xorg-xinit` and `xorg-xauth` are still installed, so `startx /usr/bin/i3` works from a tty as a fallback
when ly will not come up. Do not run a bare `startx` without naming i3: Arch's
`/etc/X11/xinit/xinitrc` falls back to `twm` and `xclock`.

`i3-wm` does not depend on `xorg-server`, which is why the X packages are in the list explicitly.

The display is SPICE (virt-manager's graphical console), paired with `spice-vdagent` for clipboard and
resize. X has no mode-setting of its own: if X fails to find the video device on first boot, it needs an
explicit driver in `/etc/X11/xorg.conf.d/`.

The resolution is pinned to 1920x1080 by `bin/x11-monitor`, run from `05-autostart.conf`'s `exec_always`.
A headless VM otherwise comes up at whatever size the last SPICE client asked for. If the GPU offers
1080p already, the script just selects it; otherwise it adds a CEA 1080p60 modeline first. Passing another
size, e.g. `$bin/x11-monitor 2560x1440`, works only if the output already lists that mode.

Nothing more than the resolution: the script selects the mode and rate, and does nothing else. Earlier
versions also switched off extra and stale outputs, forced `--pos 0x0` and resized the framebuffer, chasing a
wallpaper that appeared to tile. None of that was the cause and some of it made it worse.

The actual cause: `05-autostart.conf` ran `x11-monitor` and `x11-wallpaper` as **two** `exec_always` lines,
which i3 starts concurrently. feh painted while the GPU was still at its preferred mode, 1280x800, leaving a
1280x800 root pixmap; `x11-monitor` then switched to 1920x1080, and X tiled that stale pixmap across the
larger root window. On the VM the left and right halves of the screen matched to within 0.00/255 after
painting at 1280x800 and growing to 1920x1080, and differed by 8.80 once the two were run in sequence. They
are now one line, sequenced with `&&` in an explicit `sh -c`, because i3's `exec` does not use a shell.

`bin/x11-wallpaper` is a plain `feh --bg-fill`, with no `--bg-size` and no root-window reset.

## Firefox

`setup_firefox()` in `install.sh` installs `firefox/policies.json` to
`/etc/firefox/policies/policies.json`, the documented system-wide location on Linux. The install-directory
alternative under `/usr/lib/firefox/distribution` is read too, but a package upgrade would clobber it.

The policy does two things:

- `Extensions.Install` fetches two add-ons from AMO at Firefox's first start, so that run needs network:
  Vimium (`vimium-ff`, id `{d7742d87-e61d-4b78-b8a1-b469842139fa}`) and the Flame theme
  (`nova_flame`, id `nova-flame@mozilla.org`, requires Firefox 153+). Both ids were read out of the XPIs
  rather than guessed.
- `Preferences` sets `extensions.activeThemeID` to the theme's id, which is what actually *activates* it;
  installing a theme does not select it. It is set with status `default`, not `locked`, so the theme is
  active on a fresh profile but can still be changed in the UI. If a later build ever resets it, `locked`
  forces it.

**Vimium's options cannot be installed by policy.** Its settings live in the extension's own browser
storage, and the only import path is the Restore control on `chrome-extension://<id>/options.html`. No
Firefox policy can write extension storage, and the profile's IndexedDB cannot be authored from outside.
`install.sh` therefore copies `firefox/vimium-options.json` to `~/.config/firefox/vimium-options.json` for a
one-time manual import. See "qutebrowser" below for the same settings applied where they can be scripted.

## qutebrowser

`qutebrowser/config.py` sources `pinkrot.py` (colours) and `vimium.py` (Vimium parity). `vimium.py` is
generated from `firefox/vimium-options.json` and carries the Vimium shortcuts and search keywords in
qutebrowser's syntax: `config.bind()` instead of `map` lines, and a dict with a `{}` placeholder instead of
`keyword: URL` lines with `%s`.

Three things were checked in Vimium's source rather than assumed:

- `scrollPageDown`/`scrollPageUp` move by **half** a viewport, not a whole one, so they map to
  `scroll-page 0 0.5` / `-0.5`.
- All four mappings already coincide with qutebrowser's defaults (`J`/`K` are `tab-next`/`tab-prev`), so
  those binds pin existing behaviour rather than change it.
- A duplicate keyword resolves to the **last** definition, because Vimium assigns into an object while
  parsing. The options file defined `b` twice, for Brave and then Bing, so `b` was Bing.

Two things were resolved in the source options file rather than worked around here. The duplicate `b` line
for Bing is gone, leaving Brave as `b` in both browsers, and `mb` now uses `%s` rather than `%st`, which had
been appending a literal `t` to every query (`mb foo` searched for `foot`). Bing is therefore no longer
available under `b`; add it under its own keyword if wanted.

qutebrowser requires a `DEFAULT` search engine and the options file has none, so `DEFAULT` is Brave, the
same URL as `b`.

## Neovim

`nvim/colors/pinkrot.lua` is linked to `~/.config/nvim/colors/pinkrot.lua`, but a colourscheme file alone
does nothing: something has to select it, and a bare `neovim` package has no `init.lua`. That is why the
theme looked uninstalled on the VM while the file was present and working.

`setup_nvim()` therefore appends a managed `-- >>> athena-dots >>>` block to `~/.config/nvim/init.lua`,
creating the file if absent and never touching anything outside the markers, so an existing plugin-manager
config survives. The `nvim/lua/plugins/pinkrot-theme.lua` LazyVim spec is still linked when
`~/.config/nvim/lua/plugins/` exists.

One trap in the colours file itself: it set `vim.g.colors_name` before `highlight clear`, and that command
resets `g:colors_name`, so it read back as nil even though the colours applied. The assignment now comes
after, and `:colorscheme` reports `pinkrot` again.

Separately, the AthenaOS image ships a `~/.vimrc` from the amix/vimrc installer that hardcodes
`/home/athena/.vim_runtime`. On this VM the user is `t`, so every `source` in it failed with E484 and Vim
would not start cleanly. The paths are `$HOME`-relative now. That file is image state, not part of this repo,
so a rebuild needs the same one-line repair.

## Layout and install

- `i3/` — `config` + numbered `conf.d/` modules (see header of `i3/config`).
- One top-level dir per app (`kitty/`, `alacritty/`, `rofi/`, `dunst/`, `starship/`, …), plus `shell/` (bash integration), `bin/` (helper scripts → `~/.local/bin`).
- `~/.config/wallpapers/` is yours: `install.sh` creates it and seeds `bleach_0.png` from the `r3b1s/wallpapers`
  repo on first run, without ever overwriting an existing file. `bin/x11-wallpaper` picks a random image from
  it (jpg/jpeg/png/webp/bmp) on every i3 start and reload. A failed download is a warning, not a failure.
- `$mod+Shift+r` reloads i3 and then re-runs the wallpaper. Both halves need their own `exec`: i3 treats
  everything after a `;` as a new command, so a bare `$bin/x11-wallpaper` is rejected at runtime with
  "Expected one of these tokens: ... 'exec' ...". Note `i3 -C` validates the config file but **not** the
  command body of a `bindsym`, so it accepts that mistake silently and the bind does nothing.
- `install.sh` installs missing packages (pacman), enables `spice-vdagentd.socket`,
  symlinks the dots, then validates with `i3 -C`. It is the source of truth for the
  package list; keep it in sync with this file.
- GTK ignores `org.gnome.desktop.interface` for the theme and icon theme: it reads XSETTINGS, which needs a
  settings daemon, and there is none in a bare i3 session. `setup_gtk()` in `install.sh` therefore writes
  `~/.config/gtk-{3,4}.0/settings.ini` with `gtk-theme-name=Adwaita`, `gtk-application-prefer-dark-theme=1`
  and icon theme `pinkrot`. Two traps here, both verified on the VM. First, the dark variant comes from
  `prefer-dark` and not from the theme name: `Adwaita-dark` is not a real GTK3 theme, and naming it makes GTK
  fall back to **light** Adwaita without complaint (menu background `#F6F5F4` versus `#353535`). Second, the
  `icon-theme` dconf key is ignored here too, so the icon theme has to be named in settings.ini.
- `setup_gtk()` also generates a small `pinkrot` icon theme in `~/.local/share/icons/` from the package's
  symbolic NetworkManager icons, recoloured to `#f17e97`. nm-applet asks for the plain (non-`-symbolic`)
  names, so each is written under both, which is what replaces its pastel hardware glyph in the i3bar tray.
  No icon files live in this repo. The glyph renders at the 0.35 opacity baked into Adwaita's SVG, so it is
  dimmer than the bar text; strip the `opacity` attributes in the generated files to brighten it.
- System dark mode: `setup_dark_theme()` in `install.sh` sets dconf `color-scheme=prefer-dark` and
  `gtk-theme=Adwaita`, and enables the `xdg-desktop-portal{,-gtk}` user services. Those exist for the things
  that ask a portal rather than reading settings themselves, which is sandboxed apps and Qt6 (qutebrowser).
  GTK's own dark mode does **not** come from here: see the settings.ini bullet above. The portal backend is
  gated on `XDG_CURRENT_DESKTOP`, exported from `shell/xprofile` (-> `~/.xprofile`) because i3 has no
  `set_environment` directive. The GTK backend's descriptor, `portals/gtk.portal`, declares `UseIn=gnome`,
  which is why that variable names GNOME at all. Check it with
  `busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop
  org.freedesktop.portal.Settings ReadOne ss org.gnome.desktop.interface color-scheme`, which should answer
  `"prefer-dark"`. Run the installer from inside the i3 session, or the dconf half is skipped with
  instructions.
- Guest is qemu/kvm/libvirt: no i3lock, no picom, no brightness/nightlight/screen recording.
- Colours are the pinkrot theme throughout, kept inside each app's own dir: `i3/conf.d/01-pinkrot.conf` (window
  colours), `i3/conf.d/15-bar.conf` (bar colours; a `bar` block can't be split across includes),
  `kitty/pinkrot.conf`, `alacritty/alacritty.toml` (single file), `i3status-rust/themes/`, `rofi/`, `dunst/`,
  `qutebrowser/pinkrot.py`, `btop/`, `nvim/`; ly's is `ly/pinkrot.ini`, see "Starting i3".
- Default terminal is alacritty (`set $terminal` in `i3/config`). Kitty stays installed and keeps its
  pinkrot colours, but nothing in the config launches it and its remote-control socket is off.
- `install.sh` links whole dirs for i3, kitty, alacritty, rofi, dunst, i3status-rust, shell; individual files for
  qutebrowser, btop, nvim and `starship/starship.toml` -> `~/.config/starship.toml` (those apps write runtime
  state next to their config). `shell/xprofile` is linked separately to `~/.xprofile`, which is outside
  `~/.config`; `bin/*` goes to `~/.local/bin`; `nvim/lua/plugins/pinkrot-theme.lua` only when a LazyVim
  `plugins/` dir exists. The ly theme is merged into `/etc/ly/config.ini` instead of linked, and the GTK icon
  theme is generated into `~/.local/share/icons/`.
- `shell/` is sourced by a managed `# >>> athena-dots >>>` block appended to `~/.bashrc` (idempotent, bash only):
  `init.sh` -> `aliases` (eza, zoxide `cd`/`zd`, fzf `ff`/`eff`/`sff`, `..`/`...`/`....`) and
  `integrations` (mise activation, bash-completion, starship, zoxide, fzf key bindings). Definitions are guarded by
  `command -v`, so a missing tool silently disables its aliases.
- Requires a bash login shell; `install.sh` warns if `$SHELL` is something else.
- mise is activated in `shell/integrations` (with `set +h`, or bash caches binary paths ahead of the
  shims). No global or project mise config is managed by this repo; put one in `mise/config.toml` if wanted.
- `root/` holds dots for the root user and has its own `root/install.sh` (`sudo ./root/install.sh`).
  It is opt-in: the top-level `install.sh` never runs it. It COPIES (never symlinks) into `/root`, since
  root must not read user-writable files, and backs up differing existing files. Its `appendrc` carries the
  same eza/zoxide/fzf aliases plus root-only extras (`wipehist`, `compress`, ssh port forwards `fip`/`dip`/`lip`).
