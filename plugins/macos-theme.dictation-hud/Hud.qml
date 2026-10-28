import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// macOS-style dictation HUD: a frosted pill at the bottom center while Voxtype
// records (mic + moving level bars) or transcribes (pulsing dots).
Item {
  id: root

  // "idle", "recording", "transcribing" or "stopped", from voxtype's status feed.
  property string state: "idle"
  readonly property bool recording: state === "recording"
  readonly property bool shown: recording || state === "transcribing"

  readonly property int pillHeight: Style.space(44)
  readonly property int pad: Style.space(18)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

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

    BorderSurface {
      id: card
      width: row.implicitWidth + root.pad * 2
      height: root.pillHeight
      radius: height / 2
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      color: Util.alpha(Commons.Color.background, 0.72)
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, 1)

      opacity: root.shown ? 1 : 0
      scale: root.shown ? 1 : 0.96
      Behavior on opacity { NumberAnimation { duration: Style.duration(root.shown ? 180 : 120); easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
      Behavior on width { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

      Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.space(12)

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍬"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: Style.space(20)
          color: root.recording ? Commons.Color.bar.active : Commons.Color.popups.text
          Behavior on color { ColorAnimation { duration: Style.duration(180) } }
        }

        // Recording: level bars. Voxtype doesn't publish input levels, so the
        // motion shows "listening", not the actual loudness.
        Row {
          visible: root.recording
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)
          Repeater {
            model: [0.55, 0.9, 0.7, 1.0, 0.6, 0.85, 0.5]
            Rectangle {
              required property real modelData
              required property int index
              width: Style.space(3)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Commons.Color.popups.text
              property real peak: Style.space(18) * modelData
              height: Style.space(4)
              SequentialAnimation on height {
                running: root.recording && Style.duration(1) > 0
                loops: Animation.Infinite
                NumberAnimation { to: peak; duration: 260 + index * 37; easing.type: Easing.InOutSine }
                NumberAnimation { to: Style.space(4); duration: 260 + index * 37; easing.type: Easing.InOutSine }
              }
            }
          }
        }

        // Transcribing: label and three pulsing dots.
        Text {
          visible: !root.recording
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: strings.t("hud.transcribing")
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: Style.font.title
          color: Commons.Color.popups.text
        }
        Row {
          visible: !root.recording
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)
          Repeater {
            model: 3
            Rectangle {
              required property int index
              width: Style.space(5); height: width; radius: width / 2
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
