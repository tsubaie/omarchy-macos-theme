import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The macOS genie for one screen. Minimizing captures the screen, takes the
// window's part of it (title bar included) and pours it into its dock icon
// while the real window is hidden; restoring pours the same picture back out
// and puts the window where it lands. The overlay takes no input and is only
// mapped while it plays.
PanelWindow {
  id: genie

  // Pictures of minimized windows by address, each with where it was:
  // { grab, rect }. A window minimized some other way has none and simply
  // comes back.
  property var stash: ({})
  property bool running: false
  // The minimize waiting on its capture.
  property var pending: null
  property var finished: null
  // The plugin's folder: Qt reads shaders from files only, not from the qs://
  // address QML is loaded from.
  property string sourceDir: ""

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  visible: running
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "omarchy-dock-genie"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

  // rect is the window in this screen's coordinates; hide() hides the real
  // window once its picture covers it.
  function minimize(address, rect, icon, hide) {
    if (genie.running) {
      hide()
      return
    }
    genie.pending = { address: address, rect: rect, icon: icon, hide: hide }
    genie.running = true
    capture.active = true
  }

  // The screen is captured: keep the window's part and start pouring. Lives
  // here, not in the capture, which is unloaded before the picture arrives.
  function captured() {
    var job = genie.pending
    if (!job) return
    crop.grabToImage(function(result) {
      genie.stash[job.address] = { grab: result, rect: job.rect }
      genie.pending = null
      capture.active = false
      genie.finished = function() {
        genie.running = false
        frame.source = ""
      }
      hideWhenShown.job = job
      genie.play(result.url, job.rect, job.icon, 0, 1)
    })
  }

  function hasPicture(address) {
    return !!genie.stash[address]
  }

  // done() brings the real window back as the picture arrives.
  function restore(address, icon, done) {
    var picture = genie.stash[address]
    if (genie.running || !picture) {
      done()
      return
    }
    delete genie.stash[address]
    genie.finished = function() {
      done()
      // Gone once the window has had a frame to show itself under it.
      settle.restart()
    }
    genie.play(picture.grab.url, picture.rect, icon, 1, 0)
  }

  function play(url, rect, icon, from, to) {
    genie.running = true
    effect.win = rect
    effect.icon = icon
    effect.progress = from
    frame.source = url
    pour.from = from
    pour.to = to
    pour.duration = Style.duration(to > from ? 560 : 500)
    // Starts once the picture has loaded, so nothing blinks.
    if (frame.status === Image.Ready) pour.restart()
  }

  Timer {
    id: settle
    interval: 90
    onTriggered: {
      genie.running = false
      frame.source = ""
    }
  }

  // The window's part of a fresh capture of the screen, kept off the visible
  // area: only its picture is used.
  Item {
    id: crop
    x: genie.width + 64
    width: genie.pending ? genie.pending.rect.width : 1
    height: genie.pending ? genie.pending.rect.height : 1
    clip: true

    Loader {
      id: capture
      active: false
      x: genie.pending ? -genie.pending.rect.x : 0
      y: genie.pending ? -genie.pending.rect.y : 0

      sourceComponent: ScreencopyView {
        width: genie.width
        height: genie.height
        captureSource: genie.screen
        live: false
        onHasContentChanged: if (hasContent) genie.captured()
      }
    }
  }

  // Hides the real window as soon as its picture is on screen over it.
  QtObject {
    id: hideWhenShown
    property var job: null
  }

  // Drawn only through the effect: a hidden Image hands it no texture.
  Image {
    id: frame
    cache: false
    onStatusChanged: {
      if (status !== Image.Ready || !genie.running) return
      pour.restart()
      if (hideWhenShown.job) {
        hideWhenShown.job.hide()
        hideWhenShown.job = null
      }
    }
  }

  ShaderEffect {
    id: effect
    anchors.fill: parent
    visible: genie.running && frame.status === Image.Ready

    property variant source: ShaderEffectSource { sourceItem: frame; hideSource: true }
    property real progress: 0
    property rect win
    property rect icon

    mesh: GridMesh { resolution: Qt.size(12, 64) }
    vertexShader: genie.sourceDir ? "file://" + genie.sourceDir + "/shaders/genie.vert.qsb" : ""
    fragmentShader: genie.sourceDir ? "file://" + genie.sourceDir + "/shaders/genie.frag.qsb" : ""
  }

  NumberAnimation {
    id: pour
    target: effect
    property: "progress"
    easing.type: Easing.InOutSine
    onFinished: if (genie.finished) genie.finished()
  }
}
