import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import Quickshell.Hyprland
import "OsdModel.js" as OsdModel
import "HudIcons.js" as HudIcons

Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string message: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200

  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0
  readonly property int percent: Math.round(value * 100 / Math.max(1, maxValue))
  readonly property string hudIcon: OsdModel.hudIconName(iconKey, percent)

  // The glass of the theme's windows, as Control Center has it: their
  // background as see-through as the Glass setting makes them, over the same
  // blur (look.lua blurs this layer), without an edge, as Apple's HUDs have
  // none.
  readonly property color ink: Commons.Color.popups.text
  readonly property color glass: Util.alpha(Commons.Color.background, root.windowGlass)

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


  // The keyboard language, shown in the middle when it changes. Every
  // keyboard reports its layout, including the virtual ones that dictation
  // types through (wtype's says "English (US)", then "none"; another's says
  // "error"), and those are "main" while they type. So an event only prompts
  // a look at the main keyboard's layout, leaving those out, and only a
  // change in that shows.
  property string layout: ""
  property bool layoutOpen: false
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "activelayout") return
      // One that comes while a look is under way gets another after it.
      if (layoutCheck.running) layoutCheck.again = true
      else layoutCheck.running = true
    }
  }
  Process {
    id: layoutCheck
    property bool again: false
    running: true
    onExited: if (again) { again = false; running = true }
    // The main keyboard, unless it is a virtual one other than an input
    // method's (fcitx5, ibus), and its layout unless that names none.
    command: ["sh", "-c", "hyprctl devices -j | jq -r '[.keyboards[] | select(.main)"
      + " | select((.name | test(\"^hl-virtual-keyboard-|wtype|dotool|ydotool|eitype\") | not) or (.name | test(\"fcitx|ibus\")))"
      + " | select(.active_keymap | test(\"^(none|error|unknown|[(]unnamed[)])?$\"; \"i\") | not)][0].active_keymap // empty'"]
    stdout: SplitParser {
      onRead: function(line) {
        var next = String(line).trim()
        if (!next || next === root.layout) return
        var first = root.layout === ""
        root.layout = next
        if (first) return
        root.layoutOpen = true
        layoutTimer.restart()
      }
    }
  }
  Timer {
    id: layoutTimer
    interval: 1200
    onTriggered: root.layoutOpen = false
  }

  // The card is built out of measured columns instead of fixed widths, so it
  // keeps exactly `pad` between border and content on every side whatever
  // glyph or message it carries. Messages grow with their text up to
  // `maxMessageWidth` and elide beyond it.
  readonly property int pad: Style.space(16)
  readonly property int gap: Style.space(16)
  // A glyph next to a message reads airier than it measures: the icon outline
  // and the letterforms both fall away from their ink extremes, so the space
  // between them opens up well past the nominal gap. Text takes two thirds of
  // it; the progress bar's hard edge keeps the full gap.
  readonly property int messageGap: Math.round(root.gap * 2 / 3)
  readonly property int barWidth: Style.space(142)
  readonly property int maxMessageWidth: root.mediaOsd ? Style.space(325) : Style.space(190)

  // Nerd Font glyphs draw well outside their monospace cell, so the icon
  // column is measured by ink rather than by advance width. Progress OSDs pin
  // it to the widest glyph the model can return, so the bar doesn't shift when
  // volume crosses an icon threshold.
  readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
  readonly property int iconWidth: root.hasProgress
    ? Math.max(root.iconInkWidth, Math.ceil(widestIconMetrics.tightBoundingRect.width))
    : root.iconInkWidth
  // Same idea for the readout: it is as wide as the longest percentage so the
  // digits don't jitter between 9% and 100%.
  readonly property int valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, messageMetrics.advanceWidth))
  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  readonly property int contentWidth: root.message === "" ? root.iconWidth : root.iconWidth + root.messageGap + root.messageWidth

  function iconFor(name, percent) {
    return OsdModel.iconFor(name, percent)
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration, Commons.I18n.formatNumber)
    // Update before opening so a fresh OSD starts at its new value; only
    // subsequent updates while it remains open animate the progress bar.
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    opened = true
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration))
    } catch (e) {}
  }

  function close() { opened = false }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: "Inter"
    font.weight: Font.Medium
    font.pixelSize: Style.font.title
    text: root.message
  }

  TextMetrics {
    id: valueMetrics
    font: messageMetrics.font
    text: Commons.I18n.formatNumber(100) + "%"
  }

  TextMetrics {
    id: iconMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    text: root.icon
  }

  TextMetrics {
    id: widestIconMetrics
    font: iconMetrics.font
    text: OsdModel.widestIcon
  }

  ShellIpc {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  OverlayWindow {
    id: panel
    shown: root.opened || root.layoutOpen
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-osd"
    // Visual-only surface: keep the layer-shell input region empty so the OSD
    // never blocks clicks to the desktop below it.
    mask: Region {}

    // Volume, brightness and other levels, as macOS 27.2 (Golden Gate) shows
    // them: a rounded panel of glass, at the bottom middle, with one larger
    // icon on the left and a bar of sixteen steps, each key press filling or
    // clearing one.
    BorderSurface {
      id: hud
      visible: root.hasProgress
      width: Style.space(300)
      height: Style.space(60)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(96)
      color: root.glass
      radius: Style.space(20)
      opacity: root.opened ? 1 : 0

      Item {
        id: art
        x: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        height: width

        // Icons8's icon for the volume, brightness, microphone or keyboard;
        // any other level keeps its glyph.
        Image {
          anchors.fill: parent
          visible: root.hudIcon !== ""
          source: root.hudIcon !== "" ? HudIcons.icon(root.hudIcon, root.ink.toString()) : ""
          // Drawn at three times its size and scaled down smoothly, so it
          // stays crisp at any display scale.
          sourceSize: Qt.size(width * 3, height * 3)
          smooth: true
          mipmap: true
        }

        Text {
          anchors.centerIn: parent
          visible: root.hudIcon === ""
          textFormat: Text.PlainText
          text: root.icon
          font.family: Style.font.family
          font.pixelSize: Style.space(26)
          color: root.ink
        }
      }

      // The steps, filling from the left; a level between steps fills the
      // last one in part.
      Row {
        id: steps
        readonly property real filled: root.hasProgress ? 16 * root.value / root.maxValue : 0
        anchors.left: art.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Repeater {
          model: 16

          delegate: Rectangle {
            required property int index
            width: (steps.width - 15 * steps.spacing) / 16
            height: Style.space(6)
            radius: Style.space(2)
            color: Util.alpha(root.ink, 0.22)

            Rectangle {
              anchors.left: parent.left
              height: parent.height
              width: parent.width * Math.max(0, Math.min(1, steps.filled - parent.index))
              radius: parent.radius
              color: root.ink

              Behavior on width {
                enabled: root.opened
                NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutCubic }
              }
            }
          }
        }
      }
    }

    // The keyboard language just switched to, in the middle of the screen:
    // its short name large, its full name under it.
    BorderSurface {
      id: languageHud
      visible: root.layoutOpen
      width: Style.space(196)
      height: width
      anchors.centerIn: parent
      color: root.glass
      radius: Style.space(26)
      opacity: root.layoutOpen ? 1 : 0

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        spacing: Style.space(10)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: OsdModel.layoutCode(root.layout)
          font.family: "Inter"
          font.weight: Font.Bold
          font.pixelSize: Style.space(64)
          renderType: Text.CurveRendering
          color: root.ink
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.layout
          font.family: "Inter"
          font.weight: Font.Medium
          font.pixelSize: Style.font.body
          color: root.ink
          opacity: 0.85
        }
      }
    }

    // A message: a capsule of the same glass, its icon and text in a row.
    BorderSurface {
      id: card
      visible: !root.hasProgress
      width: card.borderLeft + root.pad + root.contentWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + Style.font.displayLarge + root.pad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(96)
      color: root.glass
      radius: height / 2
      opacity: root.opened ? 1 : 0

      Row {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.messageGap
        Item {
          width: root.iconWidth
          height: parent.height
          Text {
            textFormat: Text.PlainText
            // Sit the glyph's ink flush in the column.
            x: Math.round((root.iconWidth - root.iconInkWidth) / 2 - iconMetrics.tightBoundingRect.x)
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font: iconMetrics.font
            color: root.ink
          }
        }
        Text {
          textFormat: Text.PlainText
          visible: root.message !== ""
          width: root.messageWidth
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          font: messageMetrics.font
          color: root.ink
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }
  }

}
