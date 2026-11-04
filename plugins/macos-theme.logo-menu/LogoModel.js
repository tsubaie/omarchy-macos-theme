// The logo menu's logic, kept out of QML so node can test it:
// node tests/logo-menu.test.js

// The menu, as macOS's Apple menu has it: groups split by lines (null), each
// item a label, a key shortcut to show (not handled here; the menu only
// names it) and what it runs. Restart, Shut Down and Log Out ask first.
var ITEMS = [
  { id: "about", label: "About This Computer" },
  null,
  { id: "settings", label: "System Settings…", run: "omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'" },
  { id: "store", label: "App Store…", run: "xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-install" },
  null,
  // Force Quit: click the app's window; with ⌥, the list of apps instead
  // (for one that can't be clicked).
  { id: "forcequit", label: "Force Quit…", shortcut: "⇧⌥⌘⎋", altLabel: "Force Quit Applications…", altShortcut: "⌥⌘⎋" },
  null,
  { id: "sleep", label: "Sleep", run: "systemctl suspend" },
  { id: "restart", label: "Restart…", run: "omarchy system reboot", ask: "Restart now? Apps are closed first; unsaved work may be lost." },
  { id: "shutdown", label: "Shut Down…", run: "omarchy system shutdown", ask: "Shut down now? Apps are closed first; unsaved work may be lost." },
  null,
  // Shortcuts as they really are here: Omarchy's lock is Super+Ctrl+L, and
  // nothing logs out from the keyboard.
  { id: "lock", label: "Lock Screen", shortcut: "⌃⌘L", run: "omarchy-system-lock" },
  { id: "logout", label: "Log Out…", run: "omarchy system logout", ask: "Log out now? Apps are closed first; unsaved work may be lost." }
]

// The items alone, in order: what the arrow keys move through.
function choosable() {
  return ITEMS.filter(function(item) { return item !== null })
}

// The logos to choose from, never Apple's: the Omarchy mark (the default)
// and a few plain glyphs, drawn in the bar's text color.
var LOGOS = [
  { id: "omarchy", name: "Omarchy", glyph: "", font: "omarchy" },
  { id: "arch", name: "Arch", glyph: "" },
  { id: "command", name: "Command", glyph: "⌘" },
  { id: "circle", name: "Circle", glyph: "●" },
  { id: "hexagon", name: "Hexagon", glyph: "⬢", font: "Noto Sans Symbols 2" },
  { id: "terminal", name: "Terminal", glyph: "" }
]

function logo(id) {
  for (var i = 0; i < LOGOS.length; i++) if (LOGOS[i].id === id) return LOGOS[i]
  return LOGOS[0]
}

// Windows that are the desktop itself, never offered to quit: the shell
// (Quickshell), its bar and panels, and Hyprland's own.
var KEEP = /^(quickshell|org\.quickshell|qs|hyprland|xdg-desktop-portal.*)$/i

// The running apps from `hyprctl clients -j`: one per app (its class), with
// its name, its windows' addresses and the processes behind them, in the
// order they were last used. shellPid: the shell's own, left out too.
function apps(clients, shellPid) {
  var list = Array.isArray(clients) ? clients : []
  var byClass = {}
  var order = []
  list.slice().sort(function(a, b) { return (a.focusHistoryID || 0) - (b.focusHistoryID || 0) })
    .forEach(function(c) {
      var cls = String(c["class"] || c.initialClass || "")
      if (!cls || KEEP.test(cls) || (shellPid && c.pid === shellPid) || !(c.pid > 0)) return
      if (!byClass[cls]) { byClass[cls] = { id: cls, name: String(c.title && !c["class"] ? c.title : nameOf(cls)), addresses: [], pids: [] }; order.push(cls) }
      var app = byClass[cls]
      app.addresses.push(String(c.address))
      if (app.pids.indexOf(c.pid) < 0) app.pids.push(c.pid)
    })
  return order.map(function(cls) { return byClass[cls] })
}

// The window at a point of the desktop (Hyprland's layout coordinates), for
// Force Quit by Clicking: of the windows shown on the screens' workspaces,
// the one on top there (a special workspace's, then fullscreen, then
// floating, then tiled; among equals the last used); never the desktop's own.
function windowAt(clients, monitors, x, y) {
  var shown = {}
  ;(Array.isArray(monitors) ? monitors : []).forEach(function(m) {
    if (m.activeWorkspace) shown[m.activeWorkspace.id] = true
    if (m.specialWorkspace && m.specialWorkspace.id) shown[m.specialWorkspace.id] = true
  })
  function rank(c) { return c.workspace.id < 0 ? 0 : c.fullscreen ? 1 : c.floating ? 2 : 3 }
  var hits = (Array.isArray(clients) ? clients : []).filter(function(c) {
    return c.workspace && shown[c.workspace.id] && c.mapped !== false && !c.hidden && c.pid > 0
      && !KEEP.test(String(c["class"] || "")) && Array.isArray(c.at) && Array.isArray(c.size)
      && x >= c.at[0] && x < c.at[0] + c.size[0] && y >= c.at[1] && y < c.at[1] + c.size[1]
  })
  hits.sort(function(a, b) { return rank(a) - rank(b) || (a.focusHistoryID || 0) - (b.focusHistoryID || 0) })
  return hits[0] || null
}

// "org.gnome.Nautilus" as Nautilus, "firefox" as Firefox.
function nameOf(cls) {
  var last = String(cls).split(".").pop()
  return last.charAt(0).toUpperCase() + last.slice(1)
}

// The chip as About This Mac names it: lscpu's model, without its trademark
// marks, its "with … Graphics" and its clock speed.
function chipName(raw) {
  return String(raw || "").replace(/\((R|TM)\)/gi, "").replace(/\s+with\s+.*$/i, "")
    .replace(/\s+CPU\b.*$/i, "").replace(/\s+\d+-Core Processor$/i, "").replace(/\s+/g, " ").trim()
}

// The graphics as About This Mac names them: lspci's line as the maker and
// the card's own name in brackets ("NVIDIA GeForce RTX 5060"), else the line
// without its revision.
function gpuName(raw) {
  var line = String(raw || "").replace(/\s*\(rev [0-9a-f]+\)\s*$/i, "").trim()
  var named = /\[([^\]\/]+)\]\s*$/.exec(line)
  var maker = /^(NVIDIA|Intel|AMD|Advanced Micro Devices)/i.exec(line)
  var vendor = maker ? (/^Advanced/i.test(maker[1]) ? "AMD" : maker[1].replace(/^nvidia$/i, "NVIDIA")) : ""
  if (named) return (vendor && named[1].indexOf(vendor) !== 0 ? vendor + " " : "") + named[1].trim()
  return line.replace(/\s+Corporation\b/i, "")
}

if (typeof module !== "undefined") module.exports = { ITEMS: ITEMS, choosable: choosable, LOGOS: LOGOS, logo: logo, apps: apps, windowAt: windowAt, nameOf: nameOf, chipName: chipName, gpuName: gpuName }
