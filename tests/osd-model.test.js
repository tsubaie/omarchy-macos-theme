// The volume HUD's icons and the language HUD. Run with: node tests/osd-model.test.js
const assert = require("assert")
const m = require("../plugins/macos-theme.osd/OsdModel.js")
const icons = require("../plugins/macos-theme.osd/HudIcons.js")
const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
const read = (p) => fs.readFileSync(path.join(root, p), "utf8")

// The plugins that follow the Glass setting each find it in look.lua; their
// pattern must still find the theme's line, and read its second number.
const look = read("theme/look.lua")
for (const qml of ["control-center/ControlCenter.qml", "osd/Osd.qml", "dictation-hud/Hud.qml"]) {
  const source = read(`plugins/macos-theme.${qml}`)
  const found = /var m = \/(.+)\/\.exec\(text\(\)\)/.exec(source)
  assert.ok(found, `${qml} no longer reads the glass from look.lua`)
  const m = new RegExp(found[1]).exec(look)
  assert.ok(m, `${qml}'s glass pattern doesn't match theme/look.lua`)
  assert.strictEqual(m[1], "0.85", `${qml} reads the wrong number from look.lua`)
}
// Mission Control follows the Blur setting the same way.
{
  const source = read("plugins/macos-theme.switcher/MissionControl.qml")
  const found = /var m = \/(.+)\/m\.exec\(text\(\)\)/.exec(source)
  assert.ok(found, "MissionControl.qml no longer reads the blur from look.lua")
  const m = new RegExp(found[1], "m").exec(look)
  assert.ok(m, "MissionControl.qml's blur pattern doesn't match theme/look.lua")
  assert.strictEqual(m[1], "10", "MissionControl.qml reads the wrong number from look.lua")
}

// The speaker by volume, muted at 0 or when muted.
assert.strictEqual(m.hudIconName("volume", 0), "volume-muted")
assert.strictEqual(m.hudIconName("volume", 20), "volume-low")
assert.strictEqual(m.hudIconName("volume", 50), "volume-medium")
assert.strictEqual(m.hudIconName("volume", 100), "volume-high")
assert.strictEqual(m.hudIconName("volume-muted", 80), "volume-muted")
assert.strictEqual(m.hudIconName("brightness", 50), "brightness")
assert.strictEqual(m.hudIconName("mic-muted", 0), "microphone")
assert.strictEqual(m.hudIconName("touchpad", 0), "")
// Every name it gives has an icon, an SVG in the color asked for.
for (const n of ["volume-muted", "volume-low", "volume-medium", "volume-high", "brightness", "microphone", "keyboard"]) {
  const svg = Buffer.from(icons.icon(n, "#abcdef").split(",")[1], "base64").toString()
  assert.ok(svg.startsWith("<svg") && svg.includes('fill="#abcdef"'), n)
}
assert.strictEqual(icons.icon("nope", "#fff"), "")
for (const n of ["", "a", "ab", "abc"]) assert.strictEqual(icons.base64(n), Buffer.from(n).toString("base64"))
// The language's short name.
assert.strictEqual(m.layoutCode("English (US)"), "EN")
assert.strictEqual(m.layoutCode("Arabic"), "AR")
console.log("osd model: ok")
