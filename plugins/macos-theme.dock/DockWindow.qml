import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import Quickshell.Io
import "DockModel.js" as DockModel

// One screen's dock. It stays mapped and only hides its contents, so switching
// to a floating workspace does not wait on a fresh layer surface. While hidden the
// mask is empty and clicks fall through to the windows below.
PanelWindow {
  id: window
  // Right-to-left languages read this window mirrored.
  Binding { target: window.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: window.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }


  property var dock: null

  readonly property string position: dock ? dock.position : "bottom"
  readonly property bool vertical: dock ? dock.vertical : false
  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var workspace: monitor ? monitor.activeWorkspace : null
  readonly property int workspaceId: workspace ? workspace.id : -1
  // The most fullscreen window on the workspace, as Hyprland counts it: 1 is
  // maximized, and 2 or 3 fullscreen.
  readonly property int fullscreenMode: {
    var mode = 0
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
      var ipc = toplevel.lastIpcObject
      mode = Math.max(mode, ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    }
    return mode
  }
  readonly property bool shown: !!dock && dock.isFloating(workspaceId) && fullscreenMode < 2
  // With auto-hide on, the dock waits off screen until the pointer reaches its
  // edge, and stays while the pointer, a menu, or a drag still needs it. A
  // maximized window hides the dock the same way, so it can still be called up.
  readonly property bool autohide: !!dock && (dock.autohide || fullscreenMode === 1)
  property bool revealed: false
  // Any popup of the dock: a click anywhere else closes it (the focus grab).
  readonly property bool menuOpen: menuItem !== null || settingsMenu || trashMenu || downloadsMenu || stackOpen
  readonly property bool tucked: autohide && !(revealed || menuOpen || dragging || insertIndex >= 0)
  readonly property bool contentShown: shown && !tucked

  readonly property int gap: Style.spacing.sm
  readonly property int iconSize: Math.round(48 * Style.fontScale)
  // Each app has a square slot with its icon in the middle, and the glass
  // platter leaves room around the slots, like the macOS dock.
  readonly property int iconInset: Style.spacing.md
  readonly property int platterPadding: Style.space(8)
  readonly property int slotSize: iconSize + iconInset * 2
  // A pinned app that is not running is drawn faded.
  readonly property real idleOpacity: 0.7
  // Room inward of the dock for its menus: the tallest, the apps button's,
  // has five rows.
  readonly property int popupRoom: Math.max(Style.spacing.popupRowHeight * 5 + Style.spacing.sm * 2 + Style.normalBorderWidth * 2 + gap * 2, stackRoom)
  // The Downloads fan: up to ten files plus "Open in Files".
  readonly property int stackRoom: Math.round((iconSize * 1.05 + Style.space(10)) * 11 + Style.space(24))
  // Icons pop away from the screen edge.
  readonly property int popOrigin: position === "top" ? Item.Top
    : position === "left" ? Item.Left
    : position === "right" ? Item.Right
    : Item.Bottom

  // The app being dragged along the dock, how far the pointer has taken it,
  // and the slot it would land in.
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool dragging: dragIndex >= 0
  // Off while a drop resets the slots: they snap to where the reorder puts
  // them rather than sliding back from where they stepped aside. Set before
  // the drag state changes, so the slots never see the reset animated.
  property bool animateShifts: true
  // After a drop the slots have moved under a pointer that has not, so what
  // they think is hovered is stale until it moves again.
  property bool hoverStale: false
  property point dropPoint
  // Where an app dragged in from the app grid would land, or -1.
  property int insertIndex: -1

  // Where this window sits on its screen, which a point from the app grid's
  // fullscreen surface is given in: against its edge, clear of the space
  // other surfaces such as the bar reserve. Hyprland lists that space as
  // left, top, right, bottom.
  function origin() {
    var reserved = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
    var left = reserved[0] || 0, top = reserved[1] || 0, right = reserved[2] || 0, bottom = reserved[3] || 0
    var x = window.position === "right" ? screen.width - right - window.width : left
    var y = window.position === "bottom" ? screen.height - bottom - window.height : top
    return Qt.point(x, y)
  }

  // An app from the app grid lands where the pointer is, once it is over the
  // dock or close to it on the inward side.
  function moveExternalDrag(screenX, screenY) {
    var at = window.origin()
    var point = Qt.point(screenX - at.x - body.x, screenY - at.y - body.y)
    var reach = window.slotSize
    var along = window.vertical ? point.y : point.x
    var across = window.vertical ? point.x : point.y
    var length = window.vertical ? body.height : body.width
    var depth = window.vertical ? body.width : body.height
    var near = along >= -window.slotSize && along <= length + window.slotSize && across >= -reach && across <= depth + reach
    if (window.shown && window.autohide && near) window.revealed = true
    window.insertIndex = window.shown && near ? window.slotIndexAt(point) : -1
  }

  function dropExternalDrag(screenX, screenY, key) {
    window.moveExternalDrag(screenX, screenY)
    window.settleShifts()
    if (window.insertIndex >= 0 && key && window.dock) window.dock.pinAt(key, window.insertIndex)
    window.endExternalDrag()
  }

  function endExternalDrag() {
    window.insertIndex = -1
    if (window.autohide) hideTimer.restart()
  }

  // The slot a point along the dock falls before, counting from the first app.
  function slotIndexAt(point) {
    var along = window.vertical ? point.y : point.x
    var first = window.platterPadding
    var count = window.dock ? window.dock.itemModel.count : 0
    return Math.max(0, Math.min(count, Math.round((along - first) / window.slotSize)))
  }
  property var menuItem: null
  property Item menuSlot: null
  // The apps button's menu: where the dock sits and whether it hides.
  property bool settingsMenu: false
  // The Trash's own menu (Open / Empty Trash), and its confirm step.
  property bool trashMenu: false
  property bool downloadsMenu: false
  // Downloads "Display as": the fan ("stack") or opening the folder, kept
  // across restarts in a small state file.
  property string downloadsAs: "stack"
  readonly property string dockStateFile: Quickshell.env("HOME") + "/.local/state/omarchy/macos-dock-downloads"

  FileView {
    path: window.dockStateFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: window.downloadsAs = text().trim() === "folder" ? "folder" : "stack"
  }

  function setDownloadsAs(mode) {
    window.downloadsAs = mode
    Util.execDetached("mkdir -p " + Util.shellQuote(Quickshell.env("HOME") + "/.local/state/omarchy") + " && printf %s " + Util.shellQuote(mode) + " > " + Util.shellQuote(window.dockStateFile))
  }

  // The open submenu: its rows and the row it hangs from.
  property var submenuRows: []
  property Item submenuAnchor: null
  property bool trashConfirm: false

  onWorkspaceIdChanged: if (dock) dock.readMode(workspaceId)
  onShownChanged: {
    if (shown) return
    closeMenu()
    window.revealed = false
  }
  Component.onCompleted: if (dock) dock.readMode(workspaceId)

  function openMenu(item, slot) {
    window.settingsMenu = false
    window.menuItem = item
    window.menuSlot = slot
  }

  function openSettingsMenu(slot) {
    window.menuItem = null
    window.settingsMenu = true
    window.menuSlot = slot
  }

  function openTrashMenu(slot) {
    window.closeMenu()
    window.trashMenu = true
    window.menuSlot = slot
  }

  function openDownloadsMenu(slot) {
    window.closeMenu()
    window.downloadsMenu = true
    window.menuSlot = slot
  }

  function settleShifts() {
    window.animateShifts = false
    Qt.callLater(function() { window.animateShifts = true })
  }

  function endDrag() {
    window.settleShifts()
    window.hoverStale = true
    window.dragIndex = -1
    window.dropIndex = -1
    window.dragOffset = 0
  }

  function closeMenu() {
    window.stackOpen = false
    window.trashMenu = false
    window.downloadsMenu = false
    window.trashConfirm = false
    window.submenuRows = []
    window.submenuAnchor = null
    window.menuItem = null
    window.settingsMenu = false
    window.menuSlot = null
    if (window.autohide) hideTimer.restart()
  }

  // Places the menu inward of the dock, centered on a slot.
  function popupX(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, slot.width / 2, 0).x
    if (window.position === "left") return body.x + body.width + window.gap
    if (window.position === "right") return body.x - window.gap - popup.width
    return Math.max(window.gap, Math.min(window.width - popup.width - window.gap, center - popup.width / 2))
  }

  function popupY(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, 0, slot.height / 2).y
    if (window.position === "top") return body.y + body.height + window.gap
    if (window.position === "bottom") return body.y - window.gap - popup.height
    return Math.max(window.gap, Math.min(window.height - popup.height - window.gap, center - popup.height / 2))
  }

  visible: !remapGuard.remapping
  color: "transparent"
  WlrLayershell.namespace: "omarchy-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Kept clear of the bar's reserved edge, without reserving one of its own:
  // floating windows go where they are put.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  anchors {
    top: window.position !== "bottom"
    bottom: window.position !== "top"
    left: window.position !== "right"
    right: window.position !== "left"
  }

  implicitWidth: window.vertical ? window.gap + window.slotSize + window.popupRoom : 0
  implicitHeight: window.vertical ? 0 : window.gap + window.slotSize + window.popupRoom

  mask: Region {
    item: window.contentShown ? body : null

    Region { item: window.shown && window.autohide ? edgeTrigger : null }
    Region { item: menu.visible ? menu : null }
    Region { item: menuTail.visible ? menuTail : null }
    Region { item: submenu.visible ? submenu : null }
    Region { item: stack.visible ? stack : null }
  }

  onAutohideChanged: window.revealed = false

  Timer {
    id: hideTimer
    // Long enough to cross a gap between the edge and the icons, no longer.
    interval: 150
    onTriggered: {
      if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging) window.revealed = false
    }
  }

  // The strip along the screen edge that brings an auto-hidden dock back.
  Item {
    id: edgeTrigger

    readonly property int depth: window.gap + Style.spacing.xxs

    x: window.position === "left" ? 0 : window.position === "right" ? window.width - depth : body.x
    y: window.position === "top" ? 0 : window.position === "bottom" ? window.height - depth : body.y
    width: window.vertical ? depth : body.width
    height: window.vertical ? body.height : depth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) window.revealed = true
        else hideTimer.restart()
      }
    }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }

  HyprlandFocusGrab {
    active: window.menuOpen
    windows: [window]
    onCleared: window.closeMenu()
  }

  Item {
    id: body

    // The strip keeps its order in every language, like the bar: drags and
    // drops reckon slots along x from the first app. Only the menu mirrors.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    width: slots.implicitWidth + window.platterPadding * 2
    height: slots.implicitHeight + window.platterPadding * 2
    // How far the dock is tucked past its edge. Auto-hide slides it, but only
    // while the dock is on screen: arriving on a floating workspace shows it
    // where it belongs at once.
    property real tuck: window.tucked ? window.slotSize + window.gap : 0

    // Tucking away is quicker than coming back. A gentler curve than
    // Style.easeOut, which crosses the short slide in a frame or two.
    Behavior on tuck {
      id: tuckMotion
      enabled: window.shown
      NumberAnimation {
        duration: Style.duration(tuckMotion.targetValue > 0 ? 120 : 180)
        easing.type: Easing.OutCubic
      }
    }

    x: window.position === "left" ? window.gap - tuck
      : window.position === "right" ? window.width - width - window.gap + tuck
      : Math.round((window.width - width) / 2)
    y: window.position === "top" ? window.gap - tuck
      : window.position === "bottom" ? window.height - height - window.gap + tuck
      : Math.round((window.height - height) / 2)
    // Switching between tiled and floating workspaces shows and hides the dock
    // at once, with nothing to watch in between. Hidden by opacity rather than
    // visibility, so the icons keep their textures and are drawn on the first
    // frame back instead of being uploaded again.
    opacity: window.shown ? 1 : 0

    // The macOS dock platter: a borderless sheet of tinted glass behind the
    // icons, the same as the app switcher. Hyprland blurs what is behind it.
    Rectangle {
      anchors.fill: parent
      radius: Math.round((window.slotSize + window.platterPadding * 2) * 0.3)
      color: Qt.rgba(0.2, 0.2, 0.23, 0.34)
    }

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered && window.autohide) hideTimer.restart()
      // Only a real move clears it: the release itself reports the pointer too.
      onPointChanged: {
        if (!window.hoverStale || window.dragging) return
        var at = point.position
        if (Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > Style.space(4)) window.hoverStale = false
      }
    }

    Grid {
      id: slots
      anchors.centerIn: parent
      columns: window.vertical ? 1 : appRepeater.count + 1 + 1 + unpinnedRepeater.count + 2

      Repeater {
        id: appRepeater
        model: window.dock ? window.dock.itemModel : null

        delegate: AppSlot {}
      }

      // A divider, then running apps that are not pinned, Downloads, and
      // Trash at the very end.
      Item {
        width: window.vertical ? window.slotSize : Style.space(13)
        height: window.vertical ? Style.space(13) : window.slotSize

        Rectangle {
          anchors.centerIn: parent
          width: window.vertical ? window.iconSize : 1
          height: window.vertical ? 1 : window.iconSize
          color: Commons.Color.bar.text
          opacity: 0.3
        }
      }

      Repeater {
        id: unpinnedRepeater
        model: window.dock ? window.dock.unpinnedItems : []

        delegate: UnpinnedSlot {}
      }

      PlaceSlot {
        iconSources: window.placeIcons("folder-download")
        stack: true
        tip: "Downloads"
      }

      PlaceSlot {
        iconSources: window.placeIcons(window.trashFull ? "user-trash-full" : "user-trash")
        command: "gio open trash:///"
        trash: true
        tip: "Trash"
      }

      // The all-apps grid sits at the far end, like Launchpad in the macOS dock.
      AppsSlot {}
    }
  }

  // Whether the Trash has anything in it, checked every few seconds while the
  // dock shows, so its icon can show the paper inside.
  property bool trashFull: false

  Process {
    id: trashCheck
    command: ["sh", "-c", "[ -n \"$(ls -A \"$HOME/.local/share/Trash/files\" 2>/dev/null)\" ]"]
    onExited: function(code) { window.trashFull = code === 0 }
  }

  Timer {
    interval: 5000
    repeat: true
    running: window.shown
    triggeredOnStart: true
    onTriggered: trashCheck.running = true
  }

  // Downloads and Trash prefer MacTahoe's light icons, which are what the macOS
  // dock shows in dark mode too (MacTahoe-dark draws a dark bin), then fall back
  // to the current icon theme.
  function placeIcons(name) {
    var file = "/MacTahoe/places/scalable/" + name + ".svg"
    return [
      "file://" + Quickshell.env("HOME") + "/.local/share/icons" + file,
      "file:///usr/share/icons" + file,
      Quickshell.iconPath(name, true)
    ]
  }

  // Downloads and Trash, as on the right of the macOS dock.
  component PlaceSlot: Slot {
    id: placeSlot

    property var iconSources: []
    property int iconTry: 0
    onIconSourcesChanged: iconTry = 0
    property string command
    property bool stack: false

    property bool trash: false

    mouse.onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        if (placeSlot.trash) window.openTrashMenu(placeSlot)
        else if (placeSlot.stack) window.openDownloadsMenu(placeSlot)
        return
      }
      if (placeSlot.stack) {
        if (window.downloadsAs === "folder") {
          window.closeMenu()
          Util.execDetached("xdg-open " + Util.shellQuote(window.downloadsDir))
        } else if (window.stackOpen) window.closeMenu()
        else window.openStack(placeSlot)
        return
      }
      window.closeMenu()
      Util.execDetached(placeSlot.command)
    }

    Image {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
      // Try each candidate until one loads.
      source: placeSlot.iconSources[placeSlot.iconTry] || ""
      onStatusChanged: if (status === Image.Error && placeSlot.iconTry < placeSlot.iconSources.length - 1) placeSlot.iconTry++
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      scale: placeSlot.hovered ? 1.15 : 1
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }
  }

  // A running app that is not pinned, on the right of the divider. A click
  // brings its window forward (restoring a minimized one); right-click opens
  // the same menu as the pinned apps, where it can be kept in the dock.
  component UnpinnedSlot: Slot {
    id: unpinnedSlot
    tip: window.appName(unpinnedSlot.modelData)

    required property var modelData

    mouse.onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        window.openMenu(unpinnedSlot.modelData, unpinnedSlot)
        return
      }
      window.closeMenu()
      if (window.dock) window.dock.activate(unpinnedSlot.modelData)
    }

    Image {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
      source: window.dock ? window.dock.iconFor(unpinnedSlot.modelData) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      scale: unpinnedSlot.hovered ? 1.15 : 1
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }

    RunningDot {}
  }


  // The macOS running indicator: a small dot between the icon and the dock's edge.
  component RunningDot: Rectangle {
    readonly property int size: Math.max(4, Math.round(window.iconSize * 0.11))
    readonly property real edge: window.iconInset / 2 - size / 2

    width: size
    height: size
    radius: size / 2
    color: Commons.Color.bar.text
    x: window.position === "left" ? edge
      : window.position === "right" ? window.slotSize - size - edge
      : (window.slotSize - size) / 2
    y: window.position === "top" ? edge
      : window.position === "bottom" ? window.slotSize - size - edge
      : (window.slotSize - size) / 2
  }

  // The app name over the hovered icon, hidden while a menu or the stack is open.
  property Item tipSlot: null

  function appName(item) {
    if (!item || !window.dock) return ""
    var entry = window.dock.entryFor(item)
    if (entry && entry.name) return String(entry.name)
    var first = item.windows && item.windows.length > 0 ? item.windows[0] : null
    return first && first.toplevel ? String(first.toplevel.title || "") : String(item.key || "")
  }

  Rectangle {
    id: tipLabel

    readonly property string text: window.tipSlot ? window.tipSlot.tip : ""

    visible: window.contentShown && text !== "" && !menu.visible && !window.stackOpen && !window.dragging
    width: tipText.implicitWidth + Style.space(20)
    height: tipText.implicitHeight + Style.space(8)
    radius: Style.space(6)
    color: Qt.rgba(0.11, 0.11, 0.12, 0.88)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.14)
    x: window.tipSlot ? window.popupX(window.tipSlot, tipLabel) : 0
    y: window.tipSlot ? window.popupY(window.tipSlot, tipLabel) - Style.space(4) : 0

    Text {
      id: tipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: tipLabel.text
      color: "#ffffff"
      font.family: "Adwaita Sans"
      font.pixelSize: Math.round(15 * Style.fontScale)
    }
  }

  component Slot: Item {
    id: slot

    // Only the dragged icon is lifted while a drag is on; none of the others
    // pop as it passes over them.
    property bool hovered: mouse.containsMouse && !window.hoverStale && !window.dragging
    property bool pressed: mouse.pressed
    property alias mouse: mouse
    // The name shown above the icon on hover, as in the macOS dock.
    property string tip: ""

    onHoveredChanged: {
      if (hovered) window.tipSlot = slot
      else if (window.tipSlot === slot) window.tipSlot = null
    }
    Component.onDestruction: if (window.tipSlot === slot) window.tipSlot = null

    width: window.slotSize
    height: window.slotSize

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    }
  }

  component AppsSlot: Slot {
    id: appsSlot
    tip: "Applications"

    property real displayedShift: 0

    Behavior on displayedShift {
      enabled: window.animateShifts
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    transform: Translate {
      x: window.vertical ? 0 : appsSlot.displayedShift
      y: window.vertical ? appsSlot.displayedShift : 0
    }

    mouse.onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        window.openSettingsMenu(appsSlot)
        return
      }
      window.closeMenu()
      if (window.dock) window.dock.openApps()
    }

    // A grid of app squares reads as "all apps" in any icon theme. Drawn
    // rather than taken from a font, so its edges stay crisp on the
    // transparent dock and it fills its slot like the app icons beside it.
    Item {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      scale: appsSlot.hovered ? 1.15 : 1
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

      Grid {
        readonly property int square: Math.round(window.iconSize * 0.22)

        anchors.centerIn: parent
        columns: 3
        spacing: Math.round(window.iconSize * 0.1)

        Repeater {
          model: 9

          delegate: Rectangle {
            width: parent.square
            height: parent.square
            radius: Math.max(1, Math.round(parent.square * 0.2))
            color: Commons.Color.bar.text
          }
        }
      }
    }
  }

  component AppSlot: Slot {
    id: appSlot
    tip: window.appName(appSlot.modelData)

    required property int index
    required property string key
    readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
    readonly property bool launching: !!window.dock && window.dock.isLaunching(key)
    readonly property bool lifted: window.dragIndex === index
    property point pressPoint
    property bool dragged: false
    readonly property int windowCount: modelData ? modelData.windows.length : 0
    property real pulse: 1

    // Slots between where the dragged app was and where it would land step
    // aside to make room; the dragged one follows the pointer.
    readonly property real shift: window.insertIndex >= 0 ? (index >= window.insertIndex ? 1 : -1) * window.slotSize / 2
      : !window.dragging ? 0
      : lifted ? window.dragOffset
      : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
      : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
      : 0
    property real displayedShift: shift

    // Only while dragging: once the drop reorders the slots, they are already
    // where they were shown.
    Behavior on displayedShift {
      enabled: window.animateShifts && ((window.dragging && !appSlot.lifted) || window.insertIndex >= 0)
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    z: lifted ? 1 : 0

    // The slot, and the pointer handling in it, stays where it is; only the
    // icon moves. Reading the pointer through a slot that moves with it would
    // feed each move back into the next.
    function bodyPoint(event) {
      return appSlot.mapToItem(body, event.x, event.y)
    }

    mouse.onPressed: function(event) {
      appSlot.dragged = false
      if (event.button === Qt.LeftButton) appSlot.pressPoint = appSlot.bodyPoint(event)
    }

    mouse.onPositionChanged: function(event) {
      if (!(appSlot.mouse.pressedButtons & Qt.LeftButton)) return
      var point = appSlot.bodyPoint(event)
      var delta = window.vertical ? point.y - appSlot.pressPoint.y : point.x - appSlot.pressPoint.x
      // A press that wanders is a drag in the making, not a click.
      if (Math.hypot(point.x - appSlot.pressPoint.x, point.y - appSlot.pressPoint.y) > Style.space(4)) appSlot.dragged = true
      if (!window.dragging) {
        if (Math.abs(delta) < Style.space(6)) return
        window.closeMenu()
        // The landing slot first: with the dragged slot set and no landing
        // slot yet, every slot before it would count as in between and step
        // aside for a moment.
        window.dropIndex = appSlot.index
        window.dragIndex = appSlot.index
      }
      if (!appSlot.lifted) return
      window.dragOffset = delta
      window.dropIndex = DockModel.dropIndex(appSlot.index, delta, window.slotSize, appRepeater.count)
    }

    mouse.onReleased: function(event) {
      if (!appSlot.lifted) return
      window.dropPoint = appSlot.mapToItem(body, event.x, event.y)
      var from = window.dragIndex
      var to = window.dropIndex
      appSlot.dragged = true
      window.endDrag()
      window.dock.moveItem(from, to)
    }

    mouse.onCanceled: if (appSlot.lifted) window.endDrag()

    mouse.onClicked: function(event) {
      // A drag ends in a release over the app, which is not a click on it.
      if (appSlot.dragged) {
        appSlot.dragged = false
        return
      }
      if (event.button === Qt.RightButton) {
        window.openMenu(appSlot.modelData, appSlot)
        return
      }
      window.closeMenu()
      if (event.button === Qt.MiddleButton) window.dock.launch(appSlot.modelData)
      else window.dock.activate(appSlot.modelData)
    }

    // Like macOS: every app is drawn in full, and a dot on the dock's edge marks
    // the running ones. One that is starting pulses its dot.
    Image {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
      source: window.dock && appSlot.modelData ? window.dock.iconFor(appSlot.modelData) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }
      scale: appSlot.lifted || appSlot.hovered ? 1.15 : 1
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }

    RunningDot {
      visible: appSlot.windowCount > 0 || appSlot.launching
      opacity: appSlot.launching ? appSlot.pulse : 1
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }
    }

    // With animations off it holds still rather than spinning through
    // zero-length steps.
    SequentialAnimation {
      running: appSlot.launching && !Style.reduceMotion
      loops: Animation.Infinite
      onRunningChanged: if (!running) appSlot.pulse = 1

      NumberAnimation { target: appSlot; property: "pulse"; from: 1; to: 0.25; duration: Style.duration(500); easing.type: Easing.InOutSine }
      NumberAnimation { target: appSlot; property: "pulse"; to: 1; duration: Style.duration(500); easing.type: Easing.InOutSine }
    }
  }

  BorderSurface {
    id: menu

    readonly property var item: window.menuItem
    readonly property bool hasEntry: !!item && !!window.dock && !!window.dock.entryFor(item)
    readonly property bool running: !!item && item.windows.length > 0

    visible: window.contentShown && (!!item || window.settingsMenu || window.trashMenu || window.downloadsMenu)
    // Like the macOS dock menu: translucent slate glass with a faint light
    // edge, roomy rows, grey section headings, and a tail pointing at the icon.
    readonly property color fill: Qt.rgba(0.2, 0.2, 0.23, 0.45)
    readonly property int tail: window.position === "bottom" ? Style.space(9) : 0
    width: Math.min(Style.space(380), Math.max(Style.space(230), menuColumn.implicitWidth)) + padding * 2
    height: menuColumn.implicitHeight + padding * 2
    x: window.popupX(window.menuSlot, menu)
    y: window.popupY(window.menuSlot, menu) - tail
    radius: Style.space(10)
    color: fill
    borderSpec: Border.surfaceSpec("popups", "border", Qt.rgba(1, 1, 1, 0.18), 1)
    padding: Style.space(5)

    readonly property var windows: item ? item.windows : []

    Column {
      id: menuColumn
      x: menu.contentLeftInset
      y: menu.contentTopInset
      width: menu.width - menu.contentLeftInset - menu.contentRightInset

      Repeater {
        model: [["top", Commons.I18n.t("dock.positionTop")], ["bottom", Commons.I18n.t("dock.positionBottom")], ["left", Commons.I18n.t("dock.positionLeft")], ["right", Commons.I18n.t("dock.positionRight")]]

        delegate: MenuRow {
          required property var modelData

          visible: window.settingsMenu
          text: modelData[1]
          checked: window.position === modelData[0]
          onTriggered: Util.execDetached("omarchy-dock position " + modelData[0])
        }
      }

      MenuRow {
        visible: window.settingsMenu
        text: Commons.I18n.t("dock.autoHide")
        checked: window.autohide
        onTriggered: Util.execDetached("omarchy-dock autohide " + (window.autohide ? "off" : "on"))
      }

      // The app's open windows: a check marks the front one, a diamond a
      // minimized one, as in the macOS dock menu.
      MenuHeader { visible: window.downloadsMenu; text: "Display as" }
      MenuRow {
        visible: window.downloadsMenu
        text: "Folder"
        checked: window.downloadsAs === "folder"
        onTriggered: window.setDownloadsAs("folder")
      }
      MenuRow {
        visible: window.downloadsMenu
        text: "Stack"
        checked: window.downloadsAs !== "folder"
        onTriggered: window.setDownloadsAs("stack")
      }
      MenuSeparator { visible: window.downloadsMenu }
      MenuHeader { visible: window.downloadsMenu; text: "View content as" }
      MenuRow {
        visible: window.downloadsMenu
        text: "Fan"
        checked: true
      }
      MenuSeparator { visible: window.downloadsMenu }
      MenuRow {
        visible: window.downloadsMenu
        text: "Options"
        submenu: [["Show in Files", function() { Util.execDetached("xdg-open " + Util.shellQuote(Quickshell.env("HOME"))) }]]
      }
      MenuSeparator { visible: window.downloadsMenu }
      MenuRow {
        visible: window.downloadsMenu
        text: "Open “Downloads”"
        onTriggered: Util.execDetached("xdg-open " + Util.shellQuote(window.downloadsDir))
      }

      MenuRow {
        visible: window.trashMenu && !window.trashConfirm
        text: "Open"
        onTriggered: Util.execDetached("gio open trash:///")
      }

      MenuRow {
        visible: window.trashMenu && !window.trashConfirm
        enabled: window.trashFull
        opacity: window.trashFull ? 1 : 0.4
        text: "Empty Trash"
        keepOpen: true
        onTriggered: window.trashConfirm = true
      }

      // Emptying deletes for good, so it asks first, as macOS does.
      Text {
        visible: window.trashConfirm
        width: Math.max(implicitWidth, Style.space(200))
        textFormat: Text.PlainText
        text: "Permanently erase the items in the Trash?"
        wrapMode: Text.WordWrap
        leftPadding: Style.space(10)
        rightPadding: Style.space(10)
        topPadding: Style.space(4)
        bottomPadding: Style.space(6)
        color: Commons.Color.popups.text
        font.family: "Adwaita Sans"
        font.pixelSize: Math.round(13 * Style.fontScale)
      }

      MenuRow {
        visible: window.trashConfirm
        text: "Empty Trash"
        onTriggered: Util.execDetached("gio trash --empty")
      }

      MenuRow {
        visible: window.trashConfirm
        text: "Cancel"
      }

      Repeater {
        model: window.settingsMenu || window.trashMenu || window.downloadsMenu ? [] : menu.windows

        delegate: MenuRow {
          required property var modelData

          text: String(modelData.toplevel && modelData.toplevel.title || "") || Commons.I18n.t("dock.newWindow")
          mark: modelData.minimized ? "◆" : (modelData.toplevel && modelData.toplevel.activated ? "✓" : "")
          onTriggered: window.dock.bringForward(modelData)
        }
      }

      MenuSeparator { visible: !window.settingsMenu && !window.trashMenu && !window.downloadsMenu && menu.windows.length > 0 }

      MenuRow {
        visible: menu.hasEntry && menu.running
        text: Commons.I18n.t("dock.newWindow")
        onTriggered: window.dock.launch(menu.item)
      }

      MenuSeparator { visible: menu.hasEntry && menu.running }

      // As in macOS: Options opens a submenu, where a check shows the app is
      // kept in the dock.
      MenuRow {
        visible: menu.hasEntry
        text: "Options"
        submenu: [[Commons.I18n.t("dock.keepInDock"), function() { window.dock.setPinned(menu.item.key, !menu.item.pinned) }, !!menu.item && menu.item.pinned]]
      }

      MenuSeparator { visible: menu.running }

      MenuRow {
        visible: menu.running
        text: Commons.I18n.t("dock.quit")
        onTriggered: window.dock.quit(menu.item)
      }
    }
  }

  BorderSurface {
    id: submenu
    visible: menu.visible && window.submenuRows.length > 0 && !!window.submenuAnchor
    width: Math.max(Style.space(200), submenuColumn.implicitWidth) + padding * 2
    height: submenuColumn.implicitHeight + padding * 2
    x: menu.x + menu.width - Style.space(4)
    // Level with the row it opens from (rows sit directly in the menu's column).
    y: window.submenuAnchor ? menu.y + menuColumn.y + window.submenuAnchor.y - padding : 0
    radius: Style.space(10)
    color: menu.fill
    borderSpec: Border.surfaceSpec("popups", "border", Qt.rgba(1, 1, 1, 0.18), 1)
    padding: Style.space(5)

    Column {
      id: submenuColumn
      x: submenu.contentLeftInset
      y: submenu.contentTopInset
      width: submenu.width - submenu.contentLeftInset - submenu.contentRightInset

      Repeater {
        model: window.submenuRows
        delegate: MenuRow {
          required property var modelData
          text: modelData[0]
          checked: modelData[2] === true
          onTriggered: modelData[1]()
        }
      }
    }
  }

  Canvas {
    id: menuTail
    visible: menu.visible && menu.tail > 0 && !!window.menuSlot
    width: menu.tail * 2
    height: menu.tail
    x: window.menuSlot ? window.menuSlot.mapToItem(window.contentItem, window.menuSlot.width / 2, 0).x - width / 2 : 0
    y: menu.y + menu.height - 1
    onVisibleChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = menu.fill
      ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.18)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(0, 0)
      ctx.lineTo(width / 2, height)
      ctx.lineTo(width, 0)
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(0.5, 0.5)
      ctx.lineTo(width / 2, height - 0.5)
      ctx.lineTo(width - 0.5, 0.5)
      ctx.stroke()
    }
  }

  // Downloads stack, as on macOS: the newest downloads slide up above the dock
  // in a grid; a click opens one, and "Open in Files" opens the folder.
  property bool stackOpen: false
  property Item stackSlot: null
  property var stackFiles: []
  property var stackCollect: []
  property int stackTotal: 0
  readonly property string downloadsDir: Quickshell.env("HOME") + "/Downloads"

  function openStack(slot) {
    window.closeMenu()
    window.stackSlot = slot
    window.stackCollect = []
    window.stackTotal = -1
    stackList.running = true
    window.stackOpen = true
  }

  Process {
    id: stackList
    // Newest first; -p marks folders with a trailing slash.
    // The first line is how many items Downloads holds; then the newest ten.
    // Hidden files stay out, as in the macOS stack.
    command: ["sh", "-c", "cd \"$HOME/Downloads\" 2>/dev/null && ls | wc -l && ls -t -p | head -n 10"]
    stdout: SplitParser {
      onRead: function(line) {
        // Names are shown as plain text and only ever passed quoted to xdg-open.
        if (window.stackTotal < 0) window.stackTotal = parseInt(line, 10) || 0
        else if (line.length > 0 && line.length < 512) window.stackCollect.push(line)
      }
    }
    onExited: window.stackFiles = window.stackCollect.slice()
  }

  // Leaving both the stack and the dock for a moment closes it.
  Timer {
    interval: 900
    running: window.stackOpen && !stackHover.hovered && !bodyHover.hovered
    onTriggered: window.stackOpen = false
  }

  function stackIcon(name) {
    if (name.charAt(name.length - 1) === "/") return Quickshell.iconPath("folder", true)
    var dot = name.lastIndexOf(".")
    var ext = dot > 0 ? name.substr(dot + 1).toLowerCase() : ""
    if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg"].indexOf(ext) >= 0)
      return "file://" + encodeURI(window.downloadsDir + "/") + encodeURIComponent(name)
    var byExt = {
      pdf: "application-pdf", zip: "package-x-generic", tar: "package-x-generic", gz: "package-x-generic",
      xz: "package-x-generic", "7z": "package-x-generic", rar: "package-x-generic", deb: "package-x-generic",
      mp4: "video-x-generic", mkv: "video-x-generic", mov: "video-x-generic", webm: "video-x-generic",
      mp3: "audio-x-generic", wav: "audio-x-generic", flac: "audio-x-generic", m4a: "audio-x-generic",
      txt: "text-x-generic", md: "text-x-generic", docx: "x-office-document", xlsx: "x-office-spreadsheet",
      pptx: "x-office-presentation", appimage: "application-x-executable"
    }
    return Quickshell.iconPath(byExt[ext] || "text-x-generic", true) || Quickshell.iconPath("text-x-generic", true)
  }

  function openDownload(name) {
    window.stackOpen = false
    Util.execDetached("xdg-open " + Util.shellQuote(window.downloadsDir + "/" + name.replace(/\/$/, "")))
  }

  // The Downloads fan, like macOS: files rise in a column above the icon,
  // newest nearest the dock, each name in a dark label to the left of its
  // icon, with "Open in Files" at the top.
  Item {
    id: stack

    readonly property int icon: Math.round(window.iconSize * 1.05)
    readonly property int rowHeight: icon + Style.space(10)
    readonly property int labelRoom: Style.space(260)
    // Oldest at the top, newest at the bottom next to the dock.
    readonly property var files: window.stackFiles.slice(0, 10).reverse()
    // Room for the curve and tilt of the rows furthest from the dock.
    readonly property int lean: Style.space(140)

    visible: window.contentShown && opacity > 0
    opacity: window.stackOpen ? 1 : 0
    width: labelRoom + Style.space(10) + icon + Style.space(6) + lean
    height: fanColumn.implicitHeight
    // The icon column sits right above the Downloads icon.
    x: window.stackSlot ? window.stackSlot.mapToItem(window.contentItem, window.stackSlot.width / 2, 0).x - (labelRoom + Style.space(10) + icon / 2) : 0
    y: window.stackSlot ? body.y - height - window.gap : 0

    transform: Translate {
      y: window.stackOpen ? 0 : Style.space(18)
      Behavior on y { NumberAnimation { duration: Style.duration(window.stackOpen ? 220 : 140); easing.type: Easing.OutCubic } }
    }
    Behavior on opacity { NumberAnimation { duration: Style.duration(window.stackOpen ? 180 : 120); easing.type: Easing.OutCubic } }

    HoverHandler { id: stackHover }

    Column {
      id: fanColumn
      width: parent.width

      // "Open in Files" at the top of the fan.
      FanRow {
        label: window.stackTotal > stack.files.length ? (window.stackTotal - stack.files.length) + " More in Files" : "Open in Files"
        arrow: true
        index: stack.files.length
        onActivated: {
          window.stackOpen = false
          Util.execDetached("xdg-open " + Util.shellQuote(window.downloadsDir))
        }
      }

      Repeater {
        model: stack.files
        delegate: FanRow {
          required property string modelData
          required property int index
          label: modelData.replace(/\/$/, "")
          iconSource: window.stackIcon(modelData)
          // Counted from the dock, so the fan bends the same however long it is.
          fanIndex: stack.files.length - 1 - index
          onActivated: window.openDownload(modelData)
        }
      }
    }
  }

  // One row of the fan: a dark frosted label (dark mode), then the file's icon. Rows
  // further from the dock lean a little to the right, as the macOS fan bends.
  component FanRow: Item {
    id: fanRow

    property string label
    property url iconSource
    property bool arrow: false
    property int index: 0
    property int fanIndex: index
    signal activated()

    width: stack.width
    height: stack.rowHeight

    // The fan bends right and tilts more the further a row is from the dock.
    readonly property real bend: Math.round(fanIndex * fanIndex * Style.space(1) * 0.6)
    readonly property real tilt: 1 + fanIndex * 0.55

    Item {
      id: rowBody
      x: fanRow.bend
      // Clear margin inside the layer: a layer's own edge is not smoothed when
      // it is rotated, so nothing may touch it.
      readonly property int pad: Style.space(6)
      width: stack.labelRoom + Style.space(10) + stack.icon + pad
      height: parent.height

      transform: Rotation {
        origin.x: rowBody.width - rowBody.pad - stack.icon / 2
        origin.y: rowBody.height / 2
        angle: fanRow.tilt
      }
      // A tilted row is drawn as one smoothed, multisampled layer, so the
      // edges of icons and labels stay clean instead of stair-stepped.
      antialiasing: true
      layer.enabled: true
      layer.smooth: true
      layer.samples: 8

      Rectangle {
        anchors.right: rowIcon.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(stack.labelRoom, labelText.implicitWidth + Style.space(18))
        height: labelText.implicitHeight + Style.space(6)
        radius: Style.space(5)
        color: fanMouse.containsMouse ? "#0a84ff" : Qt.rgba(0.11, 0.11, 0.12, 0.82)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        Text {
          id: labelText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, stack.labelRoom - Style.space(18))
          textFormat: Text.PlainText
          text: fanRow.label
          elide: Text.ElideMiddle
          color: "#ffffff"
          font.family: "Adwaita Sans"
          font.pixelSize: Math.round(13 * Style.fontScale)
        }
      }

      Item {
        id: rowIcon
        anchors.right: parent.right
        anchors.rightMargin: rowBody.pad
        anchors.verticalCenter: parent.verticalCenter
        width: stack.icon
        height: stack.icon
        scale: fanMouse.containsMouse ? 1.08 : 1
        Behavior on scale { NumberAnimation { duration: Style.duration(100); easing.type: Easing.OutCubic } }

        Image {
          visible: !fanRow.arrow
          anchors.fill: parent
          sourceSize: Qt.size(stack.icon * 2, stack.icon * 2)
          source: fanRow.arrow ? "" : fanRow.iconSource
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
          antialiasing: true
        }

        // The round "more" button at the top of the fan, drawn like the
        // macOS one: a softly lit gray disc with a rounded white arrow.
        Image {
          visible: fanRow.arrow
          anchors.centerIn: parent
          width: Math.round(parent.width * 0.9)
          height: width
          sourceSize: Qt.size(width * 2, width * 2)
          source: fanRow.arrow ? Qt.resolvedUrl("icons/more.svg") : ""
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          antialiasing: true
          opacity: fanMouse.containsMouse ? 1 : 0.94
        }
      }
    }

    MouseArea {
      id: fanMouse
      x: rowBody.x
      width: rowBody.width
      height: parent.height
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: fanRow.activated()
    }
  }

  // A thin rule between groups of rows, inset like the macOS menu's.
  // A grey, unclickable section heading ("Options", "Display as").
  component MenuHeader: Item {
    property string text
    width: parent ? parent.width : 0
    implicitWidth: Style.space(30) + headerText.implicitWidth + Style.space(22)
    height: visible ? Style.space(29) : 0

    Text {
      id: headerText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(30)
      textFormat: Text.PlainText
      text: parent.text
      color: Qt.rgba(1, 1, 1, 0.4)
      font.family: "Adwaita Sans"
      font.pixelSize: Math.round(16 * Style.fontScale)
      font.weight: Font.Medium
    }
  }

  component MenuSeparator: Item {
    width: parent ? parent.width : 0
    height: visible ? Style.space(11) : 0

    // Inset from both sides.
    Rectangle {
      anchors.centerIn: parent
      width: parent.width - Style.space(20)
      height: 1
      color: Qt.rgba(1, 1, 1, 0.16)
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    property bool checked: false
    property string mark: checked ? "✓" : ""
    property bool keepOpen: false
    // Rows for a submenu: [text, action, checked]. A row with one opens it.
    property var submenu: []
    signal triggered()

    readonly property int gutter: Style.space(30)
    readonly property bool hasSubmenu: submenu.length > 0

    width: parent ? parent.width : 0
    implicitWidth: gutter + rowText.implicitWidth + Style.space(hasSubmenu ? 48 : 22)
    height: visible ? Style.space(29) : 0
    radius: Style.space(5)
    color: rowMouse.containsMouse ? "#0a84ff" : "transparent"

    Text {
      visible: row.mark !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: row.gutter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: row.mark
      color: rowMouse.containsMouse ? "#ffffff" : Commons.Color.popups.text
      font.family: "Adwaita Sans"
      font.pixelSize: row.mark === "◆" ? Math.round(10 * Style.fontScale) : Math.round(16 * Style.fontScale)
      font.weight: Font.DemiBold
    }

    Text {
      id: rowText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: row.gutter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: row.text
      color: rowMouse.containsMouse ? "#ffffff" : Commons.Color.popups.text
      font.family: "Adwaita Sans"
      font.pixelSize: Math.round(16 * Style.fontScale)
      font.weight: Font.Medium
    }

    Text {
      visible: row.hasSubmenu
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      textFormat: Text.PlainText
      text: "▶"
      color: "#ffffff"
      font.pixelSize: Math.round(12 * Style.fontScale)
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: row.enabled
      onContainsMouseChanged: {
        if (!containsMouse) return
        if (row.hasSubmenu) {
          window.submenuRows = row.submenu
          window.submenuAnchor = row
        } else if (window.submenuAnchor && window.submenuAnchor.parent === row.parent) {
          // Moving to another row of the same menu closes the submenu.
          window.submenuRows = []
          window.submenuAnchor = null
        }
      }
      onClicked: {
        if (row.hasSubmenu) return
        row.triggered()
        if (!row.keepOpen) window.closeMenu()
      }
    }
  }
}
