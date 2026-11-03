// Logic for the desktop widgets, kept out of QML so it can be tested in node.

// The month as rows of 7 days, starting on firstDay (0 Sunday … 6 Saturday,
// or Qt's 7 for Sunday); days outside the month are 0.
function monthGrid(year, month, firstDay) {
  var start = (new Date(year, month, 1).getDay() - firstDay % 7 + 7) % 7
  var days = new Date(year, month + 1, 0).getDate()
  var cells = []
  for (var i = 0; i < start; i++) cells.push(0)
  for (var d = 1; d <= days; d++) cells.push(d)
  while (cells.length % 7) cells.push(0)
  var rows = []
  for (var r = 0; r < cells.length; r += 7) rows.push(cells.slice(r, r + 7))
  return rows
}

// Open-Meteo's WMO weather code as macOS words and the Nerd Font weather
// glyph Omarchy's own weather uses for it.
function condition(code, isDay) {
  var c = Number(code)
  var night = Number(isDay) === 0
  if (c === 0) return { text: night ? "Clear" : "Sunny", icon: night ? "\ue32b" : "\ue30d" }
  if (c === 1) return { text: "Mostly Clear", icon: night ? "\ue32b" : "\ue30d" }
  if (c === 2) return { text: "Partly Cloudy", icon: night ? "\ue32e" : "\ue302" }
  if (c === 3) return { text: "Cloudy", icon: "\ue33d" }
  if (c === 45 || c === 48) return { text: "Foggy", icon: night ? "\ue346" : "\ue313" }
  if (c >= 51 && c <= 57) return { text: "Drizzle", icon: night ? "\ue333" : "\ue308" }
  if (c >= 61 && c <= 67) return { text: "Rain", icon: "\ue318" }
  if (c >= 71 && c <= 77) return { text: "Snow", icon: "\ue31a" }
  if (c >= 80 && c <= 82) return { text: "Showers", icon: night ? "\ue333" : "\ue308" }
  if (c === 85 || c === 86) return { text: "Snow Showers", icon: "\ue31a" }
  if (c >= 95) return { text: "Thunderstorms", icon: "\ue31d" }
  return { text: "", icon: "\ue33d" }
}

// Which scene the weather widget paints behind its text for a WMO code.
function scene(code) {
  var c = Number(code)
  if (c === 0 || c === 1) return "clear"
  if (c === 2) return "partly"
  if (c === 45 || c === 48) return "fog"
  if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return "rain"
  if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "snow"
  if (c >= 95) return "thunder"
  return "cloudy"
}

// The time of day the sky shows, from today's sunrise and sunset (ms): the
// warm "dawn" and "dusk" span the half hour before and the 45 minutes after
// the sun crosses the horizon, mirrored at sunset. Without the times, the
// forecast's day flag decides.
function dayPhase(now, sunrise, sunset, isDay) {
  if (typeof sunrise !== "number" || typeof sunset !== "number") return isDay ? "day" : "night"
  var min = 60 * 1000
  if (now >= sunrise - 30 * min && now < sunrise + 45 * min) return "dawn"
  if (now >= sunset - 45 * min && now < sunset + 30 * min) return "dusk"
  return now > sunrise && now < sunset ? "day" : "night"
}

// Wind from this speed (km/h, a strong breeze) blows through the scene.
var WINDY_KMH = 30

// Fahrenheit where it is the custom; a known country decides before the locale.
function usesImperial(country, localeName) {
  var c = String(country || "").toUpperCase()
  if (c) return ["US", "LR", "MM", "BS", "BZ", "KY", "PW"].indexOf(c) !== -1
  return /[-_]US$/.test(String(localeName || ""))
}

// The forecast URL for a place; the hours of today's high and low come in the
// same reply.
function forecastUrl(latitude, longitude) {
  return "https://api.open-meteo.com/v1/forecast"
    + "?latitude=" + encodeURIComponent(String(latitude))
    + "&longitude=" + encodeURIComponent(String(longitude))
    + "&current=temperature_2m,weather_code,is_day,wind_speed_10m"
    + "&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset"
    + "&forecast_days=1&timezone=auto&timeformat=unixtime"
}

// The forecast reply as what the widget shows, or null when it is unusable.
function parseForecast(raw, imperial) {
  var data
  try { data = JSON.parse(raw) } catch (e) { return null }
  var now = data && data.current
  var daily = data && data.daily
  if (!now || typeof now.temperature_2m !== "number") return null
  function temp(c) { return Math.round(imperial ? c * 9 / 5 + 32 : c) }
  var cond = condition(now.weather_code, now.is_day)
  return {
    temp: temp(now.temperature_2m),
    high: daily && daily.temperature_2m_max ? temp(daily.temperature_2m_max[0]) : null,
    low: daily && daily.temperature_2m_min ? temp(daily.temperature_2m_min[0]) : null,
    text: cond.text,
    icon: cond.icon,
    day: Number(now.is_day) !== 0,
    scene: scene(now.weather_code),
    sunrise: daily && daily.sunrise ? daily.sunrise[0] * 1000 : null,
    sunset: daily && daily.sunset ? daily.sunset[0] * 1000 : null,
    windy: Number(now.wind_speed_10m) >= WINDY_KMH
  }
}

