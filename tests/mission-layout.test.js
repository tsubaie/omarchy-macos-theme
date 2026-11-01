// Mission Control's spread. Run with: node tests/mission-layout.test.js
const assert = require("assert")
const { spread } = require("../plugins/macos-theme.switcher/MissionLayout.js")

const overlap = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
const check = (wins, W, H, gap) => {
  const out = spread(wins, W, H, gap)
  assert.strictEqual(out.length, wins.length)
  out.forEach((r, i) => {
    // Inside the area, never larger than the window, its proportions kept.
    assert.ok(r.x >= 0 && r.y >= 0 && r.x + r.w <= W + 1 && r.y + r.h <= H + 1, JSON.stringify(r))
    assert.ok(r.w <= wins[i].w && r.h <= wins[i].h)
    assert.ok(Math.abs(r.w / r.h - wins[i].w / wins[i].h) < 0.05)
    out.forEach((o, j) => { if (j > i) assert.ok(!overlap(r, o), `${i} and ${j} overlap`) })
  })
  return out
}

assert.deepStrictEqual(spread([], 1000, 800, 20), [])

// One small window stays its size, centered.
let out = check([{ x: 0, y: 0, w: 400, h: 300 }], 1000, 800, 20)
assert.deepStrictEqual(out[0], { x: 300, y: 250, w: 400, h: 300 })

// Two big side-by-side windows stay side by side, left one on the left.
out = check([{ x: 1700, y: 40, w: 1700, h: 1300 }, { x: 10, y: 40, w: 1680, h: 1300 }], 3000, 1100, 40)
assert.ok(out[1].x < out[0].x)
assert.ok(Math.abs(out[0].y - out[1].y) <= 1)

// Many windows: a grid with nothing overlapping, the short last row centered.
const many = Array.from({ length: 7 }, (_, i) => ({ x: i * 300, y: (i % 2) * 400, w: 1200, h: 800 }))
out = check(many, 2400, 1000, 30)
const rowsY = [...new Set(out.map((r) => r.y))]
assert.ok(rowsY.length >= 2)
const last = out.filter((r) => r.y === Math.max(...rowsY))
const middle = (Math.min(...last.map((r) => r.x)) + Math.max(...last.map((r) => r.x + r.w))) / 2
assert.ok(Math.abs(middle - 1200) < 2, `last row centered at ${middle}`)

console.log("mission layout: ok")
