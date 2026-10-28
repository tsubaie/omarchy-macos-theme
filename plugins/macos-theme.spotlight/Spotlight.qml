import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Spotlight-style launcher: a wide frosted search bar in the upper third of
// the screen. It finds apps and everything in the Omarchy menu (Reboot,
// Theme, Install...), a Top Hit first; Up/Down move, Return opens, Esc or a
// click outside closes. Apps and actions used often and recently rank higher.
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
  readonly property int maxRows: 9
  readonly property string recentFile: Quickshell.env("HOME") + "/.local/state/omarchy/macos-spotlight-recent"

  ShellIpc {
    target: "macos-spotlight"
    function toggle(): string { if (root.opened) root.close(); else root.open(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  // The Omarchy menu: Omarchy's own definition, then the user's extensions,
  // merged by id as the menu does.
  property var menuDefault: ({})
  property var menuUser: ({})
  property var menuItems: []

  FileView {
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/omarchy/omarchy-menu.jsonc"
    printErrors: false
    onLoaded: { root.menuDefault = root.parseJsonc(text()); root.buildMenu() }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.menuUser = root.parseJsonc(text()); root.buildMenu() }
  }

  // JSONC: drop whole-line comments and trailing commas, then parse.
  function parseJsonc(text) {
    var lines = String(text || "").split("\n").filter(function(line) { return !/^\s*\/\//.test(line) })
    try { return JSON.parse(lines.join("\n").replace(/,(\s*[}\]])/g, "$1")) } catch (e) { return ({}) }
  }

  // Every menu row, with its path of parent labels ("System") for context.
  // Rows with an action run it; submenus and links open the Omarchy menu there.
  function buildMenu() {
    var merged = {}
    var id
    for (id in root.menuDefault) merged[id] = Object.assign({}, root.menuDefault[id])
    for (id in root.menuUser) merged[id] = Object.assign(merged[id] || {}, root.menuUser[id])
    var out = []
    for (id in merged) {
      var row = merged[id]
      if (!row || typeof row !== "object" || !row.label || id === "apps") continue
      var parts = id.split(".")
      var path = []
      for (var i = 1; i < parts.length; i++) {
        var parent = merged[parts.slice(0, i).join(".")]
        if (parent && parent.label) path.push(String(parent.label))
      }
      out.push({
        id: id,
        label: String(row.label),
        path: path.join(" › "),
        glyph: String(row.icon || ""),
        iconFont: String(row.iconFont || ""),
        action: String(row.action || ""),
        route: row.action ? "" : String(row.target || id),
        search: [row.label].concat(row.aliases || [], row.description ? [row.description] : []).join(" ")
      })
    }
    root.menuItems = out
  }

  FileView {
    path: root.recentFile
    printErrors: false
    onLoaded: {
      var ids = text().split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 && s.length < 256 })
      root.recent = ids.slice(0, 50)
    }
  }

  // Where the pointer was when the results last changed: rows only take the
  // highlight once it has really moved from there.
  property point pointerRest: Qt.point(-1, -1)
  property bool pointerMoved: false

  function pointerAt(point, rowIndex) {
    if (root.pointerRest.x < 0) { root.pointerRest = point; return }
    if (!root.pointerMoved && Math.abs(point.x - root.pointerRest.x) + Math.abs(point.y - root.pointerRest.y) < 6) return
    root.pointerMoved = true
    root.index = rowIndex
  }

  function open() {
    root.query = ""
    root.results = []
    root.index = 0
    root.pointerRest = Qt.point(-1, -1)
    root.pointerMoved = false
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
    root.pointerRest = Qt.point(-1, -1)
    root.pointerMoved = false
    if (!q) { root.results = []; return }
    var out = []
    // Omarchy actions, slightly below apps on an equal match.
    for (var m = 0; m < root.menuItems.length; m++) {
      var item = root.menuItems[m]
      var ms = Math.max(root.matchScore(item.label, q), Math.round(root.matchScore(item.search, q) * 0.7),
        Math.round(root.matchScore(item.path + " " + item.label, q) * 0.6)) - 3
      // Shallower rows first, and removals last, so "theme" opens the theme
      // picker rather than removing a theme.
      ms -= item.path ? item.path.split(" › ").length * 2 : 0
      if (/^(Remove|Install)\b/.test(item.path)) ms -= 12
      if (ms < 30) continue
      var used = root.recent.indexOf("menu:" + item.id)
      if (used >= 0) ms += Math.max(4, 20 - used)
      out.push({ menu: item, score: ms, name: item.label })
    }
    var values = DesktopEntries.applications.values || []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e || e.noDisplay) continue
      var name = String(e.name || "")
      var score = Math.max(root.matchScore(name, q), Math.round(root.matchScore(String(e.genericName || ""), q) * 0.6))
      var keywords = (e.keywords || []).join(" ")
      if (keywords) score = Math.max(score, Math.round(root.matchScore(keywords, q) * 0.5))
      if (score < 20) continue
      var seen = root.recent.indexOf(e.id)
      if (seen >= 0) score += Math.max(4, 20 - seen)
      out.push({ entry: e, score: score, name: name })
    }
    out.sort(function(a, b) { return b.score - a.score || a.name.localeCompare(b.name) })
    var top = out.slice(0, 1)
    var rest = out.slice(1, root.maxRows)
    rest = rest.filter(function(r) { return !r.menu }).concat(rest.filter(function(r) { return !!r.menu }))
    root.results = top.concat(rest)
  }

  function remember(key) {
    root.recent = [key].concat(root.recent.filter(function(r) { return r !== key })).slice(0, 50)
    Util.execDetached("mkdir -p " + Util.shellQuote(Quickshell.env("HOME") + "/.local/state/omarchy") + " && printf '%s\\n' " + root.recent.map(Util.shellQuote).join(" ") + " > " + Util.shellQuote(root.recentFile))
  }

  // Runs a menu row the way the Omarchy menu does.
  function runMenu(item) {
    if (!item) return
    root.close()
    root.remember("menu:" + item.id)
    if (item.action) Util.execDetached(item.action)
    else Util.execDetached("omarchy menu summon " + Util.shellQuote(item.route))
  }

  function activate(result) {
    if (!result) return
    if (result.menu) root.runMenu(result.menu)
    else root.launch(result.entry)
  }

  function launch(entry) {
    if (!entry) return
    root.close()
    var id = String(entry.id || "")
    root.remember(id)
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
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activate(root.results[root.index])
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

        // The rest, apps first, then Omarchy actions, each under a heading.
        Repeater {
          model: root.results.slice(1)
          delegate: Column {
            required property var modelData
            required property int index
            readonly property var previous: root.results[index]
            readonly property bool newSection: index === 0 || !!previous.menu !== !!modelData.menu

            Text {
              visible: parent.newSection
              leftPadding: Math.round(22 * Style.fontScale)
              topPadding: Math.round(4 * Style.fontScale)
              bottomPadding: Math.round(4 * Style.fontScale)
              textFormat: Text.PlainText
              text: parent.modelData.menu ? "Omarchy" : "Applications"
              color: Qt.rgba(1, 1, 1, 0.45)
              font.family: "Adwaita Sans"
              font.pixelSize: Math.round(12 * Style.fontScale)
              font.weight: Font.DemiBold
            }

            ResultRow {
              result: parent.modelData
              rowIndex: parent.index + 1
            }
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

    readonly property var menuItem: resultRow.result ? resultRow.result.menu : null

    Item {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: Math.round(12 * Style.fontScale)
      anchors.verticalCenter: parent.verticalCenter
      width: resultRow.big ? Math.round(40 * Style.fontScale) : Math.round(24 * Style.fontScale)
      height: width

      Image {
        visible: !resultRow.menuItem
        anchors.fill: parent
        sourceSize: Qt.size(width * 2, height * 2)
        source: resultRow.result && !resultRow.menuItem ? root.iconFor(resultRow.result.entry) : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
      }

      // Omarchy actions show their menu glyph on a small rounded tile.
      Rectangle {
        visible: !!resultRow.menuItem
        anchors.fill: parent
        radius: width * 0.24
        color: Qt.rgba(1, 1, 1, 0.12)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: resultRow.menuItem ? resultRow.menuItem.glyph : ""
          color: "#ffffff"
          font.family: resultRow.menuItem && resultRow.menuItem.iconFont ? resultRow.menuItem.iconFont : "JetBrainsMono Nerd Font"
          font.pixelSize: Math.round(parent.width * 0.55)
        }
      }
    }

    // Where an Omarchy action lives in the menu, on the right.
    Text {
      id: rowPath
      visible: !!resultRow.menuItem && text !== ""
      anchors.right: parent.right
      anchors.rightMargin: Math.round(12 * Style.fontScale)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: resultRow.menuItem ? resultRow.menuItem.path : ""
      color: resultRow.selected ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(1, 1, 1, 0.45)
      font.family: "Adwaita Sans"
      font.pixelSize: Math.round(13 * Style.fontScale)
    }

    Text {
      anchors.left: rowIcon.right
      anchors.leftMargin: Math.round(12 * Style.fontScale)
      anchors.right: rowPath.visible ? rowPath.left : parent.right
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
      onPositionChanged: function(mouse) { root.pointerAt(mapToItem(null, mouse.x, mouse.y), resultRow.rowIndex) }
      onClicked: root.activate(resultRow.result)
    }
  }
}
