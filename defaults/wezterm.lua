local wezterm = require 'wezterm'

local config = wezterm.config_builder()

config.automatically_reload_config = true
config.audible_bell = 'Disabled'
config.scrollback_lines = 10000
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.initial_cols = 120
config.initial_rows = 32
config.adjust_window_size_when_changing_font_size = false

config.window_padding = {
  left = 8,
  right = 8,
  top = 6,
  bottom = 6,
}

local nu_ok = wezterm.run_child_process { 'nu', '--version' }
if nu_ok then
  config.default_prog = { 'nu' }
end

config.keys = {
  {
    key = 'd',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  {
    key = 'e',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
  },
  {
    key = 'h',
    mods = 'ALT|SHIFT',
    action = wezterm.action.ActivatePaneDirection 'Left',
  },
  {
    key = 'j',
    mods = 'ALT|SHIFT',
    action = wezterm.action.ActivatePaneDirection 'Down',
  },
  {
    key = 'k',
    mods = 'ALT|SHIFT',
    action = wezterm.action.ActivatePaneDirection 'Up',
  },
  {
    key = 'l',
    mods = 'ALT|SHIFT',
    action = wezterm.action.ActivatePaneDirection 'Right',
  },
}

return config
