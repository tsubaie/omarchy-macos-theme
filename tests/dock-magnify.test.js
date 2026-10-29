// Dock magnification math. Run with: node tests/dock-magnify.test.js
const assert = require("assert")
const m = require("../plugins/macos-theme.dock/DockModel.js")

const range = 180, peak = 1.75, slot = 72

assert.strictEqual(m.magnifyScale(0, range, peak), peak)
assert.strictEqual(m.magnifyScale(range, range, peak), 1)
assert.strictEqual(m.magnifyScale(-500, range, peak), 1)
assert.strictEqual(m.magnifyShift(0, range, peak), 0)
// The dock grows evenly on both sides of the pointer.
assert.ok(Math.abs(m.magnifyShift(-500, range, peak) + m.magnifyShift(500, range, peak)) < 1e-9)

// Neighboring icons never overlap by more than a sliver, wherever the pointer is.
for (let pointer = -100; pointer <= 800; pointer += 7) {
  for (let i = 0; i < 10; i++) {
    const a = i * slot + slot / 2 - pointer, b = a + slot
    const aEnd = a + m.magnifyShift(a, range, peak) + slot * m.magnifyScale(a, range, peak) / 2
    const bStart = b + m.magnifyShift(b, range, peak) - slot * m.magnifyScale(b, range, peak) / 2
    assert.ok(bStart - aEnd > -0.06 * slot, `icons ${i} and ${i + 1} overlap with the pointer at ${pointer}`)
  }
}

console.log("dock magnification: ok")
