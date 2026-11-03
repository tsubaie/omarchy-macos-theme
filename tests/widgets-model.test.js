// Desktop widget logic. Run with: node tests/widgets-model.test.js
const assert = require("assert")
const m = require("../plugins/macos-theme.widgets/WidgetsModel.js")

// November 2026 starts on a Sunday and has 30 days.
let g = m.monthGrid(2026, 10, 0)
assert.deepStrictEqual(g[0], [1, 2, 3, 4, 5, 6, 7])
assert.deepStrictEqual(g[4], [29, 30, 0, 0, 0, 0, 0])
// Weeks starting Monday push it to the last column; Qt's 7 is Sunday too.
g = m.monthGrid(2026, 10, 1)
assert.deepStrictEqual(g[0], [0, 0, 0, 0, 0, 0, 1])
assert.deepStrictEqual(m.monthGrid(2026, 10, 7), m.monthGrid(2026, 10, 0))
// Every month: each day once, whole weeks.
for (let month = 0; month < 12; month++) {
  for (const first of [0, 1, 6]) {
    const rows = m.monthGrid(2027, month, first)
    const days = rows.flat().filter(Boolean)
    assert.strictEqual(days.length, new Date(2027, month + 1, 0).getDate())
    assert.deepStrictEqual(days, days.map((_, i) => i + 1))
    assert.ok(rows.every((r) => r.length === 7))
  }
}

assert.strictEqual(m.condition(0, 1).text, "Sunny")
assert.strictEqual(m.condition(0, 0).text, "Clear")
assert.strictEqual(m.condition(63, 1).text, "Rain")
assert.strictEqual(m.condition(96, 1).text, "Thunderstorms")

// The country decides before the locale: Riyadh with en-US is Celsius.
assert.strictEqual(m.usesImperial("SA", "en-US"), false)
assert.strictEqual(m.usesImperial("US", "en-GB"), true)
assert.strictEqual(m.usesImperial("", "en-US"), true)
assert.strictEqual(m.usesImperial("", "de-DE"), false)

const reply = JSON.stringify({ current: { temperature_2m: 31.6, weather_code: 2, is_day: 1 }, daily: { temperature_2m_max: [34.2], temperature_2m_min: [21.5] } })
assert.deepStrictEqual(m.parseForecast(reply, false), { temp: 32, high: 34, low: 22, text: "Partly Cloudy", icon: "\ue302", day: true, scene: "partly", sunrise: null, sunset: null, windy: false })
assert.strictEqual(m.parseForecast(reply, true).temp, 89)
const gusty = JSON.stringify({ current: { temperature_2m: 10, weather_code: 63, is_day: 0, wind_speed_10m: 42 } })
assert.strictEqual(m.parseForecast(gusty, false).windy, true)
assert.strictEqual(m.parseForecast(gusty, false).scene, "rain")
assert.strictEqual(m.parseForecast(gusty, false).high, null)
assert.deepStrictEqual([0, 1, 2, 3, 45, 53, 65, 81, 73, 86, 95, 99, 7].map(m.scene), ["clear", "clear", "partly", "cloudy", "fog", "rain", "rain", "rain", "snow", "snow", "thunder", "thunder", "cloudy"])
assert.strictEqual(m.parseForecast("not json", false), null)
assert.strictEqual(m.parseForecast("{}", false), null)

assert.deepStrictEqual(m.parsePlace('{"name":"Riyadh","latitude":24.68,"longitude":46.72,"country":"SA"}'), { name: "Riyadh", latitude: 24.68, longitude: 46.72, country: "SA" })
assert.strictEqual(m.parsePlace('{"name":"Nowhere"}'), null)
assert.strictEqual(m.parsePlace(""), null)
assert.match(m.forecastUrl(24.68, 46.72), /latitude=24\.68&longitude=46\.72/)

// Layout: nothing saved means all four down the left edge.
const start = m.normalizeLayout(undefined)
assert.deepStrictEqual(start.map((w) => [w.id, w.col, w.row]), [["clock", 0, 0], ["calendar", 0, 1], ["weather", 0, 2], ["playing", 0, 3]])
assert.deepStrictEqual(m.normalizeLayout([]), start)
assert.deepStrictEqual(m.normalizeLayout([{ id: "nope", col: 0, row: 0 }]), start)
// Unknown ids and repeats go; a widget on a taken cell moves to a free one.
const odd = m.normalizeLayout([{ id: "clock", col: 2, row: 1 }, { id: "clock", col: 0, row: 0 }, { id: "weather", col: 2, row: 1 }, { id: "x", col: 5, row: 5 }, { id: "calendar", col: -1, row: 0 }])
assert.deepStrictEqual(odd, [{ id: "clock", col: 2, row: 1 }, { id: "weather", col: 0, row: 0 }, { id: "calendar", col: 0, row: 1 }])
assert.deepStrictEqual(m.hidden(odd), ["playing"])

