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

// An update's commits, as a short list.
assert.strictEqual(m.whatsNew(""), "")
assert.strictEqual(m.whatsNew("A better dock\nFix the clock"), "What's new:\n• A better dock\n• Fix the clock")
assert.strictEqual(m.whatsNew("1\n2\n3\n4\n5\n6\n7\n8").split("\n").slice(-2).join("|"), "• 6|…and 2 more")

console.log("labels: ok")
