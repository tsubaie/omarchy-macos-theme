// Which app a window belongs to, shared by the dock and the app switcher.
// Run with: node tests/app-entries.test.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")

const dockCopy = path.join(__dirname, "../plugins/macos-theme.dock/AppEntries.js")
const switcherCopy = path.join(__dirname, "../plugins/macos-theme.switcher/AppEntries.js")
// Each plugin installs on its own, so each carries the file; they must not drift apart.
assert.strictEqual(fs.readFileSync(switcherCopy, "utf8"), fs.readFileSync(dockCopy, "utf8"),
  "plugins/macos-theme.switcher/AppEntries.js differs from the dock's copy; copy the dock's over it")
const { entryFor, terminalEntries } = require(dockCopy)

const values = [
  { id: "org.gnome.Nautilus", name: "Files" },
  { id: "nvim", name: "Neovim", runInTerminal: true, command: ["/usr/bin/nvim"] },
  { id: "btop-tui", name: "Btop", execString: "ghostty --app-id=TUI.btop -e btop" },
  { id: "rustxt", name: "RusTXT" },
  { id: "hidden-thing", name: "Thing", noDisplay: true },
]
const apps = {
  applications: { values },
  byId: (id) => values.find((v) => v.id === id) || null,
  heuristicLookup: (id) => values.find((v) => v.id.toLowerCase() === String(id).toLowerCase()) || null,
}
const terminals = terminalEntries(values)
const named = (appId, title) => (entryFor(appId, title, apps, terminals) || {}).id || null

assert.deepStrictEqual(terminals.map((t) => t.id), ["nvim", "btop-tui"])
assert.strictEqual(named("org.gnome.Nautilus", "Home"), "org.gnome.Nautilus", "a class an entry names")
assert.strictEqual(named("org.omarchy.nvim", "notes.md"), "nvim", "Omarchy's TUI launcher's app id")
assert.strictEqual(named("TUI.btop", ""), "btop-tui", "an app id the entry hands its terminal")
assert.strictEqual(named("something.else", "x"), null)
assert.strictEqual(named("", "Untitled 1 — RusTXT"), "rustxt", "no app id: the app named at the end of the title")
assert.strictEqual(named("", "My RusTXTs"), null, "only a whole name at the very end")
assert.strictEqual(named("", "Some Thing"), null, "never a hidden entry")
assert.strictEqual(named("", ""), null)

console.log("app entries: ok")
