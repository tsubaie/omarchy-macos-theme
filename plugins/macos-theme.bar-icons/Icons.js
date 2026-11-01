// macOS style menu bar icons, keyed by the glyph Omarchy's own widget shows,
// so the widget keeps choosing the state and only the drawing changes. Each
// is an 18×18 SVG in the color "C", which the bar's color replaces. Dimmed
// parts are drawn at low opacity rather than left out, as macOS does, which
// also keeps every state the same size. Node tests it: tests/bar-icons.test.js

var DIM = 0.3

// An arc of the Wi-Fi fan, 45° either side of straight up from (9, cy).
function arc(r, cy, opacity) {
    var dx = (r * 0.7071).toFixed(2), y = (cy - r * 0.7071).toFixed(2)
    return '<path d="M' + (9 - dx).toFixed(2) + ' ' + y + ' A' + r + ' ' + r + ' 0 0 1 ' + (9 + +dx).toFixed(2) + ' ' + y
        + '" fill="none" stroke="C" stroke-width="2" stroke-linecap="round" opacity="' + opacity + '"/>'
}

// Wi-Fi as macOS draws it: a filled wedge and two arcs over it, lit from the
// wedge out by strength (0 to 4); `mark` adds a slash or an "!".
function wifi(lit, mark) {
    var cy = 14.9, w = (3.6 * 0.7071).toFixed(2)
    var parts = ['<path d="M9 ' + cy + ' L' + (9 - w).toFixed(2) + ' ' + (cy - w).toFixed(2) + ' A3.6 3.6 0 0 1 ' + (9 + +w).toFixed(2) + ' ' + (cy - w).toFixed(2)
        + ' Z" fill="C" stroke="C" stroke-width="1" stroke-linejoin="round" opacity="' + (lit > 0 ? 1 : DIM) + '"/>']
    parts.push(arc(7.2, cy, lit > 1 ? 1 : DIM))
    parts.push(arc(11.2, cy, lit > 2 ? 1 : DIM))
    if (mark === "slash") parts.push('<path d="M3 2.5 L15.5 16" stroke="C" stroke-width="1.7" stroke-linecap="round"/>')
    if (mark === "!") parts.push('<path d="M16.6 9.5 V13" stroke="C" stroke-width="1.6" stroke-linecap="round"/><circle cx="16.6" cy="15.6" r="0.95" fill="C"/>')
    return parts.join("")
}

