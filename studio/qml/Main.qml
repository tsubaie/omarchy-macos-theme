import QtCore
import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Window
import org.omarchy.macosstudio
import "BarModel.js" as BarModel
import "Labels.js" as Labels
import "Pending.js" as Pending

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

    // Studio's own updates: its newest release on GitHub, against this one's
    // name. A build from source isn't a release (its version is Cargo's), so
    // it's never offered one.
    readonly property bool releaseBuild: Labels.isRelease(backend.appVersion)
    property string studioLatest: ""
    property bool studioCheckFailed: false
    property bool studioChecking: false
    // When each was last asked, shown under its answer so a check that finds
    // nothing new still visibly did something.
    property var themeCheckedAt: null
    property var studioCheckedAt: null
    function lastChecked(at) { return Labels.lastChecked(at, new Date()) }
    // Updated, but this window still runs the old one until it reopens.
    property bool studioUpdated: false
    readonly property bool studioUpdate: !studioUpdated && Labels.studioUpdate(studioLatest, backend.appVersion)
    // A build from source asks too, to say what the newest release is.
    function checkStudio() {
        if (studioChecking) return
        studioChecking = true
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            let latest = ""
            try { latest = xhr.status === 200 ? JSON.parse(xhr.responseText).tag_name || "" : "" } catch (e) {}
            studioCheckFailed = latest === ""
            if (latest !== "") studioLatest = latest
            studioCheckedAt = new Date()
            studioChecking = false
        }
        xhr.open("GET", "https://api.github.com/repos/tsubaie/omarchy-macos-theme/releases/latest")
        xhr.setRequestHeader("Accept", "application/vnd.github+json")
        xhr.send()
    }
    Component.onCompleted: checkStudio()
    // A window left open for days still hears of updates: both asked again
    // every 6 hours, the theme not while an action is changing it.
    Timer {
        interval: 6 * 60 * 60 * 1000
        repeat: true
        running: true
        onTriggered: {
            if (!backend.busy) backend.checkTheme()
            window.checkStudio()
        }
    }
    Connections {
        target: backend
        function onCheckingChanged() { if (!backend.checking) window.themeCheckedAt = new Date() }
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

    // A question before something that changes the setup: { title, text,
    // button, action }, and optionally a third choice: { alternate, alternateAction }.
    property var confirm: null

    // What waits for Apply, one line each, in words.
    function changeLines() {
        const lines = []
        for (const piece in pendingPieces)
            lines.push((pendingPieces[piece] ? "Turn on " : "Turn off ") + Labels.piece(piece))
        for (const key in pendingSettings)
            lines.push(Labels.setting(key, Math.round(pendingSettings[key] * 100) / 100))
        for (const panel in pendingPlaces)
            lines.push(Labels.setting(panel, "at the " + pendingPlaces[panel]))
        if (pendingBar) lines.push("Rearrange the menu bar")
        if (pendingWidgets) lines.push("Show " + pendingWidgets.map(w => (desktopWidgets.find(d => d.id === w) || { name: w }).name).join(", "))
        if (pendingSwitchTo) lines.push("Switch to " + pendingSwitchTo + " first")
        return lines
    }

    // Unapplied changes a restore, an import or an update would drop: said in
    // its question rather than dropped silently.
    function droppedNote() {
        return pendingCount === 0 ? ""
            : "\n\nYour " + (pendingCount === 1 ? "change that isn't" : pendingCount + " changes that aren't") + " applied yet will be dropped."
    }

    // The theme a removal of the current one switches to first (null until picked).
    property var pendingSwitchTo: null
    // Turning the current theme off needs another theme to switch to.
    readonly property bool needsSwitchTo: status.active === true && pendingPieces.theme === false
    // The newest backup when Apply started, so Undo restores only the one it took.
    property string backupBeforeApply: ""
    property string undoBackup: ""
    property bool closeAfterApply: false
    property bool closingAnyway: false

    function installed(piece) {
        return !!status.features && status.features[piece] === true
    }

    // A setting the installed theme doesn't report is one it is too old for.
    // Before the first status comes in, every setting counts as known.
    function known(key) {
        return !status.settings || Object.keys(status.settings).length === 0 || key in status.settings
    }
    function knownPiece(piece) {
        return !status.features || Object.keys(status.features).length === 0 || piece in status.features
    }
    readonly property string tooOld: "Update the theme to use this (About > Update)"

    // Where install.sh keeps the backups, by the same rule it follows.
    readonly property string backupsFolder: localPath(StandardPaths.writableLocation(StandardPaths.ConfigLocation)) + "/omarchy/macos-theme-backups"

    // The changes waiting, in a sheet, with Apply.
    function showChanges() {
        confirm = {
            title: pendingCount === 1 ? "1 change, not applied yet" : pendingCount + " changes, not applied yet",
            text: changeLines().map(line => "·  " + line).join("\n"),
            button: "Apply",
            action: () => window.apply()
        }
    }

    function setting(key, fallback) {
        return status.settings && typeof status.settings[key] === "number" ? status.settings[key] : fallback
    }

    // Changes wait here until Apply sends them to install.sh in one call, so
    // the theme reloads once however many there are.
    property var pendingPieces: ({})
    property var pendingSettings: ({})
    // The time the page pictures show, kept to the minute.
    property date now: new Date()
    Timer { interval: 15000; running: true; repeat: true; onTriggered: window.now = new Date() }
    // The menu bar's items as the installer lists them, and the arrangement
    // waiting for Apply (null while unchanged).
    readonly property var bar: {
        try { return JSON.parse(backend.barJson) } catch (e) { return {} }
    }
    readonly property var barNames: {
        const names = {}
        for (const s in bar.sections || {}) for (const item of bar.sections[s]) names[item.id] = item.name
        for (const item of bar.hidden || []) names[item.id] = item.name
        return names
    }
    // Omdrop, which AirDrop in Control Center works through, isn't among the
    // bar's items. Unknown until the bar is read: no hint then.
    readonly property bool omdropMissing: bar.sections !== undefined && !("netmojo.omdrop" in barNames)
    // Left, Center and Right, and the hidden ones (BarModel.groups).
    readonly property var barNow: BarModel.groups(bar)

    // The backgrounds: { current, folder, yours: [paths], theme: [paths] }; an
    // older theme lists none. The pictures at the top of the pages draw the
    // one showing, or the theme's own until there is one.
    readonly property var backgrounds: {
        try { return JSON.parse(backend.backgroundsJson) } catch (e) { return {} }
    }
    // A video one (Omarchy takes those too) can't be drawn here: the theme's own then.
    readonly property string backgroundSource: fileUrl(/\.(jpe?g|png|gif|bmp|webp)$/i.test(backgrounds.current || "")
        ? backgrounds.current : backend.themeDir + "/theme/backgrounds/1-pawel-czerwinski.jpg")
    // A path as a file:// URL, with what a URL reads otherwise (#, ?) kept in the name.
    function fileUrl(path) { return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F") }
    function chooseBackground(file) {
        if (backend.busy || file === backgrounds.current) return
        start("background", file.split("/").pop())
        backend.setBackground(file)
    }
    property var pendingBar: null

    // Taking the groups back to the bar as it is takes the change away.
    function markBar(groups) {
        pendingBar = JSON.stringify(groups) === JSON.stringify(barNow) ? null : groups
    }

    // The desktop widgets shown, as the installer reports them (an older
    // theme reports none), and the ones waiting for Apply (null while unchanged).
    readonly property var desktopWidgets: [
        { id: "clock", name: "Clock" }, { id: "calendar", name: "Calendar" },
        { id: "weather", name: "Weather" }, { id: "playing", name: "Now Playing" }
    ]
    readonly property var widgetsNow: status.widgets || null
    property var pendingWidgets: null
    readonly property var widgetsShown: pendingWidgets || widgetsNow || []

    // Kept in the usual order, so turning one back on takes the change away.
    function markWidget(id, on) {
        const next = desktopWidgets.map(w => w.id).filter(w => w === id ? on : widgetsShown.includes(w))
        pendingWidgets = JSON.stringify(next) === JSON.stringify(widgetsNow) ? null : next
    }

    // Where the volume and dictation panels show ("bottom" or "top"), and
    // the places waiting for Apply. An older theme reports none: bottom.
    property var pendingPlaces: ({})
    function placeNow(panel) { return status[panel] === "top" ? "top" : "bottom" }
    function placeValue(panel) { return panel in pendingPlaces ? pendingPlaces[panel] : placeNow(panel) }
    function markPlace(panel, place) {
        const next = Object.assign({}, pendingPlaces)
        if (place === placeNow(panel)) delete next[panel]
        else next[panel] = place
        pendingPlaces = next
    }

    // Changed outside Studio (a widget removed on the desktop, install.sh in
    // a terminal): read again when you come back to the window, open a page,
    // or every 30 s, and only when what the status comes from changed.
    Timer { interval: 30000; running: true; repeat: true; onTriggered: backend.rereadIfChanged() }
    onActiveChanged: if (active) backend.rereadIfChanged()

    // A change waiting that the desktop now has anyway (made outside Studio)
    // stops waiting; the rest stay marked.
    function forgetMet() {
        const left = Pending.forgetMet(
            { pieces: pendingPieces, settings: pendingSettings, places: pendingPlaces, bar: pendingBar, widgets: pendingWidgets },
            { installed: installed, setting: key => (status.settings || {})[key], place: placeNow, bar: barNow, widgets: widgetsNow })
        if (left.pieces !== pendingPieces) pendingPieces = left.pieces
        if (left.settings !== pendingSettings) pendingSettings = left.settings
        if (left.places !== pendingPlaces) pendingPlaces = left.places
        if (left.bar !== pendingBar) pendingBar = left.bar
        if (left.widgets !== pendingWidgets) pendingWidgets = left.widgets
    }
    onStatusChanged: forgetMet()
    onBarNowChanged: forgetMet()

    readonly property int pendingCount: Object.keys(pendingPieces).length + Object.keys(pendingSettings).length
        + Object.keys(pendingPlaces).length + (pendingBar ? 1 : 0) + (pendingWidgets ? 1 : 0)


    property bool applying: false

    function pieceOn(piece) {
        return piece in pendingPieces ? pendingPieces[piece] : installed(piece)
    }

    // Why a control waits on a piece, under its row while that piece is off.
    function why(piece) {
        const names = { theme: "the theme", dock: "the macOS dock", osd: "the volume panel",
            "dictation-hud": "the dictation HUD", widgets: "the desktop widgets", lock: "the lock screen" }
        return "Turn on " + (names[piece] || piece) + " to change this"
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

    // Sliders show their value as they move (backend.preview); dropping the
    // changes puts those settings back as installed.
    // Glass is previewed in the window itself (GlassPreview); blur on the
    // desktop too, where it changes in place, and the dock's settings on the dock.
    readonly property var previewable: ["blur", "magnification", "dock-size"]
    function discard() {
        for (const key in pendingSettings)
            if (previewable.includes(key)) backend.preview(key, setting(key, pendingSettings[key]))
        revert()
    }
    // Closing with changes not applied asks first: Apply, Don't Apply or Cancel.
    onClosing: function(close) {
        if (pendingCount === 0 || closingAnyway || backend.busy) {
            discard()
            return
        }
        close.accepted = false
        confirm = {
            title: pendingCount === 1 ? "Apply your change before closing?" : "Apply your " + pendingCount + " changes before closing?",
            text: "If you don't, " + (pendingCount === 1 ? "it is" : "they are") + " dropped.",
            button: "Apply",
            action: () => { window.closeAfterApply = true; window.apply() },
            alternate: "Don't Apply",
            alternateAction: () => { window.closingAnyway = true; window.close() }
        }
    }

    function revert() {
        pendingBar = null
        pendingWidgets = null
        pendingSwitchTo = null
        pendingPieces = {}
        pendingSettings = {}
        pendingPlaces = {}
    }

    // The action running, or the last one: what the busy line, the
    // confirmation and the error's next step say. detail is what it was about
    // (how many changes, which file or backup).
    property string action: ""
    property string actionDetail: ""
    property bool stopping: false
    // What the last action did, for a few seconds once it is done.
    property string notice: ""
    property int elapsed: 0

    function start(kind, detail) {
        action = kind
        actionDetail = detail === undefined ? "" : String(detail)
        notice = ""
        stopping = false
    }

    readonly property var workingText: ({
        apply: "Applying…", update: "Updating…", backup: "Backing up…", restore: "Restoring…",
        export: "Exporting…", import: "Importing…", download: "Downloading…", undo: "Undoing…",
        remove: "Removing the macOS theme…", use: "Switching to the macOS theme…", studio: "Updating Studio…",
        background: "Setting the background…", "add-backgrounds": "Adding the pictures…"
    })

    function doneText() {
        const n = Number(actionDetail)
        switch (action) {
        case "apply": return n === 1 ? "Applied 1 change." : "Applied " + n + " changes."
        case "update": return "Updated the theme" + (backend.themeVersion ? " to " + Labels.themeVersion(backend.themeVersion) : "") + "."
        case "backup": return "Backed up. It's first in the list below."
        case "restore": return "Restored the backup from " + actionDetail + ". Your setup before it is backed up too."
        case "export": return "Exported your setup to " + actionDetail + "."
        case "import": return "Imported " + actionDetail + ". Your setup before it is backed up."
        case "download": return "Downloaded the theme."
        case "undo": return "Undid the changes. How they were is backed up too, should you want them back."
        case "remove": return "Removed the macOS theme, and what it replaced is back."
        case "use": return "The macOS theme is in use."
        case "studio": return "Updated Studio to " + actionDetail + ". Reopen it to use the new version."
        case "background": return "Set the background to " + actionDetail + "."
        case "add-backgrounds": return n === 1 ? "Added 1 picture to Yours." : "Added " + n + " pictures to Yours."
        }
        return ""
    }

    // What to do about a failure, by what failed.
    function nextStep() {
        switch (action) {
        case "apply": return "Your changes are still marked: fix what it says, then Apply again."
        case "update": return "The theme stays as it was, and Update is still offered to try again."
        case "download": return "Check the network, then Download again."
        case "studio": return "Studio stays as it was; try again."
        case "restore":
        case "undo":
        case "remove":
        case "use":
        case "import": return "If it got as far as changing anything, Backups has how things were before it."
        case "backup":
        case "background":
        case "add-backgrounds":
        case "export": return "Nothing was changed; try again."
        }
        return ""
    }

    // The actions whose done note offers Undo: the backup each took first.
    readonly property var undoable: ["apply", "remove", "use", "update", "background"]

    // Install macOS Theme, or Use macOS Theme when it is installed but another
    // theme is current: install.sh puts the theme in (your settings kept)
    // and makes it current, as turning it off and on again would.
    function useTheme() {
        start(installed("theme") ? "use" : "apply", 1)
        backupBeforeApply = backups.length > 0 ? backups[0].id : ""
        backend.apply(JSON.stringify({ add: ["theme"] }))
    }

    // Updating the theme, asked first. From What's New… the changes lead and
    // nothing is decided yet; from Update Now, what updating does leads.
    function askThemeUpdate(lookingFirst) {
        const what = "The newest version is downloaded and the pieces you use are installed again, after a backup you can restore. The theme reloads once."
        const notes = backend.updateNotes ? Labels.whatsNew(backend.updateNotes) : ""
        confirm = {
            title: lookingFirst ? "What's new in the macOS theme" : "Update the macOS theme?",
            text: (lookingFirst ? notes + "\n\n" + what : what + (notes ? "\n\n" + notes : "")) + droppedNote(),
            button: "Update Now",
            waitsForIdle: true,
            action: () => {
                discard()
                start("update")
                backupBeforeApply = backups.length > 0 ? backups[0].id : ""
                backend.update()
            }
        }
    }

    // Remove macOS Theme: every piece off in one Apply, so its progress, Stop
    // and Undo work as Apply's do; or, when there is one, the backup from
    // before the theme, whole.
    function askRemove() {
        const original = backups.find(b => b.original)
        // install.sh picks the same theme itself; it is named here so the question can say it.
        const back = status.active ? status["previous-theme"] : null
        confirm = {
            title: "Remove the macOS theme?",
            text: "The theme and all its pieces go, its icons too, and what each one replaced comes back: Omarchy's dock, bar, menu and lock screen, or your own."
                + (back ? "\n\nOmarchy switches to " + back + " first." : "")
                + "\n\nYour setup now is backed up first, so you can undo this; the icons then come back from General > MacTahoe icons."
                + (original ? "\n\nGo Back puts everything as it was on " + when(original.created) + ", before the macOS theme, instead. "
                    + "shell.json, looknfeel.lua and gtk.css come back whole, so edits you made to them since go too." : "")
                + droppedNote(),
            button: "Remove",
            destructive: true,
            alternate: original ? "Go Back" : "",
            alternateAction: () => { discard(); start("restore", when(original.created)); backend.restore(original.id) },
            action: () => {
                discard()
                start("remove")
                backupBeforeApply = backups.length > 0 ? backups[0].id : ""
                const changes = { remove: Object.keys(status.features || {}) }
                if (back) changes.switchTo = back
                backend.apply(JSON.stringify(changes))
            }
        }
    }

    function apply() {
        // Every way to Apply waits for a theme to switch to when the current
        // one is turned off, or install.sh would refuse it after the fact.
        if (needsSwitchTo && !pendingSwitchTo) {
            closeAfterApply = false
            // Apply's own next step, and no details left from an earlier failure.
            start("apply", pendingCount)
            backend.errorDetails = ""
            backend.error = "Pick the theme to switch to first, under macOS theme."
            open("general")
            return
        }
        start("apply", pendingCount)
        backupBeforeApply = backups.length > 0 ? backups[0].id : ""
        const changes = { add: [], remove: [], set: pendingSettings, places: pendingPlaces }
        if (needsSwitchTo && pendingSwitchTo) changes.switchTo = pendingSwitchTo
        if (pendingBar) changes.bar = BarModel.layout(bar, pendingBar)
        if (pendingWidgets) changes.widgets = pendingWidgets
        for (const piece in pendingPieces) (pendingPieces[piece] ? changes.add : changes.remove).push(piece)
        applying = true
        backend.apply(JSON.stringify(changes))
    }

    // Done: the switches show what is installed now. On an error the changes
    // stay marked, to fix and apply again.
    Connections {
        target: backend
        function onBusyChanged() {
            if (backend.busy) {
                window.elapsed = 0
                return
            }
            if (backend.error === "" && !window.stopping) window.notice = window.doneText()
            if (window.action === "studio" && backend.error === "" && !window.stopping) window.studioUpdated = true
            // Undo restores the backup this Apply took, the one new since it started.
            window.undoBackup = window.undoable.includes(window.action) && backend.error === "" && window.backups.length > 0
                && window.backups[0].id !== window.backupBeforeApply ? window.backups[0].id : ""
            if (!window.applying) return
            window.applying = false
            if (backend.error === "") window.revert()
            // Asked to apply before closing: closed once it went through, kept open if not.
            if (window.closeAfterApply) {
                window.closeAfterApply = false
                if (backend.error === "") { window.closingAnyway = true; Qt.callLater(window.close) }
            }
        }
        // Said aloud by a screen reader as it appears, not only shown.
        function onErrorChanged() {
            window.showDetails = false
            if (backend.error !== "" && typeof errorBanner.Accessible.announce === "function")
                errorBanner.Accessible.announce(backend.error)
        }
    }

    // The page shown first: --page <id> when given, else the last one viewed
    // (HIG, Settings: "Restore the most recently viewed pane").
    property string page: {
        const args = Qt.application.arguments
        const asked = args.indexOf("--page") >= 0 ? args[args.indexOf("--page") + 1] : prefs.lastPage
        // Before the theme is downloaded there's nothing on the other pages to set.
        return backend.downloaded && pages.some(p => p.id === asked) ? asked : "overview"
    }
    // Written at once, so it survives the app being killed rather than closed.
    onPageChanged: { prefs.lastPage = page; prefs.sync(); backend.rereadIfChanged() }

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
    // Ctrl+S applies what is waiting; Escape leaves a search.
    Shortcut {
        sequences: [StandardKey.Save]
        enabled: window.confirm === null && window.pendingCount > 0 && !backend.busy
        onActivated: window.apply()
    }
    Shortcut {
        sequence: "Escape"
        enabled: window.confirm === null && window.query !== ""
        onActivated: window.open(window.page)
    }

    // The sheet takes the focus while it asks, on Cancel when the action
    // replaces something (HIG, Alerts: a destructive action is never the
    // default), and gives it back to where it was.
    property Item focusBeforeSheet: null
    onConfirmChanged: {
        if (confirm) {
            focusBeforeSheet = window.activeFocusItem
            Qt.callLater(() => (window.confirm && window.confirm.destructive ? sheetCancel : sheetAction).forceActiveFocus())
        } else if (focusBeforeSheet) {
            focusBeforeSheet.forceActiveFocus()
            focusBeforeSheet = null
        }
    }
    // A sheet that can open while something runs (What's New…) takes its
    // action only once that is done.
    readonly property bool sheetWaits: !!confirm && !!confirm.waitsForIdle && backend.busy
    function acceptSheet() {
        if (sheetWaits) return
        const action = confirm.action
        confirm = null
        action()
    }

    // Sections group the sidebar as System Settings does; keywords are the
    // words on each page's rows, which search also finds.
    readonly property var pages: [
        { id: "overview", title: "About", icon: "about", section: 0,
          keywords: "about version license open source github omarchy remove uninstall go back" },
        { id: "general", title: "General", icon: "general", section: 1,
          keywords: "theme colors title bars gaps motion wallpapers mactahoe icons striped rows files app workspace switchers alt tab spotlight menu volume brightness capsule osd dictation pill voxtype position place top bottom" },
        { id: "windows", title: "Windows", icon: "windows", section: 1,
          keywords: "window glass reduce motion animation animations accessibility fade spring vestibular translucent transparent see-through opacity solid blur frosted browser apps electron chrome vs code web snap snapping halves corners title bar titlebar traffic lights buttons close minimize zoom" },
        { id: "dock", title: "Dock", icon: "dock", section: 1,
          keywords: "dock magnification size icon size bigger smaller resize window previews hover thumbnails downloads trash" },
        { id: "lock", title: "Lock Screen", icon: "lock", section: 1,
          keywords: "lock screen password clock account picture preview" },
        { id: "widgets", title: "Widgets", icon: "widgets", section: 1,
          keywords: "desktop widgets clock calendar weather now playing music show hide" },
        { id: "menubar", title: "Menu Bar", icon: "menubar", section: 1,
          keywords: "menu bar inter font app name control center wifi wi-fi ethernet network bluetooth sound volume display monitor symbols clock time date position left center middle right items icons widgets show hide rearrange order drag tray airdrop omdrop" },
        { id: "backgrounds", title: "Backgrounds", icon: "backgrounds", section: 1,
          keywords: "background backgrounds wallpaper wallpapers desktop picture pictures photo photos image add suggested" },
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

        // One stop for Tab, as a macOS sidebar is: Up and Down go through its
        // pages, the overview first, a ring on the one shown.
        activeFocusOnTab: true
        Accessible.role: Accessible.PageTabList
        Accessible.name: "Settings"
        Keys.onUpPressed: step(-1)
        Keys.onDownPressed: step(1)
        function step(by) {
            if (window.query !== "" || !backend.downloaded) return
            const ids = ["overview"].concat(window.listed.map(p => p.id))
            const at = ids.indexOf(window.page)
            window.page = ids[Math.max(0, Math.min(ids.length - 1, at + by))]
        }

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
                enabled: backend.downloaded
                opacity: enabled ? 1 : 0.4
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

                FocusRing { controlRadius: 8; visible: sidebar.activeFocus && window.page === "overview" }

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
                        // An update for the theme or for Studio: About has both.
                        readonly property bool hasUpdate: backend.updates > 0 || window.studioUpdate
                        text: !backend.downloaded ? "Not downloaded"
                            : hasUpdate ? "Update available"
                            : window.status.active ? "Current theme" : "Installed, not current"
                        color: hasUpdate ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.55)
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
                        // 0.6, not lighter: dimmer fails text contrast (4.5:1) on the sidebar.
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 6
                        // Dimmed and unclickable until the theme is downloaded.
                        enabled: backend.downloaded
                        opacity: enabled ? 1 : 0.35
                        color: entry.selected ? Qt.rgba(1, 1, 1, 0.12) : hover.hovered && enabled ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                        Accessible.role: Accessible.PageTab
                        Accessible.name: entry.modelData.title
                        Accessible.description: enabled ? "" : "Download the theme first"
                        Accessible.selected: entry.selected
                        Accessible.onPressAction: window.open(entry.modelData.id)

                        HoverHandler { id: hover }

                        FocusRing { controlRadius: 6; visible: sidebar.activeFocus && entry.selected }

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
        if (!backend.downloaded && id !== "overview") return
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

            Spinner {
                anchors.verticalCenter: parent.verticalCenter
                visible: backend.busy
            }
            // What it is doing now, in install.sh's or git's words when they
            // say, and for how long once it takes a while.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: backend.busy || window.pendingCount > 0
                text: backend.busy
                    ? (window.stopping ? "Stopping…" : backend.stage || window.workingText[window.action] || "Working…")
                      + (window.elapsed >= 3 ? "  ·  " + window.elapsed + " s" : "")
                    : window.pendingCount === 1 ? "1 change" : window.pendingCount + " changes"
                color: Qt.rgba(1, 1, 1, 0.6)
                // Clicked, the changes in words, to apply or look over.
                MouseArea {
                    anchors.fill: parent
                    enabled: !backend.busy && window.pendingCount > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: window.showChanges()
                }
                font.pixelSize: 13
                rightPadding: 4
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 320)
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
            MacButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: backend.busy && window.action !== ""
                text: "Stop"
                enabled: !window.stopping
                onClicked: { window.stopping = true; backend.cancel() }
            }
            MacButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: window.pendingCount > 0 || window.applying
                text: "Revert"
                enabled: !backend.busy
                onClicked: window.discard()
            }
            MacButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: window.pendingCount > 0 || window.applying
                text: "Apply"
                primary: true
                enabled: !backend.busy && (!window.needsSwitchTo || !!window.pendingSwitchTo)
                reason: window.needsSwitchTo && !window.pendingSwitchTo ? "Pick a theme to switch to first, under macOS theme" : ""
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

            // What the last action did, for a few seconds.
            Banner {
                visible: window.notice !== ""
                tint: "#30d158"
                glyph: "✓"
                timeout: 8000
                text: window.notice
                actionText: window.undoBackup !== "" && window.undoable.includes(window.action) ? "Undo" : ""
                onActed: {
                    const id = window.undoBackup
                    // An update's undo also keeps the update offered, to apply again.
                    const wasUpdate = window.action === "update"
                    window.start("undo")
                    if (wasUpdate) backend.undoUpdate(id); else backend.restore(id)
                }
                onDismissed: window.notice = ""
            }

            // Why the last action failed, in install.sh's own words, what to
            // do about it, and all it said behind Show Details.
            Banner {
                id: errorBanner
                visible: backend.error !== ""
                tint: "#ff453a"
                glyph: "!"
                text: backend.error
                more: window.nextStep()
                details: backend.errorDetails !== backend.error ? backend.errorDetails : ""
                onDismissed: { backend.error = ""; backend.errorDetails = "" }
            }

            // What the last action warned about though it succeeded (a piece
            // it skipped, a font that's missing), in install.sh's own words.
            Banner {
                visible: backend.error === "" && backend.warning !== ""
                tint: "#ff9f0a"
                glyph: "!"
                text: backend.warning
                onDismissed: backend.warning = ""
            }

            // First run: one welcome page in place of every page, until the
            // theme is downloaded (the pages' scenes draw its wallpapers).
            Column {
                visible: !backend.downloaded
                width: parent.width
                spacing: 10
                topPadding: 48

                AppIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: 96
                }
                Item { width: 1; height: 4 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Welcome to macOS Theme"
                    color: "white"
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 440)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Give Omarchy the macOS look: see-through windows with traffic lights, a dock, a menu bar with Control Center, a lock screen and desktop widgets. Download the theme first. Nothing on your desktop changes until you choose what to turn on."
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 13
                    lineHeight: 1.2
                }
                Item { width: 1; height: 8 }
                MacButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // shortcut: the size of a download of main on 2026-11-03; measure again if the theme grows a lot.
                    text: "Download (about 20 MB)"
                    primary: true
                    enabled: !backend.busy
                    onClicked: { window.start("download"); backend.download() }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 440)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "From GitHub into " + backend.themeDir
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 11
                }
            }

            // General.
            Column {
                visible: backend.downloaded && window.page === "general"
                width: parent.width
                spacing: 18

                GeneralScene { width: parent.width }

                Group {
                    title: "Theme"

                    SettingRow {
                        label: "macOS theme"
                        note: "Colors, glass, title bars, gaps, motion and wallpapers"
                        last: !window.needsSwitchTo
                        PieceSwitch { piece: "theme" }
                    }
                    // It is the current theme, so Omarchy needs another one
                    // in its place before it can go.
                    SettingRow {
                        visible: window.needsSwitchTo
                        label: "Switch to"
                        note: window.status.themes && window.status.themes.length > 0
                            ? (window.pendingSwitchTo ? "Omarchy switches to " + window.pendingSwitchTo + " before the macOS theme goes"
                                : "The macOS theme is your current theme: pick the one Omarchy switches to first")
                            : "Switch to another theme first (Omarchy menu > Style > Theme), then turn this off"
                        last: true
                        Flow {
                            width: 260
                            spacing: 6
                            layoutDirection: Qt.RightToLeft
                            Repeater {
                                model: window.status.themes || []
                                MacButton {
                                    required property string modelData
                                    text: modelData
                                    primary: window.pendingSwitchTo === modelData
                                    onClicked: window.pendingSwitchTo = modelData
                                }
                            }
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

                // Where each shows: the bottom middle, or the top right under
                // the menu bar, as macOS 27.2 has it.
                Group {
                    title: "Position"

                    SettingRow { label: "Volume and brightness capsule"; note: "Top shows it at the right, under the menu bar"; PlaceChoice { panel: "volume-hud"; needs: "osd" } }
                    SettingRow { label: "Dictation pill"; note: "Top shows it at the right, under the menu bar"; last: true; PlaceChoice { panel: "dictation-hud"; needs: "dictation-hud" } }
                }
            }

            // Windows: how see-through they are, the blur behind them, snapping.
            Column {
                visible: backend.downloaded && window.page === "windows"
                width: parent.width
                spacing: 18

                GlassPreview { width: parent.width }

                Group {
                    title: "Glass"

                    SettingRow {
                        label: "Window glass"
                        note: "How see-through the windows you aren't using are; 1 is solid. The one you are using is always solid, so its text reads."
                        SettingSlider { key: "glass"; from: 0.75; to: 1; fallback: 0.85 }
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
                    title: "Motion"

                    SettingRow {
                        label: "Reduce motion"
                        note: "Windows, menus and workspaces fade in and out instead of springing and sliding; no genie when minimizing, and the weather widget holds still"
                        last: true
                        SettingSwitch { key: "reduce-motion"; fallback: 0 }
                    }
                }

                Group {
                    title: "Title Bars"

                    SettingRow {
                        label: "Title bars"
                        note: "The bar above each window with its name and traffic lights; off, windows show their content to the top, on floating workspaces too"
                        SettingSwitch { key: "title-bars" }
                    }
                    SettingRow {
                        label: "Traffic light size"
                        note: "How big the close, minimize and zoom buttons are, in points; the bar grows to fit larger ones"
                        last: true
                        SettingSlider { key: "traffic-lights"; from: 10; to: 20; fallback: 14; decimals: 0; available: window.settingValue("title-bars", 1) === 1; unavailable: "Turn on title bars to size their traffic lights" }
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
            DockScene { visible: backend.downloaded && window.page === "dock"; width: parent.width }
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
                    SettingSlider { key: "magnification"; from: 1; to: 2; fallback: 1.75; needs: "dock" }
                }
                SettingRow {
                    label: "Size"
                    note: "How big the dock's icons are, in points"
                    SettingSlider { key: "dock-size"; from: 32; to: 80; fallback: 48; decimals: 0; needs: "dock" }
                }
                SettingRow {
                    label: "Window previews"
                    note: "An app's windows over its icon when the pointer rests on it"
                    last: true
                    SettingSwitch { key: "dock-previews"; needs: "dock" }
                }
            }

            // Lock screen.
            LockScene { visible: backend.downloaded && window.page === "lock"; width: parent.width }
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
                        reason: enabled ? "" : window.why("lock")
                        onClicked: backend.previewLock()
                    }
                }
            }

            // Backgrounds, as System Settings' Wallpaper: the one showing,
            // yours and the theme's. A click shows one at once (no Apply), after
            // a backup, so Undo in the note puts the last one back.
            Column {
                visible: backend.downloaded && window.page === "backgrounds"
                width: parent.width
                spacing: 18

                Scene { width: parent.width; height: 220 }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: !window.installed("theme") ? "Install the macOS theme first (General), then choose its background."
                        : window.status.active === false ? "Omarchy is showing another theme. The background you choose shows once the macOS theme is in use."
                        : window.backgrounds.current ? window.backgrounds.current.split("/").pop() : ""
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 12
                }

                Group {
                    title: "Yours"
                    Item {
                        width: parent.width
                        height: yours.height + 24
                        Flow {
                            id: yours
                            x: 12
                            y: 12
                            width: parent.width - 24
                            spacing: 12
                            Repeater {
                                model: window.backgrounds.yours || []
                                BackgroundTile { required property var modelData; file: modelData }
                            }
                            // Copied into Omarchy's folder for this theme's backgrounds.
                            Rectangle {
                                width: 152
                                height: 96
                                radius: 8
                                color: addMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.16)
                                opacity: enabled ? 1 : 0.4
                                enabled: !backend.busy && window.installed("theme")
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: "Add Photos…"
                                Accessible.onPressAction: addBackgroundsDialog.open()
                                Keys.onSpacePressed: addBackgroundsDialog.open()
                                Keys.onReturnPressed: addBackgroundsDialog.open()
                                Text {
                                    anchors.centerIn: parent
                                    text: "Add Photos…"
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    font.pixelSize: 13
                                }
                                FocusRing { controlRadius: 8 }
                                MouseArea {
                                    id: addMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: addBackgroundsDialog.open()
                                }
                            }
                        }
                    }
                }

                // The ones the theme comes with.
                Group {
                    title: "Suggested"
                    visible: (window.backgrounds.theme || []).length > 0
                    Item {
                        width: parent.width
                        height: theirs.height + 24
                        Flow {
                            id: theirs
                            x: 12
                            y: 12
                            width: parent.width - 24
                            spacing: 12
                            Repeater {
                                model: window.backgrounds.theme || []
                                BackgroundTile { required property var modelData; file: modelData }
                            }
                        }
                    }
                }
            }

            // Widgets: the piece, then which of them show.
            Column {
                visible: backend.downloaded && window.page === "widgets"
                width: parent.width
                spacing: 18

                WidgetsScene { width: parent.width }

                Group {
                    SettingRow {
                        label: "Desktop widgets"
                        note: "Clock, calendar, weather and now playing. Drag to move; right-click to remove or add."
                        last: true
                        PieceSwitch { piece: "widgets" }
                    }
                }

                // One switch each; the last one shown stays, as on the desktop.
                Group {
                    title: "Show on Desktop"
                    visible: window.widgetsNow !== null

                    Repeater {
                        model: window.desktopWidgets
                        SettingRow {
                            required property var modelData
                            required property int index
                            label: modelData.name
                            last: index === window.desktopWidgets.length - 1
                            MacSwitch {
                                readonly property bool shown: window.widgetsShown.includes(modelData.id)
                                checked: shown
                                enabled: !backend.busy && window.pieceOn("widgets")
                                    && !(shown && window.widgetsShown.length === 1)
                                reason: !window.pieceOn("widgets") ? window.why("widgets")
                                    : shown && window.widgetsShown.length === 1 ? "One widget always stays shown" : ""
                                onToggled: on => window.markWidget(modelData.id, on)
                            }
                        }
                    }
                }
            }

            // Menu bar.
            MenuBarScene { visible: backend.downloaded && window.page === "menubar"; width: parent.width }
            Group {
                visible: backend.downloaded && window.page === "menubar"

                SettingRow {
                    label: "macOS menu bar"
                    note: "Inter, the app name in bold, and Control Center, which holds Wi-Fi, Bluetooth, sound and displays"
                    PieceSwitch { piece: "menubar" }
                }
                SettingRow {
                    label: "macOS icons"
                    note: "For Wi-Fi and Ethernet, Bluetooth, sound and displays"
                    last: !window.omdropMissing
                    PieceSwitch { piece: "bar-icons" }
                }
                // AirDrop in Control Center works through Omdrop, a plugin of its own.
                SettingRow {
                    visible: window.omdropMissing
                    label: "AirDrop"
                    note: "Needs Omdrop, AirDrop for Omarchy, which isn't installed. Its page says how to install it."
                    last: true
                    MacButton {
                        text: "Get Omdrop"
                        onClicked: Qt.openUrlExternally("https://github.com/netmojo-systems/omdrop-plugin")
                    }
                }
            }

            // The menu bar's items: show, hide and drag to rearrange.
            Column {
                visible: backend.downloaded && window.page === "menubar" && window.bar.sections !== undefined
                width: parent.width
                spacing: 8

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Drag an item by its handle to move it, within a part of the bar or into another. The switch shows or hides it."
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 12
                    leftPadding: 4
                }

                BarItems {
                    width: parent.width
                    groups: window.pendingBar || window.barNow
                    names: window.barNames
                    enabled: !backend.busy
                    flickable: content
                    onChanged: groups => window.markBar(groups)
                }
            }

            // Backups.
            Column {
                visible: backend.downloaded && window.page === "backups"
                width: parent.width
                spacing: 18

                BackupsScene { width: parent.width }

                Group {
                    title: "This Computer"

                    SettingRow {
                        label: "Back up now"
                        note: "A backup is also taken by itself before every change. The last 10 are kept, and the first one for good."
                        MacButton {
                            text: "Back Up Now"
                            enabled: !backend.busy
                            onClicked: { window.start("backup"); backend.backUp() }
                        }
                    }
                    SettingRow {
                        label: "Where they are"
                        note: window.backupsFolder
                        last: true
                        MacButton {
                            text: "Open"
                            onClicked: Qt.openUrlExternally("file://" + window.backupsFolder)
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
                            label: modelData.original ? "Before macOS theme" : Labels.backup(modelData.note)
                            note: window.when(modelData.created) + (modelData.pinned ? "  ·  Kept" : "")
                            last: index === window.backups.length - 1

                            MacButton {
                                text: "Restore"
                                enabled: !backend.busy
                                onClicked: window.confirm = {
                                    title: "Restore the backup from " + window.when(modelData.created) + "?",
                                    text: "These go back to how they were then, whole, so edits you made to them since (a keybinding, a bar change) go too:\n"
                                        + "  ·  ~/.config/omarchy/shell.json\n  ·  ~/.config/hypr/looknfeel.lua\n  ·  ~/.config/gtk-4.0/gtk.css\n"
                                        + "  ·  ~/.config/omarchy/themes/macos/\n  ·  the theme's plugins in ~/.config/omarchy/plugins/\n"
                                        + (modelData.original ? "  ·  the theme's MacTahoe icons are removed\n" : "") + "\n"
                                        + "Your setup now is backed up first, so you can undo this." + window.droppedNote(),
                                    button: "Restore",
                                    destructive: true,
                                    action: () => { window.discard(); window.start("restore", window.when(modelData.created)); backend.restore(modelData.id) }
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

            // Overview, as About This Mac and Software Update together: what it
            // is, whether it and Studio are up to date, and the way out. All of
            // it fits the window as it opens, without scrolling.
            Column {
                visible: backend.downloaded && window.page === "overview"
                width: parent.width
                spacing: 18
                topPadding: 4

                HomeScene { width: parent.width }

                // What it is, and, when the desktop isn't showing it, the one
                // button that makes it so.
                Item {
                    width: parent.width
                    height: Math.max(appIcon.height, identity.height, useTheme.visible ? useTheme.height : 0)

                    AppIcon {
                        id: appIcon
                        size: 64
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        id: identity
                        anchors.left: appIcon.right
                        anchors.leftMargin: 16
                        anchors.right: useTheme.visible ? useTheme.left : parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Text {
                            text: "macOS Theme for Omarchy"
                            color: "white"
                            font.pixelSize: 22
                            font.weight: Font.Bold
                        }
                        Row {
                            spacing: 6
                            height: 18
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Made for"
                                color: Qt.rgba(1, 1, 1, 0.6)
                                font.pixelSize: 13
                            }
                            Image {
                                id: omarchyLogo
                                anchors.verticalCenter: parent.verticalCenter
                                visible: status === Image.Ready
                                source: backend.omarchyLogo
                                sourceSize.height: 36
                                height: 13
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                // The Omarchy versions the theme supports, not this computer's.
                                text: (omarchyLogo.status === Image.Ready ? "" : "Omarchy ") + "4 and later. Open source, MIT."
                                color: Qt.rgba(1, 1, 1, 0.6)
                                font.pixelSize: 13
                            }
                        }
                    }
                    Column {
                        id: useTheme
                        // Downloaded, or switched away from in Omarchy.
                        visible: window.status.active === false && window.knownPiece("theme")
                            && Object.keys(window.status.features || {}).length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        MacButton {
                            anchors.right: parent.right
                            large: true
                            primary: true
                            text: window.installed("theme") ? "Use macOS Theme" : "Install macOS Theme"
                            enabled: !backend.busy
                            reason: "Wait for what's running to finish"
                            onClicked: window.useTheme()
                        }
                        Text {
                            anchors.right: parent.right
                            text: window.installed("theme") ? "Omarchy is showing another theme" : "Not installed yet"
                            color: Qt.rgba(1, 1, 1, 0.6)
                            font.pixelSize: 12
                        }
                    }
                }

                // Each one on its own row, as Software Update has it: where it
                // stands, when it was last asked, and the one thing to do next.
                Group {
                    title: "Software Update"

                    SettingRow {
                        label: "Theme"
                        // Its version, the commit and its date, says which one is here.
                        readonly property string here: backend.themeVersion ? " You have " + Labels.themeVersion(backend.themeVersion) + "." : ""
                        note: backend.checking ? "Checking GitHub for new changes…"
                            : backend.updates > 0 ? (backend.updates === 1 ? "1 new change is ready." : backend.updates + " new changes are ready.")
                                + " " + window.lastChecked(window.themeCheckedAt)
                            // A check that failed (offline, say) is no "Up to date".
                            : backend.updateError !== "" ? "Couldn't reach GitHub to check. Check your connection, then check again."
                            : ("Up to date." + here + " " + window.lastChecked(window.themeCheckedAt)).trim()
                        mainControl: themeUpdate

                        // A look first, as Software Update's More Info…, so the
                        // update isn't the only thing to press; open while anything runs.
                        Row {
                            spacing: 8
                            MacButton {
                                visible: backend.updates > 0 && backend.updateNotes !== ""
                                text: "What's New…"
                                onClicked: window.askThemeUpdate(true)
                            }
                            UpdateButton {
                                id: themeUpdate
                                checking: backend.checking
                                next: backend.updates > 0 ? "Update Now" : "Check Now"
                                primary: backend.updates > 0
                                enabled: !backend.busy && !backend.checking
                                onClicked: if (backend.updates === 0) backend.checkTheme(); else window.askThemeUpdate(false)
                            }
                        }
                    }
                    SettingRow {
                        last: true
                        label: "Studio " + backend.appVersion
                        note: window.studioChecking ? "Checking GitHub for a new release…"
                            : window.studioUpdated ? "Updated to " + window.studioLatest + ". Reopen Studio to use it."
                            : window.studioUpdate ? "Version " + window.studioLatest + " is ready. " + window.lastChecked(window.studioCheckedAt)
                            : window.studioCheckFailed ? "Couldn't reach GitHub to check. Check your connection, then check again."
                            : !window.releaseBuild ? ("Built from source, so it updates with your checkout."
                                + (window.studioLatest ? " The newest release is " + window.studioLatest + "." : "")
                                + " " + window.lastChecked(window.studioCheckedAt)).trim()
                            : ("Up to date. " + window.lastChecked(window.studioCheckedAt)).trim()
                        mainControl: studioUpdateButton

                        Row {
                            spacing: 8
                            // Its release's notes, on GitHub.
                            MacButton {
                                visible: window.studioUpdate && !window.studioUpdated
                                text: "What's New…"
                                onClicked: Qt.openUrlExternally("https://github.com/tsubaie/omarchy-macos-theme/releases/tag/" + encodeURIComponent(window.studioLatest))
                            }
                            UpdateButton {
                                id: studioUpdateButton
                                checking: window.studioChecking
                                next: window.studioUpdated ? "Reopen" : window.studioUpdate ? "Update Now" : "Check Now"
                                primary: window.studioUpdate || window.studioUpdated
                                // Updating runs the downloaded theme's own get.sh. Reopening
                                // waits for what's running, and for changes waiting, so it
                                // never quits mid-Apply or leaves two windows open.
                                enabled: window.studioUpdated ? !backend.busy && window.pendingCount === 0
                                    : !window.studioChecking && !(window.studioUpdate && backend.busy)
                                reason: window.studioUpdated && enabled === false
                                    ? (backend.busy ? "Wait for what's running to finish" : "Apply or revert your changes first") : ""
                                onClicked: {
                                    if (window.studioUpdated) {
                                        if (backend.reopen()) window.close()
                                    } else if (window.studioUpdate) {
                                        window.confirm = {
                                            title: "Update Studio to " + window.studioLatest + "?",
                                            text: "The newest Studio is downloaded from GitHub and put in place of this one. Reopen it afterwards to use it; the theme isn't changed.",
                                            button: "Update",
                                            action: () => { window.start("studio", window.studioLatest); backend.updateStudio() }
                                        }
                                    } else {
                                        window.checkStudio()
                                    }
                                }
                            }
                        }
                    }
                }

                // Where it comes from, and the way out.
                Item {
                    width: parent.width
                    height: 24

                    Row {
                        spacing: 10
                        MacButton { text: "Theme on GitHub"; onClicked: Qt.openUrlExternally("https://github.com/tsubaie/omarchy-macos-theme") }
                        MacButton { text: "Studio on GitHub"; onClicked: Qt.openUrlExternally("https://github.com/tsubaie/omarchy-macos-theme/tree/main/studio") }
                    }
                    MacButton {
                        anchors.right: parent.right
                        visible: Object.values(window.status.features || {}).some(on => on)
                        // Gray, as System Settings draws its Delete… buttons: the
                        // question it opens is the red one.
                        text: "Remove macOS Theme…"
                        enabled: !backend.busy
                        reason: "Wait for what's running to finish"
                        onClicked: window.askRemove()
                    }
                }

                Text {
                    width: parent.width
                    text: "Not affiliated with Apple or Omarchy. macOS is a trademark of Apple Inc."
                    color: Qt.rgba(1, 1, 1, 0.45)
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
        onAccepted: { window.start("export", window.localPath(selectedFile)); backend.exportTo(window.localPath(selectedFile)) }
    }

    FileDialog {
        id: addBackgroundsDialog
        title: "Add Photos to Your Backgrounds"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Pictures (*.jpg *.jpeg *.png *.gif *.bmp *.webp *.JPG *.JPEG *.PNG *.GIF *.BMP *.WEBP)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: {
            const files = selectedFiles.map(f => window.localPath(f))
            window.start("add-backgrounds", files.length)
            backend.addBackgrounds(JSON.stringify(files))
        }
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
                text: "Your theme is set up to match it: its pieces, settings, dock, widgets and wallpapers. Your setup now is backed up first, so you can undo this." + window.droppedNote(),
                button: "Import",
                destructive: true,
                action: () => { window.discard(); window.start("import", file.split("/").pop()); backend.importFrom(file) }
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

            Accessible.role: Accessible.Dialog
            Accessible.name: window.confirm ? window.confirm.title : ""
            Accessible.description: window.confirm ? window.confirm.text : ""
            // Escape cancels; Return presses the focused button, which is the
            // default one when the sheet opens.
            Keys.onEscapePressed: window.confirm = null

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
                    text: window.confirm ? window.confirm.text + (window.sheetWaits ? "\n\nUpdate Now waits for what's running to finish." : "") : ""
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Item { width: 1; height: 6 }
                Row {
                    anchors.right: parent.right
                    spacing: 10
                    // Tab goes between its buttons and nowhere else while it asks.
                    // A third choice, as "Don't Save" is, when the question has one.
                    MacButton {
                        id: sheetAlternate
                        visible: !!window.confirm && !!window.confirm.alternate
                        text: window.confirm && window.confirm.alternate ? window.confirm.alternate : ""
                        KeyNavigation.tab: sheetCancel
                        KeyNavigation.backtab: sheetAction
                        onClicked: { const then = window.confirm.alternateAction; window.confirm = null; then() }
                    }
                    MacButton {
                        id: sheetCancel
                        text: "Cancel"
                        primary: !!window.confirm && !!window.confirm.destructive
                        KeyNavigation.tab: sheetAction
                        KeyNavigation.backtab: sheetAlternate.visible ? sheetAlternate : sheetAction
                        onClicked: window.confirm = null
                    }
                    MacButton {
                        id: sheetAction
                        text: window.confirm ? window.confirm.button : ""
                        primary: !window.confirm || !window.confirm.destructive
                        destructive: !!window.confirm && !!window.confirm.destructive
                        enabled: !window.sheetWaits
                        reason: window.sheetWaits ? "Wait for what's running to finish" : ""
                        KeyNavigation.tab: sheetAlternate.visible ? sheetAlternate : sheetCancel
                        KeyNavigation.backtab: sheetCancel
                        onClicked: window.acceptSheet()
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
    // A switch that marks one piece of the theme to install or remove.
    component PieceSwitch: MacSwitch {
        property string piece: ""
        readonly property bool changed: piece in window.pendingPieces
        checked: window.pieceOn(piece)
        enabled: !backend.busy && window.knownPiece(piece)
        reason: window.knownPiece(piece) ? "" : window.tooOld
        onToggled: on => window.markPiece(piece, on)
    }

    // Where a panel shows: at the bottom middle or at the top right.
    component PlaceChoice: MacSegmented {
        property string panel: ""
        property string needs: ""
        options: [{ value: "bottom", label: "Bottom" }, { value: "top", label: "Top" }]
        readonly property bool changed: panel in window.pendingPlaces
        value: window.placeValue(panel)
        enabled: !backend.busy && window.pieceOn(needs)
        reason: window.pieceOn(needs) ? "" : window.why(needs)
        onPicked: place => window.markPlace(panel, place)
    }

    // A switch for an on/off install.sh setting (1 on, 0 off), and what it is
    // when install.sh doesn't report it: on, unless a setting says otherwise.
    component SettingSwitch: MacSwitch {
        property string key: ""
        property int fallback: 1
        // The piece it waits on, as SettingSlider's.
        property string needs: "theme"
        readonly property bool changed: key in window.pendingSettings
        checked: window.settingValue(key, fallback) === 1
        enabled: !backend.busy && window.pieceOn(needs) && window.known(key)
        reason: !window.pieceOn(needs) ? window.why(needs) : window.known(key) ? "" : window.tooOld
        onToggled: on => window.markSetting(key, on ? 1 : 0, fallback)
    }

    // The picture at the top of each page: a macOS-like wallpaper in a card,
    // with what the page sets drawn over it, following its switches and
    // sliders as they move. Its content goes over the wallpaper.
    component Scene: Rectangle {
        id: scene
        default property alias content: stage.data
        property alias wallpaper: wallpaperImage
        // Blurred and dimmed behind everything, as the lock screen does.
        property bool frosted: false
        height: 168
        radius: 10
        color: "#1c1c1e"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: ShaderEffectSource {
                sourceItem: Rectangle { width: scene.width; height: scene.height; radius: scene.radius }
            }
        }

        Image {
            id: wallpaperImage
            anchors.fill: parent
            // The background showing on the desktop, as on macOS.
            source: window.backgroundSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 900
            visible: !scene.frosted
        }
        MultiEffect {
            anchors.fill: parent
            visible: scene.frosted
            source: wallpaperImage
            blurEnabled: true
            blur: 1
            blurMax: 48
            brightness: -0.15
        }
        Item { id: stage; anchors.fill: parent }
    }

    // Glass and blur as they will look, over the wallpaper: a window and a
    // browser, each as see-through as its slider says, the wallpaper behind
    // them blurred as strongly as the blur slider says. It follows the sliders
    // as they move; the desktop changes on Apply.
    component GlassPreview: Scene {
        id: preview
        readonly property real blurAmount: window.settingValue("blur", 10)

        MockWindow {
            x: parent.width * 0.06; y: 22; width: parent.width * 0.5; height: 128
            glass: window.settingValue("glass", 0.85); title: "Files"
            backdrop: preview.wallpaper; blurAmount: preview.blurAmount
        }
        MockWindow {
            x: parent.width * 0.44; y: 36; width: parent.width * 0.5; height: 116
            glass: window.settingValue("web-glass", 1); title: "Browser"
            backdrop: preview.wallpaper; blurAmount: preview.blurAmount
        }
    }

    // General: Files with striped rows, the Spotlight-like menu, and the
    // volume capsule and dictation pill where they show, each while it is on.
    component GeneralScene: Scene {
        id: general
        readonly property bool osdTop: window.placeValue("volume-hud") === "top"
        readonly property bool pillTop: window.placeValue("dictation-hud") === "top"

        MockWindow {
            x: 18; y: 18; width: parent.width * 0.42; height: 132
            glass: 0.92; title: "Files"; rows: window.pieceOn("rows")
            backdrop: general.wallpaper; blurAmount: 10
        }
        // The Spotlight-like menu: a wide search field with a magnifier.
        Rectangle {
            visible: window.pieceOn("wide-menu")
            x: parent.width * 0.5; y: 30; width: parent.width * 0.4; height: 30; radius: 9
            color: Qt.rgba(0.15, 0.15, 0.16, 0.92)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
            Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "⌕"; color: "#aeaeb2"; font.pixelSize: 15 }
            Text { x: 30; anchors.verticalCenter: parent.verticalCenter; text: "Search"; color: "#8e8e93"; font.pixelSize: 12 }
        }
        // The volume capsule: a speaker and a level.
        Rectangle {
            visible: window.pieceOn("osd")
            width: 120; height: 26; radius: 13
            x: general.osdTop ? parent.width - width - 14 : (parent.width - width) / 2 + 40
            y: general.osdTop ? 72 : parent.height - height - 14
            color: Qt.rgba(0.17, 0.17, 0.18, 0.92)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
            // A speaker: its box and cone.
            Canvas {
                x: 10; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 10
                onPaint: { const c = getContext("2d"); c.reset(); c.fillStyle = "white"
                    c.beginPath(); c.moveTo(0, 3); c.lineTo(3, 3); c.lineTo(7, 0); c.lineTo(7, 10); c.lineTo(3, 7); c.lineTo(0, 7); c.closePath(); c.fill()
                    c.strokeStyle = "white"; c.lineWidth = 1.2; c.beginPath(); c.arc(7, 5, 3.5, -0.9, 0.9); c.stroke() }
            }
            Rectangle { x: 30; anchors.verticalCenter: parent.verticalCenter; width: 78; height: 5; radius: 2.5; color: Qt.rgba(1, 1, 1, 0.25)
                Rectangle { width: parent.width * 0.62; height: parent.height; radius: 2.5; color: "white" } }
        }
        // The dictation pill: a red dot and a few bars.
        Rectangle {
            visible: window.pieceOn("dictation-hud")
            width: 64; height: 22; radius: 11
            x: general.pillTop ? parent.width - width - 14 : (parent.width - width) / 2 - 70
            y: general.pillTop ? 106 : parent.height - height - 16
            color: Qt.rgba(0.08, 0.08, 0.09, 0.92)
            Row {
                anchors.centerIn: parent; spacing: 3
                Rectangle { width: 7; height: 7; radius: 3.5; color: "#ff453a"; anchors.verticalCenter: parent.verticalCenter }
                Repeater { model: [6, 11, 8, 13, 7]; Rectangle { width: 3; height: modelData; radius: 1.5; color: "white"; anchors.verticalCenter: parent.verticalCenter } }
            }
        }
    }

    // Dock: icons as big as the Size slider says, the ones by the pointer
    // grown as far as Magnification says.
    component DockScene: Scene {
        id: dockScene
        readonly property real icon: window.settingValue("dock-size", 48) * 0.62
        readonly property real peak: window.settingValue("magnification", 1.75)
        readonly property int pointed: 3
        readonly property var tints: [["#5ac8fa", "#007aff"], ["#ffd60a", "#ff9f0a"], ["#30d158", "#248a3d"], ["#ff6482", "#ff2d55"],
            ["#bf5af2", "#8944ab"], ["#64d2ff", "#0a84ff"], ["#ff9f0a", "#ff6b00"], ["#d1d1d6", "#8e8e93"]]
        function scaleAt(i) {
            const d = Math.abs(i - pointed)
            return d >= 2.5 ? 1 : 1 + (peak - 1) * Math.cos(d / 2.5 * Math.PI / 2)
        }

        Rectangle {
            id: dockBar
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - 10
            width: icons.width + 16; height: dockScene.icon + 14; radius: 16
            color: Qt.rgba(0.2, 0.2, 0.22, 0.55)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16)
        }
        Row {
            id: icons
            anchors.horizontalCenter: dockBar.horizontalCenter
            anchors.bottom: dockBar.bottom; anchors.bottomMargin: 7
            spacing: 6
            Repeater {
                model: dockScene.tints
                Item {
                    required property var modelData
                    required property int index
                    width: dockScene.icon * dockScene.scaleAt(index)
                    height: width
                    anchors.bottom: parent.bottom
                    Rectangle {
                        anchors.fill: parent; radius: width * 0.225
                        gradient: Gradient {
                            GradientStop { position: 0; color: modelData[0] }
                            GradientStop { position: 1; color: modelData[1] }
                        }
                    }
                }
            }
        }
        // The pointer over the magnified icon.
        Text {
            text: "➤"; rotation: -120; color: "white"; style: Text.Outline; styleColor: "black"
            font.pixelSize: 16
            x: icons.x + icons.children[dockScene.pointed].x + icons.children[dockScene.pointed].width * 0.55
            y: dockBar.y + dockBar.height - 22
        }
    }

    // Lock screen: the date, a large clock, the account picture and the glass
    // password field, over the wallpaper blurred.
    component LockScene: Scene {
        frosted: true
        Column {
            anchors.horizontalCenter: parent.horizontalCenter; y: 16; spacing: 0
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(window.now, "dddd, MMMM d"); color: Qt.rgba(1, 1, 1, 0.85); font.pixelSize: 12; font.weight: Font.DemiBold }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatTime(window.now, "h:mm"); color: "white"; font.pixelSize: 52; font.weight: Font.Bold }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 62; spacing: 6
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 26; height: 26; radius: 13; color: "#8e8e93"
                Text { anchors.centerIn: parent; text: "●"; color: "#d1d1d6"; font.pixelSize: 11 } }
            Rectangle { width: 110; height: 20; radius: 10; color: Qt.rgba(1, 1, 1, 0.18)
                Text { anchors.centerIn: parent; text: "Enter Password"; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 9 } }
        }
    }

    // Widgets: the desktop widgets switched on, in a row on the wallpaper.
    component WidgetsScene: Scene {
        Row {
            anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Repeater {
                model: window.widgetsShown
                Rectangle {
                    required property string modelData
                    width: modelData === "calendar" || modelData === "playing" ? 150 : 110; height: 110; radius: 18
                    color: Qt.rgba(0.12, 0.12, 0.13, 0.72)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)

                    // Clock: a face with two hands at the time.
                    Item {
                        visible: modelData === "clock"; anchors.centerIn: parent; width: 84; height: 84
                        Rectangle { anchors.fill: parent; radius: 42; color: "white" }
                        Repeater { model: 12; Rectangle { required property int index; x: 41; y: 4; width: 2; height: 6; color: "#1c1c1e"; transform: Rotation { origin.x: 1; origin.y: 38; angle: index * 30 } } }
                        Rectangle { x: 41; y: 22; width: 3; height: 21; radius: 1.5; color: "#1c1c1e"; transform: Rotation { origin.x: 1.5; origin.y: 20; angle: (window.now.getHours() % 12 + window.now.getMinutes() / 60) * 30 } }
                        Rectangle { x: 41.5; y: 10; width: 2; height: 33; radius: 1; color: "#1c1c1e"; transform: Rotation { origin.x: 1; origin.y: 32; angle: window.now.getMinutes() * 6 } }
                    }
                    // Calendar: the month and its days, today ringed.
                    Column {
                        visible: modelData === "calendar"; x: 12; y: 10; spacing: 4
                        Text { text: Qt.formatDate(window.now, "MMMM").toUpperCase(); color: "#ff453a"; font.pixelSize: 9; font.weight: Font.Bold }
                        Grid {
                            columns: 7; columnSpacing: 6; rowSpacing: 3
                            Repeater {
                                model: 28
                                Text { required property int index; width: 12; horizontalAlignment: Text.AlignHCenter; text: index + 1; font.pixelSize: 8
                                    color: index + 1 === window.now.getDate() ? "#ff453a" : "white"; font.weight: index + 1 === window.now.getDate() ? Font.Bold : Font.Normal }
                            }
                        }
                    }
                    // Weather: a sun and a temperature.
                    Column {
                        visible: modelData === "weather"; x: 12; y: 12; spacing: 2
                        Text { text: "Weather"; color: "white"; font.pixelSize: 10; font.weight: Font.DemiBold }
                        Text { text: "24°"; color: "white"; font.pixelSize: 30; font.weight: Font.Light }
                        Text { text: "☀︎  Sunny"; color: "#ffd60a"; font.pixelSize: 10 }
                    }
                    // Now playing: artwork, a title and the controls.
                    Row {
                        visible: modelData === "playing"; x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                        Rectangle { width: 44; height: 44; radius: 8
                            gradient: Gradient { GradientStop { position: 0; color: "#ff375f" } GradientStop { position: 1; color: "#5e5ce6" } } }
                        Column {
                            spacing: 3; anchors.verticalCenter: parent.verticalCenter
                            Text { text: "Now Playing"; color: "white"; font.pixelSize: 10; font.weight: Font.DemiBold }
                            Text { text: "⏮  ⏵  ⏭"; color: Qt.rgba(1, 1, 1, 0.8); font.pixelSize: 11 }
                        }
                    }
                }
            }
        }
    }

    // Menu bar: the bar with the app name in bold and its icons, and Control
    // Center open from its icon, lit by a rounded pane.
    component MenuBarScene: Scene {
        id: barScene
        readonly property bool mac: window.pieceOn("menubar")
        Rectangle {
            width: parent.width; height: 24; color: Qt.rgba(0, 0, 0, 0.45)
            Row {
                x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 14
                Text { text: "⌘"; color: "white"; font.pixelSize: 12 }
                Text { text: barScene.mac ? "Files" : ""; color: "white"; font.pixelSize: 11; font.weight: Font.Bold }
                Text { text: "File   Edit   View   Go"; color: Qt.rgba(1, 1, 1, 0.85); font.pixelSize: 11; visible: barScene.mac }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                Text { text: "EN"; color: "white"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                // Wi-Fi: a wedge and two arcs.
                Canvas {
                    width: 14; height: 11; anchors.verticalCenter: parent.verticalCenter
                    onPaint: { const c = getContext("2d"); c.reset(); c.strokeStyle = "white"; c.fillStyle = "white"; c.lineWidth = 1.6; c.lineCap = "round"
                        c.beginPath(); c.moveTo(7, 10); c.arc(7, 10, 3, -Math.PI * 0.75, -Math.PI * 0.25); c.closePath(); c.fill()
                        for (const r of [6, 9]) { c.beginPath(); c.arc(7, 10.5, r, -Math.PI * 0.75, -Math.PI * 0.25); c.stroke() } }
                }
                Rectangle {
                    visible: barScene.mac
                    width: 30; height: 18; radius: 9; color: Qt.rgba(1, 1, 1, 0.22); anchors.verticalCenter: parent.verticalCenter
                    Column { anchors.centerIn: parent; spacing: 2
                        Repeater { model: 2; Rectangle { width: 12; height: 5; radius: 2.5; color: "transparent"; border.width: 1; border.color: "white" } } }
                }
                Text { text: Qt.formatDateTime(window.now, "ddd h:mm AP"); color: "white"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        // Control Center, open under its icon.
        Rectangle {
            visible: barScene.mac
            anchors.right: parent.right; anchors.rightMargin: 60; y: 30
            width: 170; height: 126; radius: 14
            color: Qt.rgba(0.12, 0.12, 0.13, 0.85); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
            Grid {
                x: 8; y: 8; columns: 2; spacing: 6
                Repeater {
                    model: ["Wi-Fi", "Bluetooth", "AirDrop", "Focus"]
                    Rectangle {
                        required property string modelData
                        width: 74; height: 30; radius: 15; color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.08)
                        Rectangle { x: 4; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: 11; color: modelData === "Focus" ? Qt.rgba(1, 1, 1, 0.12) : "#0a84ff" }
                        Text { x: 30; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: "white"; font.pixelSize: 8; font.weight: Font.DemiBold }
                    }
                }
            }
            Rectangle {
                x: 8; y: 82; width: 154; height: 36; radius: 12; color: Qt.rgba(1, 1, 1, 0.06)
                Text { x: 8; y: 4; text: "Sound"; color: "white"; font.pixelSize: 8; font.weight: Font.DemiBold }
                Rectangle { x: 8; y: 22; width: 138; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.2)
                    Rectangle { width: parent.width * 0.6; height: 4; radius: 2; color: "white" } }
            }
        }
    }

    // Home: the whole theme at a glance, a desktop with the menu bar, a window
    // at its glass, the clock widget and the dock at its size.
    component HomeScene: Scene {
        id: home
        height: 200
        Rectangle {
            width: parent.width; height: 22; color: Qt.rgba(0, 0, 0, 0.4)
            Row {
                x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 14
                Text { text: "⌘"; color: "white"; font.pixelSize: 11 }
                Text { text: "Files"; color: "white"; font.pixelSize: 10; font.weight: Font.Bold }
                Text { text: "File   Edit   View   Go"; color: Qt.rgba(1, 1, 1, 0.85); font.pixelSize: 10 }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                Canvas {
                    width: 14; height: 11; anchors.verticalCenter: parent.verticalCenter
                    onPaint: { const c = getContext("2d"); c.reset(); c.strokeStyle = "white"; c.fillStyle = "white"; c.lineWidth = 1.6; c.lineCap = "round"
                        c.beginPath(); c.moveTo(7, 10); c.arc(7, 10, 3, -Math.PI * 0.75, -Math.PI * 0.25); c.closePath(); c.fill()
                        for (const r of [6, 9]) { c.beginPath(); c.arc(7, 10.5, r, -Math.PI * 0.75, -Math.PI * 0.25); c.stroke() } }
                }
                Rectangle {
                    width: 26; height: 16; radius: 8; color: Qt.rgba(1, 1, 1, 0.18); anchors.verticalCenter: parent.verticalCenter
                    Column { anchors.centerIn: parent; spacing: 2
                        Repeater { model: 2; Rectangle { width: 11; height: 4; radius: 2; color: "transparent"; border.width: 1; border.color: "white" } } }
                }
                Text { text: Qt.formatDateTime(window.now, "ddd h:mm AP"); color: "white"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        MockWindow {
            x: parent.width * 0.08; y: 34; width: parent.width * 0.5; height: 96
            glass: window.settingValue("glass", 0.85); title: "Files"; rows: window.pieceOn("rows")
            backdrop: home.wallpaper; blurAmount: window.settingValue("blur", 10)
        }
        // The clock widget.
        Rectangle {
            x: parent.width - width - 22; y: 36; width: 84; height: 84; radius: 16
            color: Qt.rgba(0.12, 0.12, 0.13, 0.72); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
            Item {
                anchors.centerIn: parent; width: 64; height: 64
                Rectangle { anchors.fill: parent; radius: 32; color: "white" }
                Rectangle { x: 31; y: 17; width: 3; height: 16; radius: 1.5; color: "#1c1c1e"; transform: Rotation { origin.x: 1.5; origin.y: 15; angle: (window.now.getHours() % 12 + window.now.getMinutes() / 60) * 30 } }
                Rectangle { x: 31.5; y: 8; width: 2; height: 25; radius: 1; color: "#1c1c1e"; transform: Rotation { origin.x: 1; origin.y: 24; angle: window.now.getMinutes() * 6 } }
            }
        }
        // The dock.
        Rectangle {
            id: homeDock
            readonly property real icon: window.settingValue("dock-size", 48) * 0.48
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - 8
            width: homeIcons.width + 14; height: icon + 12; radius: 13
            color: Qt.rgba(0.2, 0.2, 0.22, 0.55); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16)
            Row {
                id: homeIcons
                anchors.centerIn: parent; spacing: 5
                Repeater {
                    model: [["#5ac8fa", "#007aff"], ["#ffd60a", "#ff9f0a"], ["#30d158", "#248a3d"], ["#ff6482", "#ff2d55"], ["#bf5af2", "#8944ab"], ["#d1d1d6", "#8e8e93"]]
                    Rectangle {
                        required property var modelData
                        width: homeDock.icon; height: width; radius: width * 0.225
                        gradient: Gradient { GradientStop { position: 0; color: modelData[0] } GradientStop { position: 1; color: modelData[1] } }
                    }
                }
            }
        }
    }

    // Backups: the latest snapshots as cards stacked back to front, each with
    // its date.
    component BackupsScene: Scene {
        Repeater {
            model: Math.min(3, Math.max(1, window.backups.length))
            Rectangle {
                required property int index
                readonly property var backup: window.backups[index] || null
                width: 190; height: 104; radius: 12
                x: parent.width / 2 - width / 2 + (index - 1) * 46
                y: 34 - index * 6 + 12
                z: 3 - index
                scale: 1 - index * 0.06
                color: Qt.rgba(0.14 - index * 0.02, 0.14 - index * 0.02, 0.15 - index * 0.02, 1); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                Row { x: 10; y: 9; spacing: 5
                    Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; Rectangle { width: 7; height: 7; radius: 3.5; color: modelData } } }
                Text { x: 12; y: 26; text: "↺"; color: "#0a84ff"; font.pixelSize: 28 }
                Column {
                    x: 50; y: 30; spacing: 3; width: parent.width - 60
                    Text { width: parent.width; elide: Text.ElideRight; text: backup ? (backup.original ? "Before macOS theme" : backup.note) : "Backups"; color: "white"; font.pixelSize: 10; font.weight: Font.DemiBold }
                    Text { width: parent.width; elide: Text.ElideRight; text: backup ? window.when(backup.created) : "Taken before every change"; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 9 }
                }
            }
        }
    }

    // One window of the preview: the wallpaper behind it blurred, then its
    // body and title bar at its glass.
    component MockWindow: Item {
        id: mock
        property real glass: 1
        property string title: ""
        // What shows through it, and how strongly it is blurred (0 to 20).
        property Item backdrop: null
        property real blurAmount: 0
        // Rows striped as in Files, instead of plain lines.
        property bool rows: false
        // Its title bar and traffic lights, as the settings have them.
        readonly property bool titleBar: window.settingValue("title-bars", 1) === 1
        readonly property real light: window.settingValue("traffic-lights", 14) * 0.65
        readonly property real barHeight: titleBar ? Math.max(24, light + 13) : 0
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: ShaderEffectSource {
                sourceItem: Rectangle { width: mock.width; height: mock.height; radius: 9 }
            }
        }

        MultiEffect {
            anchors.fill: parent
            visible: mock.glass < 1
            source: ShaderEffectSource {
                sourceItem: mock.backdrop
                sourceRect: Qt.rect(mock.x, mock.y, mock.width, mock.height)
            }
            blurEnabled: mock.blurAmount > 0
            blur: Math.min(1, mock.blurAmount / 20)
            blurMax: 48
        }
        Rectangle { anchors.fill: parent; color: "#262628"; opacity: mock.glass }
        Rectangle {
            visible: mock.titleBar
            width: parent.width; height: mock.barHeight
            color: "#323232"; opacity: mock.glass
        }
        Row {
            visible: mock.titleBar
            x: 10; anchors.verticalCenter: parent.top; anchors.verticalCenterOffset: mock.barHeight / 2
            spacing: mock.light * 0.6
            Repeater {
                model: ["#ff5f57", "#febc2e", "#28c840"]
                Rectangle { width: mock.light; height: width; radius: width / 2; color: modelData }
            }
        }
        Text {
            visible: mock.titleBar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.top; anchors.verticalCenterOffset: mock.barHeight / 2
            text: mock.title; color: "#e5e5e7"; font.pixelSize: 11; font.weight: Font.DemiBold
        }
        Column {
            visible: !mock.rows
            x: 14; y: mock.barHeight + 14; spacing: 9
            Repeater {
                model: [0.7, 0.5, 0.62, 0.4]
                Rectangle { width: mock.width * modelData; height: 7; radius: 3.5; color: Qt.rgba(1, 1, 1, 0.22) }
            }
        }
        Column {
            visible: mock.rows
            x: 6; y: mock.barHeight + 6; width: mock.width - 12
            Repeater {
                model: 6
                Rectangle {
                    required property int index
                    width: parent.width; height: 16; radius: 4
                    color: index % 2 ? "transparent" : Qt.rgba(1, 1, 1, 0.06)
                    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 8; radius: 2; color: "#5ac8fa" }
                    Rectangle { x: 24; anchors.verticalCenter: parent.verticalCenter; width: parent.width * (0.35 + (index % 3) * 0.1); height: 5; radius: 2.5; color: Qt.rgba(1, 1, 1, 0.3) }
                }
            }
        }
    }

    // A slider for one install.sh setting, set when let go.
    component SettingSlider: MacSlider {
        id: settingSlider
        // The value is drawn to the left of the slider; the row keeps room for it.
        readonly property int leading: 48
        property string key: ""
        property real fallback: 0
        // 0 for whole-number settings such as blur.
        property int decimals: 2
        property string needs: "theme"
        // False while another setting makes this one moot, and why.
        property bool available: true
        property string unavailable: ""
        width: 180
        step: decimals === 0 ? 1 : 0.05
        readonly property bool changed: key in window.pendingSettings
        value: window.settingValue(key, fallback)
        enabled: !backend.busy && window.pieceOn(needs) && available && window.known(key)
        reason: !window.pieceOn(needs) ? window.why(needs) : !window.known(key) ? window.tooOld : available ? "" : unavailable
        function take(v) {
            window.markSetting(key, decimals === 0 ? Math.round(v) : v, fallback)
            if (window.previewable.includes(key) && !previewSoon.running) previewSoon.start()
        }
        onDragged: v => take(v)
        onMoved: v => take(v)

        // Shown as it moves, at most every few frames while the knob is held.
        Timer {
            id: previewSoon
            interval: 80
            onTriggered: backend.preview(settingSlider.key, window.settingValue(settingSlider.key, settingSlider.fallback))
        }

        Text {
            anchors.right: parent.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: parent.shown.toFixed(parent.decimals)
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 12
        }
    }

    property bool showDetails: false

    // Counts the seconds an action takes, for the busy line.
    Timer {
        running: backend.busy
        interval: 1000
        repeat: true
        onTriggered: window.elapsed++
    }

    // A small spinner, as macOS shows while something works.
    component Spinner: Canvas {
        id: spinner
        width: 14
        height: 14
        onPaint: {
            const c = getContext("2d")
            c.reset()
            c.lineWidth = 2
            c.strokeStyle = Qt.rgba(1, 1, 1, 0.7)
            c.beginPath()
            c.arc(7, 7, 5.5, 0, Math.PI * 1.5)
            c.stroke()
        }
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: spinner.visible
        }
    }

    // A message across the page: what happened, an optional next step, all
    // of it behind Show Details when there is more, and a way to put it away.
    // A dark card, as macOS draws its notifications, its kind told by a small
    // colored badge rather than colored text. A timed one (timeout > 0) says
    // so with a ring draining around its close button, and holds still while
    // the pointer or the keyboard is on it, so Undo stays in reach.
    // An alert, so a screen reader reads it as one.
    component Banner: Rectangle {
        id: banner
        property color tint
        property string glyph: ""
        property string text: ""
        property string more: ""
        property string details: ""
        // A button for what to do next, such as Undo.
        property string actionText: ""
        // How long it stays, in ms; 0 until dismissed.
        property int timeout: 0
        // The share of the time left, 1 down to 0.
        property real timeLeft: 1
        signal dismissed()
        signal acted()

        width: parent ? parent.width : 0
        height: bannerColumn.height + 24
        radius: 10
        color: "#2a2a2c"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text + (more ? " " + more : "")

        // Each new message starts the time again.
        onTextChanged: if (visible) countdown.restart()
        onVisibleChanged: if (visible) countdown.restart(); else countdown.stop()
        NumberAnimation {
            id: countdown
            target: banner
            property: "timeLeft"
            from: 1
            to: 0
            duration: banner.timeout
            paused: running && (hover.hovered || banner.activeFocus || bannerButtons.activeFocusInside)
            onFinished: if (banner.timeout > 0 && banner.visible) banner.dismissed()
        }
        HoverHandler { id: hover }

        Column {
            id: bannerColumn
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 6

            Item {
                width: parent.width
                height: Math.max(bannerText.height, bannerButtons.height)

                // The kind at a glance: ✓ done, ! wrong or worth knowing.
                Rectangle {
                    id: badge
                    y: (Math.min(bannerText.height, 20) - height) / 2 + 1
                    width: 18
                    height: 18
                    radius: 9
                    color: banner.tint
                    Text {
                        anchors.centerIn: parent
                        text: banner.glyph
                        color: "#1c1c1e"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                }
                Text {
                    id: bannerText
                    x: badge.width + 10
                    width: parent.width - x - bannerButtons.width - 12
                    text: banner.text
                    color: Qt.rgba(1, 1, 1, 0.92)
                    font.pixelSize: 13
                    lineHeight: 1.15
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }
                Row {
                    id: bannerButtons
                    // Any of its buttons focused, so the countdown waits.
                    readonly property bool activeFocusInside: detailsButton.activeFocus || actButton.activeFocus || closeButton.activeFocus
                    anchors.right: parent.right
                    spacing: 8
                    MacButton {
                        id: detailsButton
                        visible: banner.details !== ""
                        text: window.showDetails ? "Hide Details" : "Show Details"
                        onClicked: window.showDetails = !window.showDetails
                    }
                    MacButton {
                        id: actButton
                        visible: banner.actionText !== ""
                        text: banner.actionText
                        onClicked: banner.acted()
                    }
                    // ×, with the time left drawn around it when it goes by itself.
                    Item {
                        id: closeButton
                        width: 24
                        height: 24
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Dismiss"
                        Accessible.onPressAction: banner.dismissed()
                        Keys.onSpacePressed: banner.dismissed()
                        Keys.onReturnPressed: banner.dismissed()
                        Keys.onEnterPressed: banner.dismissed()

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: closePress.pressed ? Qt.rgba(1, 1, 1, 0.16) : closeHover.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        }
                        Canvas {
                            id: ring
                            anchors.fill: parent
                            visible: banner.timeout > 0
                            readonly property real timeLeft: banner.timeLeft
                            onTimeLeftChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                ctx.lineWidth = 2
                                ctx.lineCap = "round"
                                const c = width / 2, rad = c - 1.5
                                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12)
                                ctx.beginPath(); ctx.arc(c, c, rad, 0, 2 * Math.PI); ctx.stroke()
                                // From twelve o'clock, emptying clockwise.
                                ctx.strokeStyle = banner.tint
                                ctx.beginPath()
                                ctx.arc(c, c, rad, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * timeLeft)
                                ctx.stroke()
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: Qt.rgba(1, 1, 1, 0.75)
                            font.pixelSize: 15
                        }
                        FocusRing { controlRadius: 12 }
                        HoverHandler { id: closeHover }
                        MouseArea {
                            id: closePress
                            anchors.fill: parent
                            onClicked: banner.dismissed()
                        }
                    }
                }
            }
            Text {
                visible: banner.more !== ""
                x: badge.width + 10
                width: parent.width - x
                text: banner.more
                color: Qt.rgba(1, 1, 1, 0.6)
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            // All of it, selectable to copy into a bug report.
            TextEdit {
                visible: banner.details !== "" && window.showDetails
                width: parent.width
                text: banner.details
                readOnly: true
                selectByMouse: true
                color: Qt.rgba(1, 1, 1, 0.75)
                font.family: "monospace"
                font.pixelSize: 11
                wrapMode: TextEdit.Wrap
            }
        }
    }

    // A background to choose: its picture with rounded corners, ringed in
    // blue while it's the one showing. A click, Space or Return shows it.
    component BackgroundTile: Rectangle {
        id: tile
        property string file: ""
        readonly property bool showing: file === window.backgrounds.current
        width: 152
        height: 96
        radius: 8
        color: "#1c1c1e"
        enabled: !backend.busy && window.installed("theme")
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: file.split("/").pop() + (showing ? ", the one showing" : "")
        Accessible.onPressAction: window.chooseBackground(file)
        Keys.onSpacePressed: window.chooseBackground(file)
        Keys.onReturnPressed: window.chooseBackground(file)

        Image {
            anchors.fill: parent
            source: window.fileUrl(tile.file)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 320
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: ShaderEffectSource {
                    sourceItem: Rectangle { width: tile.width; height: tile.height; radius: tile.radius }
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: tile.radius + 4
            color: "transparent"
            border.width: 2
            border.color: "#0a84ff"
            visible: tile.showing
        }
        FocusRing { controlRadius: tile.radius }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: window.chooseBackground(tile.file)
        }
    }

    // An update row's button: the next step's name, and while it asks,
    // "Checking…" with a spinner, at a width that holds the row still.
    component UpdateButton: MacButton {
        id: update
        property bool checking: false
        // The label when it isn't checking.
        property string next: ""
        text: checking ? "Checking…" : next
        reason: ""
        width: Math.max(112, measure.width + 24 + (checking ? 36 : 0))
        Text { id: measure; visible: false; text: update.text; font.pixelSize: 13 }
        Spinner {
            visible: update.checking
            x: 10
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // The macOS push button: gray, rounded, white text; blue for the default
    // action, red for one that replaces or removes something.
    component MacButton: Rectangle {
        id: button
        property string text: ""
        property bool primary: false
        property bool destructive: false
        // The one thing a page asks for, bigger.
        property bool large: false
        property string reason: ""
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.description: enabled ? "" : reason
        Accessible.onPressAction: if (enabled) clicked()
        signal clicked()
        // Tab reaches it; Space or Return presses it.
        activeFocusOnTab: true
        Keys.onSpacePressed: clicked()
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        width: label.width + (large ? 40 : 24)
        height: large ? 34 : 24
        radius: large ? 8 : 6
        opacity: enabled ? 1 : 0.4
        // Blues and reds dark enough for white text to read (4.5:1 and up).
        color: destructive ? (press.pressed ? "#b00012" : "#d70015")
            : primary ? (press.pressed ? "#0057b8" : "#0064d1")
            : (press.pressed ? "#5a5a5e" : "#48484c")

        FocusRing { controlRadius: 6 }

        Text {
            id: label
            anchors.centerIn: parent
            text: parent.text
            color: "white"
            font.pixelSize: button.large ? 14 : 13
            font.weight: button.large ? Font.DemiBold : Font.Normal
        }

        MouseArea {
            id: press
            anchors.fill: parent
            enabled: parent.enabled
            onClicked: parent.clicked()
        }
    }
}
