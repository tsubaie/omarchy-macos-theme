-- macOS Liquid Glass look for Omarchy.
-- Loaded last, from a line install.sh adds to ~/.config/hypr/looknfeel.lua, so
-- it wins over your own look settings only while this theme is active.

-- How strong the frosted blur is behind see-through windows, menus, the bar
-- and the dock: 0 (off; they stay see-through, unblurred) to 20
-- (install.sh --set blur=<0-20>).
local BLUR = 10

-- Title bars with traffic lights on every window: 1 on, 0 off, on floating
-- workspaces too (install.sh --set title-bars=<0|1>).
local TITLE_BARS = 1
-- How big the traffic lights are, in points: 10 to 20; the bar grows to fit
-- the larger ones (install.sh --set traffic-lights=<10-20>).
local LIGHTS = 14
local BAR_HEIGHT = TITLE_BARS == 1 and math.max(32, LIGHTS + 14) or 0

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
      enabled = BLUR > 0,
      size = math.max(BLUR, 1),
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
local function bar_glass()
  hl.layer_rule({ match = { namespace = "^omarchy-bar$" }, blur = true, blur_popups = true, ignore_alpha = 0.0 })
end
bar_glass()
-- Omarchy's Glassy bar and window toggles load after this file. Their blur
-- (default.hypr.glass: size 4, 2 passes) would replace BLUR, and their bar
-- rule skips anything under 30% opaque, which the theme's clear bar is: no
-- blur at all. So their blur does nothing while this theme is current, and
-- the bar's rule is set again once the whole config has loaded.
package.loaded["default.hypr.glass"] = function() end
hl.on("config.reloaded", bar_glass)
hl.layer_rule({ match = { namespace = "^omarchy-(dock|dock-apps|menu|keyboard-panel|notifications|clipboard|emojis|reminders|polkit|network-qr|switcher|widgets)$" }, blur = true, ignore_alpha = 0.3 })
-- The volume and dictation HUDs are light glass, as Control Center is: blur
-- under all but their clear pixels.
hl.layer_rule({ match = { namespace = "^omarchy-(osd|dictation-hud)$" }, blur = true, ignore_alpha = 0.01 })
-- The dock's genie overlay draws its own motion; Hyprland must not pop it in.
hl.layer_rule({ match = { namespace = "^omarchy-dock-genie$" }, no_anim = true })
-- Mission Control flies the windows out itself; Hyprland must not pop it in.
hl.layer_rule({ match = { namespace = "^omarchy-mission-control$" }, no_anim = true })
-- The strip a dragged window drops onto slides down itself, on frosted glass.
hl.layer_rule({ match = { namespace = "^omarchy-drop-spaces$" }, no_anim = true, blur = true, ignore_alpha = 0.3 })
-- The shade behind the menu bar is just there, never animated in.
hl.layer_rule({ match = { namespace = "^omarchy-menubar-shade$" }, no_anim = true })
-- The snap outline is frosted glass and animates itself.
hl.layer_rule({ match = { namespace = "^omarchy-snap-preview$" }, no_anim = true, blur = true, ignore_alpha = 0.01 })

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
-- Browsers, Omarchy's web apps and Electron apps (Claude, VS Code, Cursor,
-- Discord, Slack, Obsidian, Signal, Spotify) draw popups (downloads, menus) as
-- separate layers, so a fade stacks on the faded page and becomes unreadable;
-- solid unless you set it (install.sh --set web-glass=<0.5-1>).
o.window("^(brave-browser|chromium|google-chrome|firefox|zen|(brave|chrome|chromium)-.+|com\\.anthropic\\.Claude|[Cc]ode|code-oss|[Cc]ursor|discord|[Ss]lack|obsidian|[Ss]ignal|[Ss]potify)$", { opacity = "1 1" })
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
        enabled = TITLE_BARS == 1,
        workspace_tag = "",
        bar_height = BAR_HEIGHT,
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
    hl.plugin.hyprbars.add_button({ bg_color = b.color, fg_color = b.fg, size = LIGHTS, icon = b.icon, action = b.action })
  end

  -- macOS Theme Studio draws its traffic lights in its sidebar, as macOS apps
  -- do, so it gets no bar above it.
  hl.window_rule({ name = "omarchy-macos-studio-no-bar", match = { class = "^omarchy-macos-studio$" }, ["hyprbars:no_bar"] = true })

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
-- A floating workspace is one whose windows carry Omarchy's tag.
local function on_floating_workspace(window)
  if not window.workspace then return false end
  for _, other in ipairs(hl.get_workspace_windows(tostring(window.workspace.id))) do
    for _, tag in ipairs(other.tags or {}) do
      if tag == "omarchy-floating-workspace" then return true end
    end
  end
  return false
