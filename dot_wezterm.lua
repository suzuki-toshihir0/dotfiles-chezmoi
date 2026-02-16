local wezterm= require 'wezterm'
local config = {}

config.color_scheme = 'Catppuccin Mocha'

config.font = wezterm.font 'HackGen Console NF'
config.font_size = 12.0

config.window_background_opacity = 0.85
config.window_decorations = "TITLE | RESIZE"

return config
