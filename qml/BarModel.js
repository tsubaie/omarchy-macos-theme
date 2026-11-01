// The menu bar's items as three groups, Left, Center and Right, plus the
// hidden ones, on top of Omarchy's six sections. Kept out of QML so node can
// test it: node tests/bar-model.test.js

var CENTER = ["centerBegin", "center", "centerEnd"]

function ids(list) {
    return (list || []).map(function(item) { return item.id })
}

// The tray widget that holds the drawer's items; it isn't listed itself,
// since its items stand in its place.
function trayIndex(right) {
    for (var i = 0; i < right.length; i++) if (right[i].drawer) return i
    return -1
}

// {left, center, right, hidden} as lists of ids, from `install.sh --bar --json`.
// Center joins the three middle sections; Right shows the drawer's items where
// the tray is.
function groups(bar) {
    var s = (bar && bar.sections) || {}
    var right = s.right || []
    var tray = trayIndex(right)
    var shownRight = ids(right)
    if (tray >= 0) shownRight.splice.apply(shownRight, [tray, 1].concat(ids(s.tray)))
    else shownRight = shownRight.concat(ids(s.tray))
    return {
        left: ids(s.left),
        center: [].concat(ids(s.centerBegin), ids(s.center), ids(s.centerEnd)),
        right: shownRight,
        hidden: ids(bar && bar.hidden)
    }
}

function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
}

// Moves an item to a group at an index (0 is first), out of wherever it was.
// Dropping an item just below itself leaves it where it is.
function move(g, id, group, index) {
    var next = { left: [], center: [], right: [], hidden: [] }
    var from = ""
    var at = -1
    for (var k in next) {
        var list = g[k] || []
        if (list.indexOf(id) >= 0) { from = k; at = list.indexOf(id) }
        next[k] = list.filter(function(x) { return x !== id })
    }
    if (!(group in next)) return g
    if (from === group && at >= 0 && at < index) index -= 1
    var target = next[group]
    target.splice(Math.max(0, Math.min(index, target.length)), 0, id)
    return next
}

// The arrangement to apply, in Omarchy's sections: a group left as it was
// keeps its sections untouched; a changed Center goes in the middle section
// alone, and a changed Right goes on the right after the tray, with the
// drawer empty, since the tray is always open.
function layout(bar, g) {
    var s = (bar && bar.sections) || {}
    var was = groups(bar)
    var sections = { left: g.left.slice() }
    if (same(was.center, g.center)) {
        for (var i = 0; i < CENTER.length; i++) sections[CENTER[i]] = ids(s[CENTER[i]])
    } else {
        sections.centerBegin = []
        sections.center = g.center.slice()
        sections.centerEnd = []
    }
    if (same(was.right, g.right)) {
        sections.right = ids(s.right)
        sections.tray = ids(s.tray)
    } else {
        var right = s.right || []
        var tray = trayIndex(right)
        sections.right = tray >= 0 ? [right[tray].id].concat(g.right) : g.right.slice()
        sections.tray = []
    }
    return { sections: sections, hidden: g.hidden.slice() }
}

if (typeof module !== "undefined") module.exports = { groups: groups, move: move, layout: layout }