// The plain rune in a fine line, as macOS draws it whether or not anything is
// connected.
function bluetooth(opacity) {
    return '<path d="M4.8 5.6 L13 12.4 L9 16 V2 L13 5.6 L4.8 12.4" fill="none" stroke="C" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" opacity="' + opacity + '"/>'
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
// Ethernet shows as Wi-Fi too, full when connected, as the bar's network icon.
ICONS[g(0xF092F)] = wifi(0)
ICONS[g(0xF091F)] = wifi(1)
ICONS[g(0xF0922)] = wifi(2)
ICONS[g(0xF0925)] = wifi(3)
ICONS[g(0xF0928)] = wifi(4)
ICONS[g(0xF0929)] = wifi(0, "!")
ICONS[g(0xF0200)] = wifi(4)
ICONS[g(0xF0202)] = wifi(0)
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
// Agents (agents/Panel.qml): Icons8's Message Bot, filled (icons8.com,
// ios-filled), a robot face cut out of a speech bubble: solid, it holds at
// bar size. Drawn for 50 units, scaled to 18.
ICONS[g(0xF16A3)] = '<path transform="scale(0.36)" fill="C" fill-rule="evenodd" d="M 25 0 C 23.4 0 22 1.3 22 3 C 22 3.8972342 22.396463 4.6747244 23 5.2167969 L 23 8 L 27 8 L 27 5.2480469 C 27.613687 4.7051151 28 3.9156799 28 3 C 28 1.3 26.7 0 25 0 z M 6 10 L 6 41 L 27.722656 41 L 27 50 L 37.691406 41 L 44 41 L 44 10 L 6 10 z M 18 19 C 19.7 19 21 20.3 21 22 C 21 23.7 19.7 25 18 25 C 16.4 25 15 23.7 15 22 C 15 20.3 16.4 19 18 19 z M 32 19 C 33.7 19 35 20.3 35 22 C 35 23.7 33.7 25 32 25 C 30.4 25 29 23.7 29 22 C 29 20.3 30.4 19 32 19 z M 1.2734375 19.005859 C 0.53652344 18.933166 0 19.504312 0 20.382812 L 0 28.412109 C 1.4802974e-16 29.416109 0.69960938 30.419703 1.5996094 30.720703 L 2.4003906 30.921875 C 3.3003906 31.222875 4 30.621188 4 29.617188 L 4 21.587891 C 4 20.583891 3.3003906 19.579906 2.4003906 19.378906 L 1.5996094 19.078125 C 1.4871094 19.0405 1.3787109 19.016244 1.2734375 19.005859 z M 48.726562 19.005859 C 48.621289 19.016244 48.512891 19.038547 48.400391 19.076172 L 47.599609 19.378906 C 46.699609 19.580906 46 20.583891 46 21.587891 L 46 29.617188 C 46 30.621188 46.699609 31.222875 47.599609 30.921875 L 48.400391 30.720703 C 49.300391 30.419703 50 29.416109 50 28.412109 L 50 20.382812 C 50 19.504312 49.463477 18.933166 48.726562 19.005859 z M 20 29 L 30 29 C 29.3 31.3 27.3 33 25 33 C 22.7 33 20.8 31.3 20 29 z"/>'
// AirDrop, for Omdrop's own drawn icon, which has no glyph to key it by:
// Icons8's AirDrop (icons8.com, ios), rings open at the bottom around a dot,
// drawn for 30 units and scaled to 18.
ICONS["airdrop"] = '<path transform="scale(0.6)" fill="C" d="M15,3c-7.168,0 -13,5.832 -13,13c0,4.774 2.59345,8.94408 6.43945,11.20508l1.08008,-1.68164c-3.293,-1.903 -5.51953,-5.45444 -5.51953,-9.52344c0,-6.065 4.935,-11 11,-11c6.065,0 11,4.935 11,11c0,4.069 -2.22653,7.62044 -5.51953,9.52344l1.08008,1.68164c3.846,-2.261 6.43945,-6.43108 6.43945,-11.20508c0,-7.168 -5.832,-13 -13,-13zM15,7c-4.962,0 -9,4.038 -9,9c0,3.364 1.85956,6.29975 4.60156,7.84375l1.08008,-1.68359c-2.19,-1.184 -3.68164,-3.50016 -3.68164,-6.16016c0,-3.86 3.14,-7 7,-7c3.86,0 7,3.14 7,7c0,2.66 -1.49164,4.97711 -3.68164,6.16211l1.08008,1.68164c2.742,-1.545 4.60156,-4.47975 4.60156,-7.84375c0,-4.962 -4.038,-9 -9,-9zM15,11c-2.757,0 -5,2.243 -5,5c0,1.955 1.13834,3.63308 2.77734,4.45508l1.08203,-1.68164c-1.09,-0.45 -1.85937,-1.52244 -1.85937,-2.77344c0,-1.654 1.346,-3 3,-3c1.654,0 3,1.346 3,3c0,1.251 -0.77033,2.32248 -1.86133,2.77148l1.08203,1.68359c1.64,-0.821 2.7793,-2.50008 2.7793,-4.45508c0,-2.757 -2.243,-5 -5,-5zM15,15c-0.55228,0 -1,0.44772 -1,1c0,0.55228 0.44772,1 1,1c0.55228,0 1,-0.44772 1,-1c0,-0.55228 -0.44772,-1 -1,-1z"/>'

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
