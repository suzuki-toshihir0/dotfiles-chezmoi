local wezterm = require 'wezterm'
local config = {}

config.color_scheme = 'Catppuccin Mocha'

-- TERM を 'wezterm' に明示する。
-- 既定の 'xterm-256color' は terminfo で DECSLRM (左右マージン) 対応を宣言してしまい、
-- nvim の vsplit 右ペインをスクロールすると左ペインの右半分まで巻き込まれて崩れる。
-- WezTerm 自身の terminfo は DECSLRM を宣言していないため、明示することで回避できる。
config.term = 'wezterm'

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