end

-- A monitor's room for windows, clear of the bar: x, y, width, height.
local function usable_area(monitor)
  local reserved = monitor.reserved or {}
  local width = math.floor(monitor.width / monitor.scale)
  local height = math.floor(monitor.height / monitor.scale)
  return monitor.x + (reserved.left or 0), monitor.y + (reserved.top or 0),
    width - (reserved.left or 0) - (reserved.right or 0), height - (reserved.top or 0) - (reserved.bottom or 0)
end

local function settle_arrival(address)
  local window = hl.get_window("address:" .. address)
  if not window or (window.fullscreen or 0) ~= 0 then return end
  local monitor = window.monitor
  if not on_floating_workspace(window) or not monitor or not monitor.width then return end
  local _, _, width, height = usable_area(monitor)
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

-- Snapping, as in macOS and Windows: on a floating workspace, drag a window's
-- pointer to the left or right edge for that half of the screen, to a corner
-- for that quarter, or to the top edge to fill it. While the drag is over a
-- spot, a frosted outline shows where the window will go (drawn by the dock
-- plugin, when installed); letting go puts it there, with the gaps kept and
-- its title bar, which sits above its own area, on screen.
--
-- Hyprland tells nothing of a drag: the title bar plugin takes the button
-- before any bind sees it, and no event marks the start or the end. But a
-- dragged window moves exactly as the pointer does, which nothing else does.
-- So the active window is watched while on a floating workspace, and the
-- snap lands as Hyprland refocuses the window on release, or, should that
-- not come, as the pointer first moves on alone.
-- 0 turns snapping off (install.sh --set snapping=0).
local SNAPPING = 1
local SNAP_EDGE = 12
-- The ends of an edge that give a corner rather than a half, as a share of
-- the screen: thirds, so each corner is as easy to reach as the half between
-- them (KDE's default is a quarter, which proved hard to hit).
local SNAP_CORNER = 1 / 3
-- Along the top edge: the corners a quarter each, and its middle fifth (10% of
-- the screen either side of the centre) the strip of workspaces a window drops
-- onto; between them, fill.
local SNAP_TOP_CORNER = 1 / 4
local SPACES_BAND = 0.1
-- How often the active window and the pointer are checked, in milliseconds.
local SNAP_TICK = 40
local snap_shown = nil

-- The spot a drag is over. The pointer at an edge counts, and so, for the
-- sides, does the window's own edge reaching the screen's: a window held far
-- along its title bar is mostly past the edge before the pointer gets there.
local function snap_zone(cursor, monitor, window)
  local x, y, width, height = usable_area(monitor)
  local left = cursor.x <= x + SNAP_EDGE or window.at.x <= x
  local right = cursor.x >= x + width - SNAP_EDGE or window.at.x + window.size.x >= x + width
  -- The top edge is the bar's: the pointer stops on it.
  local top = cursor.y <= y + SNAP_EDGE
  local bottom = cursor.y >= y + height - SNAP_EDGE
  local upper = cursor.y <= y + height * SNAP_CORNER
  local lower = cursor.y >= y + height * (1 - SNAP_CORNER)
  if left or right then
    local side = left and "left" or "right"
    if upper then return "top-" .. side end
    if lower then return "bottom-" .. side end
    return side
  end
  if top then
    if math.abs(cursor.x - (x + width / 2)) <= width * SPACES_BAND then return "spaces" end
    if cursor.x <= x + width * SNAP_TOP_CORNER then return "top-left" end
    if cursor.x >= x + width * (1 - SNAP_TOP_CORNER) then return "top-right" end
    return "fill"
  end
  -- The bottom edge, the dock's, gives only its corners, reached from below
  -- as well as from the sides.
  if bottom then
    if cursor.x <= x + width * SNAP_CORNER then return "bottom-left" end
    if cursor.x >= x + width * (1 - SNAP_CORNER) then return "bottom-right" end
  end
  return nil
end

-- The spot a zone stands for, title bar included: x, y, width, height.
local function snap_cell(monitor, zone)
  local x, y, width, height = usable_area(monitor)
  local gap = hl.get_config("general.gaps_in")
  local edge = hl.get_config("general.gaps_out")
  gap = (type(gap) == "table" and gap.top or gap or 0) * 2
  edge = type(edge) == "table" and edge.top or edge or 0
  x, y, width, height = x + edge, y + edge, width - edge * 2, height - edge * 2
  local half_w, half_h = math.floor((width - gap) / 2), math.floor((height - gap) / 2)
  local cells = {
    fill = { x, y, width, height },
    left = { x, y, half_w, height },
    right = { x + width - half_w, y, half_w, height },
    ["top-left"] = { x, y, half_w, half_h },
    ["top-right"] = { x + width - half_w, y, half_w, half_h },
    ["bottom-left"] = { x, y + height - half_h, half_w, half_h },
    ["bottom-right"] = { x + width - half_w, y + height - half_h, half_w, half_h },
  }
  return cells[zone]
end

-- Snapped windows by address: the size each had before, and the size it
-- snapped to, so dragging it back out gives its own size back, as on macOS.
local snapped = {}
local SNAP_BAR = hl.plugin.hyprbars and BAR_HEIGHT or 0

-- Where a snapped window goes to make room when another snaps over part of
-- its spot, as in macOS and Windows: full screen gives way to the other half,
-- a half to the other quarter on its side. Missing pairs leave it be.
local SNAP_MAKE_ROOM = {
  fill = { left = "right", right = "left", ["top-left"] = "right", ["bottom-left"] = "right", ["top-right"] = "left", ["bottom-right"] = "left" },
  left = { ["top-left"] = "bottom-left", ["bottom-left"] = "top-left" },
  right = { ["top-right"] = "bottom-right", ["bottom-right"] = "top-right" },
}

local function snap(window, zone, others_stay)
  local cell = snap_cell(window.monitor, zone)
  local was = snapped[window.address]
  -- Snapping again from one spot to another keeps the size from before both.
  local own = was and { was.w, was.h } or { window.size.x, window.size.y }
  snapped[window.address] = { w = own[1], h = own[2], cw = cell[3], ch = cell[4] - SNAP_BAR, zone = zone }
  hl.dispatch(hl.dsp.window.resize({ x = cell[3], y = cell[4] - SNAP_BAR, relative = false, window = window }))
  hl.dispatch(hl.dsp.window.move({ x = cell[1], y = cell[2] + SNAP_BAR, window = window }))
  -- Apps such as the calculator settle on a size of their own near the one
  -- asked for; remember the size it took, so a drag still knows it as snapped.
  local address = window.address
  hl.timer(function()
    local now = hl.get_window("address:" .. address)
    local entry = snapped[address]
    if now and entry then entry.cw, entry.ch = now.size.x, now.size.y end
  end, { type = "oneshot", timeout = 250 })
  if others_stay or not window.workspace then return end
  -- Other windows still at their snapped size on this screen make room.
  for _, other in ipairs(hl.get_workspace_windows(tostring(window.workspace.id))) do
    local entry = snapped[other.address]
    local room = entry and SNAP_MAKE_ROOM[entry.zone] and SNAP_MAKE_ROOM[entry.zone][zone]
    if room and other.address ~= address and other.monitor and other.monitor.name == window.monitor.name
      and other.size.x == entry.cw and other.size.y == entry.ch then
      snap(other, room, true)
    end
  end
end

-- A drag of a snapped window, still at its snapped size, gives it back its own
-- size at once; the drop then centres it under the pointer by its title bar.
local function unsnap(window)
  local was = snapped[window.address]
  snapped[window.address] = nil
  if not was or window.size.x ~= was.cw or window.size.y ~= was.ch then return false end
  hl.dispatch(hl.dsp.window.resize({ x = was.w, y = was.h, relative = false, window = window }))
  return true
end


-- Shows the outline for a spot, or hides it with nil; only when it changes.
local function show_snap(window, zone)
  local key = zone and (window.monitor.name .. ":" .. zone) or nil
  if key == snap_shown then return end
  snap_shown = key
  local command = "omarchy-shell -q omarchy.dock snapHide"
  if zone then
    local cell = snap_cell(window.monitor, zone)
    command = string.format("omarchy-shell -q omarchy.dock snapShow %s %d %d %d %d", window.monitor.name, cell[1], cell[2], cell[3], cell[4])
  end
  hl.dispatch(hl.dsp.exec_cmd(command))
end

-- The last look at the active window and the pointer, and the drag, if one
-- is on: the spot it was over when last seen moving with the pointer.
local snap_seen = nil
local snap_drag = nil

-- The strip of workspaces a dragged window drops onto, as on macOS (drawn by
-- the switcher plugin, when installed): it opens as the drag reaches the
-- "spaces" spot, the top edge's middle (the whole top edge on a tiled
-- workspace, or with snapping off), stays open while the drag slides along
-- the top, and closes when it is pulled below STRIP_REACH of the screen.
-- Nearing the top within HINT_REACH, a faint outline shows where the spot is.
local STRIP_REACH = 0.2
local HINT_REACH = 0.15
-- Dropped onto a workspace, a window takes you along (1) or goes alone (0)
-- (install.sh --set drop-follow=<0|1>).
local DROP_FOLLOW = 1
local strip_file = io.open((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/omarchy/plugins/macos-theme.switcher/manifest.json", "r")
local STRIP = strip_file ~= nil
if strip_file then strip_file:close() end
local function drop_spaces(args)
  hl.dispatch(hl.dsp.exec_cmd("omarchy-shell -q macos-drop-spaces " .. args))
end

-- A drag over: no outline, no hint, no strip.
local function end_drag(drag)
  show_snap(nil, nil)
  if drag and (drag.strip or drag.hint) then drop_spaces("close") end
end

-- The drag in the strip's part of the screen: open it, keep it, or close it,
-- and say which workspace the pointer is over. True while the strip is open.
local function follow_strip(window, drag, cursor, zone)
  if not STRIP then return false end
  local monitor = window.monitor
  local height = math.floor(monitor.height / monitor.scale)
  local down = cursor.y - monitor.y
  if drag.strip and down > height * STRIP_REACH then
    -- Pulled back down: the strip closes and the drag goes on.
    drag.strip = false
    drag.hint = false
    drop_spaces("close")
  elseif not drag.strip and zone == "spaces" then
    drag.strip = true
    drop_spaces("open " .. monitor.name)
  end
  if drag.strip then
    drop_spaces(string.format("hover %d", math.floor(cursor.x - monitor.x)))
    return true
  end
  local hint = down <= height * HINT_REACH
  if hint ~= (drag.hint or false) then
    drag.hint = hint
    drop_spaces(hint and ("hint " .. monitor.name) or "close")
  end
  return false
end

-- Let go: into the spot the drag was over, onto a workspace in the strip, or,
-- for a window unsnapped on the way, under the pointer.
local function drop(window, drag, cursor)
  if drag.strip then
    -- The drop closes the strip itself: closing it first would empty it
    -- before the drop asks which workspace the pointer was over.
    show_snap(nil, nil)
    -- Back where the drag began, then onto the workspace it was dropped on
    -- (or left there, dropped on none). A tiled window goes back into its
    -- layout by itself.
    if drag.floating then
      hl.dispatch(hl.dsp.window.move({ x = drag.from.x, y = drag.from.y, window = window }))
    end
    drop_spaces(string.format("drop %s %d %s", window.address, math.floor(cursor.x - window.monitor.x), DROP_FOLLOW == 1 and "true" or "false"))
    return
  end
  end_drag(drag)
  if drag.zone then
    snap(window, drag.zone)
  elseif drag.unsnapped then
    hl.dispatch(hl.dsp.window.move({
      x = math.floor(cursor.x - window.size.x / 2),
      y = math.floor(cursor.y + SNAP_BAR / 2),
      window = window,
    }))
  end
end

-- A floating window's title bar is its only handle: one moved above the
-- screen (opened too high, or moved by an app or a script) could never be
-- dragged back. So a floating window keeps its title bar below the bar and
-- above the bottom, with REACHABLE of it on screen sideways; it slides back
-- as little as that takes. Checked on the active window while it is not
-- dragged, so one stuck off screen comes back as soon as it is clicked.
local REACHABLE = 120
local function keep_reachable(window)
  if not window.floating or (window.fullscreen or 0) ~= 0 or not window.monitor or not window.monitor.width then return end
  local x, y, width, height = usable_area(window.monitor)
  local bar = hl.plugin.hyprbars and BAR_HEIGHT or 0
  local nx = math.max(x + REACHABLE - window.size.x, math.min(window.at.x, x + width - REACHABLE))
  local ny = math.max(y + bar, math.min(window.at.y, y + height - REACHABLE + bar))
  if nx ~= window.at.x or ny ~= window.at.y then
    hl.dispatch(hl.dsp.window.move({ x = math.floor(nx), y = math.floor(ny), window = window }))
  end
end

local function snap_tick()
  local window = hl.get_active_window()
  local cursor = hl.get_cursor_pos()
  local seen = snap_seen
  snap_seen = nil
  -- Floating windows on a floating workspace snap; any other window can
  -- only be dropped onto another workspace (and is still watched, to keep
  -- its title bar in reach).
  if window and (window.fullscreen or 0) == 0 and window.monitor then
    local floating = window.floating and on_floating_workspace(window) and SNAPPING == 1
    snap_seen = { address = window.address, x = window.at.x, y = window.at.y, w = window.size.x, h = window.size.y,
                  cx = cursor.x, cy = cursor.y, floating = floating }
  end
  local now = snap_seen
  if seen and now and seen.address == now.address and snap_drag and snap_drag.unsnapped and not snap_drag.resized then
    -- The unsnap's own resize: the drag goes on.
    snap_drag.resized = true
  elseif not (seen and now and seen.address == now.address and seen.w == now.w and seen.h == now.h) then
    -- Another window, a resize, or none: no drag to follow. A tiled window
    -- let go over the strip is resized back into its layout: that is the drop.
    local drag = snap_drag
    snap_drag = nil
    local dragged = drag and drag.strip and seen and hl.get_window("address:" .. seen.address)
    if dragged then
      drop(dragged, drag, cursor)
    elseif drag then
      end_drag(drag)
    end
  else
    local wx, wy = now.x - seen.x, now.y - seen.y
    local cx, cy = now.cx - seen.cx, now.cy - seen.cy
    local moved = wx ~= 0 or wy ~= 0
    if moved and math.abs(wx - cx) <= 2 and math.abs(wy - cy) <= 2 then
      -- Moving with the pointer: dragged. Show the spot it is over.
      if not snap_drag then
        snap_drag = { floating = now.floating, from = { x = seen.x, y = seen.y } }
        if now.floating then snap_drag.unsnapped = unsnap(window) end
      end
      snap_drag.alone = 0
      local zone
      if snap_drag.floating then
        zone = snap_zone(cursor, window.monitor, window)
      else
        -- Not snapping: the whole top edge is the strip's.
        local _, top = usable_area(window.monitor)
        zone = cursor.y <= top + SNAP_EDGE and "spaces" or nil
      end
      if follow_strip(window, snap_drag, cursor, zone) then
        snap_drag.zone = nil
        show_snap(nil, nil)
      else
        -- Without the strip, the top edge's middle is just more of fill.
        if zone == "spaces" then zone = snap_drag.floating and "fill" or nil end
        snap_drag.zone = snap_drag.floating and zone or nil
        show_snap(window, snap_drag.zone)
      end
    elseif snap_drag and not moved and (cx ~= 0 or cy ~= 0) and (snap_drag.alone or 0) < 1 then
      -- The pointer moved alone once; a second time means it was let go.
      snap_drag.alone = (snap_drag.alone or 0) + 1
    elseif snap_drag and not moved and (cx ~= 0 or cy ~= 0) then
      -- The pointer moves on alone: let go where the drag last was.
      local drag = snap_drag
      snap_drag = nil
      drop(window, drag, cursor)
    elseif snap_drag and moved then
      -- Moved some other way, by a key or a script.
      end_drag(snap_drag)
      snap_drag = nil
    end
  end
  -- Still, and no drag on: keep its title bar in reach.
  if window and not snap_drag and seen and seen.address == window.address and seen.x == window.at.x and seen.y == window.at.y then
    keep_reachable(window)
  end
  hl.timer(snap_tick, { type = "oneshot", timeout = SNAP_TICK })
end

hl.timer(snap_tick, { type = "oneshot", timeout = SNAP_TICK })

-- Letting go of a drag refocuses the window, which Hyprland reports even
-- though it already had focus: that is the release, so snap right away.
hl.on("window.active", function(window)
  if not snap_drag or not window or not snap_seen or window.address ~= snap_seen.address then return end
  local drag = snap_drag
  snap_drag = nil
  local current = hl.get_window("address:" .. window.address)
  if current then drop(current, drag, hl.get_cursor_pos()) end
end)

-- A closed window's snap is forgotten.
hl.on("window.destroy", function(window)
  -- A closing window can come without its address.
  if window and window.address then snapped[window.address] = nil end
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

-- Alt+Tab opens the macOS app switcher, Super+Tab the workspace switcher and
-- Ctrl+Up Mission Control when the plugin is installed: Tab and Shift+Tab move while the modifier is
-- held, letting go of it switches.
local switcher = io.open((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/omarchy/plugins/macos-theme.switcher/manifest.json", "r")
if switcher then
  switcher:close()
  o.rebind("ALT + TAB", "App switcher", "omarchy-shell -q macos-switcher next")
  o.rebind("ALT + SHIFT + TAB", "App switcher (previous)", "omarchy-shell -q macos-switcher prev")
  o.rebind("SUPER + TAB", "Workspace switcher", "omarchy-shell -q macos-spaces next")
  o.rebind("SUPER + SHIFT + TAB", "Workspace switcher (previous)", "omarchy-shell -q macos-spaces prev")
  -- Ctrl+Up opens Mission Control, as on macOS.
  o.rebind("CTRL + UP", "Mission Control", "omarchy-shell -q macos-mission-control toggle")
end
