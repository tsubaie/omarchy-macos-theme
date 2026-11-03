// Changes waiting that the desktop has anyway. Run with: node tests/pending.test.js
const assert = require("assert")
const m = require("../qml/Pending.js")

const now = {
  installed: (piece) => piece === "dock",
  setting: (key) => ({ magnification: 1.5 })[key],
  place: () => "bottom",
  bar: { left: ["menu"], center: [], right: [], hidden: [] },
  widgets: ["clock"],
}
const pending = {
  // The dock turned on outside Studio; the lock still to come.
  pieces: { dock: true, lock: true },
  // Magnification set to the same outside; blur not reported by an older theme.
  settings: { magnification: 1.502, blur: 5 },
  places: { "volume-hud": "bottom", "dictation-hud": "top" },
  bar: { left: ["menu"], center: [], right: [], hidden: [] },
  // The weather removed on the desktop, as marked here.
  widgets: ["clock"],
}

assert.deepStrictEqual(m.forgetMet(pending, now), {
  pieces: { lock: true },
  settings: { blur: 5 },
  places: { "dictation-hud": "top" },
  bar: null,
  widgets: null,
})

// Nothing met: the very same objects back, so QML sees no change.
const waiting = { pieces: { lock: true }, settings: { blur: 5 }, places: {}, bar: null, widgets: ["calendar"] }
const left = m.forgetMet(waiting, now)
assert.strictEqual(left.pieces, waiting.pieces)
assert.strictEqual(left.settings, waiting.settings)
assert.strictEqual(left.places, waiting.places)
assert.strictEqual(left.bar, null)
assert.strictEqual(left.widgets, waiting.widgets)

console.log("pending: ok")
