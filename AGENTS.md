These dotfiles are intended to set up a custom [AthenaOS](https://athenaos.org/) desktop in a VM. Intended as a CTF / Engagement environment.

AthenaOS is downstream of arch linux and has access to all official Arch repos. It also has access to the blackarch repos and chaotic-aur repos.

## Starting i3

The VM has no display manager and no desktop environment. `xorg-server` and `xorg-xinit` are installed, so
the session is started by hand from a TTY:

    startx /usr/bin/i3

There is deliberately no `~/.xinitrc` managed here yet, and no autologin. `i3-wm` does not depend on
`xorg-server`, which is why both are in the package list. Arch's `/etc/X11/xinit/xinitrc` falls back to
`twm`/`xclock`, so do not run a bare `startx` without naming i3.

The display is SPICE (virt-manager's graphical console), paired with `spice-vdagent` for clipboard and
resize. X has no mode-setting of its own: if X fails to find the video device on first boot, it needs an
explicit driver in `/etc/X11/xorg.conf.d/`.

The resolution is pinned to 1920x1080 by `bin/x11-monitor`, run from `05-autostart.conf`'s `exec_always`.
A headless VM otherwise comes up at whatever size the last SPICE client asked for. If the GPU offers
1080p already, the script just selects it; otherwise it adds a CEA 1080p60 modeline first. Passing another
size, e.g. `$bin/x11-monitor 2560x1440`, works only if the output already lists that mode.

## Layout and install

- `i3/` — `config` + numbered `conf.d/` modules (see header of `i3/config`).
- One top-level dir per app (`kitty/`, `rofi/`, `dunst/`, `starship/`, …), plus `shell/` (bash integration), `bin/` (helper scripts → `~/.local/bin`).
- `~/.config/wallpapers/` is yours: install.sh only creates it if missing, and `bin/x11-wallpaper` picks a
  random image from it on every i3 start/reload. `$mod+Shift+r` reloads i3 to reshuffle.
- `install.sh` installs missing packages (pacman), enables `spice-vdagentd.socket`,
  symlinks the dots, then validates with `i3 -C`. It is the source of truth for the
  package list; keep it in sync with this file.
- Runtime helpers beyond the list above: jq, xdotool, maim, xclip, xcolor, feh (random wallpaper), numlockx,
  polkit-gnome, network-manager-applet, spice-vdagent, qemu-guest-agent, pipewire-pulse,
  ttf-jetbrains-mono-nerd, starship, eza, zoxide, fzf, bat (previews `ff`), bash-completion.
- qutebrowser is installed ONLY as chaotic-aur/qutebrowser-git (no fallback; install.sh fails loudly if chaotic-aur is missing).
- nix is for project-specific environments only: install.sh enables `nix-daemon.socket` and nothing else (no channels).
- Guest is qemu/kvm/libvirt: no i3lock, no picom, no brightness/nightlight/screen recording.
- Colours are the pinkrot theme throughout, kept inside each app's own dir: `i3/conf.d/01-pinkrot.conf` (window
  colours), `i3/conf.d/15-bar.conf` (bar colours; a `bar` block can't be split across includes),
  `kitty/pinkrot.conf`, `i3status-rust/themes/`, `rofi/`, `dunst/`, `qutebrowser/pinkrot.py`, `btop/`, `nvim/`.
- `install.sh` links whole dirs for i3, kitty, rofi, dunst, i3status-rust, shell; individual files for
  qutebrowser, btop, nvim and `starship/starship.toml` -> `~/.config/starship.toml` (those apps write runtime
  state next to their config).
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
