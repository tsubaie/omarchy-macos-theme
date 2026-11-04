import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "LogoModel.js" as Model

// The logo at the far left of the bar, opening a menu like macOS's Apple menu
// (About This Computer, System Settings, Force Quit, sleep and power, lock and
// log out) on the theme's glass, with Force Quit Applications and About This
// Computer as small glass windows of their own. The logo is the theme's or
// yours, never Apple's: shell.json's "logo" says which ({ glyph, file,
// keepColors }), set with install.sh --set logo=… / logo-file=… or in Studio.
BarWidget {
  id: root
  moduleName: "macos-theme.logo-menu"

  // Room for the open pill, the workspace pill's size, and 4 px each side.
  readonly property int pillIcon: Math.round(Style.bar.iconCanvas * 0.85)
  implicitWidth: Math.max(button.implicitWidth, pillIcon + Math.round(pillIcon * 0.45) * 2 + Style.space(8))
  implicitHeight: button.implicitHeight

  // Moving to another workspace or screen closes the menu.
  Connections {
    target: Hyprland
    enabled: root.open
    function onRawEvent(event) {
      if (/^(workspace|workspacev2|focusedmon|focusedmonv2|activespecial)$/.test(event.name)) root.close()
    }
  }

  readonly property real s: Style.fontScale
  readonly property color ink: Commons.Color.popups.text
  // Frosted glass from the theme's windows: their background, a little more
  // see-through than the Glass setting makes them, over Hyprland's blur.
  readonly property color glass: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g,
    Commons.Color.background.b, Math.max(0.3, root.windowGlass - 0.3))
  property real windowGlass: 0.85
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/look.lua"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: {
      var m = /o\.window\("\.\*", \{ opacity = "[0-9.]+ ([0-9.]+)/.exec(text())
      if (m) root.windowGlass = Math.max(0.3, Math.min(1, parseFloat(m[1])))
    }
    onFileChanged: reload()
  }
  readonly property color foreground: root.bar ? root.bar.barForeground : Commons.Color.foreground

  // The logo, followed as shell.json changes.
  property var logoConfig: ({})
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.logoConfig = parsed && typeof parsed.logo === "object" && parsed.logo !== null ? parsed.logo : ({})
      } catch (e) { root.logoConfig = ({}) }
    }
  }
  readonly property var glyph: Model.logo(logoConfig.glyph)
  readonly property string file: typeof logoConfig.file === "string" ? logoConfig.file : ""

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.file ? "" : root.glyph.glyph
    fontFamily: root.glyph.font || Style.font.family
    iconComponent: root.file ? ownLogo : null
    onPressed: function(which) {
      if (which === Qt.RightButton) Quickshell.execDetached(["xdg-terminal-exec"])
      else root.toggle()
    }
  }
  // Your own picture, in the bar's color unless it keeps its own.
  Component {
    id: ownLogo
    Image {
      width: Style.bar.iconCanvas
      height: width
      source: "file://" + root.file
      sourceSize: Qt.size(width * 2, height * 2)
      fillMode: Image.PreserveAspectFit
      smooth: true
      layer.enabled: root.logoConfig.keepColors !== true
      layer.effect: MultiEffect { brightness: 1; colorization: 1; colorizationColor: root.foreground }
    }
  }
  Accessible.role: Accessible.Button
  Accessible.name: "System menu"
  Accessible.onPressAction: root.toggle()

  // ------------------------------------------------------------- the menu

  property bool open: false
  // ⌥ held while it's open: Force Quit becomes Force Quit Applications (the list).
  property bool altHeld: false
  // The item the arrow keys are on, -1 for none.
  property int current: -1
  // An item that asks first (Restart, Shut Down, Log Out) while it asks.
  property var asking: null
  readonly property var choosable: Model.choosable()

  function toggle() { open ? close() : show() }
  function show() { current = -1; asking = null; altHeld = false; open = true; Qt.callLater(function() { keys.forceActiveFocus() }) }
  function close() { open = false; asking = null; altHeld = false }

  function choose(item) {
    if (!item) return
    if (item.ask) { asking = item; return }
    var alt = altHeld  // close() clears it
    close()
    if (item.id === "about") { quitWindow.visible = false; aboutWindow.visible = true }
    else if (item.id === "forcequit") { if (alt) quitter.show(); else startKilling() }
    else if (item.run) Quickshell.execDetached(["sh", "-c", item.run])
  }
  function confirm() {
    var item = asking
    close()
    if (item && item.run) Quickshell.execDetached(["sh", "-c", item.run])
  }

  ShellIpc {
    target: "macos-logo-menu"
    function open(): string { root.show(); return "ok" }
    function forceQuit(): string { quitter.show(); return "ok" }
    function forceQuitByClicking(): string { root.startKilling(); return "ok" }
    function about(): string { quitWindow.visible = false; aboutWindow.visible = true; return "ok" }
  }

  Binding {
    target: keys.parent ? keys.parent.parent : null
    property: "color"
    value: root.glass
  }

  PopupCard {
    id: card
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.open
    padding: Style.space(6)
    contentWidth: card.fittedContentWidth(Style.space(250))
    contentHeight: card.fittedContentHeight(menu.implicitHeight)

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Alt) { root.altHeld = true; return }
        if (event.key === Qt.Key_Escape) { if (root.asking) root.asking = null; else root.close() }
        else if (root.asking && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) root.confirm()
        else if (event.key === Qt.Key_Down) root.current = Math.min(root.choosable.length - 1, root.current + 1)
        else if (event.key === Qt.Key_Up) root.current = Math.max(0, root.current - 1)
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.current >= 0) root.choose(root.choosable[root.current])
        else return
        event.accepted = true
      }
      Keys.onReleased: function(event) { if (event.key === Qt.Key_Alt) root.altHeld = false }

      Column {
        id: menu
        width: parent.width
        visible: !root.asking

        Repeater {
          model: Model.ITEMS
          delegate: Item {
            id: entry
            required property var modelData
            readonly property bool line: modelData === null
            // By id: the row's copy of the item isn't the list's own object.
            readonly property int index: line ? -1 : root.choosable.findIndex(function(i) { return i.id === entry.modelData.id })
            readonly property bool lit: !line && index >= 0 && (hover.hovered || root.current === index)
            width: menu.width
            height: line ? Style.space(9) : Style.space(26)

            Rectangle {
              visible: entry.line
              anchors.centerIn: parent
              width: parent.width - Style.space(16)
              height: 1
              color: Qt.rgba(1, 1, 1, 0.12)
            }
            Rectangle {
              visible: entry.lit
              anchors.fill: parent
              radius: Style.space(5)
              color: "#0a84ff"
            }
            Text {
              visible: !entry.line
              x: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: entry.line ? "" : (root.altHeld && entry.modelData.altLabel ? entry.modelData.altLabel : entry.modelData.label)
              color: entry.lit ? "white" : root.ink
              font.family: "Inter"
              font.pixelSize: Math.round(13 * root.s)
            }
            Text {
              readonly property bool alt: !entry.line && root.altHeld && !!entry.modelData.altLabel
              visible: text !== ""
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: entry.line ? "" : ((alt ? entry.modelData.altShortcut : entry.modelData.shortcut) || "")
              color: entry.lit ? "white" : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
              font.family: "Inter"
              font.pixelSize: Math.round(13 * root.s)
            }
            HoverHandler { id: hover; enabled: !entry.line; onHoveredChanged: if (hovered) root.current = entry.index }
            TapHandler { enabled: !entry.line; onTapped: root.choose(entry.modelData) }
            Accessible.role: entry.line ? Accessible.Separator : Accessible.MenuItem
            Accessible.name: entry.line ? "" : entry.modelData.label
            Accessible.onPressAction: root.choose(entry.modelData)
          }
        }
      }

      // Restart, Shut Down and Log Out ask first, in the menu itself.
      Column {
        visible: !!root.asking
        width: parent.width
        padding: Style.space(10)
        spacing: Style.space(10)
        Text {
          width: parent.width - Style.space(20)
          textFormat: Text.PlainText
          text: root.asking ? root.asking.ask : ""
          color: root.ink
          wrapMode: Text.WordWrap
          font.family: "Inter"
          font.pixelSize: Math.round(13 * root.s)
        }
        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)
          GlassButton { label: "Cancel"; onChosen: root.asking = null }
          GlassButton { label: root.asking ? root.asking.label.replace("…", "") : ""; primary: true; onChosen: root.confirm() }
        }
      }
    }
  }

  // ------------------------------------------------- Force Quit Applications

  QtObject {
    id: quitter
    property var apps: []
    property int chosen: 0
    function show() { aboutWindow.visible = false; list.running = true; quitWindow.visible = true }
  }
  Process {
    id: list
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { quitter.apps = Model.apps(JSON.parse(text)) } catch (e) { quitter.apps = [] }
        quitter.chosen = Math.min(quitter.chosen, Math.max(0, quitter.apps.length - 1))
      }
    }
  }
  function quitChosen() {
    var app = quitter.apps[quitter.chosen]
    if (!app) return
    // As macOS's Force Quit: the app's processes end at once, unsaved work and all.
    Quickshell.execDetached(["kill", "-KILL"].concat(app.pids.map(String)))
    refresh.restart()
  }
  Timer { id: refresh; interval: 400; onTriggered: list.running = true }

  SheetWindow {
    id: quitWindow
    title: "Force Quit Applications"
    closable: true
    onKey: function(event) {
      if (event.key === Qt.Key_Down) quitter.chosen = Math.min(quitter.apps.length - 1, quitter.chosen + 1)
      else if (event.key === Qt.Key_Up) quitter.chosen = Math.max(0, quitter.chosen - 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.quitChosen()
      else return false
      return true
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "If an app doesn't respond for a while, choose it and click Force Quit. Its unsaved changes are lost."
      color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
      wrapMode: Text.WordWrap
      font.family: "Inter"
      font.pixelSize: Math.round(12 * root.s)
    }
    Rectangle {
      width: parent.width
      height: Math.max(Style.space(60), Math.min(Style.space(240), apps.contentHeight + Style.space(8)))
      radius: Style.space(8)
      color: Qt.rgba(0, 0, 0, 0.25)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.08)
      ListView {
        id: apps
        anchors.fill: parent
        anchors.margins: Style.space(4)
        clip: true
        model: quitter.apps
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: apps.width
          height: Style.space(30)
          radius: Style.space(5)
          color: index === quitter.chosen ? "#0a84ff" : "transparent"
          Image {
            id: icon
            x: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(20)
            height: width
            source: Quickshell.iconPath(String(modelData.id).toLowerCase(), "application-x-executable")
            sourceSize: Qt.size(width * 2, height * 2)
          }
          Text {
            anchors.left: icon.right
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: modelData.name
            color: index === quitter.chosen ? "white" : root.ink
            font.family: "Inter"
            font.pixelSize: Math.round(13 * root.s)
          }
          TapHandler { onTapped: quitter.chosen = index; onDoubleTapped: root.quitChosen() }
        }
        Text {
          visible: quitter.apps.length === 0
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "No apps are open"
          color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
          font.family: "Inter"
          font.pixelSize: Math.round(13 * root.s)
        }
      }
    }
    Row {
      anchors.right: parent.right
      spacing: Style.space(8)
      GlassButton { label: "Cancel"; onChosen: quitWindow.visible = false }
      GlassButton { label: "Force Quit"; primary: true; enabled: quitter.apps.length > 0; onChosen: root.quitChosen() }
    }
  }

  // While Force Quit or About is open, a click on any other screen closes
  // it too: a clear catcher there, as the window's own covers its screen.
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: (aboutWindow.visible || quitWindow.visible) && modelData !== aboutWindow.screen
      color: "transparent"
      WlrLayershell.namespace: "macos-theme-sheet-catcher"
      WlrLayershell.layer: WlrLayer.Overlay
      // While a window holds the keyboard, Hyprland gives clicks only to
      // windows that do: so does this one, handing keys on to the sheet.
      WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      MouseArea {
        anchors.fill: parent
        onPressed: { aboutWindow.visible = false; quitWindow.visible = false }
      }
      Item {
        anchors.fill: parent
        focus: parent.visible
        Keys.onPressed: function(event) {
          var sheet = quitWindow.visible ? quitWindow : aboutWindow
          if (event.key === Qt.Key_Escape) { sheet.visible = false; event.accepted = true }
          else if (typeof sheet.onKey === "function" && sheet.onKey(event)) event.accepted = true
        }
      }
    }
  }

  // --------------------------------------------- Force Quit by Clicking
  // As xkill, the macOS way: the pointer becomes a red ×, the window under it
  // is outlined with the app's name, and a click force quits that window's
  // process (the whole app, unless its windows run apart). Esc or a right click
  // cancels. Every screen is covered, so it works on all of them.

  property bool killing: false
  property var killClients: []
  property var killMonitors: []
  property var killTarget: null
  function startKilling() {
    aboutWindow.visible = false
    quitWindow.visible = false
    killTarget = null
    killRead.running = true
  }
  Process {
    id: killRead
    command: ["sh", "-c", "hyprctl clients -j | jq -c .; hyprctl monitors -j | jq -c ."]
    stdout: StdioCollector {
      onStreamFinished: {
        var l = text.split("\n")
        try { root.killClients = JSON.parse(l[0]); root.killMonitors = JSON.parse(l[1]) } catch (e) { return }
        root.killing = true
      }
    }
  }
  function aimAt(x, y) { killTarget = Model.windowAt(killClients, killMonitors, x, y) }
  function killAimed() {
    var target = killTarget
    killing = false
    // The clicked window's own process only: one terminal, not every one.
    if (target) Quickshell.execDetached(["kill", "-KILL", String(target.pid)])
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: killLayer
      required property var modelData
      screen: modelData
      visible: root.killing
      color: "transparent"
      WlrLayershell.namespace: "macos-theme-force-quit"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }

      // The window that would be force quit, outlined in red.
      Rectangle {
        visible: !!root.killTarget
        x: root.killTarget ? root.killTarget.at[0] - killLayer.modelData.x : 0
        y: root.killTarget ? root.killTarget.at[1] - killLayer.modelData.y : 0
        width: root.killTarget ? root.killTarget.size[0] : 0
        height: root.killTarget ? root.killTarget.size[1] : 0
        radius: Style.space(10)
        color: Qt.rgba(1, 0.37, 0.34, 0.12)
        border.width: 3
        border.color: "#ff5f57"
      }

      MouseArea {
        id: aim
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPositionChanged: function(mouse) { root.aimAt(killLayer.modelData.x + mouse.x, killLayer.modelData.y + mouse.y) }
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) { root.killing = false; return }
          root.aimAt(killLayer.modelData.x + mouse.x, killLayer.modelData.y + mouse.y)
          root.killAimed()
        }
      }

      // The pointer: a red traffic light with its ×, and the app it would quit.
      Item {
        visible: aim.containsMouse
        x: aim.mouseX - Style.space(11)
        y: aim.mouseY - Style.space(11)
        Rectangle {
          width: Style.space(22)
          height: width
          radius: width / 2
          color: "#ff5f57"
          border.width: 1
          border.color: Qt.rgba(0, 0, 0, 0.25)
          Text {
            anchors.centerIn: parent
            text: "×"
            color: Qt.rgba(0.3, 0, 0, 0.85)
            font.family: "Inter"
            font.weight: Font.Bold
            font.pixelSize: Math.round(17 * root.s)
          }
        }
        Rectangle {
          visible: !!root.killTarget
          x: Style.space(28)
          y: Style.space(2)
          width: killName.implicitWidth + Style.space(16)
          height: Style.space(22)
          radius: height / 2
          color: Qt.rgba(0, 0, 0, 0.7)
          Text {
            id: killName
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.killTarget ? "Force Quit " + Model.nameOf(root.killTarget["class"]) : ""
            color: "white"
            font.family: "Inter"
            font.pixelSize: Math.round(12 * root.s)
          }
        }
      }

      Item {
        anchors.fill: parent
        focus: killLayer.visible
        Keys.onPressed: function(event) { if (event.key === Qt.Key_Escape) { root.killing = false; event.accepted = true } }
      }
    }
  }

  // ------------------------------------------------ About This Computer

  property var details: []
  Process {
    id: detailsRead
    running: aboutWindow.visible
    command: ["sh", "-c",
      'printf "%s\\n" "$(hostnamectl hostname 2>/dev/null || cat /etc/hostname)" "$(omarchy-version 2>/dev/null)" '
      // Memory as installed, as macOS says it: the usable total up to its power of two.
      + '"$(lscpu | sed -n "s/^Model name: *//p" | head -1)" "$(awk "/^MemTotal/{g=\\$2/1048576; p=1; while (p<g) p*=2; print p \\" GB\\"}" /proc/meminfo)" '
      + '"$(lspci 2>/dev/null | sed -n "s/.*\\(VGA compatible controller\\|3D controller\\): //p" | head -1)" '
      + '"$(df -B1 --output=avail,size / | tail -1 | awk "{printf \\"%d GB available of %d GB\\", \\$1/1e9, \\$2/1e9}")"']
    stdout: StdioCollector {
      onStreamFinished: {
        var l = text.split("\n")
        root.details = [
          { label: "Chip", value: Model.chipName(l[2]) }, { label: "Memory", value: l[3] || "" },
          { label: "Graphics", value: Model.gpuName(l[4]) }, { label: "Storage", value: l[5] || "" }
        ].filter(function(d) { return d.value !== "" })
        root.hostname = l[0] || ""
        root.version = l[1] || ""
      }
    }
  }
  property string hostname: ""
  property string version: ""

  SheetWindow {
    id: aboutWindow
    closable: true
    cardWidth: Style.space(340)

    // The logo, the one big thing: large, on a soft light of the theme's accent.
    Item {
      width: parent.width
      height: Style.space(128)
      Rectangle {
        anchors.centerIn: parent
        width: Style.space(96)
        height: width
        radius: width / 2
        color: Commons.Color.menu.selectedBackground
        opacity: 0.45
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64; autoPaddingEnabled: true }
      }
      Text {
        anchors.centerIn: parent
        visible: !root.file
        textFormat: Text.PlainText
        text: root.glyph.glyph
        color: root.ink
        font.family: root.glyph.font || Style.font.family
        font.pixelSize: Style.space(76)
      }
      Image {
        anchors.centerIn: parent
        visible: !!root.file
        width: Style.space(84)
        height: width
        source: root.file ? "file://" + root.file : ""
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
      }
    }
    Column {
      width: parent.width
      spacing: Style.space(3)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: root.hostname
        color: root.ink
        font.family: "Inter"
        font.weight: Font.Bold
        font.letterSpacing: -0.4
        font.pixelSize: Math.round(24 * root.s)
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.version ? "Omarchy " + root.version : ""
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
        font.family: "Inter"
        font.pixelSize: Math.round(12 * root.s)
      }
    }
    Item { width: 1; height: Style.space(4) }
    // As About This Mac: names gray, left of a line; values right of it.
    Column {
      width: parent.width
      spacing: Style.space(7)
      Repeater {
        model: root.details
        Item {
          required property var modelData
          width: parent.width
          height: value.implicitHeight
          Item { id: split; x: parent.width * 0.34 }
          Text {
            anchors.right: split.left
            anchors.rightMargin: Style.space(5)
            textFormat: Text.PlainText
            text: modelData.label
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
            font.family: "Inter"
            font.pixelSize: Math.round(12 * root.s)
          }
          Text {
            id: value
            anchors.left: split.left
            anchors.leftMargin: Style.space(5)
            width: parent.width * 0.66 - Style.space(5)
            textFormat: Text.PlainText
            text: modelData.value
            color: root.ink
            wrapMode: Text.WordWrap
            font.family: "Inter"
            font.pixelSize: Math.round(12 * root.s)
          }
        }
      }
    }
    Item { width: 1; height: Style.space(6) }
  }

  // ----------------------------------------------------------- the parts

  // A small glass window in the middle of the screen the bar is on: Esc or a
  // click outside closes it. Its items go in a column.
  component SheetWindow: PanelWindow {
    id: sheet
    property string title: ""
    // Keys the window takes before Esc: returns true when it did.
    property var onKey: null
    // A red traffic-light close button at the top left, as a Mac window has.
    property bool closable: false
    property real cardWidth: Style.space(360)
    default property alias content: column.data
    visible: false
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    color: "transparent"
    // Its own name, blurred by look.lua; the launcher opening closes it, so
    // it never opens hidden under it.
    WlrLayershell.namespace: "macos-theme-sheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    Connections {
      target: Hyprland
      enabled: sheet.visible
      function onRawEvent(event) {
        if (event.name === "openlayer" && event.data === "omarchy-menu") sheet.visible = false
      }
    }
    MouseArea { anchors.fill: parent; onClicked: sheet.visible = false }
    Rectangle {
      anchors.centerIn: parent
      width: sheet.cardWidth
      height: column.implicitHeight + Style.space(32) + column.y - Style.space(16)
      radius: Style.space(14)
      color: root.glass
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.12)
      // Clicks on the card stay on it.
      MouseArea { anchors.fill: parent }
      Rectangle {
        visible: sheet.closable
        x: Style.space(12)
        y: Style.space(12)
        width: Style.space(12)
        height: width
        radius: width / 2
        color: closeTap.pressed ? "#bf4942" : "#ff5f57"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.12)
        Text {
          anchors.centerIn: parent
          visible: closeHover.hovered
          text: "×"
          color: Qt.rgba(0.3, 0, 0, 0.75)
          font.family: "Inter"
          font.weight: Font.Bold
          font.pixelSize: Math.round(11 * root.s)
        }
        HoverHandler { id: closeHover; margin: Style.space(4) }
        TapHandler { id: closeTap; margin: Style.space(4); onTapped: sheet.visible = false }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
        Accessible.onPressAction: sheet.visible = false
      }
      Item {
        anchors.fill: parent
        focus: sheet.visible
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { sheet.visible = false; event.accepted = true; return }
          if (typeof sheet.onKey === "function" && sheet.onKey(event)) event.accepted = true
        }
        Column {
          id: column
          x: Style.space(16)
          // Below the close button when there is one.
          y: Style.space(sheet.closable ? 30 : 16)
          width: parent.width - Style.space(32)
          spacing: Style.space(12)
          Text {
            visible: sheet.title !== ""
            textFormat: Text.PlainText
            text: sheet.title
            color: root.ink
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(14 * root.s)
          }
        }
      }
    }
  }

  // A small macOS push button: gray, or blue for the main action.
  component GlassButton: Rectangle {
    id: glassButton
    property string label: ""
    property bool primary: false
    signal chosen()
    width: buttonText.implicitWidth + Style.space(24)
    height: Style.space(26)
    radius: Style.space(6)
    opacity: enabled ? 1 : 0.4
    color: primary ? (buttonHover.hovered ? "#3395ff" : "#0a84ff") : (buttonHover.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.14))
    Text {
      id: buttonText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: glassButton.label
      color: "white"
      font.family: "Inter"
      font.pixelSize: Math.round(13 * root.s)
    }
    HoverHandler { id: buttonHover }
    TapHandler { onTapped: glassButton.chosen() }
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: chosen()
  }
}
