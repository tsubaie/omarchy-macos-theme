// The theme's pieces and settings in the words Studio's rows use, for the
// list of changes waiting for Apply and the backups' labels. Kept out of QML
// so node can test it: node tests/labels.test.js

var PIECES = {
    theme: "macOS theme", icons: "MacTahoe icons", rows: "Striped rows in Files", switcher: "App and workspace switchers",
    "wide-menu": "Spotlight-like menu", osd: "Volume and brightness capsule", "dictation-hud": "Dictation pill",
    dock: "macOS dock", lock: "macOS lock screen", widgets: "Desktop widgets", menubar: "macOS menu bar", "bar-icons": "macOS icons",
    notifications: "macOS notifications"
}
var SETTINGS = {
    glass: "Window glass", "web-glass": "Browser and Electron app glass", blur: "Frosted blur", "reduce-motion": "Reduce motion",
    "title-bars": "Title bars", "traffic-lights": "Traffic light size", snapping: "Snapping", "drop-follow": "Going along with a dropped window",
    magnification: "Dock magnification", "dock-size": "Dock size", "dock-previews": "Dock window previews", clock: "Clock",
    "volume-hud": "Volume and brightness capsule", "dictation-hud": "Dictation pill"
}
// Settings that are on (1) or off (0).
var SWITCHES = ["reduce-motion", "title-bars", "snapping", "drop-follow", "dock-previews"]

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

// What an update brings in, for its confirmation: the commits' subjects (one
// per line, newest first) as a short list, the rest counted.
function whatsNew(notes) {
    var all = String(notes || "").split("\n").filter(function(line) { return line.trim() !== "" })
    if (all.length === 0) return ""
    var shown = all.slice(0, 6).map(function(line) { return "• " + line })
    if (all.length > shown.length) shown.push("…and " + (all.length - shown.length) + " more")
    return "What's new:\n" + shown.join("\n")
}

// Studio's releases are named for the day they're made, as the release
// workflow names them: 2026.11.03, then 2026.11.03.2. A build from source
// has Cargo's version (0.1.0) and is never a release.
function isRelease(version) { return /^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$/.test(version) }

// Whether GitHub's newest release is one to offer this build: a release
// build, and another name than its own.
function studioUpdate(latest, version) { return isRelease(version) && !!latest && latest !== version }

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
// "Last checked today at 16:44.", or "… 3 Nov at 09:05." on another day;
// empty before the first check.
function lastChecked(at, now) {
    if (!at) return ""
    var two = function(n) { return (n < 10 ? "0" : "") + n }
    var day = at.toDateString() === now.toDateString() ? "today" : at.getDate() + " " + MONTHS[at.getMonth()]
    return "Last checked " + day + " at " + two(at.getHours()) + ":" + two(at.getMinutes()) + "."
}

// The theme's version as git describes it, "de449a2, 2026-11-03" (or
// "v1.2.0, 2026-11-03" once it has releases), by its date, as people say it:
// "the 3 Nov 2026 version (de449a2)", "v1.2.0, from 3 Nov 2026".
function themeVersion(version) {
    var m = /^(.+), ([0-9]{4})-([0-9]{2})-([0-9]{2})$/.exec(version || "")
    if (!m) return version || ""
    var date = Number(m[4]) + " " + MONTHS[Number(m[3]) - 1] + " " + m[2]
    return /^v[0-9]/.test(m[1]) ? m[1] + ", from " + date : "the " + date + " version (" + m[1] + ")"
}

if (typeof module !== "undefined") module.exports = {
    piece: piece, setting: setting, backup: backup, whatsNew: whatsNew,
    isRelease: isRelease, studioUpdate: studioUpdate, lastChecked: lastChecked, themeVersion: themeVersion
}
