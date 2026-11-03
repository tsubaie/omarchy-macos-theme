// What Hyprland shows, for the workspace switcher, Mission Control and the
// workspaces a dragged window drops onto: one query, read one way.

// Clients, monitors, workspaces, the active workspace and the wallpaper, a
// line of @@ apart.
var COMMAND = ["sh", "-c", "hyprctl clients -j; echo; echo @@; hyprctl monitors -j; echo; echo @@; "
  + "hyprctl workspaces -j; echo; echo @@; hyprctl activeworkspace -j; echo; echo @@; "
  + "readlink -f \"$HOME/.local/state/omarchy/current/background\""]

// COMMAND's output as { clients, monitors, workspaces, active, wallpaper };
// a part that doesn't parse is empty.
function parse(text) {
  var parts = String(text || "").split("\n@@\n")
  function json(i, empty) {
    try { return JSON.parse(parts[i]) } catch (e) { return empty }
  }
  return { clients: json(0, []), monitors: json(1, []), workspaces: json(2, []), active: json(3, {}),
           wallpaper: String(parts[4] || "").trim() }
}

// A window on screen on a regular workspace.
function seen(client) {
  return !!client && client.mapped && !client.hidden && !!client.workspace && client.workspace.id > 0
}

// The live window behind a Hyprland address, for a screen copy; toplevels is
// Hyprland.toplevels.values.
function toplevelFor(address, toplevels) {
  var want = String(address || "").replace(/^0x/, "")
  for (var i = 0; i < (toplevels || []).length; i++) {
    if (String(toplevels[i].address || "").replace(/^0x/, "") === want) return toplevels[i].wayland
  }
  return null
}

// Where the workspace switcher opens, in spaces ordered current first, then
// most recent: on the one before the current, as Alt+Tab does with apps. On an
// empty workspace, which isn't in the list, that is the first one.
function startIndex(spaces, activeId, direction) {
  if (!spaces || spaces.length === 0) return 0
  if (direction < 0) return spaces.length - 1
  return spaces[0].id === activeId && spaces.length > 1 ? 1 : 0
}

if (typeof module !== "undefined") {
  module.exports = { COMMAND: COMMAND, parse: parse, seen: seen, toplevelFor: toplevelFor, startIndex: startIndex }
}
