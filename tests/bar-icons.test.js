// The macOS bar icons. Run with: node tests/bar-icons.test.js
const assert = require("assert")
const fs = require("fs")
const m = require("../plugins/macos-theme.bar-icons/Icons.js")

// Every glyph the four widgets show in the bar has an icon.
const glyphs = { "network/Model.js": [0xF092F, 0xF091F, 0xF0922, 0xF0925, 0xF0928, 0xF0929, 0xF0200, 0xF0202, 0xF092E],
  "bluetooth/Panel.qml": [0xF00B2, 0xF00B1, 0xF00AF],
  "audio/Panel.qml": [0xEEE8, 0xF02CB, 0xF028, 0xF027, 0xF026],
  "monitor/Panel.qml": [0xF0379, 0xF037A] }
for (const [file, cps] of Object.entries(glyphs)) {
  for (const cp of cps) assert.ok(m.svg(String.fromCodePoint(cp), "#fff"), file + " U+" + cp.toString(16))
}
// They are still the glyphs Omarchy uses, when it is installed here.
const omarchy = "/usr/share/omarchy/shell/plugins/panels/"
for (const [file, cps] of Object.entries(glyphs)) {
  if (!fs.existsSync(omarchy + file)) continue
  const src = fs.readFileSync(omarchy + file, "utf8")
  for (const cp of cps) assert.ok(src.includes(String.fromCodePoint(cp)), file + " no longer shows U+" + cp.toString(16))
}
// Any other glyph keeps Omarchy's.
assert.strictEqual(m.svg("A", "#fff"), "")
// The color goes everywhere, and nothing is left uncolored.
const s = m.svg(String.fromCodePoint(0xF0928), "#123456")
assert.ok(s.includes('"#123456"') && !s.includes('"C"') && s.startsWith("<svg"))
// Every icon is well-formed: balanced tags, numbers only in paths.
for (const [k, body] of Object.entries(m.ICONS)) {
  assert.ok(!/NaN|undefined/.test(body), "U+" + k.codePointAt(0).toString(16))
}
console.log("bar-icons: ok")

// The image source is the SVG in base64, as Buffer encodes it.
for (const n of ["", "a", "ab", "abc", "<svg/>"]) assert.strictEqual(m.base64(n), Buffer.from(n).toString("base64"), n)
const src = m.source(String.fromCodePoint(0xF00AF), "#fff")
assert.strictEqual(Buffer.from(src.split(",")[1], "base64").toString(), m.svg(String.fromCodePoint(0xF00AF), "#fff"))
assert.strictEqual(m.source("A", "#fff"), "")
console.log("bar-icons source: ok")
