-- macOS Liquid Glass look for Omarchy.
-- Loaded last, from a line install.sh adds to ~/.config/hypr/looknfeel.lua, so
-- it wins over your own look settings only while this theme is active.
hl.config({
  general = {
    gaps_in = 6,
    gaps_out = 10,
    border_size = 1,
  },
  decoration = {
    rounding = 16,
    dim_inactive = false,
    active_opacity = 1.0,
    inactive_opacity = 0.97,
    shadow = {
      enabled = true,
      range = 30,
      render_power = 3,
      color = "rgba(00000050)",
      color_inactive = "rgba(00000030)",
    },
    blur = {
      enabled = true,
      size = 10,
      passes = 3,
      ignore_opacity = true,
      new_optimizations = true,
      vibrancy = 0.2,
      vibrancy_darkness = 0.2,
      brightness = 0.75,
      contrast = 1.0,
      noise = 0.02,
      popups = true,
    },
  },
})

-- Springy pop-in and sideways Spaces-style workspace slides.
hl.curve("macSpring", { type = "bezier", points = { { 0.34, 1.8 }, { 0.64, 1 } } })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "macSpring", style = "popin 90%" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })

-- Frosted glass behind the bar (it is almost clear, so blur every pixel of it)
-- and behind the dock, menus, launcher, notifications and popups.
hl.layer_rule({ match = { namespace = "^omarchy-bar$" }, blur = true, blur_popups = true, ignore_alpha = 0.0 })
hl.layer_rule({ match = { namespace = "^omarchy-(dock|dock-apps|menu|keyboard-panel|notifications|osd|clipboard|emojis|reminders|polkit|network-qr|dictation-hud|switcher)$" }, blur = true, ignore_alpha = 0.3 })
-- The dock's genie overlay draws its own motion; Hyprland must not pop it in.
hl.layer_rule({ match = { namespace = "^omarchy-dock-genie$" }, no_anim = true })

