import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HudIcons.js" as HudIcons

// macOS-style dictation HUD: the volume HUD's glass panel at the bottom
// middle while Voxtype records (the mic and moving level bars) or transcribes
// (pulsing dots).
Item {
  id: root

  // "idle", "recording", "transcribing" or "stopped", from voxtype's status feed.
  property string state: "idle"
  readonly property bool recording: state === "recording"
  readonly property bool shown: recording || state === "transcribing"


  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

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


  // Only known states are accepted; anything else from the feed is ignored.
  function update(line) {
    try {
      var s = String(JSON.parse(line).class || "")
      if (["idle", "recording", "transcribing", "stopped"].indexOf(s) !== -1) root.state = s
    } catch (e) {}
  }

  Process {
    id: feed
    command: ["voxtype", "status", "--follow", "--format", "json"]
    running: true
    stdout: SplitParser { onRead: function(data) { root.update(data) } }
    // The feed ends when the voxtype daemon stops or restarts; try again shortly.
    onExited: { root.state = "idle"; restart.start() }
  }

  Timer { id: restart; interval: 3000; onTriggered: feed.running = true }

  OverlayWindow {
    shown: root.shown
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-dictation-hud"
    // Visual only: never block clicks to whatever is underneath.
    mask: Region {}

    // The same panel as the volume HUD (macOS 27.2): the theme's window glass
    // at the bottom middle, without an edge, the microphone on the left where
    // the speaker is.
    BorderSurface {
      id: card
      width: Style.space(300)
      height: Style.space(60)
      radius: Style.space(20)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(96)
      color: Util.alpha(Commons.Color.background, root.windowGlass)

      opacity: root.shown ? 1 : 0
      scale: root.shown ? 1 : 0.96
      Behavior on opacity { NumberAnimation { duration: Style.duration(root.shown ? 180 : 120); easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

      // Icons8's microphone, drawn at three times its size and scaled down
      // smoothly, so it stays crisp at any display scale.
      Image {
        id: mic
        x: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        height: width
        source: HudIcons.icon("microphone", Commons.Color.popups.text.toString())
        sourceSize: Qt.size(width * 3, height * 3)
        smooth: true
        mipmap: true
      }

      // Recording: level bars where the volume HUD has its steps. Voxtype
      // doesn't publish input levels, so the motion shows "listening", not
      // the actual loudness.
      Row {
        id: levels
        visible: root.recording
        anchors.left: mic.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(26)
        spacing: Style.space(3)
        Repeater {
          model: [0.35, 0.6, 0.45, 0.8, 0.55, 1.0, 0.7, 0.4, 0.85, 0.6, 0.95, 0.5, 0.75, 0.45, 0.9, 0.6, 0.4, 0.7, 0.5, 0.3]
          Rectangle {
            required property real modelData
            required property int index
            width: (levels.width - 19 * levels.spacing) / 20
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Commons.Color.popups.text
            property real peak: levels.height * modelData
            height: Style.space(4)
            SequentialAnimation on height {
              running: root.recording && Style.duration(1) > 0
              loops: Animation.Infinite
              NumberAnimation { to: peak; duration: 240 + (index % 7) * 41; easing.type: Easing.InOutSine }
              NumberAnimation { to: Style.space(4); duration: 240 + (index % 7) * 41; easing.type: Easing.InOutSine }
            }
          }
        }
      }

      // Transcribing: label and three pulsing dots.
      Row {
        visible: !root.recording
        anchors.left: mic.right
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: strings.t("hud.transcribing")
          font.family: "Inter"
          font.weight: Font.Medium
          font.pixelSize: Style.font.body
          color: Commons.Color.popups.text
        }
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)
          Repeater {
            model: 3
            Rectangle {
              required property int index
              width: Style.space(4); height: width; radius: width / 2
              color: Commons.Color.popups.text
              opacity: 0.3
              SequentialAnimation on opacity {
                running: root.shown && !root.recording && Style.duration(1) > 0
                loops: Animation.Infinite
                PauseAnimation { duration: index * 160 }
                NumberAnimation { to: 1; duration: 320 }
                NumberAnimation { to: 0.3; duration: 320 }
                PauseAnimation { duration: (2 - index) * 160 }
              }
            }
          }
        }
      }
    }
  }
}