// Dropping on another widget swaps them; on a free cell just moves.
let l = m.moveTo(start, "clock", 0, 2)
assert.deepStrictEqual(m.find(l, "clock"), { id: "clock", col: 0, row: 2 })
assert.deepStrictEqual(m.find(l, "weather"), { id: "weather", col: 0, row: 0 })
l = m.moveTo(l, "playing", 3, 1)
assert.deepStrictEqual(m.find(l, "playing"), { id: "playing", col: 3, row: 1 })
assert.strictEqual(new Set(l.map((w) => w.col + "," + w.row)).size, l.length)

// Removing keeps at least one; adding takes the first free cell.
l = m.remove(m.remove(m.remove(start, "clock"), "calendar"), "weather")
assert.deepStrictEqual(l.map((w) => w.id), ["playing"])
assert.deepStrictEqual(m.remove(l, "playing"), l)
l = m.add(l, "clock", 3, 4)
assert.deepStrictEqual(m.find(l, "clock"), { id: "clock", col: 0, row: 0 })
assert.deepStrictEqual(m.add(l, "clock", 3, 4), l)
assert.deepStrictEqual(m.add(start, "clock", 1, 4), start)
assert.strictEqual(m.add([{ id: "clock", col: 0, row: 0 }], "weather", 1, 1).length, 1)

// Laid out on a 4K screen, shown on a 7 × 4 laptop: a widget past the edge
// takes the first free cell, so it can still be seen and right-clicked; one
// that fits stays; the saved layout itself is left as it was.
const wide = [{ id: "clock", col: 12, row: 0 }, { id: "calendar", col: 0, row: 0 }, { id: "weather", col: 3, row: 6 }]
const fitted = m.fitLayout(wide, 7, 4)
assert.deepStrictEqual(fitted, [{ id: "calendar", col: 0, row: 0 }, { id: "clock", col: 0, row: 1 }, { id: "weather", col: 0, row: 2 }])
assert.strictEqual(wide[0].col, 12)
assert.deepStrictEqual(m.fitLayout(start, 7, 4), start)
// A grid with no free cell left: the last cell, rather than off screen.
assert.deepStrictEqual(m.fitLayout([{ id: "clock", col: 0, row: 0 }, { id: "weather", col: 5, row: 0 }], 1, 1),
  [{ id: "clock", col: 0, row: 0 }, { id: "weather", col: 0, row: 0 }])

// Snapping rounds to the nearest cell and stays on the grid.
assert.deepStrictEqual(m.snap(250, 80, 172, 5, 4), { col: 1, row: 0 })
assert.deepStrictEqual(m.snap(-300, 9000, 172, 5, 4), { col: 0, row: 3 })

// Day phases around today's sunrise (06:00) and sunset (18:00).
const at = (h, mi = 0) => Date.UTC(2026, 10, 1, h, mi)
const rise = at(6), set = at(18)
assert.deepStrictEqual([at(3), at(5, 40), at(6, 30), at(7), at(12), at(17, 20), at(18, 20), at(19), at(23)].map((t) => m.dayPhase(t, rise, set, true)),
  ["night", "dawn", "dawn", "day", "day", "dusk", "dusk", "night", "night"])
assert.strictEqual(m.dayPhase(at(12), null, null, false), "night")
assert.strictEqual(m.dayPhase(at(12), null, null, true), "day")
const withSun = m.parseForecast(JSON.stringify({ current: { temperature_2m: 20, weather_code: 0, is_day: 1 }, daily: { temperature_2m_max: [25], temperature_2m_min: [15], sunrise: [1793502010], sunset: [1793542395] } }), false)
assert.strictEqual(withSun.sunrise, 1793502010000)
assert.strictEqual(withSun.sunset, 1793542395000)
assert.match(m.forecastUrl(1, 2), /sunrise,sunset.*timeformat=unixtime/)

console.log("widgets model: ok")
