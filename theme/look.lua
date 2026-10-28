-- macOS Liquid Glass look for Omarchy.
-- Loaded last, from a line install.sh adds to ~/.config/hypr/looknfeel.lua, so
-- it wins over your own look settings only while this theme is active.
hl.config({
  general = {
    gaps_in = 2,
    gaps_out = 4,
    border_size = 1,
  },
  decoration = {
    rounding = 14,
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
hl.curve("macSpring", { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1 } } })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "macSpring", style = "popin 90%" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })

-- Frosted glass behind the bar (it is almost clear, so blur every pixel of it)
-- and behind the dock, menus, launcher, notifications and popups.
hl.layer_rule({ match = { namespace = "^omarchy-bar$" }, blur = true, blur_popups = true, ignore_alpha = 0.0 })
hl.layer_rule({ match = { namespace = "^omarchy-(dock|dock-apps|menu|keyboard-panel|notifications|osd|clipboard|emojis|reminders|polkit|network-qr|dictation-hud)$" }, blur = true, ignore_alpha = 0.3 })

-- Menus, popups and the launcher pop in with the same spring as windows.
hl.animation({ leaf = "layersIn", enabled = true, speed = 3.5, bezier = "macSpring", style = "popin 92%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2, bezier = "easeOutQuint", style = "popin 95%" })

-- Every app fades to frosted glass like Files (apps draw solid backgrounds,
-- so the whole window fades). GTK apps get their blur from gtk.css.
o.window(".*", { opacity = "0.8 0.8" })
-- Ghostty has its own glass background with solid text; keep it as is.
o.window("^(com\\.mitchellh\\.ghostty|TUI\\..*)$", { opacity = "1 1" })
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
        bar_text_font = "Adwaita Sans",
        bar_text_size = 14,
        bar_text_weight = "bold",
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
    { color = "rgb(febc2e)", fg = "rgb(7a4500)", icon = "", action = "omarchy-hyprland-window-minimize %WINDOW%" },
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
