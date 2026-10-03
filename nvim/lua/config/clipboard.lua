-- Clipboard: yank/paste reaches the X11 clipboard and survives SSH/tmux.
--
-- Ported from the Omarchy host's remote_clipboard.lua, swapped from Wayland
-- (wl-copy/wl-paste) to X11 (xclip, already a dependency for screenshots):
-- every copy is emitted as OSC 52 when under tmux/SSH (tmux rebroadcasts its
-- buffer to every attached client), and xclip syncs the X11 CLIPBOARD when a
-- display is available. Paste prefers the local X11 clipboard when one
-- exists, so content copied in other apps remains pasteable; without a
-- display, paste is an OSC 52 query that tmux (or the terminal) answers.
local M = {}

local function shell_ok(cmd)
  return cmd ~= nil and cmd ~= "" and vim.fn.executable(cmd) == 1
end

function M.setup()
  local in_tmux = vim.env.TMUX ~= nil
  local in_ssh = vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil

  if not (in_tmux or in_ssh) then
    return
  end

  local osc52 = require("vim.ui.clipboard.osc52")
  local has_display = vim.env.DISPLAY ~= nil or vim.env.XAUTHORITY ~= nil
  local has_xclip = has_display and shell_ok("xclip")

  local function copy(register)
    local emit = osc52.copy(register)

    return function(lines)
      if has_xclip then
        local cmd = { "xclip", "-selection", "clipboard" }
        if register == "*" then
          cmd = { "xclip", "-selection", "primary" }
        end
        vim.fn.system(cmd, lines)
      end

      emit(lines)
    end
  end

  local function paste(register)
    if not has_xclip then
      return osc52.paste(register)
    end

    return function()
      local cmd = { "xclip", "-selection", "clipboard", "-o" }
      if register == "*" then
        cmd = { "xclip", "-selection", "primary", "-o" }
      end

      local lines = vim.fn.systemlist(cmd, "", 1)
      return vim.v.shell_error == 0 and lines or {}
    end
  end

  vim.g.clipboard = {
    name = "AthenaClipboard",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste("+"), ["*"] = paste("*") },
    cache_enabled = 0,
  }
end

return M
