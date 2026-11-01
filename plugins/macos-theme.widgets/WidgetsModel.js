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
    + "&current=temperature_2m,weather_code,is_day"
    + "&daily=temperature_2m_max,temperature_2m_min"
    + "&forecast_days=1&timezone=auto"
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
    day: Number(now.is_day) !== 0
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

if (typeof module !== "undefined") module.exports = { monthGrid: monthGrid, condition: condition, usesImperial: usesImperial, forecastUrl: forecastUrl, parseForecast: parseForecast, parsePlace: parsePlace }
