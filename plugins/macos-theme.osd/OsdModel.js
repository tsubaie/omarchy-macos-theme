function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// The widest glyph `iconFor` can return. The progress OSD sizes its icon
// column to it so the bar keeps its place as the icon changes.
var widestIcon = ""

function iconFor(name, percent) {
  var n = String(name || "").toLowerCase()
  if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return ""
  if (n === "volume-low") return ""
  if (n === "volume-medium") return ""
  if (n === "volume-high" || n === "volume") return ""
  if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "󰍭"
  if (n === "microphone" || n === "mic") return "󰍬"
  if (n === "keyboard") return "󰌌"
  if (n === "brightness" || n === "display") return "󰍹"
  if (n === "touchpad") return "󰟸"
  if (n === "touch" || n === "touchscreen") return "󰝁"
  if (n === "reboot" || n === "restart") return "󰜉"
  if (n === "shutdown" || n === "power" || n === "poweroff") return "󰐥"
  if (n === "logout" || n === "sign-out" || n === "leave") return "󰍃"
  if (n === "media" || n === "player") return "󰝚"
  if (n === "media-source" || n === "player-source") return "󰝚"
  if (n === "media-play" || n === "player-play") return "󰐊"
  if (n === "media-pause" || n === "player-pause") return "󰏤"
  if (n === "media-next" || n === "player-next") return "󰒭"
  if (n === "media-previous" || n === "player-previous") return "󰒮"
  if (n.length > 0) return name
  if (percent <= 0) return ""
  if (percent <= 33) return ""
  if (percent <= 66) return ""
  return ""
}

// fmt(value) writes the percentage in the display language; QML passes
// I18n.formatNumber, and without it the digits stay as they are.
function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration, fmt) {
  var number = typeof fmt === "function" ? fmt : function(v) { return String(v) }
  var maxValue = Math.max(1, parseInt(rawMax || "100", 10))
  var parsedValue = parseInt(rawValue || "0", 10)
  var hasProgress = rawValue !== "" && !isNaN(parsedValue) && rawMessage === ""
  var value = hasProgress ? clamp(parsedValue, 0, maxValue) : 0
  var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  var parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    iconKey: String(iconName || "").toLowerCase(),
    maxValue: maxValue,
    hasProgress: hasProgress,
    value: value,
    message: String(rawMessage || (hasProgress ? (rawProgressText || number(percent) + "%") : "")),
    icon: iconFor(iconName, percent),
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
  }
}

// The HUD's icon for an OSD (HudIcons.js), by its kind and level: the
// speaker by volume (muted at 0, as macOS shows it), the sun for brightness,
// the microphone and the keyboard; "" for any other, which keeps its glyph.
function hudIconName(iconKey, percent) {
  var k = String(iconKey || "").toLowerCase()
  if (k.indexOf("volume") === 0 || k === "muted" || k === "mute") {
    if (k.indexOf("mute") >= 0 || percent <= 0) return "volume-muted"
    if (percent <= 33) return "volume-low"
    if (percent <= 66) return "volume-medium"
    return "volume-high"
  }
  if (k === "brightness" || k === "display") return "brightness"
  if (k.indexOf("microphone") === 0 || k.indexOf("mic") === 0) return "microphone"
  if (k === "keyboard") return "keyboard"
  return ""
}

// A keyboard layout's short name, as the bar writes it: "English (US)" is
// "EN", "Arabic" is "AR".
function layoutCode(name) {
  var letters = String(name || "").replace(/[^A-Za-z]/g, "")
  return letters.slice(0, 2).toUpperCase()
}

if (typeof module !== "undefined") {
  module.exports = {
    widestIcon: widestIcon,
    iconFor: iconFor,
    stateForShow: stateForShow,
    hudIconName: hudIconName,
    layoutCode: layoutCode
  }
}
