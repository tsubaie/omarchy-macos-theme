// macOS style menu bar icons, keyed by the glyph Omarchy's own widget shows,
// so the widget keeps choosing the state and only the drawing changes. Each
// is an 18×18 SVG in the color "C", which the bar's color replaces. Dimmed
// parts are drawn at low opacity rather than left out, as macOS does, which
// also keeps every state the same size. Node tests it: tests/bar-icons.test.js

var DIM = 0.3

function arc(r, cy, opacity) {
    var dx = (r * 0.7071).toFixed(2), y = (cy - r * 0.7071).toFixed(2)
    return '<path d="M' + (9 - dx).toFixed(2) + ' ' + y + ' A' + r + ' ' + r + ' 0 0 1 ' + (9 + +dx).toFixed(2) + ' ' + y
        + '" fill="none" stroke="C" stroke-width="1.9" stroke-linecap="round" opacity="' + opacity + '"/>'
}

// Wi-Fi: the dot and up to three arcs lit; `mark` adds a slash or an "!".
function wifi(lit, mark) {
    var parts = ['<circle cx="9" cy="14.6" r="1.45" fill="C" opacity="' + (lit > 0 ? 1 : DIM) + '"/>']
    var radii = [4, 7.3, 10.6]
    for (var i = 0; i < 3; i++) parts.push(arc(radii[i], 14.6, lit > i + 1 ? 1 : DIM))
    if (mark === "slash") parts.push('<path d="M3 2.5 L15.5 16" stroke="C" stroke-width="1.7" stroke-linecap="round"/>')
    if (mark === "!") parts.push('<path d="M16.6 9.5 V13" stroke="C" stroke-width="1.6" stroke-linecap="round"/><circle cx="16.6" cy="15.6" r="0.95" fill="C"/>')
    return parts.join("")
}

// Ethernet: macOS's network mark, ‹···›.
function ethernet(opacity) {
    return '<g opacity="' + opacity + '" fill="none" stroke="C" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
        + '<path d="M5 4.5 L1.5 9 L5 13.5"/><path d="M13 4.5 L16.5 9 L13 13.5"/></g>'
        + '<g fill="C" opacity="' + opacity + '"><circle cx="6.3" cy="9" r="1.1"/><circle cx="9" cy="9" r="1.1"/><circle cx="11.7" cy="9" r="1.1"/></g>'
}

// The plain rune, as macOS draws it whether or not anything is connected.
function bluetooth(opacity) {
    return '<path d="M4.8 5.6 L13 12.4 L9 16 V2 L13 5.6 L4.8 12.4" fill="none" stroke="C" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" opacity="' + opacity + '"/>'
}

// The speaker with up to three waves lit, or struck through when muted.
function speaker(lit) {
    var s = '<path d="M1.8 6.8 H4.6 L8.8 3.2 V14.8 L4.6 11.2 H1.8 Z" fill="C" stroke="C" stroke-width="1" stroke-linejoin="round"/>'
    if (lit < 0) return s + '<path d="M11.5 6.5 L16 11.5 M16 6.5 L11.5 11.5" stroke="C" stroke-width="1.7" stroke-linecap="round"/>'
    var radii = [2.8, 5.3, 7.8]
    for (var i = 0; i < 3; i++) {
        var r = radii[i], x = (8.8 + r * 0.6428).toFixed(2), dy = (r * 0.766).toFixed(2)
        s += '<path d="M' + x + ' ' + (9 - dy).toFixed(2) + ' A' + r + ' ' + r + ' 0 0 1 ' + x + ' ' + (9 + +dy).toFixed(2)
            + '" fill="none" stroke="C" stroke-width="1.6" stroke-linecap="round" opacity="' + (lit > i ? 1 : DIM) + '"/>'
    }
    return s
}

var HEADPHONES = '<path d="M2.8 11 V9 A6.2 6.2 0 0 1 15.2 9 V11" fill="none" stroke="C" stroke-width="1.7"/>'
    + '<rect x="1.8" y="10" width="3.6" height="6" rx="1.4" fill="C"/><rect x="12.6" y="10" width="3.6" height="6" rx="1.4" fill="C"/>'

