// Changes waiting for Apply that the desktop has anyway (made outside
// Studio) stop waiting; the rest stay. Kept out of QML so node can test it:
// node tests/pending.test.js

// The changes not met yet: the same object when none are, so QML sees no change.
function unmet(changes, met) {
    var left = {}
    for (var key in changes) if (!met(key, changes[key])) left[key] = changes[key]
    return Object.keys(left).length === Object.keys(changes).length ? changes : left
}

function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
}

// pending: { pieces, settings, places, bar, widgets }, as Main.qml keeps them.
// now: installed(piece), setting(key) (undefined when the theme doesn't
// report it), place(panel), and the bar and widgets as they are.
function forgetMet(pending, now) {
    return {
        pieces: unmet(pending.pieces, function(piece, on) { return on === now.installed(piece) }),
        settings: unmet(pending.settings, function(key, value) {
            var installed = now.setting(key)
            return typeof installed === "number" && Math.abs(value - installed) < 0.005
        }),
        places: unmet(pending.places, function(panel, place) { return place === now.place(panel) }),
        bar: pending.bar && same(pending.bar, now.bar) ? null : pending.bar,
        widgets: pending.widgets && same(pending.widgets, now.widgets) ? null : pending.widgets,
        // "all" or workspace numbers; null while unchanged.
        workspaces: pending.workspaces == null || same(pending.workspaces, now.workspaces) ? null : pending.workspaces
    }
}

if (typeof module !== "undefined") module.exports = { forgetMet: forgetMet }
