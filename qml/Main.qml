import QtQuick
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

    function installed(piece) {
        return !!status.features && status.features[piece] === true
    }

    function setting(key, fallback) {
        return status.settings && typeof status.settings[key] === "number" ? status.settings[key] : fallback
    }

    function toggle(piece, on) {
        if (on) backend.addPiece(piece)
        else backend.removePiece(piece)
    }

    property string page: "general"

    readonly property var pages: [
        { id: "general", title: "General", icon: 0xF0493, tint: "#8e8e93" },
        { id: "dock", title: "Dock", icon: 0xF10A9, tint: "#0a84ff" },
        { id: "lock", title: "Lock Screen", icon: 0xF033E, tint: "#5e5ce6" },
        { id: "widgets", title: "Widgets", icon: 0xF072C, tint: "#ff9f0a" },
        { id: "menubar", title: "Menu Bar", icon: 0xF10AB, tint: "#30b0c7" },
        { id: "about", title: "About", icon: 0xF02FC, tint: "#8e8e93" }
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

                Rectangle {
                    id: badge
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#5aa9ff" }
                        GradientStop { position: 1; color: "#0a5bd8" }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xF0035)
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 22
                    }
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
        contentHeight: column.height + 48
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
                            checked: window.setting("snapping", 1) === 1
                            enabled: !backend.busy && window.installed("theme")
                            onToggled: on => backend.setSetting("snapping", on ? 1 : 0)
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

            // About.
            Group {
                visible: window.page === "about"

                SettingRow { label: "Version"; Text { text: "0.1.0"; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 13 } }
                SettingRow { label: "Theme folder"; note: backend.themeDir; last: true }
            }
        }
    }

    // A switch that installs or removes one piece of the theme.
    component PieceSwitch: MacSwitch {
        property string piece: ""
        checked: window.installed(piece)
        enabled: !backend.busy
        onToggled: on => window.toggle(piece, on)
    }

    // A slider for one install.sh setting, set when let go.
    component SettingSlider: MacSlider {
        property string key: ""
        property real fallback: 0
        property string needs: "theme"
        width: 180
        value: window.setting(key, fallback)
        enabled: !backend.busy && window.installed(needs)
        onMoved: v => backend.setSetting(key, v)

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
        signal clicked()
        width: label.width + 24
        height: 24
        radius: 6
        opacity: enabled ? 1 : 0.4
        color: press.pressed ? "#5a5a5e" : "#48484c"

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
