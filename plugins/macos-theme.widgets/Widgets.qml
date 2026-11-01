import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "WidgetsModel.js" as Model

// macOS desktop widgets: a clock, a calendar, the weather and what's playing,
// stacked at the top left of the desktop on frosted glass. They sit on the
// desktop layer, so windows cover them, as on macOS.
Item {
  id: root

  property var shell: null

  readonly property real s: Style.fontScale
  readonly property int size: Math.round(158 * s)
  readonly property int pad: Math.round(14 * s)
  readonly property int radius: Math.round(22 * s)
  readonly property int gap: Math.round(14 * s)
  readonly property var formatLocale: Qt.locale(Commons.I18n.formatLocale)
  readonly property color red: "#ff453a"

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
  }

  // Weather: the place Omarchy's weather was given, or Omarchy's own lookup of
  // this network's city, then Open-Meteo, every 15 minutes.
  property var place: null
  property var weather: null

  FileView {
    id: placeFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.findPlace()
    onLoadFailed: root.findPlace()
  }

  function findPlace() {
    var saved = Model.parsePlace(placeFile.text())
    if (saved) { root.place = saved; root.fetchWeather() }
    else if (!lookup.running) lookup.running = true
  }

  function fetchWeather() {
    if (!root.place || forecast.running) return
    forecast.command = ["curl", "-fsS", "--max-time", "8", Model.forecastUrl(root.place.latitude, root.place.longitude)]
    forecast.running = true
  }

  Process {
    id: lookup
    command: ["curl", "-fsS", "--max-time", "5", "https://geo.omarchy.org/"]
    stdout: StdioCollector {
      onStreamFinished: {
        var found = Model.parsePlace(text)
        if (found) { root.place = found; root.fetchWeather() }
      }
    }
  }

  Process {
    id: forecast
    stdout: StdioCollector {
      onStreamFinished: {
        // A failed fetch keeps the last report on screen.
        var report = Model.parseForecast(text, Model.usesImperial(root.place ? root.place.country : "", Commons.I18n.formatLocale))
        if (report) root.weather = report
      }
    }
  }

  Timer {
    interval: 15 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.place ? root.fetchWeather() : root.findPlace()
  }

  // Now playing: Omarchy's media service picks the player, as its bar widget does.
  readonly property var media: shell && shell.firstPartyServiceFor ? shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var player: media ? media.activePlayer : (Mpris.players.values.length > 0 ? Mpris.players.values[0] : null)

  function mediaAction(action) {
    if (media && media.runAction) media.runAction(action, false)
    else if (player) {
      if (action === "playPause") player.togglePlaying()
      else if (action === "next") player.next()
      else if (action === "previous") player.previous()
    }
  }

  // The screen named by "widgets": { "screen": "<name>" } in shell.json
  // (names as hyprctl monitors lists them), else the first screen.
  property var config: ({})

  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.config = parsed && typeof parsed.widgets === "object" && parsed.widgets !== null ? parsed.widgets : ({})
      } catch (e) {
        root.config = ({})
      }
    }
  }
  readonly property var targetScreen: Quickshell.screens.find(function(each) { return each.name === String(root.config.screen || "") })
    || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

  PanelWindow {
    id: window
    screen: root.targetScreen
    color: "transparent"
    WlrLayershell.namespace: "omarchy-widgets"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    anchors { top: true; left: true }
    margins { top: root.gap; left: Math.round(20 * root.s) }
    implicitWidth: column.width
    implicitHeight: column.height

    Column {
      id: column
      spacing: root.gap

      // Clock: an analog face with a red second hand.
      Glass {
        Canvas {
          id: face
          anchors.fill: parent
          anchors.margins: root.pad
          readonly property date now: clock.date
          onNowChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            var w = width, r = w / 2
            ctx.reset()
            ctx.translate(r, r)
            ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2)
            ctx.fillStyle = "rgba(28, 28, 30, 0.85)"; ctx.fill()
            // Numbers 1 to 12.
            ctx.fillStyle = "white"
            ctx.font = "500 " + Math.round(r * 0.2) + "px Inter"
            ctx.textAlign = "center"; ctx.textBaseline = "middle"
            for (var i = 1; i <= 12; i++) {
              var a = i * Math.PI / 6
              ctx.fillText(String(i), Math.sin(a) * r * 0.78, -Math.cos(a) * r * 0.78)
            }
            function hand(angle, length, width, color) {
              ctx.save(); ctx.rotate(angle)
              ctx.beginPath(); ctx.moveTo(0, r * 0.1); ctx.lineTo(0, -length)
              ctx.lineWidth = width; ctx.lineCap = "round"; ctx.strokeStyle = color; ctx.stroke()
              ctx.restore()
            }
            var h = now.getHours() % 12, m = now.getMinutes(), sec = now.getSeconds()
            hand((h + m / 60) * Math.PI / 6, r * 0.5, r * 0.07, "white")
            hand((m + sec / 60) * Math.PI / 30, r * 0.74, r * 0.05, "white")
            hand(sec * Math.PI / 30, r * 0.8, r * 0.022, root.red)
            ctx.beginPath(); ctx.arc(0, 0, r * 0.05, 0, Math.PI * 2); ctx.fillStyle = root.red; ctx.fill()
          }
        }
      }

      // Calendar: the month with today in a red disc.
      Glass {
        id: calendar
        readonly property date today: clock.date
        readonly property var rows: Model.monthGrid(today.getFullYear(), today.getMonth(), root.formatLocale.firstDayOfWeek)
        readonly property real cell: (width - root.pad * 2) / 7

        Column {
          x: root.pad
          y: root.pad
          spacing: Math.round(2 * root.s)

          Text {
            textFormat: Text.PlainText
            text: root.formatLocale.toString(calendar.today, "MMMM").toUpperCase()
            color: root.red
            font.family: "Inter"
            font.weight: Font.Bold
            font.pixelSize: Math.round(11 * root.s)
            bottomPadding: Math.round(3 * root.s)
          }

          Row {
            Repeater {
              model: 7
              delegate: Text {
                required property int index
                width: calendar.cell
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.formatLocale.standaloneDayName((root.formatLocale.firstDayOfWeek + index) % 7, Locale.NarrowFormat)
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: "Inter"
                font.weight: Font.DemiBold
                font.pixelSize: Math.round(9 * root.s)
              }
            }
          }

          Repeater {
            model: calendar.rows
            delegate: Row {
              required property var modelData
              Repeater {
                model: modelData
                delegate: Item {
                  required property int modelData
                  readonly property bool isToday: modelData === calendar.today.getDate()
                  width: calendar.cell
                  height: Math.round(calendar.cell * 0.82)

                  Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) + 2
                    height: width
                    radius: width / 2
                    color: root.red
                    visible: parent.isToday
                  }

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.modelData > 0 ? Commons.I18n.formatNumber(parent.modelData) : ""
                    color: "white"
                    font.family: "Inter"
                    font.weight: parent.isToday ? Font.Bold : Font.Medium
                    font.pixelSize: Math.round(9.5 * root.s)
                  }
                }
              }
            }
          }
        }
      }

      // Weather: the place, the temperature, the sky and today's high and low,
      // on blue by day and navy by night, as the macOS widget is.
      Glass {
        fill: root.weather && !root.weather.day ? ["#1c2541", "#0b132b"] : ["#3a8dde", "#2160b0"]

        Column {
          x: root.pad
          y: root.pad
          width: parent.width - root.pad * 2

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.place && root.place.name ? root.place.name : "Weather"
            color: "white"
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(13 * root.s)
          }

          Text {
            textFormat: Text.PlainText
            text: root.weather ? Commons.I18n.formatNumber(root.weather.temp) + "°" : "--"
            color: "white"
            font.family: "Inter Display"
            font.weight: Font.Normal
            font.pixelSize: Math.round(40 * root.s)
          }
        }

        Column {
          x: root.pad
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.pad
          width: parent.width - root.pad * 2

          Text {
            textFormat: Text.PlainText
            text: root.weather ? root.weather.icon : ""
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Math.round(16 * root.s)
          }

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.weather ? root.weather.text : ""
            color: "white"
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(11 * root.s)
          }

          Text {
            textFormat: Text.PlainText
            visible: !!root.weather && root.weather.high !== null
            text: root.weather ? "H:" + Commons.I18n.formatNumber(root.weather.high) + "°  L:" + Commons.I18n.formatNumber(root.weather.low) + "°" : ""
            color: "white"
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(11 * root.s)
          }
        }
      }

      // Now playing: the artwork, the song and its artist, and the controls.
      Glass {
        id: playing
        readonly property bool has: !!root.player && !!(root.player.trackTitle || root.player.trackArtist)

        Item {
          id: art
          x: root.pad
          y: root.pad
          width: Math.round(56 * root.s)
          height: width

          Rectangle {
            id: artMask
            anchors.fill: parent
            radius: Math.round(8 * root.s)
            visible: false
            layer.enabled: true
          }

          Rectangle {
            anchors.fill: parent
            radius: artMask.radius
            color: Qt.rgba(1, 1, 1, 0.12)
            visible: artImage.status !== Image.Ready

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "♪"
              color: Qt.rgba(1, 1, 1, 0.6)
              font.pixelSize: Math.round(parent.height * 0.45)
            }
          }

          Image {
            id: artImage
            anchors.fill: parent
            source: playing.has && root.player.trackArtUrl ? root.player.trackArtUrl : ""
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
          }

          MultiEffect {
            anchors.fill: parent
            source: artImage
            visible: artImage.status === Image.Ready
            maskEnabled: true
            maskSource: artMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
          }
        }

        Column {
          x: root.pad
          y: art.y + art.height + Math.round(8 * root.s)
          width: parent.width - root.pad * 2

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: playing.has ? (root.player.trackTitle || "") : "Not Playing"
            color: "white"
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(12 * root.s)
          }

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: playing.has ? (root.player.trackArtist || "") : ""
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: "Inter"
            font.pixelSize: Math.round(11 * root.s)
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Math.round(10 * root.s)
          spacing: Math.round(20 * root.s)
          visible: playing.has

          Control { glyph: String.fromCodePoint(0xF04AE); action: "previous" }
          Control { glyph: String.fromCodePoint(root.player && root.player.isPlaying ? 0xF03E4 : 0xF040A); action: "playPause"; big: true }
          Control { glyph: String.fromCodePoint(0xF04AD); action: "next" }
        }
      }
    }
  }

  // A widget's frosted square; Hyprland blurs what is behind it. A gradient
  // in place of the glass when fill is given.
  component Glass: Rectangle {
    id: glass
    property var fill: null
    width: root.size
    height: root.size
    radius: root.radius
    color: Qt.rgba(0.16, 0.16, 0.18, 0.5)
    gradient: fill ? fillGradient : null
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    Gradient {
      id: fillGradient
      GradientStop { position: 0; color: glass.fill ? glass.fill[0] : "transparent" }
      GradientStop { position: 1; color: glass.fill ? glass.fill[1] : "transparent" }
    }
  }

  component Control: Text {
    property string glyph: ""
    property string action: ""
    property bool big: false
    textFormat: Text.PlainText
    text: glyph
    color: controlMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.85)
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Math.round((big ? 22 : 16) * root.s)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    MouseArea {
      id: controlMouse
      anchors.fill: parent
      anchors.margins: -Math.round(6 * root.s)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.mediaAction(parent.action)
    }
  }
}
