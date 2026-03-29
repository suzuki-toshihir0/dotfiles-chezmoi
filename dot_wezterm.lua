local wezterm = require 'wezterm'
local config = {}

config.color_scheme = 'Catppuccin Mocha'

config.font = wezterm.font_with_fallback {
  'HackGen Console NF',
  'Noto Sans Symbols 2',
}
config.font_size = 12.0

config.window_background_opacity = 0.85
config.window_decorations = "TITLE | RESIZE"

-- Leader key: Ctrl+a（tmux風）
config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 }

config.keys = {
  -- Ctrl+a → - : 上下に分割
  {
    key = '-',
    mods = 'LEADER',
    action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
  },
  -- Ctrl+a → | : 左右に分割
  {
    key = '|',
    mods = 'LEADER|SHIFT',
    action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
}

return config
