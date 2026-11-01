import QtCore
import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Window
import org.omarchy.macosstudio

// macOS Theme Studio, shaped like macOS System Settings: a sidebar of
// sections with colored icons, and grouped rows of switches and sliders.
Window {
    id: window

    width: 860
    height: 600
    minimumWidth: 700
    minimumHeight: 460
    visible: true
    title: window.pages.find(p => p.id === window.page).title
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

    // The page shown first: --page <id> when given, else the last one viewed
    // (HIG, Settings: "Restore the most recently viewed pane").
    property string page: {
        const args = Qt.application.arguments
        const asked = args.indexOf("--page") >= 0 ? args[args.indexOf("--page") + 1] : prefs.lastPage
        return pages.some(p => p.id === asked) ? asked : "overview"
    }
    // Written at once, so it survives the app being killed rather than closed.
    onPageChanged: { prefs.lastPage = page; prefs.sync() }

    Settings {
        id: prefs
        property string lastPage: "overview"
    }

    // Search, as in System Settings: it filters the sidebar as people type and
    // also finds the settings inside each page, by the words on its rows.
    property string query: ""
    readonly property var results: pages.filter(p => {
        const words = query.toLowerCase().split(/\s+/).filter(w => w)
        const text = (p.title + " " + p.keywords).toLowerCase()
        return words.every(w => text.indexOf(w) >= 0)
    })
    // What the sidebar lists: every page but the overview, which the theme
    // card at the top opens, as the account card does in System Settings;
    // while searching, the results, the overview among them.
    readonly property var listed: query === "" ? pages.filter(p => p.id !== "overview") : results
    // The result ↑ and ↓ move to while searching; Return opens it.
    property int resultIndex: 0
    onQueryChanged: resultIndex = 0

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: searchField.focusField()
    }

    // Sections group the sidebar as System Settings does; keywords are the
    // words on each page's rows, which search also finds.
    readonly property var pages: [
        { id: "overview", title: "About", icon: "about", section: 0,
          keywords: "about version license open source github omarchy" },
        { id: "general", title: "General", icon: "general", section: 1,
          keywords: "theme colors title bars gaps motion wallpapers mactahoe icons striped rows files app workspace switchers alt tab spotlight menu volume brightness capsule osd dictation pill voxtype" },
        { id: "windows", title: "Windows", icon: "windows", section: 1,
          keywords: "window glass translucent transparent see-through opacity solid blur frosted browser apps electron chrome vs code web snap snapping halves corners" },
        { id: "dock", title: "Dock", icon: "dock", section: 1,
          keywords: "dock magnification window previews downloads trash" },
        { id: "lock", title: "Lock Screen", icon: "lock", section: 1,
          keywords: "lock screen password clock account picture preview" },
        { id: "widgets", title: "Widgets", icon: "widgets", section: 1,
          keywords: "desktop widgets clock calendar weather now playing music" },
        { id: "menubar", title: "Menu Bar", icon: "menubar", section: 1,
          keywords: "menu bar inter font app name control center" },
        { id: "backups", title: "Backups", icon: "backups", section: 2,
          keywords: "backup back up restore undo export import another computer snapshot" }
    ]

    // The sidebar: the window's full height, edge to edge, a shade darker than
    // the content with a hairline between them, as Files and Finder draw it;
    // search at the top (HIG, Search fields: "Include search at the top of the
    // sidebar when filtering… navigation there").
    Rectangle {
        id: sidebar
        width: 232
        height: parent.height
        color: "#181818"

        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            anchors.topMargin: 0
            spacing: 2

            // The window controls, where macOS puts them, on a strip people
            // drag the window by, as they would a title bar.
            Item {
                width: parent.width
                height: 52

                MouseArea {
                    anchors.fill: parent
                    onPressed: window.startSystemMove()
                    onDoubleClicked: backend.zoomWindow()
                }

                TrafficLights {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    active: window.active
                    onClose: window.close()
                    onMinimize: if (!backend.minimizeWindow()) window.showMinimized()
                    onZoom: backend.zoomWindow()
                }
            }

            SearchField {
                id: searchField
                width: parent.width
                onTextChanged: window.query = text
                onMove: step => {
                    if (window.results.length > 0)
                        window.resultIndex = Math.max(0, Math.min(window.results.length - 1, window.resultIndex + step))
                }
                onAccepted: if (window.results.length > 0) window.open(window.results[window.resultIndex].id)
            }

            Item { width: 1; height: 8 }

            // The theme, as macOS puts the account at the top; it opens the
            // overview, as the account card opens its pane.
            Rectangle {
                width: parent.width
                height: 52
                visible: window.query === ""
                radius: 8
                color: window.page === "overview" ? Qt.rgba(1, 1, 1, 0.12) : cardHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                Accessible.role: Accessible.PageTab
                Accessible.name: "About macOS Theme"
                Accessible.selected: window.page === "overview"
                Accessible.onPressAction: window.open("overview")

                HoverHandler { id: cardHover }

                MouseArea {
                    anchors.fill: parent
                    onClicked: window.open("overview")
                }

                AppIcon {
                    id: badge
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    size: 36
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
                            : backend.updates > 0 ? "Update available"
                            : window.status.active ? "Current theme" : "Installed, not current"
                        color: backend.updates > 0 ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: 11
                    }
                }
            }

            Item { width: 1; height: window.query === "" ? 6 : 0 }

            Repeater {
                model: window.listed

                delegate: Column {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool selected: window.query === "" ? window.page === modelData.id : index === window.resultIndex
                    // A little room where a new section starts, as in System Settings.
                    // A gray heading where a section starts, as in Finder.
                    readonly property bool newSection: window.query === "" && (index === 0 || window.listed[index - 1].section !== modelData.section)
                    width: parent.width

                    Text {
                        visible: entry.newSection
                        x: 8
                        topPadding: entry.index === 0 ? 2 : 12
                        bottomPadding: 4
                        text: ["", "Theme", "Data"][entry.modelData.section]
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 6
                        color: entry.selected ? Qt.rgba(1, 1, 1, 0.12) : hover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                        Accessible.role: Accessible.PageTab
                        Accessible.name: entry.modelData.title
                        Accessible.selected: entry.selected
                        Accessible.onPressAction: window.open(entry.modelData.id)

                        HoverHandler { id: hover }

                        // A gray line symbol with no tile, as macOS draws sidebars
                        // in the graphite accent: a step dimmer than the label,
                        // full white on the selected row.
                        Glyph {
                            id: icon
                            x: 6
                            anchors.verticalCenter: parent.verticalCenter
                            name: entry.modelData.icon
                            size: 20
                            opacity: entry.selected ? 1 : 0.6
                        }

                        Text {
                            anchors.left: icon.right
                            anchors.leftMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.title
                            color: "white"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: window.open(entry.modelData.id)
                        }
                    }
                }
            }

            Text {
                visible: window.query !== "" && window.results.length === 0
                width: parent.width
                topPadding: 24
                horizontalAlignment: Text.AlignHCenter
                text: "No Results"
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 13
            }
        }
    }

    // Opens a page; from a search, the search is done.
    function open(id) {
        window.page = id
        window.query = ""
        searchField.clear()
    }

    // The toolbar, as macOS draws it: the page's title level with the traffic
    // lights, and on the right what is waiting with Revert and Apply. It is
    // also where the window is dragged; a double click zooms.
    Item {
        id: topBar
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        height: 52

        MouseArea {
            anchors.fill: parent
            onPressed: window.startSystemMove()
            onDoubleClicked: backend.zoomWindow()
        }

        Text {
            x: 28
            anchors.verticalCenter: parent.verticalCenter
            text: window.pages.find(p => p.id === window.page).title
            color: "white"
            // Title 3, emphasized: what macOS uses for a pane's title.
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: backend.busy || window.pendingCount > 0
                text: window.applying ? "Applying…" : backend.busy ? "Working…"
                    : window.pendingCount === 1 ? "1 change" : window.pendingCount + " changes"
                color: Qt.rgba(1, 1, 1, 0.6)
                font.pixelSize: 13
                rightPadding: 4
            }
            MacButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: window.pendingCount > 0 || window.applying
                text: "Revert"
                enabled: !backend.busy
                onClicked: window.revert()
            }
            MacButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: window.pendingCount > 0 || window.applying
                text: "Apply"
                primary: true
                enabled: !backend.busy
                onClicked: window.apply()
            }
        }
    }

    // Content.
    Flickable {
        id: content
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        contentHeight: column.height + 48
        clip: true

        Column {
            id: column
            x: 28
            y: 4
            width: content.width - 56
            spacing: 18

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
                        last: true
                        PieceSwitch { piece: "theme" }
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

            // Windows: how see-through they are, the blur behind them, snapping.
            Column {
                visible: backend.downloaded && window.page === "windows"
                width: parent.width
                spacing: 18

                Group {
                    title: "Glass"

                    SettingRow {
                        label: "Window glass"
                        note: "How see-through windows are; 1 is solid"
                        SettingSlider { key: "glass"; from: 0.5; to: 1; fallback: 0.7 }
                    }
                    SettingRow {
                        label: "Browser and Electron app glass"
                        note: "Browsers, web apps, and Electron apps such as Claude, VS Code, Slack and Discord. Solid by default, since their menus are hard to read on glass."
                        SettingSlider { key: "web-glass"; from: 0.5; to: 1; fallback: 1 }
                    }
                    SettingRow {
                        label: "Frosted blur"
                        note: "How strongly what is behind see-through windows, menus, the bar and the dock is blurred. 0 turns it off; they stay see-through."
                        last: true
                        SettingSlider { key: "blur"; from: 0; to: 20; fallback: 10; decimals: 0 }
                    }
                }

                Group {
                    title: "Arrangement"

                    SettingRow {
                        label: "Snap windows to halves and corners"
                        note: "Drag a window by its title bar to an edge or corner of the screen"
                        last: true
                        SettingSwitch { key: "snapping" }
                    }
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
                    text: "macOS Theme for Omarchy"
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
                            anchors.verticalCenter: parent.verticalCenter
                            visible: status === Image.Ready
                            source: backend.omarchyLogo
                            sourceSize.height: 36
                            height: 14
                            fillMode: Image.PreserveAspectFit
                        }
                        Value {
                            // The Omarchy versions the theme supports, not this computer's.
                            text: omarchyLogo.status === Image.Ready ? "4+" : "Omarchy 4+"
                        }
                    }

                    Fact { text: "Theme" }
                    Row {
                        spacing: 10
                        height: 18

                        Value {
                            anchors.verticalCenter: parent.verticalCenter
                            text: !backend.downloaded ? "Not downloaded yet"
                                : backend.updates > 0 ? "Update available" : "Up to date"
                            color: backend.updates > 0 ? "#0a84ff" : "white"
                        }

                        MacButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: backend.updates > 0
                            text: "Update"
                            primary: true
                            enabled: !backend.busy
                            onClicked: window.confirm = {
                                title: "Update the macOS theme?",
                                text: "The newest version is downloaded and the pieces you use are installed again, after a backup you can restore. The theme reloads once.",
                                button: "Update",
                                action: () => { window.revert(); backend.update() }
                            }
                        }
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
                    MacButton { text: "App on GitHub"; onClicked: Qt.openUrlExternally("https://github.com/tsubaie/omarchy-macos-studio") }
                }

                Item { width: 1; height: 28 }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Not affiliated with Apple or Omarchy. macOS is a trademark of Apple Inc."
                    color: Qt.rgba(1, 1, 1, 0.55)
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

    // The app's icon: Omarchy's square frame, redrawn as a macOS app icon.
    component AppIcon: Image {
        property int size: 40
        width: size
        height: size
        source: "qrc:/qt/qml/org/omarchy/macosstudio/assets/icon-omarchy.svg"
        sourceSize: Qt.size(size * 2, size * 2)
        smooth: true
        mipmap: true
    }

    // An Icons8 glyph (SF Symbols style, white) from assets/icons, drawn at
    // the screen's real pixel size so its thin strokes stay sharp.
    component Glyph: Image {
        property string name: ""
        property int size: 14
        width: size
        height: size
        source: name ? "qrc:/qt/qml/org/omarchy/macosstudio/assets/icons/" + name + ".svg" : ""
        sourceSize: Qt.size(size * Screen.devicePixelRatio * 2, size * Screen.devicePixelRatio * 2)
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

    // A switch for an on/off install.sh setting (1 on, 0 off; on by default).
    component SettingSwitch: MacSwitch {
        property string key: ""
        checked: window.settingValue(key, 1) === 1
        enabled: !backend.busy && window.pieceOn("theme")
        onToggled: on => window.markSetting(key, on ? 1 : 0, 1)
    }

    // A slider for one install.sh setting, set when let go.
    component SettingSlider: MacSlider {
        // The value is drawn to the left of the slider; the row keeps room for it.
        readonly property int leading: 48
        property string key: ""
        property real fallback: 0
        // 0 for whole-number settings such as blur.
        property int decimals: 2
        property string needs: "theme"
        width: 180
        value: window.settingValue(key, fallback)
        enabled: !backend.busy && window.pieceOn(needs)
        onMoved: v => window.markSetting(key, decimals === 0 ? Math.round(v) : v, fallback)

        Text {
            anchors.right: parent.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: parent.shown.toFixed(parent.decimals)
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 12
        }
    }

    // The macOS push button: gray, rounded, white text.
    component MacButton: Rectangle {
        id: button
        property string text: ""
        property bool enabled: true
        property bool primary: false
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: if (enabled) clicked()
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
            onClicked: parent.clicked()
        }
    }
}
