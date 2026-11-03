// The macOS lock screen: the date and a large clock at the top, the account
// picture, name and a glass password pill at the bottom, over the wallpaper.
// install.sh drops this over a clone of Omarchy's lock plugin (omarchy.lock),
// so locking, PAM and fingerprint stay Omarchy's own code; this file only
// draws. It keeps every property, signal and key behavior of Omarchy's
// LockView, which Service.qml relies on.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property string videoPosterPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool fingerprintUnavailable: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  readonly property real s: Style.fontScale
  readonly property string placeholderText: Commons.I18n.t("lock.enterPassword")
  readonly property int fieldWidth: Math.round(260 * s)
  readonly property int fieldHeight: Math.round(36 * s)
  readonly property int avatarSize: Math.round(76 * s)
  readonly property int fieldFontSize: Math.round(14 * s)
  readonly property int passwordDotFontSize: Math.round(12 * s)
  readonly property int passwordDotLetterSpacing: Math.round(3 * s)
  // Room on each side of the dots for the fingerprint icon or the arrow, so
  // the centered dots stay symmetric and never run under them.
  readonly property real sideReserve: Math.round(fieldHeight * 0.8)
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0

  // A video wallpaper shows its still poster: nothing plays behind the lock.
  readonly property bool video: Util.isVideoPath(root.backgroundPath)

  // Signing in, as macOS has it: the wallpaper sharp while locked, blurred
  // once the pointer is on the password field, and while there is something
  // typed, being checked or refused.
  readonly property bool signingIn: fieldHover.hovered || passwordInput.text.length > 0 || authenticatingPassword || errorState
  property real blurAmount: signingIn ? 1 : 0
  Behavior on blurAmount { enabled: !root.reduceMotion; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

  // Motion kept still: Omarchy's animations off, or the theme's Reduce
  // motion (install.sh --set reduce-motion=1), read from the look Hyprland has loaded.
  property bool lookReducesMotion: false
  readonly property bool reduceMotion: Style.reduceMotion || lookReducesMotion
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/look.lua"
    watchChanges: true
    printErrors: false
    onLoaded: root.lookReducesMotion = /^local REDUCE_MOTION = 1$/m.test(text())
    onLoadFailed: root.lookReducesMotion = false
    onFileChanged: reload()
  }

  // The keyboard: its layouts, which one is on and Caps Lock, as Hyprland
  // reports its main one ({ keymap, index, layouts, variants, caps }).
  property var keyboard: null
  readonly property var layouts: keyboard ? String(keyboard.layouts || "").split(",").filter(function(l) { return l !== "" }) : []
  readonly property bool capsLock: !!(keyboard && keyboard.caps)
  // As Omarchy's bar labels it: Arabic as AR, English (US) as EN.
  property var layoutBriefs: ({})
  readonly property string layoutLabel: keyboard ? shortLabel(keyboard.keymap, layoutBriefs) : ""

  // Locked, Hyprland runs only the bindings marked to run while locked, so
  // the user's own layout bindings are caught here: the ones Hyprland
  // describes as switching the keyboard layout or input language, or that
  // run a layout switch ([{ key, mods, back }]). Without this a password
  // could only be typed in the layout the screen locked in.
  property var layoutBindings: []

  function checkKeyboard() {
    if (keyboardCheck.running) keyboardCheck.again = true
    else keyboardCheck.running = true
  }

  // To the next layout (the one before for a "back" binding), and fcitx5
  // (Omarchy's input method) to the same one when it types plain keyboard
  // layouts, so the two can't disagree.
  function switchLayout(step) {
    if (layouts.length < 2 || layoutSwitch.running) return
    var next = (keyboard.index + step + layouts.length) % layouts.length
    var variant = String(keyboard.variants || "").split(",")[next] || ""
    layoutSwitch.command = ["sh", "-c",
      'hyprctl switchxkblayout all "$1" >/dev/null; '
      + 'command -v fcitx5-remote >/dev/null && fcitx5-remote >/dev/null 2>&1 && '
      + 'case $(fcitx5-remote -n) in keyboard-*) fcitx5-remote -s "$2" ;; esac; true',
      "sh", String(next), "keyboard-" + layouts[next] + (variant ? "-" + variant : "")]
    layoutSwitch.running = true
  }

  // A Hyprland key name as Qt reports the key: Shift_L as Shift, i as I.
  function qtKey(name) {
    var named = { space: Qt.Key_Space, Tab: Qt.Key_Tab, Caps_Lock: Qt.Key_CapsLock,
      Shift_L: Qt.Key_Shift, Shift_R: Qt.Key_Shift, Control_L: Qt.Key_Control, Control_R: Qt.Key_Control,
      Alt_L: Qt.Key_Alt, Alt_R: Qt.Key_Alt, Super_L: Qt.Key_Meta, Super_R: Qt.Key_Meta }
    name = String(name)
    if (Object.prototype.hasOwnProperty.call(named, name)) return named[name]
    return name.length === 1 ? name.toUpperCase().charCodeAt(0) : -1
  }

  // The binding a key press is, if any: its key, with exactly its Shift,
  // Ctrl, Alt and Super (Hyprland's 1, 4, 8 and 64), leaving out the one the
  // key itself is, which Qt may or may not count as held.
  // shortcut: keys named in qtKey only (letters, digits, space, Tab, modifiers); add a name when a binding uses another.
  function layoutBindingFor(key, modifiers, bindings) {
    var mods = [[1, Qt.ShiftModifier, Qt.Key_Shift], [4, Qt.ControlModifier, Qt.Key_Control],
      [8, Qt.AltModifier, Qt.Key_Alt], [64, Qt.MetaModifier, Qt.Key_Meta]]
    if (key === Qt.Key_Super_L || key === Qt.Key_Super_R) key = Qt.Key_Meta
    return (bindings || []).find(function(binding) {
      return qtKey(binding.key) === key && mods.every(function(m) {
        return m[2] === key || !!(binding.mods & m[0]) === !!(modifiers & m[1])
      })
    }) || null
  }

  // Omarchy's own labels (its bar's KeyboardLayoutModel.js): xkbcli pairs each
  // layout's description, the keymap hyprctl reports, with a short language
  // code; one it doesn't list reads as its description's first word.
  function parseBriefs(text) {
    var briefs = {}
    var brief = ""
    String(text || "").split("\n").forEach(function(line) {
      if (/^\s*- /.test(line)) brief = ""
      var field = line.match(/^  (brief|description): (.*)$/)
      if (!field) return
      if (field[1] === "brief") brief = field[2].replace(/^'|'$/g, "")
      else if (brief) { briefs[field[2]] = brief; brief = "" }
    })
    return briefs
  }
  function shortLabel(description, briefs) {
    if (!description) return ""
    var brief = Object.prototype.hasOwnProperty.call(briefs || {}, description) ? briefs[description] : ""
    return String(brief ? brief.split("-")[0] : description.split(/\s+/)[0]).substring(0, 3).toUpperCase()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { if (event.name === "activelayout") root.checkKeyboard() }
  }
  Process {
    id: keyboardCheck
    property bool again: false
    running: true
    onExited: if (again) { again = false; running = true }
    // The main keyboard, leaving out the virtual ones dictation types
    // through, as the volume panel picks it.
    command: ["sh", "-c", "hyprctl devices -j | jq -c '[.keyboards[] | select(.main)"
      + " | select((.name | test(\"^hl-virtual-keyboard-|wtype|dotool|ydotool|eitype\") | not) or (.name | test(\"fcitx|ibus\")))][0]"
      + " // empty | {keymap: .active_keymap, index: .active_layout_index, layouts: .layout, variants: .variant, caps: .capsLock}'"]
    stdout: SplitParser {
      onRead: function(line) {
        try { root.keyboard = JSON.parse(line) } catch (e) {}
      }
    }
  }
  Process {
    id: bindingsRead
    running: true
    command: ["sh", "-c", "hyprctl binds -j | jq -c '[.[] | select(.locked | not)"
      + " | select(((.description // \"\") | test(\"(keyboard|input).*(layout|language)\"; \"i\"))"
      + " or ((.arg // \"\") | test(\"switchxkblayout|kb-layout\")))"
      + " | {key, mods: .modmask, back: ((.description // \"\") | test(\"\\\\b(back|previous)\\\\b\"; \"i\"))}]'"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.layoutBindings = JSON.parse(text) } catch (e) {} }
    }
  }
  Process {
    running: true
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector { onStreamFinished: root.layoutBriefs = root.parseBriefs(text) }
  }
  Process {
    id: layoutSwitch
    onExited: root.checkKeyboard()
  }

  readonly property var formatLocale: Qt.locale(Commons.I18n.formatLocale)
  // 12- or 24-hour as the bar's clock shows it, and like macOS without AM/PM.
  // Built by hand: Qt's "h" is 24-hour unless the format also has AP.
  readonly property bool twelveHour: barClockFormat().replace(/'[^']*'/g, "").indexOf("h") !== -1

  function timeText(date) {
    var h = date.getHours()
    if (twelveHour) h = h % 12 || 12
    var text = (twelveHour ? String(h) : ("0" + h).slice(-2)) + ":" + ("0" + date.getMinutes()).slice(-2)
    return text.split("").map(function(c) { return c === ":" ? c : Commons.I18n.formatNumber(c) }).join("")
  }

  function barClockFormat() {
    var found = ""
    function walk(node) {
      if (found || !node || typeof node !== "object") return
      if (node.id === "omarchy.clock" && typeof node.format === "string") { found = node.format; return }
      for (var k in node) walk(node[k])
    }
    try { walk(JSON.parse(shellConfig.text())) } catch (e) {}
    return found || formatLocale.timeFormat(Locale.ShortFormat)
  }

  FileView {
    id: shellConfig
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    blockLoading: true
  }

  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
  property string fullName: ""
  readonly property string displayName: fullName || (userName ? userName.charAt(0).toUpperCase() + userName.slice(1) : "")
  // The account picture: ~/.face as GNOME and SDDM use it, then AccountsService's.
  readonly property var avatarSources: [
    "file://" + Quickshell.env("HOME") + "/.face",
    "file:///var/lib/AccountsService/icons/" + userName
  ]
  property int avatarTry: 0

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function submit() {
    var submitted = root.passwordText
    root.passwordTextEdited("")
    if (submitted.length > 0) root.submitPassword(submitted)
  }

  // Waking a DPMS-blanked display can stall the compositor for seconds while
  // the monitor modesets, so the wake key's release arrives late and client-side
  // key repeat floods the field with that character. A held key has no business
  // typing a password; only holding Backspace/Delete to clear stays useful.
  function dropsAutoRepeat(key) {
    return key !== Qt.Key_Backspace && key !== Qt.Key_Delete
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) {
      Qt.callLater(forcePasswordFocus)
      checkKeyboard()
    }
  }
  // A wrong password shakes the field, as on macOS.
  property int shownAttempts: 0
  onFailedAttemptsChanged: {
    if (failedAttempts > shownAttempts && !Style.reduceMotion) shake.restart()
    shownAttempts = failedAttempts
  }
  Component.onCompleted: {
    shownAttempts = failedAttempts
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // The full name from the account's GECOS field, when it has one.
  Process {
    running: root.userName.length > 0
    command: ["getent", "passwd", root.userName]
    stdout: StdioCollector {
      onStreamFinished: root.fullName = String(text.split(":")[4] || "").split(",")[0].trim()
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  TextMetrics {
    id: dotMetrics
    font.family: "Inter"
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background

    BackgroundMedia {
      id: wallpaper
      objectName: "lockWallpaper"
      anchors.fill: parent
      path: root.loadBackground ? (root.video ? root.videoPosterPath : root.backgroundPath) : ""
      version: root.backgroundVersion
      // Decode only once sized, at the lock's own size, which is what the
      // lock service keeps decoded ahead of the lock.
      cached: true
      constrainDecode: true
      decodeSize: Qt.size(width, height)

      // Blurred while signing in, and drawn a little larger so the blur's
      // soft rim stays off the screen.
      scale: 1 + 0.04 * root.blurAmount
      layer.enabled: root.blurAmount > 0
      layer.effect: MultiEffect {
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: root.blurAmount
      }
    }

    // macOS keeps the wallpaper sharp while locked; a soft shade at the top and
    // bottom keeps the clock and the field readable on a bright one.
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        // At least 0.42 behind the clock (the top quarter) and the account
        // (the bottom fifth): 3:1 for their large white text on a white wallpaper.
        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.5) }
        GradientStop { position: 0.25; color: Qt.rgba(0, 0, 0, 0.42) }
        GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.04) }
        GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.04) }
        GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.42) }
        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.5) }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // The keyboard layout, at the top right as macOS shows it on its lock
    // screen; a click goes to the next. Only with more than one.
    Rectangle {
      id: layoutBadge
      visible: root.layouts.length > 1
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Math.round(18 * root.s)
      height: Math.round(26 * root.s)
      width: Math.max(height, layoutText.implicitWidth + Math.round(18 * root.s))
      radius: Math.round(7 * root.s)
      color: Qt.rgba(0, 0, 0, badgeMouse.pressed ? 0.6 : badgeMouse.containsMouse ? 0.5 : 0.38)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.28)

      Text {
        id: layoutText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.layoutLabel
        color: "white"
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(12 * root.s)
      }

      MouseArea {
        id: badgeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.switchLayout(1); root.forcePasswordFocus() }
        Accessible.role: Accessible.Button
        Accessible.name: "Keyboard: " + (root.keyboard ? root.keyboard.keymap : "") + ". Switch to the next layout"
        Accessible.onPressAction: root.switchLayout(1)
      }
    }

    // The date over a large clock.
    Column {
      id: clockBlock
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round(parent.height * 0.07)
      spacing: Math.round(-parent.height * 0.012)

      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.6)
        shadowBlur: 0.8
        shadowVerticalOffset: 2
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.formatLocale.toString(clock.date, "dddd, MMMM d")
        color: Qt.rgba(1, 1, 1, 0.9)
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: Math.max(14, Math.round(root.height * 0.024))
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.timeText(clock.date)
        color: Qt.rgba(1, 1, 1, 0.92)
        font.family: "Inter Display"
        font.weight: Font.DemiBold
        font.pixelSize: Math.max(48, Math.round(root.height * 0.15))
      }
    }

    // The account picture, the name and the password field.
    Column {
      id: account
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.round(parent.height * 0.09)
      spacing: Math.round(10 * root.s)

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.avatarSize
        height: root.avatarSize

        Rectangle {
          id: avatarMask
          anchors.fill: parent
          radius: width / 2
          visible: false
          layer.enabled: true
        }

        Image {
          id: avatar
          anchors.fill: parent
          source: root.avatarSources[root.avatarTry] || ""
          sourceSize: Qt.size(root.avatarSize * 2, root.avatarSize * 2)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          smooth: true
          visible: false
          onStatusChanged: if (status === Image.Error && root.avatarTry < root.avatarSources.length) root.avatarTry++
        }

        MultiEffect {
          anchors.fill: parent
          source: avatar
          visible: avatar.status === Image.Ready
          maskEnabled: true
          maskSource: avatarMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1
        }

        // No picture: macOS's gray disc with the initial.
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          visible: avatar.status !== Image.Ready
          gradient: Gradient {
            GradientStop { position: 0; color: "#a1a1a6" }
            GradientStop { position: 1; color: "#6e6e73" }
          }

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.displayName.charAt(0).toUpperCase()
            color: "white"
            font.family: "Inter"
            font.weight: Font.Medium
            font.pixelSize: Math.round(parent.height * 0.45)
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.displayName
        color: "white"
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(15 * root.s)
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Qt.rgba(0, 0, 0, 0.4)
          shadowBlur: 0.6
        }
      }

      // The glass pill; it shakes after a wrong password.
      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.fieldWidth
        height: root.fieldHeight

        Rectangle {
          id: inputField
          width: parent.width
          height: parent.height
          radius: height / 2
          // Dark glass, so the white text and dots read on a white wallpaper too.
          color: Qt.rgba(0, 0, 0, passwordInput.activeFocus ? 0.62 : 0.55)
          border.width: 1
          border.color: root.errorState ? Commons.Color.lock.textError : Qt.rgba(1, 1, 1, 0.28)
          clip: true

          transform: Translate { id: shakeShift }
          HoverHandler { id: fieldHover }

          SequentialAnimation {
            id: shake
            NumberAnimation { target: shakeShift; property: "x"; to: -14 * root.s; duration: 50; easing.type: Easing.OutQuad }
            NumberAnimation { target: shakeShift; property: "x"; to: 12 * root.s; duration: 70 }
            NumberAnimation { target: shakeShift; property: "x"; to: -9 * root.s; duration: 60 }
            NumberAnimation { target: shakeShift; property: "x"; to: 6 * root.s; duration: 55 }
            NumberAnimation { target: shakeShift; property: "x"; to: -3 * root.s; duration: 50 }
            NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 45; easing.type: Easing.InQuad }
          }

          TextInput {
            id: passwordInput
            Accessible.name: "Password"
            Accessible.description: (root.capsLock ? "Caps Lock is on. " : "")
              + (root.fingerprintConfigured ? "Or touch the fingerprint reader" : "")
            anchors.fill: parent
            anchors.leftMargin: root.sideReserve
            anchors.rightMargin: root.sideReserve
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            activeFocusOnPress: true
            clip: true
            enabled: root.inputEnabled && !root.authenticatingPassword
            readOnly: root.authenticatingPassword
            echoMode: TextInput.Password
            passwordCharacter: "●"
            passwordMaskDelay: 0
            color: "white"
            selectionColor: Commons.Color.lock.selection
            selectedTextColor: "white"
            font.family: "Inter"
            font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
            font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
            cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
            cursorDelegate: Rectangle {
              width: 2
              color: "white"
              visible: passwordInput.cursorVisible
            }

            onTextChanged: {
              if (!root.syncingPasswordText) root.passwordTextEdited(text)
              if (text.length > 0) {
                root.wakeRequested()
              }
              if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
            }

            onAccepted: root.submit()

            Keys.onPressed: function(event) {
              root.wakeRequested()
              if (event.isAutoRepeat && root.dropsAutoRepeat(event.key)) {
                event.accepted = true
                return
              }
              var binding = root.layoutBindingFor(event.key, event.modifiers, root.layoutBindings)
              if (binding) {
                root.switchLayout(binding.back ? -1 : 1)
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                root.passwordTextEdited("")
                event.accepted = true
              }
            }
            // Caps Lock is a key of its own, or both Shifts with
            // shift:both_capslock_cancel: looked at again once they're let go.
            Keys.onReleased: function(event) {
              if (event.key === Qt.Key_CapsLock || event.key === Qt.Key_Shift) root.checkKeyboard()
            }
          }

          // Caps Lock on, marked in the field as macOS does.
          Text {
            objectName: "capsLockIndicator"
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: Math.round(parent.height * 0.3)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.capsLock
            text: "⇪"
            color: Qt.rgba(1, 1, 1, 0.8)
            font.family: "Inter"
            font.pixelSize: Math.round(root.fieldFontSize * 1.15)
          }

          Text {
            textFormat: Text.PlainText
            anchors.fill: passwordInput
            text: root.authenticatingPassword ? Commons.I18n.t("lock.checking") : root.placeholderText
            visible: passwordInput.text.length === 0
            color: Qt.rgba(1, 1, 1, root.authenticatingPassword ? 0.9 : 0.8)
            font.family: "Inter"
            font.pixelSize: root.fieldFontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          // The arrow that submits, shown once something is typed.
          Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: Math.round(parent.height * 0.14)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(parent.height * 0.68)
            height: width
            radius: width / 2
            visible: passwordInput.text.length > 0 && !root.authenticatingPassword
            color: "transparent"
            border.width: Math.max(1, Math.round(1.5 * root.s))
            border.color: Qt.rgba(1, 1, 1, 0.75)

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "→"
              color: Qt.rgba(1, 1, 1, 0.9)
              font.family: "Inter"
              font.weight: Font.DemiBold
              font.pixelSize: Math.round(parent.height * 0.6)
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.submit()
              Accessible.role: Accessible.Button
              Accessible.name: "Unlock"
              Accessible.onPressAction: root.submit()
            }
          }

          // Fingerprint hint while the field is empty, so the user knows they
          // can touch to unlock. A reader the shell cannot reach crosses out
          // rather than disappears, so it stops inviting touches.
          Text {
            id: fingerprintIcon
            objectName: "fingerprintIndicator"
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: Math.round(parent.height * 0.3)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.fingerprintConfigured && passwordInput.text.length === 0
            text: root.fingerprintUnavailable ? "󰺱" : "󰈷"
            color: root.fingerprintUnavailable ? Commons.Color.lock.textError : Qt.rgba(1, 1, 1, 0.7)
            font.family: Style.font.family
            font.pixelSize: Math.round(root.fieldFontSize * 1.15)
          }
        }
      }

      // Below the field: why the last try failed, or that the reader is gone.
      Text {
        objectName: "fingerprintUnavailableNotice"
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        visible: root.errorState || (root.fingerprintConfigured && root.fingerprintUnavailable)
        text: root.errorState ? root.failureMessage : Commons.I18n.t("lock.fingerprintUnavailable")
        color: "white"
        opacity: 0.85
        font.family: "Inter"
        font.pixelSize: Math.round(13 * root.s)
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Qt.rgba(0, 0, 0, 0.5)
          shadowBlur: 0.6
        }
      }
    }
  }
}
