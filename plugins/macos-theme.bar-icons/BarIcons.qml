import QtQuick
import Quickshell
import "Icons.js" as Icons

// macOS style icons on Omarchy's own Network, Bluetooth, Audio and Display
// widgets, and a chat bot on its Agents widget. They stay Omarchy's widgets,
// updates and all: this only hands each one's bar button an icon for the
// glyph it picked, and Omarchy's glyph comes back for any it shows that has
// no icon here, or when this is removed. It sits on the bar, unseen, as that
// is where the widgets are within reach.
Item {
    id: root

    // Set by the bar; unused, but a bar widget takes them.
    property var bar: null
    property string moduleName: ""
    property var settings: ({})

    readonly property var widgets: ["omarchy.network", "omarchy.bluetooth", "omarchy.audio", "omarchy.monitor", "omarchy.agents"]
    property var patched: []
    // Omdrop draws its own icon rather than a glyph: its button gets AirDrop's,
    // and its own comes back when this is removed.
    readonly property string omdrop: "netmojo.omdrop"
    property var omdropButtons: []

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    // The bar surface this sits on.
    function surface() {
        var item = root
        while (item.parent) item = item.parent
        return item
    }

    // A widget's bar button: the item in it taking an iconComponent.
    function buttonIn(item) {
        if (item !== root && "iconComponent" in item && "text" in item) return item
        for (var i = 0; i < item.children.length; i++) {
            var found = buttonIn(item.children[i])
            if (found) return found
        }
        return null
    }

    function scan(item) {
        if ("moduleName" in item && item.moduleName === root.omdrop) {
            var own = buttonIn(item)
            if (own && !root.omdropButtons.some(function(o) { return o.button === own })) {
                root.omdropButtons.push({ button: own, original: own.iconComponent })
                own.iconComponent = airdrop
            }
            return
        }
        if ("moduleName" in item && root.widgets.indexOf(item.moduleName) >= 0 && item !== root) {
            var button = buttonIn(item)
            if (button && root.patched.indexOf(button) < 0) {
                button.iconComponent = Qt.binding(function() { return Icons.svg(button.text, "#fff") ? icon : null })
                root.patched.push(button)
            }
            return
        }
        for (var i = 0; i < item.children.length; i++) scan(item.children[i])
    }

    // Widgets are loaded again as they move about the bar; a look now and
    // then finds the new ones.
    Timer {
        interval: 1500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.patched = root.patched.filter(function(b) { try { return !!b.parent } catch (e) { return false } })
            root.omdropButtons = root.omdropButtons.filter(function(o) { try { return !!o.button.parent } catch (e) { return false } })
            root.scan(root.surface())
        }
    }

    Component.onDestruction: {
        for (var i = 0; i < patched.length; i++) {
            try { patched[i].iconComponent = null } catch (e) {}
        }
        for (var j = 0; j < omdropButtons.length; j++) {
            try { omdropButtons[j].button.iconComponent = omdropButtons[j].original } catch (e) {}
        }
    }

    Component {
        id: icon

        Image {
            // The button this draws in, for its glyph and its colors.
            readonly property var button: {
                var item = parent
                while (item && !("iconComponent" in item)) item = item.parent
                return item
            }
            readonly property color tint: !button ? "white"
                : (button.active && button.useActiveColor ? button.activeColor : button.foreground)
            // Drawn at exactly the pixels it covers: rendered large and scaled
            // down, or at a size between pixels (18 points is 22.5 pixels at a
            // 1.25 scale), an icon's edges come out soft. Qt renders an SVG at
            // its source size times the screen's scale.
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            width: Math.round(18 * dpr) / dpr
            height: width
            sourceSize: Qt.size(width, height)
            smooth: true
            source: button ? Icons.source(button.text, tint.toString()) : ""
        }
    }

    // AirDrop's icon on Omdrop's button, in Omdrop's own color for its state,
    // dimmed while it can't be used, as its own is struck through.
    Component {
        id: airdrop

        Image {
            readonly property var button: {
                var item = parent
                while (item && !("iconComponent" in item)) item = item.parent
                return item
            }
            readonly property var widget: button ? button.parent : null
            readonly property color tint: widget && widget.barIconColor !== undefined ? widget.barIconColor
                : button ? button.foreground : "white"
            // Drawn at exactly the pixels it covers: rendered large and scaled
            // down, or at a size between pixels (18 points is 22.5 pixels at a
            // 1.25 scale), an icon's edges come out soft. Qt renders an SVG at
            // its source size times the screen's scale.
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            width: Math.round(18 * dpr) / dpr
            height: width
            sourceSize: Qt.size(width, height)
            smooth: true
            opacity: widget && widget.usable === false ? 0.45 : 1
            source: Icons.source("airdrop", tint.toString())
        }
    }
}
