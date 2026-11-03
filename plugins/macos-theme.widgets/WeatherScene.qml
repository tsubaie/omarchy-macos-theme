import QtQuick
import QtQuick.Effects
import qs.Commons

// The sky behind the weather widget's text, as the macOS Weather app paints
// it: a sun or a moon and stars when it is clear, drifting clouds, rain,
// snow, fog or lightning, and wind streaks when it blows. It is cut to the
// widget's rounded square, and holds still when motion is reduced.
Item {
  id: root

  property string scene: "clear"
  // "dawn", "day", "dusk" or "night", from today's sunrise and sunset.
  property string phase: "day"
  readonly property bool day: phase !== "night"
  // The warm sky around sunrise and sunset, with the sun low on the horizon.
  readonly property bool golden: sky && (phase === "dawn" || phase === "dusk")
  property bool windy: false
  property real radius: 0

  readonly property real w: width
  // Still while tiled windows cover the desktop, as nobody sees it move, and
  // with reduced motion.
  property bool still: false
  readonly property bool moving: visible && !still && !Style.reduceMotion
  readonly property bool sky: scene === "clear" || scene === "partly"
  readonly property bool wet: scene === "rain" || scene === "thunder"
  // Clouds cross in about a minute, in a quarter of that in wind.
  readonly property real drift: windy ? 0.25 : 1

  // A stable spread for the drops, flakes and stars.
  // A hash, not a step: a stepped spread made a flake's place and its start
  // depend on each other, lining every flake up on one diagonal.
  function spread(i, salt) {
    var v = Math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
    return v - Math.floor(v)
  }

  readonly property var colors: ({
    clear: day ? ["#4aa6f2", "#2a6fd0"] : ["#0a1430", "#1f2d58"],
    partly: day ? ["#5c9fdc", "#3973bd"] : ["#141e3a", "#283a66"],
    cloudy: day ? ["#8396ab", "#56687c"] : ["#2c3442", "#1b2029"],
    fog: day ? ["#a1abb6", "#6f7a86"] : ["#3b4149", "#24292f"],
    rain: day ? ["#5a6b7e", "#34404c"] : ["#222b37", "#141a22"],
    thunder: ["#3e3f58", "#1f2035"],
    snow: day ? ["#aebfd1", "#7b91a8"] : ["#3c4757", "#222a35"]
  })
  readonly property var fill: golden
    ? (phase === "dawn" ? ["#6c90d2", "#f4b07c"] : ["#57498c", "#f08a5d"])
    : (colors[scene] || colors.cloudy)

  Rectangle {
    id: mask
    anchors.fill: parent
    radius: root.radius
    visible: false
    layer.enabled: true
  }

  layer.enabled: true
  layer.effect: MultiEffect {
    maskEnabled: true
    maskSource: mask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: root.fill[0] }
      GradientStop { position: 1; color: root.fill[1] }
    }
  }

  // The sun: a warm disc in a soft glow, past the top right corner, breathing.
  Item {
    visible: root.sky && root.day
    x: root.w * 0.56
    y: root.golden ? root.w * 0.5 : -root.w * 0.14
    width: root.w * 0.56
    height: width

    Repeater {
      model: [1.0, 0.78, 0.6]
      delegate: Rectangle {
        required property real modelData
        required property int index
        anchors.centerIn: parent
        width: parent.width * modelData
        height: width
        radius: width / 2
        color: index === 2 ? (root.golden ? "#ffab5e" : "#ffd95e")
          : root.golden ? Qt.rgba(1, 0.6, 0.35, index === 0 ? 0.2 : 0.34)
          : Qt.rgba(1, 0.86, 0.45, index === 0 ? 0.16 : 0.3)
      }
    }

    SequentialAnimation on scale {
      running: root.moving && root.sky && root.day
      loops: Animation.Infinite
      NumberAnimation { to: 1.07; duration: 2800; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 2800; easing.type: Easing.InOutSine }
    }
  }

  // The moon, a crescent, and twinkling stars.
  Item {
    anchors.fill: parent
    visible: root.sky && !root.day

    Repeater {
      model: 12
      delegate: Rectangle {
        required property int index
        x: root.spread(index, 1) * root.w
        y: root.spread(index, 2) * root.height * 0.55
        width: Math.max(1.5, root.w * (index % 3 === 0 ? 0.016 : 0.011))
        height: width
        radius: width / 2
        color: "white"
        opacity: 0.8

        SequentialAnimation on opacity {
          running: root.moving && root.sky && !root.day
          loops: Animation.Infinite
          PauseAnimation { duration: 400 * (index % 5) }
          NumberAnimation { to: 0.25; duration: 1400 + 150 * (index % 4); easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.85; duration: 1400 + 150 * (index % 4); easing.type: Easing.InOutSine }
        }
      }
    }

    Canvas {
      x: root.w * 0.66
      y: root.w * 0.08
      width: root.w * 0.24
      height: width
      onWidthChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        var r = width / 2
        ctx.reset()
        ctx.fillStyle = "#f5f1dc"
        ctx.beginPath(); ctx.arc(r, r, r, 0, Math.PI * 2); ctx.fill()
        ctx.globalCompositeOperation = "destination-out"
        ctx.beginPath(); ctx.arc(r * 1.55, r * 0.7, r * 0.92, 0, Math.PI * 2); ctx.fill()
      }
    }
  }

  // Clouds: one in front of the sun or moon when partly cloudy, a sky of them
  // otherwise, dark over rain and storms. Each drifts right and comes round.
  Repeater {
    model: root.scene === "partly" ? 1 : root.sky ? 0 : 3

    delegate: Cloud {
      required property int index
      readonly property bool front: root.scene === "partly"
      width: root.w * (front ? 0.5 : [0.8, 0.62, 0.7][index])
      y: front ? root.w * 0.06 : root.w * [-0.08, 0.1, -0.02][index]
      tone: root.wet ? Qt.rgba(0.62, 0.66, 0.72, 1) : root.scene === "snow" ? Qt.rgba(0.92, 0.95, 1, 1) : "white"
      opacity: front ? 0.9 : root.wet ? [0.55, 0.45, 0.5][index] : [0.55, 0.4, 0.48][index]

      // Each starts part of the way along, so the sky is never empty.
      readonly property real phase: front ? 0.6 : [0.45, 0.72, 0.25][index]
      property real t: 0
      x: -root.w * 0.8 + ((t + phase) % 1) * root.w * 1.85

      NumberAnimation on t {
        running: root.moving
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: (front ? 70000 : [56000, 74000, 64000][index]) * root.drift
      }
    }
  }

  // Fog: soft bands drifting across.
  Repeater {
    model: root.scene === "fog" ? 4 : 0

    delegate: Rectangle {
      required property int index
      y: root.height * (0.22 + index * 0.17)
      width: root.w * 1.1
      height: root.w * 0.11
      radius: height / 2
      color: "white"
      opacity: 0.16

      SequentialAnimation on x {
        running: root.moving
        loops: Animation.Infinite
        NumberAnimation { from: -root.w * 0.25; to: root.w * 0.1; duration: (9000 + index * 1700) * root.drift; easing.type: Easing.InOutSine }
        NumberAnimation { to: -root.w * 0.25; duration: (9000 + index * 1700) * root.drift; easing.type: Easing.InOutSine }
      }
    }
  }

  // Rain: falling streaks, slanted in wind.
  Repeater {
    model: root.wet ? 22 : 0

    delegate: Rectangle {
      required property int index
      readonly property real span: 650 + root.spread(index, 3) * 400
      x: root.spread(index, 4) * root.w * 1.1 - root.w * 0.05
      width: Math.max(1, root.w * 0.009)
      height: root.w * 0.08
      radius: width / 2
      rotation: root.windy ? 22 : 10
      color: "white"
      opacity: 0.45

      // Each drop starts part of the way down, so it rains from the first frame.
      property real t: 0
      y: -root.w * 0.12 + ((t + root.spread(index, 6)) % 1) * (root.height + root.w * 0.12)

      NumberAnimation on t {
        running: root.moving
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: span
      }
    }
  }

  // Snow: flakes drifting down, swaying.
  Repeater {
    model: root.scene === "snow" ? 26 : 0

    delegate: Rectangle {
      required property int index
      readonly property real home: root.spread(index, 7) * root.w
      width: Math.max(2, root.w * (0.018 + root.spread(index, 8) * 0.016))
      height: width
      radius: width / 2
      color: "white"
      opacity: 0.85
      x: home

      property real t: 0
      y: -root.w * 0.05 + ((t + root.spread(index, 9)) % 1) * (root.height + root.w * 0.05)

      NumberAnimation on t {
        running: root.moving
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: 4200 + root.spread(index, 10) * 2600
      }
      SequentialAnimation on x {
        running: root.moving
        loops: Animation.Infinite
        NumberAnimation { to: home + root.w * (root.windy ? 0.14 : 0.05); duration: 1300; easing.type: Easing.InOutSine }
        NumberAnimation { to: home - root.w * 0.05; duration: 1300; easing.type: Easing.InOutSine }
      }
    }
  }

  // Lightning: now and then the sky lights up, twice.
  Rectangle {
    anchors.fill: parent
    color: "#e8ecff"
    opacity: 0
    visible: root.scene === "thunder"

    SequentialAnimation on opacity {
      running: root.moving && root.scene === "thunder"
      loops: Animation.Infinite
      PauseAnimation { duration: 4200 }
      NumberAnimation { to: 0.55; duration: 60 }
      NumberAnimation { to: 0; duration: 140 }
      PauseAnimation { duration: 90 }
      NumberAnimation { to: 0.35; duration: 50 }
      NumberAnimation { to: 0; duration: 420 }
      PauseAnimation { duration: 2600 }
    }
  }

  // Wind: thin streaks gusting across.
  Repeater {
    model: root.windy ? 4 : 0

    delegate: Rectangle {
      id: streak
      required property int index
      y: root.height * (0.3 + index * 0.16)
      width: root.w * 0.34
      height: Math.max(1, root.w * 0.008)
      radius: height / 2
      color: "white"
      opacity: 0

      ParallelAnimation {
        running: root.moving
        loops: Animation.Infinite
        SequentialAnimation {
          PauseAnimation { duration: 500 * index }
          NumberAnimation { target: streak; property: "x"; from: -root.w * 0.4; to: root.w * 1.05; duration: 1400; easing.type: Easing.InQuad }
          PauseAnimation { duration: 1800 - 500 * index }
        }
        SequentialAnimation {
          PauseAnimation { duration: 500 * index }
          NumberAnimation { target: streak; property: "opacity"; from: 0; to: 0.45; duration: 350 }
          NumberAnimation { target: streak; property: "opacity"; to: 0; duration: 1050 }
        }
      }
    }
  }

  // A cloud: overlapping rounds on a flat base.
  component Cloud: Item {
    property color tone: "white"
    height: width * 0.55
    // Drawn as one shape, so its see-through rounds don't show their overlaps.
    layer.enabled: true

    Rectangle { x: 0; y: parent.height * 0.45; width: parent.width; height: parent.height * 0.5; radius: height / 2; color: parent.tone }
    Rectangle { x: parent.width * 0.12; y: parent.height * 0.22; width: parent.width * 0.42; height: width; radius: width / 2; color: parent.tone }
    Rectangle { x: parent.width * 0.38; y: 0; width: parent.width * 0.5; height: width; radius: width / 2; color: parent.tone }
  }
}