var STAND = '<path d="M6.5 16 H11.5" stroke="C" stroke-width="1.6" stroke-linecap="round"/>'
var DISPLAY = '<rect x="1.5" y="2.5" width="15" height="10.5" rx="1.6" fill="none" stroke="C" stroke-width="1.6"/>'
    + '<path d="M9 13 V16" stroke="C" stroke-width="1.6"/>' + STAND
// Two displays, the one behind showing past the front one's corner.
var DISPLAYS = '<path d="M5.5 3.2 V2.6 A1.3 1.3 0 0 1 6.8 1.3 H15.4 A1.3 1.3 0 0 1 16.7 2.6 V8.6 A1.3 1.3 0 0 1 15.4 9.9 H14.6" fill="none" stroke="C" stroke-width="1.5"/>'
    + '<rect x="1.3" y="4.6" width="12.6" height="8.8" rx="1.4" fill="none" stroke="C" stroke-width="1.5"/>'
    + '<path d="M7.6 13.4 V16" stroke="C" stroke-width="1.5"/><path d="M5.2 16 H10" stroke="C" stroke-width="1.5" stroke-linecap="round"/>'

function g(cp) { return String.fromCodePoint(cp) }

var ICONS = {}
// Network (network/Model.js): Wi-Fi by strength, restricted, Ethernet, off.
ICONS[g(0xF092F)] = wifi(0)
ICONS[g(0xF091F)] = wifi(1)
ICONS[g(0xF0922)] = wifi(2)
ICONS[g(0xF0925)] = wifi(3)
ICONS[g(0xF0928)] = wifi(4)
ICONS[g(0xF0929)] = wifi(0, "!")
ICONS[g(0xF0200)] = ethernet(1)
ICONS[g(0xF0202)] = ethernet(0.45)
ICONS[g(0xF092E)] = wifi(0, "slash")
// Bluetooth (bluetooth/Panel.qml): off, connected, on.
ICONS[g(0xF00B2)] = bluetooth(0.4)
ICONS[g(0xF00B1)] = bluetooth(1)
ICONS[g(0xF00AF)] = bluetooth(1)
// Audio (audio/Panel.qml outputIcon): muted or none, headphones, by volume.
ICONS[g(0xEEE8)] = speaker(-1)
ICONS[g(0xF02CB)] = HEADPHONES
ICONS[g(0xF028)] = speaker(3)
ICONS[g(0xF027)] = speaker(2)
ICONS[g(0xF026)] = speaker(1)
// Display (monitor/Panel.qml): one screen, several.
ICONS[g(0xF0379)] = DISPLAY
ICONS[g(0xF037A)] = DISPLAYS

// The SVG for a glyph in a color, or "" for one without a macOS icon, which
// then keeps Omarchy's glyph.
function svg(glyph, color) {
    var body = ICONS[glyph]
    if (!body) return ""
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18">' + body.replace(/"C"/g, '"' + color + '"') + '</svg>'
}

// The SVG as an image source. Qt loads SVG from a data URL only in base64,
// and its own Qt.btoa(string) is deprecated; the icons are plain ASCII.
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function base64(text) {
    var out = ""
    for (var i = 0; i < text.length; i += 3) {
        var a = text.charCodeAt(i), b = text.charCodeAt(i + 1), c = text.charCodeAt(i + 2)
        var n = (a << 16) | ((b || 0) << 8) | (c || 0)
        out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63]
            + (i + 1 < text.length ? B64[(n >> 6) & 63] : "=") + (i + 2 < text.length ? B64[n & 63] : "=")
    }
    return out
}
function source(glyph, color) {
    var text = svg(glyph, color)
    return text ? "data:image/svg+xml;base64," + base64(text) : ""
}

if (typeof module !== "undefined") module.exports = { svg: svg, source: source, base64: base64, ICONS: ICONS }
