// Pieces and settings in Studio's words. Run with: node tests/labels.test.js
const assert = require("assert")
const m = require("../qml/Labels.js")

// Notes as install.sh's describe_changes writes them.
assert.strictEqual(m.backup("Added theme dock"), "Added macOS theme, macOS dock")
assert.strictEqual(m.backup("Removed osd; glass 0.9; snapping 0"), "Removed Volume and brightness capsule; Window glass 0.9; Snapping off")
assert.strictEqual(m.backup("Arranged the bar; Showed widgets clock, weather"), "Arranged the bar; Showed widgets clock, weather")
// Its own notes, and ones it doesn't know the shape of, stay as they are.
assert.strictEqual(m.backup("Backed up by hand"), "Backed up by hand")
assert.strictEqual(m.backup("Before importing mine.tar.gz"), "Before importing mine.tar.gz")
assert.strictEqual(m.backup("Added something-new"), "Added something-new")
assert.strictEqual(m.backup(""), "")
assert.strictEqual(m.setting("reduce-motion", 1), "Reduce motion on")
assert.strictEqual(m.setting("dock-size", 56), "Dock size 56")
assert.strictEqual(m.setting("dock-previews", 0), "Dock window previews off")
assert.strictEqual(m.setting("logo-menu", 1), "Logo opens the macOS menu on")

// Studio's releases, as the release workflow names them, against a build
// from source, which is never offered one.
for (const v of ["2026.11.03", "2026.11.03.2", "2026.11.03.12"]) assert.ok(m.isRelease(v), v)
for (const v of ["0.1.0", "", "2026.11.3", "v2026.11.03", "2026.11.03-rc1"]) assert.ok(!m.isRelease(v), v)
assert.strictEqual(m.studioUpdate("2026.11.03.2", "2026.11.03"), true)
assert.strictEqual(m.studioUpdate("2026.11.03", "2026.11.03"), false)
assert.strictEqual(m.studioUpdate("", "2026.11.03"), false)
assert.strictEqual(m.studioUpdate("2026.11.03.2", "0.1.0"), false)

// When each was last checked: today by the clock, another day by its date.
const now = new Date(2026, 10, 3, 16, 44)
assert.strictEqual(m.lastChecked(null, now), "")
assert.strictEqual(m.lastChecked(new Date(2026, 10, 3, 9, 5), now), "Last checked today at 09:05.")
assert.strictEqual(m.lastChecked(new Date(2026, 10, 2, 23, 59), now), "Last checked 2 Nov at 23:59.")

// The theme's version by its date, the commit or release after it.
assert.strictEqual(m.themeVersion("de449a2, 2026-11-03"), "the 3 Nov 2026 version (de449a2)")
assert.strictEqual(m.themeVersion("v1.2.0, 2026-01-09"), "v1.2.0, from 9 Jan 2026")
assert.strictEqual(m.themeVersion(""), "")
assert.strictEqual(m.themeVersion("something else"), "something else")

// An update's commits, as a short list.
assert.strictEqual(m.whatsNew(""), "")
assert.strictEqual(m.whatsNew("A better dock\nFix the clock"), "What's new:\n• A better dock\n• Fix the clock")
assert.strictEqual(m.whatsNew("1\n2\n3\n4\n5\n6\n7\n8").split("\n").slice(-2).join("|"), "• 6|…and 2 more")

console.log("labels: ok")
