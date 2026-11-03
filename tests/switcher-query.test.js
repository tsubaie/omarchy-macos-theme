// What the workspace switcher, Mission Control and the drop strip read from
// Hyprland. Run with: node tests/switcher-query.test.js
const assert = require("assert")
const { parse, seen, toplevelFor, startIndex } = require("../plugins/macos-theme.switcher/HyprQuery.js")

const out = [
  JSON.stringify([{ address: "0xa1", mapped: true, workspace: { id: 2 } }]),
  JSON.stringify([{ id: 0, name: "DP-1" }]),
  JSON.stringify([{ id: 2 }, { id: 3 }]),
  JSON.stringify({ id: 3 }),
  "/home/me/wall.jpg\n",
].join("\n@@\n")
const got = parse(out)
assert.strictEqual(got.clients[0].address, "0xa1")
assert.strictEqual(got.monitors[0].name, "DP-1")
assert.strictEqual(got.workspaces.length, 2)
assert.strictEqual(got.active.id, 3)
assert.strictEqual(got.wallpaper, "/home/me/wall.jpg")
// Cut short (a query that failed): what parses is kept, the rest is empty.
assert.deepStrictEqual(parse("[]\n@@\n{not json"), { clients: [], monitors: [], workspaces: [], active: {}, wallpaper: "" })

assert.strictEqual(seen({ mapped: true, workspace: { id: 1 } }), true)
assert.strictEqual(seen({ mapped: true, hidden: true, workspace: { id: 1 } }), false)
assert.strictEqual(seen({ mapped: true, workspace: { id: -98 } }), false, "special workspaces")
assert.strictEqual(seen({ mapped: false, workspace: { id: 1 } }), false)

const live = { wayland: "the window" }
assert.strictEqual(toplevelFor("0xabc", [{ address: "abc", wayland: "the window" }]), live.wayland)
assert.strictEqual(toplevelFor("abc", [{ address: "0xabc", wayland: "the window" }]), live.wayland)
assert.strictEqual(toplevelFor("0xdef", [{ address: "abc" }]), null)

// Super+Tab on workspace 3, from 2 (and 1 before): it opens on 2.
const spaces = (...ids) => ids.map((id) => ({ id }))
assert.strictEqual(startIndex(spaces(3, 2, 1), 3, 1), 1)
// On an empty workspace 3, which has no windows and so isn't listed: still 2, not 1.
assert.strictEqual(startIndex(spaces(2, 1), 3, 1), 0)
assert.strictEqual(startIndex(spaces(3), 3, 1), 0)
assert.strictEqual(startIndex(spaces(3, 2, 1), 3, -1), 2, "Shift: the oldest")
assert.strictEqual(startIndex([], 3, 1), 0)

console.log("switcher query: ok")
