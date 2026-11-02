// The menu bar's three groups. Run with: node tests/bar-model.test.js
const assert = require("assert")
const m = require("../qml/BarModel.js")

const item = (id, extra) => ({ id, name: id, ...extra })
const bar = {
  sections: {
    left: [item("menu"), item("workspaces")],
    centerBegin: [item("indicators")],
    center: [item("clock")],
    centerEnd: [item("weather")],
    right: [item("tray", { drawer: true }), item("keyboard"), item("control")],
    tray: [item("network"), item("audio")],
  },
  hidden: [item("media")],
}

// Center joins the middle sections; Right shows the drawer's items in the
// tray's place, and not the tray itself.
const g = m.groups(bar)
assert.deepStrictEqual(g, {
  left: ["menu", "workspaces"],
  center: ["indicators", "clock", "weather"],
  right: ["network", "audio", "keyboard", "control"],
  hidden: ["media"],
})

// Nothing changed: every section stays exactly as it was.
assert.deepStrictEqual(m.layout(bar, g), {
  sections: { left: ["menu", "workspaces"], centerBegin: ["indicators"], center: ["clock"], centerEnd: ["weather"], right: ["tray", "keyboard", "control"], tray: ["network", "audio"] },
  hidden: ["media"],
})

// Moving within a group: down past the next one, and dropping just below
// itself leaves it in place.
assert.deepStrictEqual(m.move(g, "menu", "left", 2).left, ["workspaces", "menu"])
assert.deepStrictEqual(m.move(g, "menu", "left", 1).left, ["menu", "workspaces"])
assert.deepStrictEqual(m.move(g, "workspaces", "left", 0).left, ["workspaces", "menu"])
assert.deepStrictEqual(m.move(g, "clock", "center", 0).center, ["clock", "indicators", "weather"])

// The clock to the right: center becomes one section, the right side gets the
// tray first and the drawer is emptied onto the bar; left is untouched.
const moved = m.move(g, "clock", "right", 4)
assert.deepStrictEqual(moved.center, ["indicators", "weather"])
assert.deepStrictEqual(moved.right, ["network", "audio", "keyboard", "control", "clock"])
assert.deepStrictEqual(m.layout(bar, moved).sections, {
  left: ["menu", "workspaces"], centerBegin: [], center: ["indicators", "weather"], centerEnd: [],
  right: ["tray", "network", "audio", "keyboard", "control", "clock"], tray: [],
})

// Hiding and showing.
const hidden = m.move(g, "weather", "hidden", 99)
assert.deepStrictEqual(hidden.hidden, ["media", "weather"])
assert.deepStrictEqual(m.layout(bar, hidden).hidden, ["media", "weather"])
assert.deepStrictEqual(m.move(g, "media", "left", 1), { left: ["menu", "media", "workspaces"], center: g.center, right: g.right, hidden: [] })

// Every move keeps each item exactly once.
const all = (x) => [...x.left, ...x.center, ...x.right, ...x.hidden].sort()
for (const id of all(g)) for (const group of ["left", "center", "right", "hidden"]) for (let i = 0; i <= 5; i++) {
  assert.deepStrictEqual(all(m.move(g, id, group, i)), all(g), `${id} to ${group} ${i}`)
}
// An unknown group changes nothing.
assert.deepStrictEqual(m.move(g, "clock", "middle", 0), g)
// No tray on the bar: the drawer's items join the end of the right side.
const noTray = { sections: { right: [item("a")], tray: [item("b")] }, hidden: [] }
assert.deepStrictEqual(m.groups(noTray).right, ["a", "b"])

// The keyboard's one place up or down: within a group, across into the next
// at its edge, and nowhere past the very ends.
const k = { left: ["a", "b"], center: ["c"], right: [], hidden: ["d"] }
assert.deepStrictEqual(m.nudge(k, "a", 1).left, ["b", "a"])
assert.deepStrictEqual(m.nudge(k, "b", -1).left, ["b", "a"])
assert.deepStrictEqual(m.nudge(k, "b", 1), { left: ["a"], center: ["b", "c"], right: [], hidden: ["d"] })
assert.deepStrictEqual(m.nudge(k, "c", -1), { left: ["a", "b", "c"], center: [], right: [], hidden: ["d"] })
assert.deepStrictEqual(m.nudge(k, "c", 1), { left: ["a", "b"], center: [], right: ["c"], hidden: ["d"] })
assert.deepStrictEqual(m.nudge(k, "a", -1), k)
assert.deepStrictEqual(m.nudge(k, "d", 1), k)

console.log("bar model: ok")
