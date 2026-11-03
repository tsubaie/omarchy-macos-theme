.pragma library
// Control Centers on every bar, sharing one look at the camera: the first of
// them still there runs it, and the rest copy what it found. One library
// instance serves them all (.pragma library).

var watchers = []

function join(watcher) { watchers.push(watcher) }
function leave(watcher) { watchers = watchers.filter(function(w) { return w !== watcher }) }
// The one that looks; null when none is left.
function leader() { return watchers.length > 0 ? watchers[0] : null }
