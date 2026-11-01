import QtCore
import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Window
import org.omarchy.macossettings

// macOS Theme Settings, shaped like macOS System Settings: a sidebar of
// sections with colored icons, and grouped rows of switches and sliders.
Window {
    id: window

    width: 860
    height: 600
    minimumWidth: 700
    minimumHeight: 460
    visible: true
    title: "macOS Theme"
    color: "#1e1e1e"

    ThemeBackend {
        id: backend
        Component.onCompleted: refresh()
    }

    readonly property var status: {
        try { return JSON.parse(backend.statusJson) } catch (e) { return {} }
    }

    readonly property var backups: {
        try { return JSON.parse(backend.backupsJson) } catch (e) { return [] }
    }

    // "1 Nov 2026, 14:07" from an ISO date.
    function when(iso) {
        return Qt.formatDateTime(new Date(iso), "d MMM yyyy, hh:mm")
    }

    function localPath(url) {
        return decodeURIComponent(url.toString().replace(/^file:\/\//, ""))
    }

    // A question before something that changes the setup: { title, text, button, action }.
    property var confirm: null

    function installed(piece) {
        return !!status.features && status.features[piece] === true
    }

    function setting(key, fallback) {
        return status.settings && typeof status.settings[key] === "number" ? status.settings[key] : fallback
    }

    // Changes wait here until Apply sends them to install.sh in one call, so
    // the theme reloads once however many there are.
    property var pendingPieces: ({})
    property var pendingSettings: ({})
    readonly property int pendingCount: Object.keys(pendingPieces).length + Object.keys(pendingSettings).length
    property bool applying: false

    function pieceOn(piece) {
        return piece in pendingPieces ? pendingPieces[piece] : installed(piece)
    }

    function settingValue(key, fallback) {
        return key in pendingSettings ? pendingSettings[key] : setting(key, fallback)
    }

    // Marking a piece back to what is installed takes the change away again.
    function markPiece(piece, on) {
        const next = Object.assign({}, pendingPieces)
        if (on === installed(piece)) delete next[piece]
        else next[piece] = on
        pendingPieces = next
    }

    function markSetting(key, value, fallback) {
        const next = Object.assign({}, pendingSettings)
        if (Math.abs(value - setting(key, fallback)) < 0.005) delete next[key]
        else next[key] = value
        pendingSettings = next
    }

    function revert() {
        pendingPieces = {}
        pendingSettings = {}
    }

    function apply() {
        const changes = { add: [], remove: [], set: pendingSettings }
        for (const piece in pendingPieces) (pendingPieces[piece] ? changes.add : changes.remove).push(piece)
        applying = true
        backend.apply(JSON.stringify(changes))
    }

    // Done: the switches show what is installed now. On an error the changes
    // stay marked, to fix and apply again.
    Connections {
        target: backend
        function onBusyChanged() {
            if (backend.busy || !window.applying) return
            window.applying = false
            if (backend.error === "") window.revert()
        }
    }

    // The page shown first: --page <id> opens another, such as --page backups.
    property string page: {
        const args = Qt.application.arguments
        const asked = args[args.indexOf("--page") + 1]
        return args.indexOf("--page") >= 0 && pages.some(p => p.id === asked) ? asked : "overview"
    }

    readonly property var pages: [
        { id: "overview", title: "Overview", icon: 0xF02FC, tint: "#0a84ff" },
        { id: "general", title: "General", icon: 0xF0493, tint: "#8e8e93" },
        { id: "dock", title: "Dock", icon: 0xF10A9, tint: "#0a84ff" },
        { id: "lock", title: "Lock Screen", icon: 0xF033E, tint: "#5e5ce6" },
        { id: "widgets", title: "Widgets", icon: 0xF072C, tint: "#ff9f0a" },
        { id: "menubar", title: "Menu Bar", icon: 0xF10AB, tint: "#30b0c7" },
        { id: "backups", title: "Backups", icon: 0xF006F, tint: "#34c759" }
    ]

    // Sidebar.
    Rectangle {
        id: sidebar
        width: 230
        height: parent.height
        color: "#262628"

        Column {
            anchors.fill: parent
            anchors.margins: 10
            anchors.topMargin: 16
            spacing: 2

            // The theme, as macOS puts the account at the top.
            Item {
                width: parent.width
                height: 58

                AppIcon {
                    id: badge
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    size: 40
                }

                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "macOS Theme"
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: !backend.downloaded ? "Not downloaded"
                            : window.status.active ? "Current theme" : "Installed, not current"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 11
                    }
                }
            }

            Item { width: 1; height: 8 }

            Repeater {
                model: window.pages

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: window.page === modelData.id

                    width: parent.width
                    height: 30
                    radius: 6
                    color: selected ? "#0a84ff" : hover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                    HoverHandler { id: hover }

                    Rectangle {
                        id: icon
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: 5
                        color: modelData.tint

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(modelData.icon)
                            color: "white"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }
                    }

                    Text {
                        anchors.left: icon.right
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        color: "white"
                        font.pixelSize: 13
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: window.page = modelData.id
                    }
                }
            }
        }
    }

    // Content.
    Flickable {
        id: content
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        contentHeight: column.height + 48 + (applyBar.visible ? applyBar.height : 0)
        clip: true

        Column {
            id: column
            x: 28
            y: 20
            width: content.width - 56
            spacing: 18

            Item {
                width: parent.width
                height: pageTitle.height

                Text {
                    id: pageTitle
                    text: window.pages.find(p => p.id === window.page).title
                    color: "white"
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: backend.busy
                    text: "Working…"
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 12
                }
            }

            // Why the last action failed, in install.sh's own words.
            Rectangle {
                visible: backend.error !== ""
                width: parent.width
                height: errorText.height + 20
                radius: 8
                color: Qt.rgba(1, 0.27, 0.23, 0.15)
                border.width: 1
                border.color: Qt.rgba(1, 0.27, 0.23, 0.4)

                Text {
                    id: errorText
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24
                    text: backend.error
                    color: "#ff6961"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            // Not downloaded yet: one button to fetch it.
            Group {
                visible: !backend.downloaded

                SettingRow {
                    label: "Download the macOS theme"
                    note: "From GitHub into " + backend.themeDir
                    last: true

                    MacButton {
                        text: "Download"
                        enabled: !backend.busy
                        onClicked: backend.download()
                    }
                }
            }

            // General.
            Column {
                visible: backend.downloaded && window.page === "general"
                width: parent.width
                spacing: 18

                Group {
                    title: "Theme"

                    SettingRow {
                        label: "macOS theme"
                        note: "Colors, glass, title bars, gaps, motion and wallpapers"
                        PieceSwitch { piece: "theme" }
                    }
                    SettingRow {
                        label: "Window glass"
                        note: "How solid windows are; 1 is solid"
                        SettingSlider { key: "glass"; from: 0.5; to: 1; fallback: 0.7 }
                    }
                    SettingRow {
                        label: "Browser and app glass"
                        note: "Browsers, web apps and Electron apps"
                        SettingSlider { key: "web-glass"; from: 0.5; to: 1; fallback: 1 }
                    }
                    SettingRow {
                        label: "Snap windows to halves and corners"
                        last: true
                        MacSwitch {
                            checked: window.settingValue("snapping", 1) === 1
                            enabled: !backend.busy && window.pieceOn("theme")
                            onToggled: on => window.markSetting("snapping", on ? 1 : 0, 1)
                        }
                    }
                }

                Group {
                    title: "More"

                    SettingRow { label: "MacTahoe icons"; PieceSwitch { piece: "icons" } }
                    SettingRow { label: "Striped rows in Files"; PieceSwitch { piece: "rows" } }
                    SettingRow { label: "App and workspace switchers"; note: "Alt+Tab and Super+Tab"; PieceSwitch { piece: "switcher" } }
                    SettingRow { label: "Spotlight-like menu"; PieceSwitch { piece: "wide-menu" } }
                    SettingRow { label: "Volume and brightness capsule"; PieceSwitch { piece: "osd" } }
                    SettingRow { label: "Dictation pill"; note: "For Voxtype"; last: true; PieceSwitch { piece: "dictation-hud" } }
                }
            }

            // Dock.
            Group {
                visible: backend.downloaded && window.page === "dock"

                SettingRow {
                    label: "macOS dock"
                    note: "Magnification, window previews, Downloads and Trash"
                    PieceSwitch { piece: "dock" }
                }
                SettingRow {
                    label: "Magnification"
                    note: "How far icons grow under the pointer; 1 is off"
                    last: true
                    SettingSlider { key: "magnification"; from: 1; to: 2; fallback: 1.75; needs: "dock" }
                }
            }

            // Lock screen.
            Group {
                visible: backend.downloaded && window.page === "lock"

                SettingRow {
                    label: "macOS lock screen"
                    note: "Date, large clock, account picture and a glass password field"
                    PieceSwitch { piece: "lock" }
                }
                SettingRow {
                    label: "Preview"
                    note: "See it without locking; click to close"
                    last: true
                    MacButton {
                        text: "Show"
                        enabled: window.installed("lock")
                        onClicked: backend.previewLock()
                    }
                }
            }

            // Widgets.
            Group {
                visible: backend.downloaded && window.page === "widgets"

                SettingRow {
                    label: "Desktop widgets"
                    note: "Clock, calendar, weather and now playing. Drag to move; right-click to remove or add."
                    last: true
                    PieceSwitch { piece: "widgets" }
                }
            }

            // Menu bar.
            Group {
                visible: backend.downloaded && window.page === "menubar"

                SettingRow {
                    label: "macOS menu bar"
                    note: "Inter, the app name in bold, and Control Center"
                    last: true
                    PieceSwitch { piece: "menubar" }
                }
            }

            // Backups.
            Column {
                visible: backend.downloaded && window.page === "backups"
                width: parent.width
                spacing: 18

                Group {
                    title: "This Computer"

                    SettingRow {
                        label: "Back up now"
                        note: "A backup is also taken by itself before every change. The last 10 are kept, and the first one for good."
                        last: true
                        MacButton {
                            text: "Back Up Now"
                            enabled: !backend.busy
                            onClicked: backend.backUp()
                        }
                    }
                }

                Group {
                    title: "Backups"
                    visible: window.backups.length > 0

                    Repeater {
                        model: window.backups

                        delegate: SettingRow {
                            required property var modelData
                            required property int index
                            label: modelData.original ? "Before macOS theme" : modelData.note
                            note: window.when(modelData.created) + (modelData.pinned ? "  ·  Kept" : "")
                            last: index === window.backups.length - 1

                            MacButton {
                                text: "Restore"
                                enabled: !backend.busy
                                onClicked: window.confirm = {
                                    title: "Restore the backup from " + window.when(modelData.created) + "?",
                                    text: "Your theme goes back to how it was then. Your setup now is backed up first, so you can undo this.",
                                    button: "Restore",
                                    action: () => { window.revert(); backend.restore(modelData.id) }
                                }
                            }
                        }
                    }
                }

                Group {
                    title: "Another Computer"

                    SettingRow {
                        label: "Export"
                        note: "Saves your choices to one file: the pieces you use, your settings, your dock and widgets, and wallpapers you added. Import it on another computer or a new install."
                        MacButton {
                            text: "Export…"
                            enabled: !backend.busy && window.installed("theme")
                            onClicked: exportDialog.open()
                        }
                    }
                    SettingRow {
                        label: "Import"
                        note: "Sets this computer up from an export. Your setup now is backed up first."
                        last: true
                        MacButton {
                            text: "Import…"
                            enabled: !backend.busy
                            onClicked: importDialog.open()
                        }
                    }
                }
            }

            // Overview, as About This Mac: who made it, for what, and that it is
            // safe to use.
            Column {
                visible: window.page === "overview"
                width: parent.width
                spacing: 6
                topPadding: 16

                AppIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: 96
                }

                Item { width: 1; height: 8 }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "macOS Theme"
                    color: "white"
                    font.pixelSize: 26
                    font.weight: Font.Bold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Version " + backend.appVersion
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 13
                }

                Item { width: 1; height: 18 }

                // The theme on a desktop, from the theme's own folder, so it
                // shows the version installed; hidden until it is downloaded.
                // Always a 16:10 frame filled from the middle of the shot, so a
                // wide screenshot is cropped, never squeezed.
                Item {
                    id: preview
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 560)
                    // No room is kept until it has loaded, as before it is downloaded.
                    height: shot.status === Image.Ready ? Math.round(width * 10 / 16) : 0
                    visible: height > 0

                    // The shadow, drawn on its own behind the frame: an effect
                    // that both rounds and shadows pads itself and stretches
                    // the picture into the padding.
                    RectangularShadow {
                        anchors.fill: parent
                        radius: 12
                        offset.y: 6
                        blur: 24
                        color: Qt.rgba(0, 0, 0, 0.5)
                    }

                    // Decoded at the screen's real pixel size, so it is drawn
                    // one to one and stays sharp.
                    Image {
                        id: shot
                        anchors.fill: parent
                        source: backend.downloaded ? "file://" + backend.themeDir + "/docs/screenshots/desktop.jpg" : ""
                        sourceSize: Qt.size(Math.round(preview.width * Screen.devicePixelRatio), Math.round(preview.width * 10 / 16 * Screen.devicePixelRatio))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        visible: false
                    }

                    Rectangle {
                        id: shotMask
                        anchors.fill: parent
                        radius: 12
                        visible: false
                        layer.enabled: true
                        layer.textureSize: Qt.size(Math.round(width * Screen.devicePixelRatio), Math.round(height * Screen.devicePixelRatio))
                    }

                    // Only the rounded corners: no padding, so the picture
                    // stays exactly inside its frame.
                    MultiEffect {
                        anchors.fill: parent
                        source: shot
                        autoPaddingEnabled: false
                        maskEnabled: true
                        maskSource: shotMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                    }
                }

                Item { width: 1; height: preview.visible ? 22 : 0 }

                // The facts, labels right-aligned against their values, as macOS lists them.
                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 8

                    Fact { text: "Made for" }
                    Row {
                        spacing: 8
                        height: 18

                        Image {
                            id: omarchyLogo
                            visible: false
                            source: backend.omarchyLogo
                            sourceSize.height: 36
                            height: 14
                            fillMode: Image.PreserveAspectFit
                        }
                        // Omarchy draws its logo black; white here, on the dark window.
                        MultiEffect {
                            anchors.verticalCenter: parent.verticalCenter
                            width: omarchyLogo.paintedWidth
                            height: omarchyLogo.height
                            source: omarchyLogo
                            visible: omarchyLogo.status === Image.Ready
                            brightness: 1
                        }
                        Value {
                            text: omarchyLogo.status === Image.Ready ? backend.omarchyVersion : "Omarchy " + backend.omarchyVersion
                        }
                    }

                    Fact { text: "Theme" }
                    Value {
                        text: !backend.downloaded ? "Not downloaded yet"
                            : (window.status.active ? "In use" : "Installed, not in use")
                              + (backend.themeVersion ? "  ·  " + backend.themeVersion : "")
                    }

                    Fact { text: "License" }
                    Value { text: "Open source, MIT" }
                }

                Item { width: 1; height: 22 }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 440)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Every change is made by the theme's own installer, after a backup you can restore."
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 13
                    lineHeight: 1.2
                }

                Item { width: 1; height: 14 }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    MacButton { text: "Theme on GitHub"; onClicked: Qt.openUrlExternally("https://github.com/tsubaie/omarchy-macos-theme") }
                    MacButton { text: "App on GitHub"; onClicked: Qt.openUrlExternally("https://github.com/tsubaie/omarchy-macos-settings") }
                }

                Item { width: 1; height: 28 }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Not affiliated with Apple or Omarchy. macOS is a trademark of Apple Inc."
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.pixelSize: 11
                }
            }
        }
    }

    FileDialog {
        id: exportDialog
        title: "Export Your macOS Theme Setup"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "tar.gz"
        nameFilters: ["macOS theme export (*.tar.gz)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        selectedFile: currentFolder + "/macos-theme-" + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".tar.gz"
        onAccepted: backend.exportTo(window.localPath(selectedFile))
    }

    FileDialog {
        id: importDialog
        title: "Import a macOS Theme Setup"
        fileMode: FileDialog.OpenFile
        nameFilters: ["macOS theme export (*.tar.gz)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: {
            const file = window.localPath(selectedFile)
            window.confirm = {
                title: "Import " + file.split("/").pop() + "?",
                text: "Your theme is set up to match it: its pieces, settings, dock, widgets and wallpapers. Your setup now is backed up first, so you can undo this.",
                button: "Import",
                action: () => { window.revert(); backend.importFrom(file) }
            }
        }
    }

    // The question sheet, over a dimmed window, as macOS asks.
    Rectangle {
        anchors.fill: parent
        visible: window.confirm !== null
        color: Qt.rgba(0, 0, 0, 0.45)
        z: 10

        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: 380
            height: sheet.height + 40
            radius: 12
            color: "#2c2c2e"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            Column {
                id: sheet
                x: 20
                y: 20
                width: parent.width - 40
                spacing: 10

                Text {
                    width: parent.width
                    text: window.confirm ? window.confirm.title : ""
                    color: "white"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: window.confirm ? window.confirm.text : ""
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Item { width: 1; height: 6 }
                Row {
                    anchors.right: parent.right
                    spacing: 10
                    MacButton { text: "Cancel"; onClicked: window.confirm = null }
                    MacButton {
                        text: window.confirm ? window.confirm.button : ""
                        primary: true
                        onClicked: {
                            const action = window.confirm.action
                            window.confirm = null
                            action()
                        }
                    }
                }
            }
        }
    }

    // The bar under the content while changes wait: how many, Revert and Apply.
    Rectangle {
        id: applyBar
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 52
        visible: window.pendingCount > 0 || window.applying
        color: "#2a2a2c"

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

        Text {
            x: 28
            anchors.verticalCenter: parent.verticalCenter
            text: window.applying ? "Applying…"
                : window.pendingCount === 1 ? "1 change" : window.pendingCount + " changes"
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: 13
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            MacButton {
                text: "Revert"
                enabled: !backend.busy
                onClicked: window.revert()
            }
            MacButton {
                text: "Apply"
                primary: true
                enabled: !backend.busy
                onClicked: window.apply()
            }
        }
    }

    // The app's icon: Omarchy's square frame, redrawn as a macOS app icon.
    component AppIcon: Image {
        property int size: 40
        width: size
        height: size
        source: "qrc:/qt/qml/org/omarchy/macossettings/assets/icon.svg"
        sourceSize: Qt.size(size * 2, size * 2)
        smooth: true
        mipmap: true
    }

    // A label in the Overview's facts, right-aligned.
    component Fact: Text {
        width: 90
        horizontalAlignment: Text.AlignRight
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 13
    }

    component Value: Text {
        color: "white"
        font.pixelSize: 13
    }

    // A switch that marks one piece of the theme to install or remove.
    component PieceSwitch: MacSwitch {
        property string piece: ""
        checked: window.pieceOn(piece)
        enabled: !backend.busy
        onToggled: on => window.markPiece(piece, on)
    }

    // A slider for one install.sh setting, set when let go.
    component SettingSlider: MacSlider {
        property string key: ""
        property real fallback: 0
        property string needs: "theme"
        width: 180
        value: window.settingValue(key, fallback)
        enabled: !backend.busy && window.pieceOn(needs)
        onMoved: v => window.markSetting(key, v, fallback)

        Text {
            anchors.right: parent.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: parent.shown.toFixed(2)
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 12
        }
    }

    // The macOS push button: gray, rounded, white text.
    component MacButton: Rectangle {
        property string text: ""
        property bool enabled: true
        property bool primary: false
        signal clicked()
        width: label.width + 24
        height: 24
        radius: 6
        opacity: enabled ? 1 : 0.4
        color: primary ? (press.pressed ? "#0a6fdc" : "#0a84ff") : (press.pressed ? "#5a5a5e" : "#48484c")

        Text {
            id: label
            anchors.centerIn: parent
            text: parent.text
            color: "white"
            font.pixelSize: 13
        }

        MouseArea {
            id: press
            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
