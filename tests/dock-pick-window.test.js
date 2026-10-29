// Which window a click on a dock icon brings forward. Run with: node tests/dock-pick-window.test.js
const assert = require("assert")
const { pickWindow } = require("../plugins/macos-theme.dock/DockModel.js")

// Minimized on workspace 5 while still reporting itself active; others on 3 and 4.
const windows = [
  { workspaceId: 3, minimized: false, activated: false },
  { workspaceId: -99, minimized: true, activated: true },
  { workspaceId: 4, minimized: false, activated: false },
]
assert.strictEqual(pickWindow(windows, 5), 1, "the minimized window comes back first")

// A window in front on this workspace: the click moves on to the next one.
assert.strictEqual(pickWindow([
  { workspaceId: 5, minimized: false, activated: true },
  { workspaceId: 3, minimized: false, activated: false },
], 5), 1)

console.log("dock pick window: ok")
