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
assert.deepStrictEqual(m.parseForecast(reply, false), { temp: 32, high: 34, low: 22, text: "Partly Cloudy", icon: "\ue302", day: true })
assert.strictEqual(m.parseForecast(reply, true).temp, 89)
assert.strictEqual(m.parseForecast("not json", false), null)
assert.strictEqual(m.parseForecast("{}", false), null)

assert.deepStrictEqual(m.parsePlace('{"name":"Riyadh","latitude":24.68,"longitude":46.72,"country":"SA"}'), { name: "Riyadh", latitude: 24.68, longitude: 46.72, country: "SA" })
assert.strictEqual(m.parsePlace('{"name":"Nowhere"}'), null)
assert.strictEqual(m.parsePlace(""), null)
assert.match(m.forecastUrl(24.68, 46.72), /latitude=24\.68&longitude=46\.72/)

console.log("widgets model: ok")