// The place to look up: weather.json as Omarchy's weather saves it, else
// Omarchy's own network lookup; null when neither has coordinates.
function parsePlace(raw) {
  var data
  try { data = JSON.parse(raw) } catch (e) { return null }
  var lat = parseFloat(String(data && data.latitude))
  var lon = parseFloat(String(data && data.longitude))
  if (isNaN(lat) || isNaN(lon)) return null
  return { name: String(data.name || ""), latitude: lat, longitude: lon, country: String(data.country || "") }
}

// The widgets, in their first-run order down the left edge.
var WIDGETS = ["clock", "calendar", "weather", "playing"]
var NAMES = { clock: "Clock", calendar: "Calendar", weather: "Weather", playing: "Now Playing" }

function occupied(layout, col, row) {
  for (var i = 0; i < layout.length; i++) if (layout[i].col === col && layout[i].row === row) return layout[i]
  return null
}

// Where each shown widget sits, as [{ id, col, row }] grid cells, from what
// shell.json saved. Unknown ids and repeats are dropped, a widget on a taken
// cell moves to a free one, and nothing saved (or nothing usable) means all
// of them down the left edge, so the desktop never loses every widget.
// known: the ids that can show, the theme's own and yours (the theme's own
// alone when left out); with nothing saved, the theme's own show.
function normalizeLayout(saved, known) {
  known = known || WIDGETS
  var out = []
  if (Array.isArray(saved)) {
    var later = []
    for (var i = 0; i < saved.length; i++) {
      var w = saved[i] || {}
      var id = String(w.id || "")
      if (known.indexOf(id) < 0 || find(out, id) || later.indexOf(id) >= 0) continue
      var col = Number(w.col), row = Number(w.row)
      if (Number.isInteger(col) && Number.isInteger(row) && col >= 0 && row >= 0 && !occupied(out, col, row))
        out.push({ id: id, col: col, row: row })
      else
        later.push(id)
    }
    for (var j = 0; j < later.length; j++) {
      var cell = freeCell(out, 64, 64)
      out.push({ id: later[j], col: cell.col, row: cell.row })
    }
  }
  if (out.length === 0) out = WIDGETS.map(function(id, n) { return { id: id, col: 0, row: n } })
  return out
}

function find(layout, id) {
  for (var i = 0; i < layout.length; i++) if (layout[i].id === id) return layout[i]
  return null
}

// The widgets not shown, in their usual order, yours after the theme's own.
function hidden(layout, known) {
  return (known || WIDGETS).filter(function(id) { return !find(layout, id) })
}

// The first free cell, down each column from the left; null when all are taken.
function freeCell(layout, cols, rows) {
  for (var c = 0; c < cols; c++)
    for (var r = 0; r < rows; r++)
      if (!occupied(layout, c, r)) return { col: c, row: r }
  return null
}

// Where each widget shows on a grid of cols × rows: a cell saved on a larger
// screen (one since unplugged) is off this one, so that widget takes the first
// free cell instead, or the last cell when none is free. Only for showing:
// what was saved stays, and the larger screen gets its places back.
function fitLayout(layout, cols, rows) {
  var fits = function(w) { return w.col < cols && w.row < rows }
  var out = layout.filter(fits).map(function(w) { return { id: w.id, col: w.col, row: w.row } })
  layout.filter(function(w) { return !fits(w) }).forEach(function(w) {
    var cell = freeCell(out, cols, rows) || { col: cols - 1, row: rows - 1 }
    out.push({ id: w.id, col: cell.col, row: cell.row })
  })
  return out
}

// A widget dropped on a cell; one already there swaps into the cell it left.
function moveTo(layout, id, col, row) {
  var moving = find(layout, id)
  if (!moving) return layout
  var other = occupied(layout, col, row)
  return layout.map(function(w) {
    if (w.id === id) return { id: w.id, col: col, row: row }
    if (other && w.id === other.id) return { id: w.id, col: moving.col, row: moving.row }
    return { id: w.id, col: w.col, row: w.row }
  })
}

// Without a widget, but never the last one: right-click is the way back.
function remove(layout, id) {
  return layout.length <= 1 ? layout : layout.filter(function(w) { return w.id !== id })
}

function add(layout, id, cols, rows, known) {
  if ((known || WIDGETS).indexOf(id) < 0 || find(layout, id)) return layout
  var cell = freeCell(layout, cols, rows)
  return cell ? layout.concat([{ id: id, col: cell.col, row: cell.row }]) : layout
}

// The cell nearest a position, kept on the grid.
function snap(x, y, cell, cols, rows) {
  return {
    col: Math.max(0, Math.min(cols - 1, Math.round(x / cell))),
    row: Math.max(0, Math.min(rows - 1, Math.round(y / cell)))
  }
}

if (typeof module !== "undefined") module.exports = { monthGrid: monthGrid, condition: condition, usesImperial: usesImperial, forecastUrl: forecastUrl, parseForecast: parseForecast, parsePlace: parsePlace, WIDGETS: WIDGETS, NAMES: NAMES, scene: scene, dayPhase: dayPhase, normalizeLayout: normalizeLayout, fitLayout: fitLayout, find: find, hidden: hidden, freeCell: freeCell, moveTo: moveTo, remove: remove, add: add, snap: snap }
