import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
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

  // Dawn, day, dusk or night now, rechecked every minute.
  readonly property string dayPhase: root.weather
    ? Model.dayPhase(minute.date.getTime(), root.weather.sunrise, root.weather.sunset, root.weather.day)
    : "day"

  SystemClock {
    id: minute
    precision: SystemClock.Minutes
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
  readonly property var homeScreen: Quickshell.screens.find(function(each) { return each.name === String(root.config.screen || "") })
    || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
  // The widgets show on every screen showing a workspace they show on (each
  // window decides). This is the one whose desktop the weather watches to
  // rest when covered: the one being worked on, else the first showing them,
  // else their own screen (widgets.screen, else the first).
  readonly property var targetScreen: {
    var chosen = root.config.workspaces
    var showing = function(screen) {
      var monitor = Hyprland.monitorFor(screen)
      return !!monitor && !!monitor.activeWorkspace && Model.showsOn(chosen, monitor.activeWorkspace.id)
    }
    var focused = Hyprland.focusedMonitor ? Quickshell.screens.find(function(each) { return each.name === Hyprland.focusedMonitor.name }) : null
    if (focused && showing(focused)) return focused
    return Quickshell.screens.find(showing) || root.homeScreen
  }

  // The grid: each widget sits in a cell a widget plus a gap wide, from the
  // top left; dragging one snaps it to the nearest cell, and dropping it on
  // another swaps them. Where each sits is saved in shell.json.
  readonly property int cell: size + gap
  readonly property var layout: Model.normalizeLayout(config.layout, known)
  // Motion kept still: Omarchy's animations off, or the theme's Reduce
  // motion (install.sh --set reduce-motion=1), read from the look Hyprland has
  // loaded and followed as it changes.
  property bool lookReducesMotion: false
  readonly property bool reduceMotion: Style.reduceMotion || lookReducesMotion
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/look.lua"
    watchChanges: true
    printErrors: false
    onLoaded: root.lookReducesMotion = /^local REDUCE_MOTION = 1$/m.test(text())
    onLoadFailed: root.lookReducesMotion = false
    onFileChanged: reload()
  }

  // The layout as this screen shows it, every widget on it.

  // The desktop under the widgets is in sight when the workspace on their
  // screen is empty or floating; tiled windows cover it, and the weather's
  // rain, snow and clouds stop there rather than run unseen all day.
  readonly property var shownWorkspace: {
    var monitor = root.targetScreen ? Hyprland.monitorFor(root.targetScreen) : null
    return monitor ? monitor.activeWorkspace : null
  }
  property bool shownFloating: false
  // On every workspace, or only those "workspaces": [1, 2] in shell.json names
  // (install.sh --widget-workspaces, Studio's Widgets page); hidden elsewhere.
  readonly property bool onThisWorkspace: !shownWorkspace || Model.showsOn(root.config.workspaces, shownWorkspace.id)
  readonly property bool desktopSeen: onThisWorkspace && (!shownWorkspace || shownWorkspace.toplevels.values.length === 0 || shownFloating)
  onShownWorkspaceChanged: readMode()
  // A first value sends no change, so the workspace shown at login is read here.
  Component.onCompleted: readMode()
  // shortcut: a workspace's layout changed while it stays shown is seen on the next switch; the dock's refresh IPC would cover it.
  function readMode() {
    if (!shownWorkspace || !(shownWorkspace.id >= 1)) return
    if (modeRead.running) { modeRead.again = true; return }
    modeRead.command = ["omarchy-hyprland-workspace-layout-current", String(shownWorkspace.id)]
    modeRead.running = true
  }
  Process {
    id: modeRead
    property bool again: false
    stdout: StdioCollector { onStreamFinished: root.shownFloating = text.trim() === "floating" }
    onExited: if (again) { again = false; Qt.callLater(root.readMode) }
  }
  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"

  // Shown at once, then written to shell.json (through a temporary file, so
  // the shell never reads half of it), one write at a time.
  property var pendingLayout: null

  // Widgets of your own: a folder each in ~/.config/omarchy/macos-theme-widgets,
  // named for its id, with a Widget.qml and maybe a manifest.json naming it
  // (docs/make-a-widget/SKILL.md). Looked for at start and whenever a widget's
  // menu opens, so a new one can be added without a restart.
  readonly property string customDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/macos-theme-widgets"
  property var custom: []
  property bool scanned: false
  readonly property var known: Model.WIDGETS.concat(custom.map(function(w) { return w.id }))
  function nameOf(id) {
    var own = custom.find(function(w) { return w.id === id })
    return own ? own.name : (Model.NAMES[id] || id)
  }
  Process {
    id: scan
    running: true
    // The same rule as install.sh's custom_widget: a safe name, not the theme's own.
    command: ["sh", "-c", 'for d in "$1"/*/; do id=$(basename "$d"); '
      + 'case "$id" in clock|calendar|weather|playing) continue ;; esac; '
      + 'printf "%s" "$id" | grep -qE "^[a-z0-9][a-z0-9-]*$" && [ -f "$d/Widget.qml" ] || continue; '
      + 'name=$(jq -r ".name | strings" "$d/manifest.json" 2>/dev/null); '
      + 'jq -cn --arg id "$id" --arg name "${name:-$id}" "{id: \\$id, name: \\$name}"; done | jq -cs .', "sh", root.customDir]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.custom = JSON.parse(text) } catch (e) { root.custom = [] }
        root.scanned = true
      }
    }
  }

  function save(layout) {
    // Not before your own widgets are known, or their places would be dropped.
    if (!root.scanned) return
    root.config = Object.assign({}, root.config, { layout: layout })
    root.pendingLayout = layout
    if (!saver.running) root.writeNext()
  }

  function writeNext() {
    if (!root.pendingLayout) return
    saver.command = ["sh", "-c",
      // Beside the real file (a dotfiles symlink stays one), with its mode.
      'f=$(readlink -f "$1"); [ -s "$f" ] || echo "{}" > "$f"; t=$(mktemp "$f.XXXXXX") && chmod --reference="$f" "$t" && jq --argjson v "$2" ".widgets.layout = \\$v" "$f" > "$t" && mv "$t" "$f" || rm -f "$t"',
      "sh", root.configPath, JSON.stringify(root.pendingLayout)]
    root.pendingLayout = null
    saver.running = true
  }

  Process {
    id: saver
    onExited: root.writeNext()
  }

  // The right-click menu: Remove Widget, and Add for each widget not shown.
  property string menuFor: ""
  property point menuAt: Qt.point(0, 0)

  function openMenu(id, x, y) {
    if (!scan.running) scan.running = true
    root.menuFor = id
    root.menuAt = Qt.point(x, y)
    menuLeave.stop()
  }

  Timer {
    id: menuLeave
    interval: 700
    onTriggered: root.menuFor = ""
  }

  readonly property var contents: ({ clock: clockContent, calendar: calendarContent, weather: weatherContent, playing: playingContent })

  // One window on every screen, always mapped, as the dock's are: moving the
  // widgets to another screen or workspace only shows them in the window
  // that's already there, where a fresh window wouldn't be drawn until the
  // pointer moved over it. Only the target screen's builds the widgets; while
  // hidden, a window takes no clicks.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: window
      required property var modelData
      screen: modelData
      // Shown on every screen showing a workspace they show on, each screen
      // laying them out on its own grid; their own screen when Hyprland
      // doesn't say which workspace a screen shows.
      readonly property var monitor: Hyprland.monitorFor(modelData)
      readonly property bool showing: monitor && monitor.activeWorkspace
        ? Model.showsOn(root.config.workspaces, monitor.activeWorkspace.id)
        : modelData === root.homeScreen
      readonly property int cols: Math.max(1, Math.floor((width - area.x + root.gap) / root.cell))
      readonly property int rows: Math.max(1, Math.floor((height - area.y + root.gap) / root.cell))
      readonly property var shown: Model.fitLayout(root.layout, cols, rows)
      color: "transparent"
      WlrLayershell.namespace: "omarchy-widgets"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0
      anchors { top: true; bottom: true; left: true; right: true }
  
      // Only the widgets (and the menu) take clicks; the rest of the desktop is
      // left alone. A drag keeps the pointer past these bounds until released.
      mask: Region {
        x: tiles.childrenRect.x + area.x
        y: tiles.childrenRect.y + area.y
        width: window.showing ? tiles.childrenRect.width : 0
        height: window.showing ? tiles.childrenRect.height : 0
  
        Region { item: root.menuFor && window.showing ? menu : null }
      }
  
      Item {
        id: area
        visible: window.showing
        x: Math.round(20 * root.s)
        y: root.gap
        width: parent.width - x
        height: parent.height - y
  
        Item {
          id: tiles
          anchors.fill: parent
  
          Repeater {
            model: window.showing ? root.known : []
  
            delegate: Glass {
              id: tile
              required property string modelData
              readonly property var spot: Model.find(window.shown, modelData)
              readonly property bool dragging: dragArea.drag.active
  
              visible: spot !== null
              x: spot ? spot.col * root.cell : 0
              y: spot ? spot.row * root.cell : 0
              z: dragging ? 10 : 0
              scale: dragging ? 1.04 : 1
              opacity: dragging ? 0.92 : 1
  
              Behavior on x { enabled: !tile.dragging && !root.reduceMotion; NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
              Behavior on y { enabled: !tile.dragging && !root.reduceMotion; NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
              Behavior on scale { NumberAnimation { duration: 120 } }
  
              // Under the content, so the media buttons still take their clicks.
              MouseArea {
                id: dragArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                drag.target: tile
                drag.threshold: 6
                cursorShape: dragArea.drag.active ? Qt.ClosedHandCursor : Qt.ArrowCursor
                onPressed: function(event) {
                  if (event.button === Qt.RightButton) {
                    var p = mapToItem(area, event.x, event.y)
                    root.openMenu(tile.modelData, p.x, p.y)
                  } else root.menuFor = ""
                }
                onReleased: {
                  if (!tile.spot) return
                  var cell = Model.snap(tile.x, tile.y, root.cell, window.cols, window.rows)
                  // Back under the layout's control, then to the cell it snapped to.
                  tile.x = Qt.binding(function() { return tile.spot ? tile.spot.col * root.cell : 0 })
                  tile.y = Qt.binding(function() { return tile.spot ? tile.spot.row * root.cell : 0 })
                  if (cell.col !== tile.spot.col || cell.row !== tile.spot.row)
                    // From where widgets show, so a swap lands on this screen too.
                    root.save(Model.moveTo(window.shown, tile.modelData, cell.col, cell.row))
                }
              }
  
              Loader {
                anchors.fill: parent
                active: !!root.contents[tile.modelData]
                sourceComponent: root.contents[tile.modelData]
              }
              // One of yours: its Widget.qml, filling the card. One that doesn't
              // load says so in its card, and the others carry on.
              Loader {
                id: own
                anchors.fill: parent
                active: !root.contents[tile.modelData]
                source: active ? "file://" + root.customDir + "/" + tile.modelData + "/Widget.qml" : ""
              }
              Text {
                visible: own.active && own.status === Loader.Error
                anchors.fill: parent
                anchors.margins: Math.round(16 * root.s)
                text: root.nameOf(tile.modelData) + " couldn't load. Its Widget.qml has an error; the shell's log says which."
                color: Qt.rgba(1, 1, 1, 0.7)
                font.pixelSize: Math.round(12 * root.s)
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
              }
            }
          }
        }
  
        Rectangle {
          id: menu
          visible: root.menuFor !== ""
          x: Math.min(root.menuAt.x, area.width - width - root.gap)
          y: Math.min(root.menuAt.y, area.height - height - root.gap)
          z: 20
          width: Math.max(Math.round(170 * root.s), menuColumn.implicitWidth + Math.round(12 * root.s))
          height: menuColumn.implicitHeight + Math.round(12 * root.s)
          radius: Math.round(10 * root.s)
          color: Qt.rgba(0.16, 0.16, 0.18, 0.92)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.14)
  
          HoverHandler {
            onHoveredChanged: hovered ? menuLeave.stop() : menuLeave.restart()
          }
  
          Column {
            id: menuColumn
            anchors.centerIn: parent
            width: parent.width - Math.round(12 * root.s)
  
            MenuRow {
              label: "Remove Widget"
              enabled: root.layout.length > 1
              onChosen: root.save(Model.remove(root.layout, root.menuFor))
            }
  
            Rectangle {
              visible: Model.hidden(root.layout, root.known).length > 0
              width: parent.width
              height: visible ? Math.round(9 * root.s) : 0
              color: "transparent"
              Rectangle { anchors.centerIn: parent; width: parent.width - Math.round(12 * root.s); height: 1; color: Qt.rgba(1, 1, 1, 0.14) }
            }
  
            Repeater {
              model: Model.hidden(root.layout, root.known)
              delegate: MenuRow {
                required property string modelData
                label: "Add " + root.nameOf(modelData)
                onChosen: root.save(Model.add(root.layout, modelData, window.cols, window.rows, root.known))
              }
            }
          }
        }
      }
    }
  }

  component MenuRow: Rectangle {
    id: row
    property string label: ""
    signal chosen()
    width: parent ? parent.width : 0
    height: Math.round(26 * root.s)
    radius: Math.round(6 * root.s)
    color: rowMouse.containsMouse && row.enabled ? "#0a84ff" : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      x: Math.round(10 * root.s)
      textFormat: Text.PlainText
      text: row.label
      color: row.enabled ? "white" : Qt.rgba(1, 1, 1, 0.35)
      font.family: "Inter"
      font.pixelSize: Math.round(13 * root.s)
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: row.enabled
      // The action first: Remove reads which widget the menu is for. An Add
      // row is gone once its widget is added, so the menu is held beforehand.
      onClicked: {
        var owner = root
        row.chosen()
        owner.menuFor = ""
      }
    }
  }

  // Clock: an analog face with a red second hand.
  Component {
    id: clockContent
    Item {
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
  }

  // Calendar: the month with today in a red disc.
  Component {
    id: calendarContent
    Item {
      id: calendar
      anchors.fill: parent
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

  }

  // Weather: the place, the temperature, the sky and today's high and low,
  // on blue by day and navy by night, as the macOS widget is.
  Component {
    id: weatherContent
    Item {
      anchors.fill: parent

      WeatherScene {
        anchors.fill: parent
        visible: !!root.weather
        scene: root.weather ? root.weather.scene : "cloudy"
        phase: root.dayPhase
        windy: root.weather ? root.weather.windy : false
        still: !root.desktopSeen || root.reduceMotion
        radius: root.radius
      }

      Column {
        x: root.pad
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Qt.rgba(0, 0, 0, 0.45)
          shadowBlur: 0.5
          shadowVerticalOffset: 1
        }
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
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Qt.rgba(0, 0, 0, 0.45)
          shadowBlur: 0.5
          shadowVerticalOffset: 1
        }
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

  }

  // Now playing: the artwork, the song and its artist, and the controls.
  Component {
    id: playingContent
    Item {
      id: playing
      anchors.fill: parent
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

  // A widget's frosted square, the wallpaper showing through as on macOS;
  // Hyprland blurs what is behind it (theme/look.lua's light-glass rule).
  component Glass: Rectangle {
    width: root.size
    height: root.size
    radius: root.radius
    color: Qt.rgba(0.12, 0.12, 0.14, 0.3)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.16)
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
