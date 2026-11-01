import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// macOS theme: the menu a right-click on a workspace in the bar opens, as a
// macOS menu-bar item's: the workspace's layout (tiling, scrolling or
// floating) with a check by the one it has, picked in one click without
// going there, and the layout new workspaces get. Installed by install.sh
// --menubar into its clone of Omarchy's workspaces widget, next to the
// Workspaces.qml workspaces-patch.pl changes.
Item {
  id: menu

  property var bar: null
  property Item anchorItem: null
  property int workspace: 0
  property int slot: 0
  // The workspace's layout and the default, read as the menu opens.
  property string mode: ""
  property string defaultMode: ""
  property bool open: false

  readonly property var modes: [
    { mode: "dwindle", label: "Tiling" },
    { mode: "scrolling", label: "Scrolling" },
    { mode: "floating", label: "Floating" }
  ]
  function labelOf(mode) {
    for (var i = 0; i < modes.length; i++) if (modes[i].mode === mode) return modes[i].label
    return mode
  }

  function show(item, id, slot) {
    menu.anchorItem = item
    menu.workspace = id
    menu.slot = slot
    menu.mode = ""
    menu.defaultMode = ""
    reader.running = true
    menu.open = true
  }

  function close() {
    menu.open = false
  }

  Process {
    id: reader
    command: ["sh", "-c", "omarchy-hyprland-workspace-layout-current \"$1\"; omarchy-hyprland-workspace-layout-default", "sh", String(menu.workspace)]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        menu.mode = lines[0] || ""
        menu.defaultMode = lines[1] || ""
      }
    }
  }

  // Sets one workspace's layout as Super + L does for the current one: saved
  // so it comes back at the next login, or forgotten when it is the default,
  // so the workspace follows the default again.
  function setMode(mode) {
    menu.close()
    Quickshell.execDetached(["sh", "-c",
      "apply=\"o.workspace_mode({ workspace = \\\"$1\\\", mode = \\\"$2\\\" })\"\n" +
      "hyprctl eval \"$apply\" >/dev/null 2>&1 || exit 1\n" +
      "dir=\"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts\"\n" +
      "if [ \"$2\" = \"$(omarchy-hyprland-workspace-layout-default)\" ]; then rm -f \"$dir/$1.lua\"\n" +
      "else mkdir -p \"$dir\" && printf '%s\\n' \"$apply\" >\"$dir/$1.lua\"; fi\n" +
      "omarchy-shell -q omarchy.workspaces refresh\n" +
      "omarchy-shell -q omarchy.dock refresh",
      "sh", String(menu.workspace), mode])
  }

  function setDefault(mode) {
    menu.close()
    Quickshell.execDetached(["omarchy-hyprland-workspace-layout-default", mode])
  }

  Loader {
    active: menu.anchorItem !== null
    sourceComponent: PopupCard {
      id: card
      anchorItem: menu.anchorItem
      owner: menu
      bar: menu.bar
      open: menu.open
      padding: Style.space(5)
      contentWidth: card.fittedContentWidth(Style.space(230))
      contentHeight: card.fittedContentHeight(column.implicitHeight)

      Column {
        id: column
        width: parent.width

        Text {
          leftPadding: Style.space(10)
          topPadding: Style.space(3)
          bottomPadding: Style.space(4)
          textFormat: Text.PlainText
          text: "Desktop " + menu.slot
          color: Commons.Color.popups.text
          opacity: 0.55
          font.family: "Inter"
          font.pixelSize: Math.round(12 * Style.fontScale)
          font.weight: Font.DemiBold
        }

        Repeater {
          model: menu.modes
          delegate: MenuRow {
            required property var modelData
            layout: modelData.mode
            label: modelData.label
            checked: menu.mode === modelData.mode
            onPicked: menu.setMode(modelData.mode)
          }
        }

        Rectangle {
          x: Style.space(10)
          width: parent.width - Style.space(20)
          height: 1
          color: Commons.Color.popups.text
          opacity: 0.15
        }
        Item { width: 1; height: Style.space(4) }

        MenuRow {
          label: menu.mode && menu.mode !== menu.defaultMode
            ? "Use " + menu.labelOf(menu.mode) + " for New Desktops"
            : menu.labelOf(menu.defaultMode) + " Is the Default"
          enabled: !!menu.mode && menu.mode !== menu.defaultMode
          onPicked: menu.setDefault(menu.mode)
        }
      }
    }
  }

  // A macOS menu row: a check column, the layout's icon, the label, lit in
  // the accent color under the pointer.
  component MenuRow: Rectangle {
    id: row
    property string layout: ""
    property string label: ""
    property bool checked: false
    signal picked()

    width: parent ? parent.width : 0
    height: Style.space(26)
    radius: Style.space(5)
    color: hover.hovered && row.enabled ? "#0a84ff" : "transparent"
    opacity: row.enabled ? 1 : 0.45

    Text {
      x: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      visible: row.checked
      textFormat: Text.PlainText
      text: "✓"
      color: hover.hovered ? "white" : Commons.Color.popups.text
      font.family: "Inter"
      font.pixelSize: Math.round(13 * Style.fontScale)
      font.weight: Font.DemiBold
    }
    LayoutIcon {
      x: Style.space(26)
      anchors.verticalCenter: parent.verticalCenter
      visible: row.layout !== ""
      mode: row.layout
      size: Style.space(16)
      color: hover.hovered && row.enabled ? "white" : Commons.Color.popups.text
    }
    Text {
      x: row.layout !== "" ? Style.space(50) : Style.space(26)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.label
      color: hover.hovered && row.enabled ? "white" : Commons.Color.popups.text
      font.family: "Inter"
      font.pixelSize: Math.round(13 * Style.fontScale)
    }

    HoverHandler { id: hover }
    TapHandler { enabled: row.enabled; onTapped: row.picked() }
  }
}
