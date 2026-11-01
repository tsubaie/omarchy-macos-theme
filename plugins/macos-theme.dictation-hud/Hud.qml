import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HudIcons.js" as HudIcons

// macOS-style dictation HUD: the volume HUD's glass panel, where the
// dictation-hud setting puts it (bottom middle or top right), while Voxtype records (the
// mic and moving level bars) or transcribes (pulsing dots).
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
  property var shell: null
  // Where the HUD sits: the bottom middle (the default), or top right under
  // the bar as macOS 27.2 opens it under its menu bar icon. "hud":
  // { "dictation": "top" } in shell.json, from install.sh --set dictation-hud=<bottom|top>.
  property bool atTop: false
  // Read again at every open too: install.sh and Omarchy replace shell.json
  // rather than write into it, and the watch doesn't follow a replaced file.
  FileView {
    id: placeFile
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.atTop = !!(parsed && parsed.hud && parsed.hud.dictation === "top")
      } catch (e) { root.atTop = false }
    }
  }

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
      if (["idle", "recording", "transcribing", "stopped"].indexOf(s) === -1) return
      if (!root.shown && (s === "recording" || s === "transcribing")) placeFile.reload()
      root.state = s
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
    id: panel
    shown: root.shown
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-dictation-hud"
    // Visual only: never block clicks to whatever is underneath.
    mask: Region {}
    // How far a top bar reaches down on this screen, for the top position.
    readonly property int barClear: root.shell && root.shell.bar && !root.shell.bar.barHidden && root.shell.bar.position === "top"
      ? root.shell.bar.barSizeFor(screen ? screen.name : "") : 0

    // The same capsule as the volume HUD (macOS 27.2), in its place,
    // the microphone on the left where the speaker is. Its glass and rim
    // are Osd.qml's; see there for why.
    BorderSurface {
      id: card
      width: Style.space(300)
      height: Style.space(60)
      radius: height / 2
      x: root.atTop ? parent.width - width - Style.space(10) : Math.round((parent.width - width) / 2)
      y: root.atTop ? panel.barClear + Style.space(6) : parent.height - height - Style.space(96)
      color: Util.alpha(Commons.Color.background, root.windowGlass * root.windowGlass * 0.5)

      Rectangle { anchors.fill: parent; radius: card.radius; color: Qt.rgba(1, 1, 1, 0.05) }
      Repeater {
        model: 7
        Item {
          required property int index
          y: index * parent.height * 0.06
          width: parent.width
          height: parent.height * 0.06
          clip: true
          Rectangle { y: -parent.y; width: parent.width; height: parent.parent.height; radius: card.radius; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.2 * (1 - parent.index / 7)) }
        }
      }

      // Slides in from the nearer edge from the frame the fresh surface is revealed.
      readonly property bool live: root.shown && panel.contentRevealed
      opacity: live ? 1 : 0
      transform: Translate { y: card.live ? 0 : (root.atTop ? -1 : 1) * Style.space(10); Behavior on y { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutBack; easing.overshoot: 1.2 } } }
      Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

      // Icons8's microphone, drawn at three times its size and scaled down
      // smoothly, so it stays crisp at any display scale.
      Image {
        id: mic
        x: Style.space(22)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32)
        height: width
        source: HudIcons.icon("microphone", Commons.Color.popups.text.toString())
        sourceSize: Qt.size(width * 3, height * 3)
        smooth: true
        mipmap: true
      }

      // Recording: a waveform where the volume HUD has its steps, drawn as
      // Apple draws one: hairline rounded bars close together, one smooth
      // wave moving through them, tapered toward both ends. Voxtype doesn't
      // publish input levels, so the motion shows "listening", not the
      // actual loudness.
      Item {
        id: levels
        visible: root.recording
        anchors.left: mic.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(22)
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(24)

        readonly property real barWidth: Math.max(2, Math.round(Style.space(2)))
        readonly property real pitch: barWidth * 2
        readonly property int count: Math.max(1, Math.floor((width + barWidth) / pitch))
        readonly property real minHeight: barWidth
        property real phase: 0
        NumberAnimation on phase {
          running: root.recording && Style.duration(1) > 0
          from: 0; to: 2 * Math.PI
          duration: 1400
          loops: Animation.Infinite
        }

        Repeater {
          model: levels.count
          Rectangle {
            required property int index
            readonly property real along: levels.count > 1 ? index / (levels.count - 1) : 0.5
            // Tall in the middle, low at the ends; two waves of different
            // length make the motion look less mechanical.
            readonly property real swing: 0.5 + 0.3 * Math.sin(levels.phase + along * 9) + 0.2 * Math.sin(levels.phase * 2 - along * 5)
            x: index * levels.pitch
            anchors.verticalCenter: parent.verticalCenter
            width: levels.barWidth
            height: levels.minHeight + (levels.height - levels.minHeight) * Math.sin(Math.PI * along) * swing
            radius: width / 2
            color: Commons.Color.popups.text
            opacity: 0.9
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
