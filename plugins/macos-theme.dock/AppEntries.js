// Which app a window belongs to, by its desktop entry. The dock and the app
// switcher each carry this same file, so they name and draw every app alike;
// tests/app-entries.test.js checks the two copies match.

// A terminal app's window carries the app id its launcher gave the terminal,
// which no desktop entry names as its class. The entry that passes that app id
// claims it, and so does a terminal entry for the command Omarchy's TUI
// launcher named it after (org.omarchy.nvim for nvim). Entries are
// { id, execString, command, runInTerminal }.
function claimingEntryId(appId, entries) {
  var id = String(appId || "")
  if (!id) return ""
  var list = entries || []
  var flag = "--app-id=" + id
  for (var i = 0; i < list.length; i++) {
    var words = String(list[i].execString || "").split(/\s+/)
    if (words.indexOf(flag) >= 0) return list[i].id
  }
  if (id.indexOf("org.omarchy.") !== 0) return ""
  var command = id.slice("org.omarchy.".length)
  for (var j = 0; j < list.length; j++) {
    var program = String((list[j].command || [])[0] || "")
    if (list[j].runInTerminal && program.slice(program.lastIndexOf("/") + 1) === command) return list[j].id
  }
  return ""
}

// The entries that can claim a terminal app's window: those run in a
// terminal, and those that hand the terminal an app id of their own.
function terminalEntries(values) {
  var out = []
  for (var i = 0; i < (values || []).length; i++) {
    var entry = values[i]
    if (entry.runInTerminal || String(entry.execString || "").indexOf("--app-id=") >= 0)
      out.push({ id: entry.id, execString: entry.execString, command: entry.command, runInTerminal: entry.runInTerminal })
  }
  return out
}

// A window with no app id can still name its app in its title, as in
// "Untitled 1 — RusTXT": the longest app name the title ends with.
function entryForTitle(title, values) {
  title = String(title || "")
  if (!title) return null
  var best = null
  for (var i = 0; i < (values || []).length; i++) {
    var name = String(values[i].name || "")
    if (name.length < 3 || values[i].noDisplay) continue
    var at = title.length - name.length
    var bounded = at === 0 || /[\s\-—–|:·]/.test(title.charAt(at - 1))
    if (at >= 0 && title.substr(at) === name && bounded && (!best || name.length > best.name.length)) best = values[i]
  }
  return best
}

// The entry for a window, or null. apps is Quickshell's DesktopEntries (or
// anything with heuristicLookup, byId and applications.values); terminals is
// terminalEntries() of its entries.
function entryFor(appId, title, apps, terminals) {
  if (!appId) return entryForTitle(title, apps.applications.values)
  var entry = apps.heuristicLookup(appId)
  if (entry) return entry
  var id = claimingEntryId(appId, terminals)
  return id ? apps.byId(id) : null
}

if (typeof module !== "undefined") {
  module.exports = { claimingEntryId: claimingEntryId, terminalEntries: terminalEntries, entryForTitle: entryForTitle, entryFor: entryFor }
}
