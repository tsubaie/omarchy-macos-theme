// Mission Control's spread, kept out of QML so it can be tested in node.

// Places windows ({ x, y, w, h } on screen) in a grid inside an area of
// width × height, each at its own proportions and never bigger than it is,
// none overlapping, the rows centered. Windows keep their order from the
// screen: top to bottom, then left to right, so each lands near where it was.
// Returns { x, y, w, h } per window, in the order given, relative to the area.
function spread(windows, width, height, gap) {
  var n = windows.length
  if (n === 0 || width <= 0 || height <= 0) return []
  gap = gap || 0
  var order = windows.map(function(w, i) { return i })
  order.sort(function(a, b) {
    var wa = windows[a], wb = windows[b]
    var rowA = Math.round(wa.y / 200), rowB = Math.round(wb.y / 200)
    return rowA !== rowB ? rowA - rowB : wa.x - wb.x
  })

  // The column count that shows the windows largest.
  var best = null
  for (var cols = 1; cols <= n; cols++) {
    var rows = Math.ceil(n / cols)
    var cellW = (width - gap * (cols - 1)) / cols
    var cellH = (height - gap * (rows - 1)) / rows
    if (cellW <= 0 || cellH <= 0) continue
    var area = 0
    var scales = order.map(function(i) {
      var w = windows[i]
      var s = Math.min(1, cellW / Math.max(1, w.w), cellH / Math.max(1, w.h))
      area += w.w * s * w.h * s
      return s
    })
    if (!best || area > best.area) best = { cols: cols, rows: rows, cellW: cellW, cellH: cellH, scales: scales, area: area }
  }
  if (!best) return windows.map(function() { return { x: 0, y: 0, w: 0, h: 0 } })

  var out = new Array(n)
  var gridH = best.rows * best.cellH + gap * (best.rows - 1)
  for (var r = 0; r < best.rows; r++) {
    var first = r * best.cols
    var inRow = Math.min(best.cols, n - first)
    // A short last row sits centered, as on macOS.
    var rowW = inRow * best.cellW + gap * (inRow - 1)
    var left = (width - rowW) / 2
    for (var c = 0; c < inRow; c++) {
      var k = first + c
      var i = order[k]
      var s = best.scales[k]
      var w = windows[i].w * s, h = windows[i].h * s
      var cellX = left + c * (best.cellW + gap)
      var cellY = (height - gridH) / 2 + r * (best.cellH + gap)
      out[i] = {
        x: Math.round(cellX + (best.cellW - w) / 2),
        y: Math.round(cellY + (best.cellH - h) / 2),
        w: Math.round(w),
        h: Math.round(h)
      }
    }
  }
  return out
}

if (typeof module !== "undefined") module.exports = { spread: spread }
