// The macOS lock screen: the date and a large clock at the top, the account
// picture, name and a glass password pill at the bottom, over the wallpaper.
// install.sh drops this over a clone of Omarchy's lock plugin (omarchy.lock),
// so locking, PAM and fingerprint stay Omarchy's own code; this file only
// draws. It keeps every property, signal and key behavior of Omarchy's
// LockView, which Service.qml relies on.
import QtQuick
import QtQuick.Effects
import Quickshell
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
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
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
    }

    // macOS keeps the wallpaper sharp; a soft shade at the top and bottom keeps
    // the clock and the field readable on a bright one.
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.28) }
        GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.04) }
        GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.04) }
        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.32) }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
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
        shadowColor: Qt.rgba(0, 0, 0, 0.35)
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
          color: Qt.rgba(1, 1, 1, passwordInput.activeFocus ? 0.22 : 0.16)
          border.width: 1
          border.color: root.errorState ? Commons.Color.lock.textError : Qt.rgba(1, 1, 1, 0.28)
          clip: true

          transform: Translate { id: shakeShift }

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
              if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                root.passwordTextEdited("")
                event.accepted = true
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.fill: passwordInput
            text: root.authenticatingPassword ? Commons.I18n.t("lock.checking") : root.placeholderText
            visible: passwordInput.text.length === 0
            color: Qt.rgba(1, 1, 1, root.authenticatingPassword ? 0.9 : 0.6)
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
