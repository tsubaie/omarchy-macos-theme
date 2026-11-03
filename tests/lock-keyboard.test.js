// The lock screen's keyboard: which key presses are the user's own layout
// bindings, and the layout's short label. The functions are read out of
// lock/LockView.qml itself, which stays one file so the lock never loads
// without them. Run with: node tests/lock-keyboard.test.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "../lock/LockView.qml"), "utf8")
function extract(name) {
  const start = source.indexOf(`function ${name}(`)
  assert.ok(start >= 0, `LockView.qml has no ${name}()`)
  let depth = 0
  for (let i = source.indexOf("{", start); i < source.length; i++) {
    if (source[i] === "{") depth++
    else if (source[i] === "}" && --depth === 0) return source.slice(start, i + 1)
  }
  throw new Error(`${name}() never closes`)
}

// Qt's own values for the keys and modifiers these use.
const Qt = {
  Key_Space: 0x20, Key_Tab: 0x01000001, Key_Shift: 0x01000020, Key_Control: 0x01000021,
  Key_Meta: 0x01000022, Key_Alt: 0x01000023, Key_CapsLock: 0x01000024,
  Key_Super_L: 0x01000053, Key_Super_R: 0x01000054, Key_I: 0x49,
  ShiftModifier: 0x02000000, ControlModifier: 0x04000000, AltModifier: 0x08000000, MetaModifier: 0x10000000,
}
const lock = new Function("Qt", ["qtKey", "layoutBindingFor", "parseBriefs", "shortLabel"].map(extract).join("\n")
  + "\nreturn { layoutBindingFor, parseBriefs, shortLabel }")(Qt)

// As hyprctl binds lists them on a seat with Omarchy's Super+I and Alt+Shift.
const bindings = [
  { key: "I", mods: 64, back: false },
  { key: "I", mods: 65, back: true },
  { key: "Shift_L", mods: 8, back: false },
]
const press = (key, ...mods) => lock.layoutBindingFor(key, mods.reduce((a, m) => a | m, 0), bindings)

// Super+I, as Qt reports Super either way; Super+Shift+I goes back.
assert.strictEqual(press(Qt.Key_I, Qt.MetaModifier), bindings[0])
assert.strictEqual(press(Qt.Key_I, Qt.MetaModifier, Qt.ShiftModifier), bindings[1])
// Alt then Shift, whether or not Qt counts the Shift being pressed as held.
assert.strictEqual(press(Qt.Key_Shift, Qt.AltModifier), bindings[2])
assert.strictEqual(press(Qt.Key_Shift, Qt.AltModifier, Qt.ShiftModifier), bindings[2])
// Not a binding: a plain I, I with another modifier, Shift alone, Shift then Alt.
assert.strictEqual(press(Qt.Key_I), null)
assert.strictEqual(press(Qt.Key_I, Qt.MetaModifier, Qt.ControlModifier), null)
assert.strictEqual(press(Qt.Key_Shift), null)
assert.strictEqual(press(Qt.Key_Alt, Qt.ShiftModifier), null)
// No bindings, no shortcut.
assert.strictEqual(lock.layoutBindingFor(Qt.Key_I, Qt.MetaModifier, []), null)

// Labels as Omarchy's bar shows them: the language code xkbcli gives.
const briefs = lock.parseBriefs([
  "layouts:",
  "- layout: 'us'",
  "  variant: ''",
  "  brief: 'en'",
  "  description: English (US)",
  "- layout: 'ara'",
  "  variant: ''",
  "  brief: 'ar'",
  "  description: Arabic",
  "- layout: 'mm'",
  "  variant: 'zawgyi'",
  "  brief: 'my-zwg'",
  "  description: Burmese (Zawgyi)",
].join("\n"))
assert.strictEqual(lock.shortLabel("Arabic", briefs), "AR")
assert.strictEqual(lock.shortLabel("English (US)", briefs), "EN")
assert.strictEqual(lock.shortLabel("Burmese (Zawgyi)", briefs), "MY")
// Not listed: its first word, three letters at most.
assert.strictEqual(lock.shortLabel("Portuguese (Brazil)", briefs), "POR")
assert.strictEqual(lock.shortLabel("constructor", briefs), "CON")
assert.strictEqual(lock.shortLabel("", briefs), "")

console.log("lock keyboard: ok")
