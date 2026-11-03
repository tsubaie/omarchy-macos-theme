// The dock's pins and order, which a drag writes back to the pinned apps
// (omarchy-dock pinned). Run with: node tests/dock-model.test.js
const assert = require("assert")
const { buildItems, orderItems, orderWithKeyAt, pinsInOrder } = require("../plugins/macos-theme.dock/DockModel.js")

const win = (key, extra) => Object.assign({ key, hasEntry: true, workspaceId: 1 }, extra)

// Pinned apps first in pin order, running or not; running ones after, in the order their first window came.
const items = buildItems(["files", "browser", "notes"], [win("terminal"), win("browser"), win("terminal"), win("music")])
assert.deepStrictEqual(items.map((i) => [i.key, i.pinned, i.windows.length]),
  [["files", true, 0], ["browser", true, 1], ["notes", true, 0], ["terminal", false, 2], ["music", false, 1]])
// Helpers with no visible entry and scratchpad windows stay out; a minimized window always shows.
assert.deepStrictEqual(buildItems([], [win("agent", { hasEntry: false }), win("pad", { workspaceId: -98 }),
  win("gone", { minimized: true, hasEntry: false, workspaceId: -99 })]).map((i) => i.key), ["gone"])

// The session's order wins; apps it doesn't know follow.
assert.deepStrictEqual(orderItems(items, ["notes", "files"]).map((i) => i.key), ["notes", "files", "browser", "terminal", "music"])

// Dragging "notes" to the front: every pin is kept, in the new order, and a
// pin the dock isn't showing (its app isn't installed) stays at the end.
const shown = ["files", "browser", "notes"]
const order = orderWithKeyAt(shown, "notes", 0)
assert.deepStrictEqual(order, ["notes", "files", "browser"])
const pinned = { files: true, browser: true, notes: true }
const allPinned = ["files", "uninstalled", "browser", "notes"]
assert.deepStrictEqual(pinsInOrder(order, pinned, allPinned), ["notes", "files", "browser", "uninstalled"])
// Dragged past the end, it lands last; nothing is lost or doubled.
assert.deepStrictEqual(pinsInOrder(orderWithKeyAt(shown, "files", 99), pinned, allPinned), ["browser", "notes", "files", "uninstalled"])
// A running app in the order that isn't pinned is never saved as a pin.
assert.deepStrictEqual(pinsInOrder(["terminal", "files", "browser", "notes"], pinned, allPinned), ["files", "browser", "notes", "uninstalled"])

console.log("dock model: ok")
