// The theme's pieces and settings in the words Studio's rows use, for the
// list of changes waiting for Apply and the backups' labels. Kept out of QML
// so node can test it: node tests/labels.test.js

var PIECES = {
    theme: "macOS theme", icons: "MacTahoe icons", rows: "Striped rows in Files", switcher: "App and workspace switchers",
    "wide-menu": "Spotlight-like menu", osd: "Volume and brightness capsule", "dictation-hud": "Dictation pill",
    dock: "macOS dock", lock: "macOS lock screen", widgets: "Desktop widgets", menubar: "macOS menu bar", "bar-icons": "macOS icons"
}
var SETTINGS = {
    glass: "Window glass", "web-glass": "Browser and Electron app glass", blur: "Frosted blur", "reduce-motion": "Reduce motion",
    "title-bars": "Title bars", "traffic-lights": "Traffic light size", snapping: "Snapping", "drop-follow": "Going along with a dropped window",
    magnification: "Dock magnification", "dock-size": "Dock size", clock: "Clock",
    "volume-hud": "Volume and brightness capsule", "dictation-hud": "Dictation pill"
}
// Settings that are on (1) or off (0).
var SWITCHES = ["reduce-motion", "title-bars", "snapping", "drop-follow"]

function piece(id) { return PIECES[id] || id }

// "Window glass 0.9", "Snapping off".
function setting(key, value) {
    if (SWITCHES.indexOf(key) >= 0) return (SETTINGS[key] || key) + (Number(value) === 1 ? " on" : " off")
    return (SETTINGS[key] || key) + " " + value
}

// A backup's note as install.sh writes it ("Added theme dock; glass 0.9"),
// in the rows' words ("Added macOS theme, macOS dock; Window glass 0.9").
// Notes it doesn't know the shape of stay as they are.
function backup(note) {
    return String(note || "").split("; ").map(function(part) {
        var words = part.split(" ")
        if (words[0] === "Added" || words[0] === "Removed")
            return words[0] + " " + words.slice(1).map(piece).join(", ")
        if (words.length === 2 && SETTINGS[words[0]]) return setting(words[0], words[1])
        return part
    }).join("; ")
}

if (typeof module !== "undefined") module.exports = { piece: piece, setting: setting, backup: backup }
