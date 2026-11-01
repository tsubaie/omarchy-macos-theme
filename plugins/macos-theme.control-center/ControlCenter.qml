import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// macOS Control Center: one icon in the bar for the system's switches, on a
// card of frosted glass in the theme's colors, laid out as macOS has it:
// Wi-Fi and Bluetooth by what is playing, then Tailscale, Focus, Display and
// Power, then brightness and sound. A click on a switch's icon turns it on or
// off; anywhere else on it opens Omarchy's own panel, with the full controls.
// Only the widgets on the bar show here, as their panels live in them.
BarWidget {
  id: root
  moduleName: "macos-theme.control-center"

  property bool open: false
  // The Power pill shows its actions in place; one that ends the session
  // waits for a second click, while it says so.
  property bool powerOpen: false
  property string armed: ""

  function power(action) {
    if (action !== "lock" && armed !== action) {
      armed = action
      disarm.restart()
      return
    }
    root.open = false
    Util.execDetached(action === "lock" ? "omarchy-system-lock" : "omarchy-system " + action)
  }
  Timer {
    id: disarm
    interval: 4000
    onTriggered: root.armed = ""
  }
  readonly property color foreground: root.bar ? root.bar.barForeground : Commons.Color.foreground

  // What each switch is doing, read when the card opens.
  property string networkKind: ""
  property string networkName: ""
  property bool bluetoothOn: false
  property bool tailscaleOn: false
  property bool wifiOn: false
  // Focus is Omarchy's Do Not Disturb for notifications.
  property bool focusOn: false

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  // The apps recording from the microphone, as Omarchy's Microphone widget
  // tells them: a recording stream, not muted, that isn't the shell's own
  // level meter or audio processing that always records.
  readonly property var micSource: Pipewire.defaultAudioSource
  readonly property bool micMuted: UntypedInput.active ? (!UntypedInput.known || UntypedInput.muted)
    : (micSource && micSource.audio ? micSource.audio.muted : true)
  readonly property var recording: {
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    var names = nodes.filter(function(n) { return n && n.name }).map(function(n) { return String(n.name) })
    return nodes.filter(function(n) {
      return n && n.isStream && n.isSink === false && !(n.audio && n.audio.muted)
        && !AudioNodes.isShellLevelMeter(n.name) && !AudioNodes.platformHides(n.name, names)
    })
  }
  readonly property bool micInUse: recording.length > 0 && !micMuted
  // Each app as {name, icon}, by its launcher entry where one matches.
  function appFor(key, fallback) {
    var entry = (key && DesktopEntries.heuristicLookup(key)) || (fallback && DesktopEntries.heuristicLookup(fallback))
      || entryFor(String(key || fallback || "").toLowerCase())
    // Unchecked: the check misses icons only the base hicolor theme has,
    // which still load; one that doesn't shows the name's first letter.
    var icon = entry && entry.icon ? Quickshell.iconPath(entry.icon) : ""
    return { name: entry && entry.name ? entry.name : (fallback || key || "An app"), icon: icon }
  }
  // An app's launcher entry by its process name, as "chrome" is Chrome's:
  // an entry whose id or command is that name, else the shortest id that
  // has it in it.
  function entryFor(name) {
    if (!name) return null
    var all = DesktopEntries.applications.values, best = null
    for (var i = 0; i < all.length; i++) {
      var e = all[i], id = String(e.id || "").toLowerCase()
      var command = e.command && e.command.length ? String(e.command[0]).split("/").pop().toLowerCase() : ""
      if (id === name || command === name) return e
      if (id.indexOf(name) >= 0 && (!best || id.length < String(best.id).length)) best = e
    }
    return best
  }
  function uniqueApps(list) {
    var seen = [], out = []
    for (var i = 0; i < list.length; i++) {
      if (seen.indexOf(list[i].name) >= 0) continue
      seen.push(list[i].name)
      out.push(list[i])
    }
    return out
  }
  readonly property var micApps: uniqueApps(recording.map(function(n) {
    var p = n.properties || {}
    return appFor(p["application.process.binary"] || "", p["application.name"] || n.nickname || n.description || n.name)
  }))
  readonly property var cameraAppList: uniqueApps(cameraApps.map(function(n) { return appFor(n.toLowerCase(), n) }))
  PwObjectTracker { objects: root.micSource ? [root.micSource].concat(root.recording) : root.recording }

  // The apps using a camera: those holding a /dev/video device open, looked
  // up every two seconds. One using it through PipeWire shows as PipeWire's
  // own, so it is named "Camera" alone.
  property var cameraApps: []
  property bool cameraInUse: false
  Process {
    id: camera
    command: ["sh", "-c", "for p in $(fuser /dev/video* 2>/dev/null); do cat /proc/$p/comm; done | sort -u"]
    property var found: []
    onStarted: found = []
    stdout: SplitParser {
      onRead: function(line) { camera.found.push(String(line).trim()) }
    }
    onExited: {
      var apps = found.filter(function(n) { return n && !/^(pipewire|wireplumber)/.test(n) })
        .map(function(n) { return n.charAt(0).toUpperCase() + n.slice(1) })
      root.cameraInUse = found.length > 0
      if (apps.join() !== root.cameraApps.join()) root.cameraApps = apps
    }
  }
  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!camera.running) camera.running = true
  }

  // The apps that stopped using them in the last two minutes.
  property var micRecent: []
  property var cameraRecent: []
  property var lastMicApps: []
  property var lastCameraApps: []
  onMicAppsChanged: if (micApps.length) lastMicApps = micApps
  onCameraAppListChanged: if (cameraAppList.length) lastCameraApps = cameraAppList
  onMicInUseChanged: {
    if (micInUse) micRecent = []
    else { micRecent = lastMicApps; forget.restart() }
  }
  onCameraInUseChanged: {
    if (cameraInUse) cameraRecent = []
    else { cameraRecent = lastCameraApps; forget.restart() }
  }
  Timer {
    id: forget
    interval: 120000
    onTriggered: {
      root.micRecent = []
      root.cameraRecent = []
    }
  }

  // Now playing: the player that is playing, else the first with a track.
  readonly property var player: {
    var all = Mpris.players.values.filter(function(p) { return p && (p.trackTitle || p.trackArtist) })
    return all.find(function(p) { return p.isPlaying }) || all[0] || null
  }

  function close() {
    root.open = false
  }

  // The widgets this stands in for. They stay on the bar, where their panels
  // live, but out of sight, so their panels open from here alone.
  readonly property var standsInFor: ["omarchy.network", "omarchy.bluetooth", "omarchy.tailscale",
    "omarchy.audio", "omarchy.monitor", "omarchy.power"]
  property var hidden: []

  function hideWidgets(item) {
    if (item !== root && "moduleName" in item && root.standsInFor.indexOf(item.moduleName) >= 0) {
      if (!root.hidden.some(function(h) { return h.target === item })) {
        root.hidden = root.hidden.concat([hider.createObject(root, { target: item })])
      }
      return
    }
    for (var i = 0; i < item.children.length; i++) hideWidgets(item.children[i])
  }

  // Widgets are loaded again as they move about the bar; a look now and then
  // finds the new ones.
  Timer {
    interval: 1500
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      var kept = root.hidden.filter(function(h) {
        if (h.target) return true
        h.destroy()
        return false
      })
      if (kept.length !== root.hidden.length) root.hidden = kept
      var top = root
      while (top.parent) top = top.parent
      root.hideWidgets(top)
    }
  }

  // Whether a widget is on this bar, so its controls show here, and the
  // widget itself (the holder's activeItem) for what it offers.
  function live(id) {
    return root.hidden.some(function(h) { return h.target && h.target.moduleName === id })
  }
  function widget(id) {
    var h = root.hidden.find(function(h) { return h.target && h.target.moduleName === id })
    return h && h.target ? h.target.activeItem : null
  }
  readonly property var display: widget("omarchy.monitor")

  // Their own visibility comes back when Control Center goes.
  Component {
    id: hider
    Binding {
      property: "visible"
      value: false
      restoreMode: Binding.RestoreBindingOrValue
    }
  }

  // Opens one of Omarchy's panels for the full controls, on this monitor. Its
  // bar widget is on the bar, unseen, which keeps the panel alive.
  function openPanel(target) {
    root.open = false
    var window = root.QsWindow.window
    var screen = window && window.screen ? String(window.screen.name || "") : ""
    // The focus is for the panel's keyboard. The panel itself is this bar's
    // own copy of the widget: asked by id, the shell picks the copy on the
    // monitor it last heard had focus, which may still be the other one.
    if (screen) Util.execDetached("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + screen + "\" })"))
    var own = root.hidden.find(function(h) { return h.target && h.target.moduleName === target })
    // What is hidden is the bar's holder for the widget; the widget is its
    // activeItem, and its own open() opens the panel on this monitor.
    var widget = own && own.target ? own.target.activeItem : null
    if (widget && typeof widget.open === "function") widget.open()
    else Util.execDetached("omarchy-shell -q " + target + " open")
  }

  onOpenChanged: {
    if (open) status.running = true
    else {
      powerOpen = false
      armed = ""
    }
  }

  // One "key:value" line each: the connected network, and whether Wi-Fi,
  // Bluetooth, Tailscale and Focus are on.
  Process {
    id: status
    command: ["sh", "-c",
      "nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '$2==\"connected\" && ($1==\"wifi\"||$1==\"ethernet\") {print \"net:\"$1\":\"$3; exit}'; "
      + "echo wifi:$(nmcli radio wifi 2>/dev/null); "
      + "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo bt:on || echo bt:off; "
      // Tailscale's own state; its interface stays "connected" while it is
      // off. Only where its CLI can't reach the daemon, the interface.
      + "ts=$(tailscale status --json 2>/dev/null | grep -o '\"BackendState\": *\"[A-Za-z]*\"'); "
      + "if [ -n \"$ts\" ]; then case $ts in *Running*) echo ts:on ;; *) echo ts:off ;; esac; "
      + "else nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -q '^tailscale0:connected' && echo ts:on || echo ts:off; fi; "
      + "echo focus:$(omarchy-shell notifications isDnd 2>/dev/null)"]
    // Read as the lines come: the exit can be reported before the last one.
    stdout: SplitParser {
      onRead: function(line) { root.readStatus(String(line).trim()) }
    }
    onStarted: {
      root.networkKind = ""
      root.networkName = ""
    }
  }

  function readStatus(line) {
    var colon = line.indexOf(":")
    if (colon < 0) return
    var key = line.slice(0, colon), value = line.slice(colon + 1)
    if (key === "net") {
      var at = value.indexOf(":")
      root.networkKind = at > 0 ? value.slice(0, at) : ""
      root.networkName = at > 0 ? value.slice(at + 1) : ""
    }
    else if (key === "wifi") root.wifiOn = value === "enabled"
    else if (key === "bt") root.bluetoothOn = value === "on"
    else if (key === "ts") root.tailscaleOn = value === "on"
    else if (key === "focus") root.focusOn = value === "on"
  }

  // A switch flips at once on the card, then is read again once the system
  // has had a moment to follow.
  function run(command) {
    Util.execDetached(command)
    recheck.restart()
  }
  Timer {
    id: recheck
    interval: 1500
    onTriggered: if (!status.running) status.running = true
  }

  visible: !vertical
  implicitWidth: Style.space(30) + (micInUse || cameraInUse ? dots.width + Style.space(6) : 0)
  implicitHeight: barSize

  // macOS's dots while an app is using them: green for a camera, orange
  // for the microphone. Control Center names the apps.
  Row {
    id: dots
    x: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Repeater {
      model: [
        { on: root.cameraInUse, color: "#30d158" },
        { on: root.micInUse, color: "#ff9f0a" }
      ]

      delegate: Rectangle {
        required property var modelData
        visible: modelData.on
        width: Style.space(7)
        height: width
        radius: width / 2
        color: modelData.color
      }
    }
  }

  // The Control Center icon: two switches, one on and one off.
  Column {
    anchors.right: parent.right
    anchors.rightMargin: (Style.space(30) - width) / 2
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Repeater {
      model: [true, false]

      delegate: Rectangle {
        required property bool modelData
        width: Style.space(15)
        height: Style.space(6)
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: root.foreground

        Rectangle {
          width: parent.height - 2
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          x: parent.modelData ? parent.width - width - 1 : 1
          color: root.foreground
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.open = !root.open
  }

  // The switches under Wi-Fi and Bluetooth, in order: those whose widgets
  // are here, Focus always. Power opens across the whole row; in the right
  // column it would wrap to the next, so the one beside it moves after it
  // instead and Power stays put.
  readonly property var pillOrder: {
    var ids = []
    if (live("omarchy.tailscale")) ids.push("tailscale")
    ids.push("focus")
    if (live("omarchy.monitor")) ids.push("display")
    if (powerOpen && ids.length % 2 === 1) ids.splice(ids.length - 1, 0, "power")
    else ids.push("power")
    return ids
  }

  function pillInfo(id) {
    if (id === "tailscale") return { glyph: "󰖂", title: "Tailscale", subtitle: tailscaleOn ? "Connected" : "Off", on: tailscaleOn }
    // Focus is a switch alone: Omarchy has no panel for it.
    if (id === "focus") return { glyph: "󰖔", title: "Focus", subtitle: focusOn ? "On" : "Off", on: focusOn }
    if (id === "display") return { glyph: "󰍹", title: "Display", subtitle: "Arrange", on: true }
    return { glyph: "󰐥", title: "Power", subtitle: powerOpen ? "Lock, Log Out, Restart or Shut Down" : "Lock, Restart…", on: powerOpen }
  }

  function pillToggled(id) {
    if (id === "tailscale") {
      tailscaleOn = !tailscaleOn
      run("omarchy-shell -q omarchy.tailscale toggleTailscale")
    } else if (id === "focus") {
      focusOn = !focusOn
      run("omarchy-toggle-notification-silencing")
    } else pillActivated(id)
  }

  function pillActivated(id) {
    if (id === "tailscale") openPanel("omarchy.tailscale")
    else if (id === "display") openPanel("omarchy.monitor")
    else if (id === "focus") pillToggled(id)
    else {
      powerOpen = !powerOpen
      armed = ""
    }
  }

  // Lock, Log Out, Restart and Shut Down inside the open Power switch, as
  // Omarchy's own system menu does them: its apps are closed first.
  Component {
    id: powerActions
    Item {
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.space(2)
        spacing: Style.space(6)

        Repeater {
          model: [
            { action: "lock", glyph: "󰌾", title: "Lock" },
            { action: "logout", glyph: "󰍃", title: "Log Out" },
            { action: "reboot", glyph: "󰜉", title: "Restart" },
            { action: "shutdown", glyph: "󰐥", title: "Shut Down" }
          ]

          delegate: Item {
            id: action
            required property var modelData
            readonly property bool armed: root.armed === modelData.action
            width: (content.width - Style.space(24) - Style.space(18)) / 4
            height: Style.space(64)

            Rectangle {
              id: circle
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(38)
              height: width
              radius: width / 2
              color: action.armed ? "#ff453a"
              : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, actionMouse.containsMouse ? 0.26 : 0.16)

              Text {
                anchors.centerIn: parent
                text: action.modelData.glyph
                color: action.armed ? "#ffffff" : root.ink
                font.pixelSize: Math.round(parent.width * 0.48)
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: circle.bottom
              anchors.topMargin: Style.space(6)
              text: action.armed ? action.modelData.title + "?" : action.modelData.title
              color: action.armed ? "#ff453a" : root.ink
              font.family: "Inter"
              font.weight: action.armed ? Font.DemiBold : Font.Normal
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: actionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.power(action.modelData.action)
            }
          }
        }
      }
    }
  }

  // The glass of the theme's windows: their background as see-through as the
  // Glass setting makes them, over the same blur, so the card matches them.
  readonly property color ink: Commons.Color.popups.text
  readonly property color glass: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g,
    Commons.Color.background.b, root.windowGlass)

  // How see-through windows are, the theme's Glass setting (the app's
  // Windows page, install.sh --set glass): the opacity look.lua gives every
  // window, read from the look Hyprland has loaded and followed as it changes.
  property real windowGlass: 0.7
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/look.lua"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: {
      var m = /o\.window\("\.\*", \{ opacity = "([0-9.]+)/.exec(text())
      if (m) root.windowGlass = Math.max(0.3, Math.min(1, parseFloat(m[1])))
    }
    onFileChanged: reload()
  }

  readonly property real gap: Style.space(10)
  readonly property real pillHeight: Style.space(54)

  Binding {
    target: content.parent ? content.parent.parent : null
    property: "color"
    value: root.glass
  }

  PopupCard {
    id: card
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.open
    padding: Style.space(12)
    contentWidth: card.fittedContentWidth(Style.space(340))
    contentHeight: card.fittedContentHeight(content.implicitHeight)

    // Light catching the glass's top edge.
    Rectangle {
      x: -card.padding
      y: -card.padding
      width: content.width + card.padding * 2
      height: Style.space(140)
      radius: Style.cornerRadius
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.1) }
        GradientStop { position: 1; color: "transparent" }
      }
    }

    Column {
      id: content
      width: parent.width
      spacing: root.gap
      readonly property real half: (width - root.gap) / 2

      // Which apps are using the camera and microphone, at the top as macOS
      // has it; for two minutes after, "recently". The lines are centered
      // together, their icons in a column.
      Item {
        width: content.width
        height: usage.height
        visible: usage.height > 0

        Column {
          id: usage
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Repeater {
            model: [
              { color: "#30d158", glyph: "󰕧", now: root.cameraInUse, apps: root.cameraInUse ? root.cameraAppList : root.cameraRecent, what: "Camera" },
              { color: "#ff9f0a", glyph: "󰍬", now: root.micInUse, apps: root.micInUse ? root.micApps : root.micRecent, what: "Microphone" }
            ]

            delegate: Row {
              required property var modelData
              visible: modelData.now || modelData.apps.length > 0
              spacing: Style.space(8)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                height: width
                radius: width / 2
                color: parent.modelData.color

                Text {
                  anchors.centerIn: parent
                  text: parent.parent.modelData.glyph
                  color: "#ffffff"
                  font.pixelSize: Math.round(parent.width * 0.6)
                }
              }

              Text {
                readonly property var line: parent.modelData
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, content.width - Style.space(40))
                elide: Text.ElideRight
                text: (line.apps.length ? line.apps.map(function(a) { return a.name }).join(", ") : line.what)
                  + (line.now ? "" : ", recently")
                color: root.ink
                font.family: "Inter"
                font.weight: Font.DemiBold
                font.pixelSize: Style.font.body
              }
            }
          }
        }
      }

      // Wi-Fi and Bluetooth, and what is playing beside them.
      Row {
        spacing: root.gap

        Column {
          id: radios
          width: content.half
          spacing: root.gap

          // On a cable, it names it; the icon is still Wi-Fi's switch.
          Pill {
            visible: root.live("omarchy.network")
            glyph: root.wifiOn ? "󰖩" : "󰖪"
            title: "Wi-Fi"
            subtitle: root.networkKind === "wifi" ? root.networkName
              : root.networkKind === "ethernet" ? "Ethernet"
              : root.wifiOn ? "Not Connected" : "Off"
            on: root.wifiOn
            onToggled: {
              root.wifiOn = !root.wifiOn
              root.run("nmcli radio wifi " + (root.wifiOn ? "on" : "off"))
            }
            onActivated: root.openPanel("omarchy.network")
          }

          Pill {
            visible: root.live("omarchy.bluetooth")
            glyph: "󰂯"
            title: "Bluetooth"
            subtitle: root.bluetoothOn ? "On" : "Off"
            on: root.bluetoothOn
            onToggled: {
              root.bluetoothOn = !root.bluetoothOn
              root.run("omarchy-bluetooth-power " + (root.bluetoothOn ? "on" : "off"))
            }
            onActivated: root.openPanel("omarchy.bluetooth")
          }
        }

        NowPlaying {
          width: content.half
          height: Math.max(radios.height, root.pillHeight * 2 + root.gap)
        }
      }

      // Tailscale and Focus, then Display and Power: whichever are here,
      // two to a row. Power opens where it is: the switch beside it moves on.
      Flow {
        width: parent.width
        spacing: root.gap

        Repeater {
          model: root.pillOrder

          delegate: Pill {
            required property string modelData
            readonly property var info: root.pillInfo(modelData)
            width: modelData === "power" && root.powerOpen ? content.width : content.half
            height: root.pillHeight + (modelData === "power" && root.powerOpen ? Style.space(78) : 0)
            glyph: info.glyph
            title: info.title
            subtitle: info.subtitle
            on: info.on
            extra: modelData === "power" ? powerActions : null
            onToggled: root.pillToggled(modelData)
            onActivated: root.pillActivated(modelData)
          }
        }
      }

      // Brightness, where Omarchy's Display widget can set it.
      SliderTile {
        visible: !!root.display && root.display.brightnessAvailable === true
        title: "Display"
        glyph: "󰃞"
        endGlyph: "󰃠"
        value: root.display ? root.display.brightnessPercent / 100 : 0
        onMoved: function(v) { if (root.display) root.display.setBrightness(Math.round(v * 100)) }
        onMore: root.openPanel("omarchy.monitor")
      }

      SliderTile {
        title: "Sound"
        glyph: root.muted ? "󰖁" : "󰕿"
        endGlyph: "󰕾"
        value: root.volume
        dim: root.muted
        onGlyphClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.muted
        onMoved: function(v) {
          if (!root.sink || !root.sink.audio) return
          root.sink.audio.muted = false
          root.sink.audio.volume = v
        }
        onMore: root.openPanel("omarchy.audio")
      }
    }
  }

  // A module of the card: a lighter pane of the glass, with a fine edge.
  component Tile: Rectangle {
    id: tile
    property bool hoverable: false
    readonly property bool hovered: tileMouse.containsMouse
    signal activated()

    radius: Style.space(18)
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, tile.hoverable && tileMouse.containsMouse ? 0.2 : 0.13)
    border.width: 1
    border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.18)

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      enabled: tile.hoverable
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.activated()
    }
  }

  // A round icon, blue while its switch is on.
  component Glyph: Rectangle {
    property string glyph
    property bool on: false

    width: Style.space(34)
    height: width
    radius: width / 2
    color: on ? "#0a84ff" : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)

    Text {
      anchors.centerIn: parent
      text: parent.glyph
      color: parent.on ? "#ffffff" : root.ink
      font.pixelSize: Math.round(parent.width * 0.52)
    }
  }

  // A switch as a capsule: its icon turns it on or off, and the rest opens
  // its panel.
  component Pill: Tile {
    id: pill
    property string glyph
    property string title
    property string subtitle
    property bool on: false
    signal toggled()

    // More of the switch, under its header while the pill is taller.
    property Component extra: null

    width: parent ? parent.width : 0
    height: root.pillHeight
    radius: root.pillHeight / 2
    hoverable: true
    clip: true
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Glyph {
      id: icon
      x: (root.pillHeight - height) / 2
      y: (root.pillHeight - height) / 2
      glyph: pill.glyph
      on: pill.on
      opacity: iconMouse.containsMouse ? 0.85 : 1

      MouseArea {
        id: iconMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.toggled()
      }
    }

    Column {
      y: (root.pillHeight - height) / 2
      x: icon.x + icon.width + Style.space(8)
      width: pill.width - x - Style.space(10)

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: pill.title
        color: root.ink
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: pill.subtitle
        color: root.ink
        opacity: 0.6
        font.family: "Inter"
        font.pixelSize: Style.font.caption
      }
    }

    Loader {
      y: root.pillHeight
      width: pill.width
      height: pill.height - root.pillHeight
      active: pill.extra !== null && height > 0
      sourceComponent: pill.extra
    }
  }

  // What is playing: artwork, title and artist, and its controls; "Not
  // Playing" while nothing is.
  component NowPlaying: Tile {
    id: playing
    readonly property var player: root.player

    Item {
      id: art
      x: Style.space(14)
      y: Style.space(14)
      width: Style.space(40)
      height: width

      Rectangle {
        anchors.fill: parent
        radius: Style.space(8)
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
        visible: artImage.status !== Image.Ready

        Text {
          anchors.centerIn: parent
          text: "󰝚"
          color: root.ink
          opacity: 0.6
          font.pixelSize: Style.font.body
        }
      }

      Image {
        id: artImage
        anchors.fill: parent
        source: playing.player && playing.player.trackArtUrl ? playing.player.trackArtUrl : ""
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
      }

      Rectangle {
        id: artMask
        anchors.fill: parent
        radius: Style.space(8)
        visible: false
        layer.enabled: true
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
      x: Style.space(14)
      y: art.y + art.height + Style.space(8)
      width: playing.width - Style.space(28)

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: playing.player ? (playing.player.trackTitle || "") : "Not Playing"
        color: root.ink
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        visible: !!playing.player
        text: playing.player ? (playing.player.trackArtist || playing.player.identity || "") : ""
        color: root.ink
        opacity: 0.6
        font.family: "Inter"
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(8)
      spacing: Style.space(10)
      opacity: playing.player ? 1 : 0.35

      Repeater {
        model: ["previous", "playPause", "next"]

        delegate: Text {
          required property string modelData
          width: Style.space(28)
          height: width
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData === "previous" ? "󰒮" : modelData === "next" ? "󰒭"
            : (playing.player && playing.player.isPlaying ? "󰏤" : "󰐊")
          color: root.ink
          opacity: control.containsMouse ? 1 : 0.85
          font.pixelSize: modelData === "playPause" ? Style.font.title : Style.font.body

          MouseArea {
            id: control
            anchors.fill: parent
            enabled: !!playing.player
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var p = playing.player
              if (parent.modelData === "playPause") p.togglePlaying()
              else if (parent.modelData === "next") p.next()
              else p.previous()
            }
          }
        }
      }
    }
  }

  // A titled slider, as macOS's Display and Sound: a thin track filled to
  // the value with a round knob, an icon at each end; its title opens the
  // panel for the rest.
  component SliderTile: Tile {
    id: slider
    property string title
    property string glyph
    property string endGlyph
    property real value: 0
    property bool dim: false
    signal moved(real value)
    signal glyphClicked()
    signal more()

    width: parent ? parent.width : 0
    height: Style.space(74)

    Text {
      x: Style.space(14)
      y: Style.space(12)
      text: slider.title
      color: root.ink
      opacity: titleMouse.containsMouse ? 0.75 : 1
      font.family: "Inter"
      font.weight: Font.DemiBold
      font.pixelSize: Style.font.body

      MouseArea {
        id: titleMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: slider.more()
      }
    }

    Item {
      x: Style.space(14)
      y: Style.space(40)
      width: slider.width - Style.space(28)
      height: Style.space(22)

      Text {
        id: low
        anchors.verticalCenter: parent.verticalCenter
        text: slider.glyph
        color: root.ink
        font.pixelSize: Style.font.body

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          cursorShape: Qt.PointingHandCursor
          onClicked: slider.glyphClicked()
        }
      }

      Text {
        id: high
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: slider.endGlyph
        color: root.ink
        font.pixelSize: Style.font.body
      }

      Item {
        id: track
        anchors.left: low.right
        anchors.right: high.left
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        height: parent.height
        readonly property real knob: Style.space(18)
        readonly property real at: Math.max(0, Math.min(1, slider.value)) * (width - knob)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: Style.space(5)
          radius: height / 2
          color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.2)

          Rectangle {
            width: track.at + track.knob / 2
            height: parent.height
            radius: parent.radius
            color: root.ink
            opacity: slider.dim ? 0.4 : 1
          }
        }

        Rectangle {
          x: track.at
          anchors.verticalCenter: parent.verticalCenter
          width: track.knob
          height: width
          radius: width / 2
          color: "#ffffff"
          border.width: 1
          border.color: Qt.rgba(0, 0, 0, 0.15)
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          function set(x) { slider.moved(Math.max(0, Math.min(1, (x - track.knob / 2) / (track.width - track.knob)))) }
          onPressed: function(mouse) { set(mouse.x) }
          onPositionChanged: function(mouse) { if (pressed) set(mouse.x) }
        }
      }
    }
  }
}