-- Menus, popups and the launcher pop in with the same spring as windows.
hl.animation({ leaf = "layersIn", enabled = true, speed = 4.5, bezier = "macSpring", style = "popin 92%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2, bezier = "easeOutQuint", style = "popin 95%" })

-- Every app fades to frosted glass like Files (apps draw solid backgrounds,
-- so the whole window fades). GTK apps get their blur from gtk.css.
o.window(".*", { opacity = "0.7 0.7" })
-- Ghostty has its own glass background with solid text; keep it as is.
o.window("^(com\\.mitchellh\\.ghostty|TUI\\..*)$", { opacity = "1 1" })
-- Files draws its own glass (see-through sidebar, solid list) from gtk.css.
o.window("^org\\.gnome\\.Nautilus$", { opacity = "1 1" })
-- Browsers draw popups (downloads, menus) as separate layers, so a fade stacks
-- on the faded page and becomes unreadable; keep them solid.
o.window("^(brave-browser|chromium|google-chrome|firefox|zen)$", { opacity = "1 1" })
-- Keep video and images true to color.
o.window("^(mpv|imv|org\\.gnome\\.Loupe)$", { opacity = "1 1" })

-- macOS traffic lights on every window, via Omarchy's own titlebar plugin
-- (normally only loaded for floating workspaces). The plugin reloads the config
-- once loaded, which is the pass where hl.plugin.hyprbars exists.
local TITLEBARS = "/usr/lib/omarchy-hyprland-titlebars/titlebars.so"
local plugin_file = io.open(TITLEBARS, "r")
if plugin_file then
  plugin_file:close()
  hl.plugin.load(TITLEBARS)
end
if hl.plugin.hyprbars then
  local window = [[window = "address:%WINDOW%"]]
  -- macOS dark title-bar gray with the app's name centered.
  local bar = "rgb(323232)"
  hl.config({
    plugin = {
      hyprbars = {
        enabled = true,
        workspace_tag = "",
        bar_height = 32,
        bar_title_enabled = true,
        bar_blur = true,
        bar_color_inactive = "rgb(2a2a2a)",
        bar_color = bar,
        col = { text = "rgb(e5e5e7)" },
        bar_text_font = "Inter",
        bar_text_size = 13,
        bar_text_weight = "semibold",
        bar_text_align = "center",
        bar_buttons_alignment = "left",
        bar_part_of_window = true,
        bar_precedence_over_border = true,
        bar_padding = 12,
        bar_button_padding = 8,
        button_rounding = -1, -- circular
        icon_on_hover = true,
        inactive_button_color = "rgb(48484a)",
        on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\", " .. window .. " })'",
      },
    },
  })
  -- Left to right: close, minimize, zoom.
  for _, b in ipairs({
    { color = "rgb(ff5f57)", fg = "rgb(4d0000)", icon = "", action = "hyprctl dispatch 'hl.dsp.window.close({ " .. window .. " })'" },
    { color = "rgb(febc2e)", fg = "rgb(7a4500)", icon = "", action = 'bash "$HOME/.local/state/omarchy/current/theme/minimize.sh" %WINDOW%' },
    { color = "rgb(28c840)", fg = "rgb(004d00)", icon = "", action = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\", " .. window .. " })'" },
  }) do
    hl.plugin.hyprbars.add_button({ bg_color = b.color, fg_color = b.fg, size = 14, icon = b.icon, action = b.action })
  end

  -- Omarchy sets up its own title bars for floating workspaces after this file
  -- loads, and again when a workspace turns floating. Keep ours: ignore any
  -- later title-bar options and buttons. Each config reload starts Lua fresh.
  hl.plugin.hyprbars.add_button = function() end
  local apply_config = hl.config
  hl.config = function(options)
    if type(options) == "table" and type(options.plugin) == "table" and options.plugin.hyprbars ~= nil then
      options.plugin.hyprbars = nil
      if next(options.plugin) == nil then options.plugin = nil end
      if next(options) == nil then return end
    end
    return apply_config(options)
  end
end

-- A window dragged with the mouse from a tiled workspace onto a floating one
-- can land still tiled (under every floating window, filling the screen, and
-- not raised by a click) or floating at its tiled size. Omarchy floats and
-- sizes only windows that arrive tiled once the move has settled, and leaves
-- floating ones their size. Finish the job: float it as Omarchy does,
-- claimed, so it tiles again if the workspace does, at the size Omarchy opens
-- windows at there, centered.
local function settle_arrival(address)
  local window = hl.get_window("address:" .. address)
  if not window or (window.fullscreen or 0) ~= 0 or not window.workspace then return end
  -- A floating workspace is one whose windows carry Omarchy's tag.
  local on_floating = false
  for _, other in ipairs(hl.get_workspace_windows(tostring(window.workspace.id))) do
    for _, tag in ipairs(other.tags or {}) do
      if tag == "omarchy-floating-workspace" then on_floating = true end
    end
  end
  local monitor = window.monitor
  if not on_floating or not monitor or not monitor.width then return end
  local reserved = monitor.reserved or {}
  local width = math.floor(monitor.width / monitor.scale) - (reserved.left or 0) - (reserved.right or 0)
  local height = math.floor(monitor.height / monitor.scale) - (reserved.top or 0) - (reserved.bottom or 0)
  if not window.floating then
    hl.dispatch(hl.dsp.window.tag({ tag = "+omarchy-floating-workspace", window = window }))
    hl.dispatch(hl.dsp.window.tag({ tag = "+omarchy-mode-floated", window = window }))
    hl.dispatch(hl.dsp.window.float({ action = "on", window = window }))
  elseif window.size.x < width * 0.9 and window.size.y < height * 0.9 then
    return
  end
  hl.dispatch(hl.dsp.window.resize({
    x = math.min(1100, math.floor(width * 0.64)),
    y = math.min(760, math.floor(height * 0.68)),
    relative = false,
    window = window,
  }))
  hl.dispatch(hl.dsp.window.center({ window = window }))
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
end

hl.on("window.move_to_workspace", function(moved)
  local address = moved.address
  -- After Omarchy's own arranging (1ms), and again once a drag has let go.
  hl.timer(function() settle_arrival(address) end, { type = "oneshot", timeout = 30 })
  hl.timer(function() settle_arrival(address) end, { type = "oneshot", timeout = 300 })
end)
-- No window stays tiled on a floating workspace, so should a drag ever skip
-- the move event, a click on the window still floats it.
hl.on("window.active", function(window)
  if window and window.address and not window.floating then settle_arrival(window.address) end
end)

-- Omarchy makes windows on floating workspaces fully opaque; keep the same
-- glass there as on tiled workspaces. Rules it adds later for that tag drop
-- their opacity, everything else about them stays.
local add_window_rule = o.window
o.window = function(match, rules)
  if type(match) == "table" and match.tag == "omarchy-floating-workspace" and type(rules) == "table" and rules.opacity ~= nil then
    rules.opacity = nil
    if next(rules) == nil then return end
  end
  return add_window_rule(match, rules)
end

-- Alt+Tab opens the macOS app switcher and Super+Tab the workspace switcher
-- when the plugin is installed: Tab and Shift+Tab move while the modifier is
-- held, letting go of it switches.
local switcher = io.open((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/omarchy/plugins/macos-theme.switcher/manifest.json", "r")
if switcher then
  switcher:close()
  o.rebind("ALT + TAB", "App switcher", "omarchy-shell -q macos-switcher next")
  o.rebind("ALT + SHIFT + TAB", "App switcher (previous)", "omarchy-shell -q macos-switcher prev")
  o.rebind("SUPER + TAB", "Workspace switcher", "omarchy-shell -q macos-spaces next")
  o.rebind("SUPER + SHIFT + TAB", "Workspace switcher (previous)", "omarchy-shell -q macos-spaces prev")
end
