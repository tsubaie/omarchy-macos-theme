import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Spotlight-style app launcher: a wide frosted search bar in the upper third
// of the screen. Results grow below it as you type, a Top Hit first; Up/Down
// move, Return opens, Esc or a click outside closes. Apps you open often and
// recently rank higher.
Item {
  id: root

  property bool opened: false
  property string query: ""
  property var results: []
  property int index: 0
  // Desktop ids, most recently launched first.
  property var recent: []

  readonly property int barWidth: Math.round(680 * Style.fontScale)
  readonly property int rowHeight: Math.round(36 * Style.fontScale)
  readonly property int maxRows: 8
  readonly property string recentFile: Quickshell.env("HOME") + "/.local/state/omarchy/macos-spotlight-recent"

  ShellIpc {
    target: "macos-spotlight"
    function toggle(): string { if (root.opened) root.close(); else root.open(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  FileView {
    path: root.recentFile
    printErrors: false
    onLoaded: {
      var ids = text().split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 && s.length < 256 })
      root.recent = ids.slice(0, 50)
    }
  }

  function open() {
    root.query = ""
    root.results = []
    root.index = 0
    root.opened = true
    focusTimer.restart()
  }

  // Typing must land in the search field on every open, even when the window
  // was already mapped and its reveal signal does not fire again.
  Timer {
    id: focusTimer
    interval: 60
    repeat: true
    property int tries: 0
    onRunningChanged: if (running) tries = 0
    onTriggered: {
      field.text = ""
      field.forceActiveFocus()
      if (field.activeFocus || ++tries > 15) stop()
    }
  }

  function close() {
    root.opened = false
  }

  // Name match quality: whole name, start of name, start of a word, anywhere,
  // then the letters in order (so "brv" finds Brave). 0 means no match.
  function matchScore(name, q) {
    name = name.toLowerCase()
    if (name === q) return 100
    if (name.indexOf(q) === 0) return 80
    var words = name.split(/[\s\-_.]+/)
    for (var w = 0; w < words.length; w++) if (words[w].indexOf(q) === 0) return 65
    if (name.indexOf(q) >= 0) return 50
    // Letters in order only count from the start of the name, so "brv"
    // finds Brave without dragging in everything with a b, r and v.
    if (q.charAt(0) !== name.charAt(0)) return 0
    var at = 0
    for (var i = 0; i < q.length; i++) {
      at = name.indexOf(q.charAt(i), at)
      if (at < 0) return 0
      at++
    }
    return 25
  }

  function search(text) {
    var q = String(text || "").trim().toLowerCase()
    root.query = text
    root.index = 0
    if (!q) { root.results = []; return }
    var out = []
    var values = DesktopEntries.applications.values || []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e || e.noDisplay) continue
      var name = String(e.name || "")
      var score = Math.max(root.matchScore(name, q), Math.round(root.matchScore(String(e.genericName || ""), q) * 0.6))
      var keywords = (e.keywords || []).join(" ")
      if (keywords) score = Math.max(score, Math.round(root.matchScore(keywords, q) * 0.5))
      if (score <= 0) continue
      var seen = root.recent.indexOf(e.id)
      if (seen >= 0) score += Math.max(4, 20 - seen)
      out.push({ entry: e, score: score, name: name })
    }
    out.sort(function(a, b) { return b.score - a.score || a.name.localeCompare(b.name) })
    root.results = out.slice(0, root.maxRows)
  }

  function launch(entry) {
    if (!entry) return
    root.close()
    var id = String(entry.id || "")
    root.recent = [id].concat(root.recent.filter(function(r) { return r !== id })).slice(0, 50)
    Util.execDetached("mkdir -p " + Util.shellQuote(Quickshell.env("HOME") + "/.local/state/omarchy") + " && printf '%s\\n' " + root.recent.map(Util.shellQuote).join(" ") + " > " + Util.shellQuote(root.recentFile))
    // Terminal apps go through Omarchy's TUI launcher, the rest through
    // gtk-launch in their own scope, as Omarchy launches apps.
    if (entry.runInTerminal && entry.command && entry.command.length > 0) {
      Util.execDetached("omarchy-launch-tui " + entry.command.map(function(w) { return Util.shellQuote(w) }).join(" "))
      return
    }
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  function iconFor(entry) {
    return Quickshell.iconPath(String(entry && entry.icon || ""), true) || Quickshell.iconPath("application-x-executable", true)
  }

  OverlayWindow {
    shown: root.opened
    shownKeyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "omarchy-spotlight"
    onContentRevealedChanged: if (contentRevealed) field.forceActiveFocus()

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    // The frosted panel: the search bar, then results below it.
    Rectangle {
      id: panel
      width: root.barWidth
      height: column.height
      x: Math.round((parent.width - width) / 2)
      y: Math.round(parent.height * 0.22)
      radius: Math.round(26 * Style.fontScale)
      color: Qt.rgba(0.2, 0.2, 0.23, 0.55)
      clip: true

      MouseArea { anchors.fill: parent }

      Column {
        id: column
        width: parent.width

        // Search bar.
        Item {
          width: parent.width
          height: Math.round(58 * Style.fontScale)

          Text {
            id: glass
            anchors.left: parent.left
            anchors.leftMargin: Math.round(20 * Style.fontScale)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: ""
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Math.round(20 * Style.fontScale)
          }

          TextInput {
            id: field
            anchors.left: glass.right
            anchors.leftMargin: Math.round(14 * Style.fontScale)
            anchors.right: parent.right
            anchors.rightMargin: Math.round(20 * Style.fontScale)
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"
            selectionColor: "#0a84ff"
            selectedTextColor: "#ffffff"
            font.family: "Adwaita Sans"
            font.pixelSize: Math.round(22 * Style.fontScale)
            clip: true
            focus: true
            onTextChanged: root.search(text)
            onVisibleChanged: if (visible) text = ""

            Text {
              visible: field.text.length === 0
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Spotlight Search"
              color: Qt.rgba(1, 1, 1, 0.42)
              font: field.font
            }

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) root.close()
              else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { if (root.results.length) root.index = (root.index + 1) % root.results.length }
              else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { if (root.results.length) root.index = (root.index - 1 + root.results.length) % root.results.length }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { var r = root.results[root.index]; if (r) root.launch(r.entry) }
              else return
              event.accepted = true
            }
          }
        }

        Rectangle {
          visible: root.results.length > 0
          width: parent.width
          height: 1
          color: Qt.rgba(1, 1, 1, 0.12)
        }

        // Top Hit: the best result, larger.
        Item {
          visible: root.results.length > 0
          width: parent.width
          height: visible ? topHit.height + Math.round(12 * Style.fontScale) : 0

          ResultRow {
            id: topHit
            y: Math.round(8 * Style.fontScale)
            result: root.results[0] || null
            rowIndex: 0
            big: true
          }
        }

        // The rest, under an "Applications" heading.
        Text {
          visible: root.results.length > 1
          leftPadding: Math.round(22 * Style.fontScale)
          topPadding: Math.round(2 * Style.fontScale)
          bottomPadding: Math.round(4 * Style.fontScale)
          textFormat: Text.PlainText
          text: "Applications"
          color: Qt.rgba(1, 1, 1, 0.45)
          font.family: "Adwaita Sans"
          font.pixelSize: Math.round(12 * Style.fontScale)
          font.weight: Font.DemiBold
        }

        Repeater {
          model: root.results.slice(1)
          delegate: ResultRow {
            required property var modelData
            required property int index
            result: modelData
            rowIndex: index + 1
          }
        }

        Item {
          visible: root.results.length > 0
          width: 1
          height: Math.round(8 * Style.fontScale)
        }

        Text {
          visible: root.query.trim().length > 0 && root.results.length === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          topPadding: Math.round(14 * Style.fontScale)
          bottomPadding: Math.round(18 * Style.fontScale)
          textFormat: Text.PlainText
          text: "No Results"
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: "Adwaita Sans"
          font.pixelSize: Math.round(15 * Style.fontScale)
        }
      }
    }
  }

  // One result: icon and name; the selected row in macOS blue.
  component ResultRow: Item {
    id: resultRow

    property var result: null
    property int rowIndex: 0
    property bool big: false
    readonly property bool selected: rowIndex === root.index

    x: Math.round(8 * Style.fontScale)
    width: root.barWidth - Math.round(16 * Style.fontScale)
    height: big ? Math.round(56 * Style.fontScale) : root.rowHeight

    Rectangle {
      anchors.fill: parent
      radius: Math.round(9 * Style.fontScale)
      color: resultRow.selected ? "#0a84ff" : "transparent"
    }

    Image {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: Math.round(12 * Style.fontScale)
      anchors.verticalCenter: parent.verticalCenter
      width: resultRow.big ? Math.round(40 * Style.fontScale) : Math.round(24 * Style.fontScale)
      height: width
      sourceSize: Qt.size(width * 2, height * 2)
      source: resultRow.result ? root.iconFor(resultRow.result.entry) : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
      asynchronous: true
    }

    Text {
      anchors.left: rowIcon.right
      anchors.leftMargin: Math.round(12 * Style.fontScale)
      anchors.right: parent.right
      anchors.rightMargin: Math.round(12 * Style.fontScale)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: resultRow.result ? resultRow.result.name : ""
      elide: Text.ElideRight
      color: "#ffffff"
      font.family: "Adwaita Sans"
      font.pixelSize: resultRow.big ? Math.round(18 * Style.fontScale) : Math.round(15 * Style.fontScale)
      font.weight: resultRow.big ? Font.DemiBold : Font.Normal
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      // Only a real pointer move selects, not results appearing under a
      // resting pointer.
      onPositionChanged: root.index = resultRow.rowIndex
      onClicked: if (resultRow.result) root.launch(resultRow.result.entry)
    }
  }
}
