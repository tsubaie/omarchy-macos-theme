// Real pointer tests for the menu bar's arrangement: presses, drags and
// releases on the handles, and the switches. Run with:
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
import QtQuick
import QtTest
import "../../qml"

Item {
    id: top
    width: 600
    height: 900

    Flickable {
        id: page
        anchors.fill: parent
        contentHeight: list.height + 40

        BarItems {
            id: list
            width: 560
            flickable: page
            names: ({ menu: "Menu", workspaces: "Workspaces", clock: "Clock", weather: "Weather", network: "Network", keyboard: "Keyboard", media: "Media" })
            onChanged: g => { spy.last = g; groups = g }
        }
    }

    QtObject {
        id: spy
        property var last: null
    }

    TestCase {
        name: "BarItems"
        when: windowShown

        readonly property var start: ({ left: ["menu", "workspaces"], center: ["clock", "weather"], right: ["network", "keyboard"], hidden: ["media"] })

        function init() {
            page.contentY = 0
            spy.last = null
            list.groups = JSON.parse(JSON.stringify(start))
            wait(50)
        }

        function find(name) {
            const item = findChild(list, name)
            verify(item, name)
            return item
        }

        // Drags a row's handle so its middle passes over `target`, at `where`
        // (0 top … 1 bottom) of it, in small steps, as a hand would.
        function drag(id, target, where) {
            const grip = find("grip-" + id)
            const from = grip.mapToItem(top, grip.width / 2, grip.height / 2)
            const row = find("row-" + id)
            const fromRow = row.mapToItem(top, 0, row.height / 2)
            const to = target.mapToItem(top, 0, target.height * where)
            const dy = to.y - fromRow.y
            mousePress(top, from.x, from.y)
            const steps = 20
            for (let i = 1; i <= steps; i++) {
                mouseMove(top, from.x, from.y + dy * i / steps)
                wait(5)
            }
            mouseRelease(top, from.x, from.y + dy)
            wait(30)
        }

        // The keyboard: Down on a handle moves the item a place, past its
        // group's end into the next, and the handle keeps the focus.
        function test_keyboard_moves_an_item_and_keeps_the_focus() {
            find("grip-workspaces").forceActiveFocus()
            keyClick(Qt.Key_Down)
            compare(spy.last.left, ["menu"])
            compare(spy.last.center, ["workspaces", "clock", "weather"])
            tryVerify(() => findChild(list, "grip-workspaces") && findChild(list, "grip-workspaces").activeFocus)
            keyClick(Qt.Key_Up)
            compare(spy.last.left, ["menu", "workspaces"])
            keyClick(Qt.Key_Up)
            compare(spy.last.left, ["workspaces", "menu"])
        }

        function test_move_down_within_a_group() {
            drag("menu", find("row-workspaces"), 0.8)
            verify(spy.last)
            compare(spy.last.left, ["workspaces", "menu"])
        }

        function test_move_up_within_a_group() {
            drag("weather", find("row-clock"), 0.2)
            compare(spy.last.center, ["weather", "clock"])
        }

        function test_dropping_on_itself_changes_nothing() {
            drag("clock", find("row-clock"), 0.5)
            verify(spy.last === null || JSON.stringify(spy.last.center) === JSON.stringify(["clock", "weather"]))
        }

        function test_move_into_another_group() {
            drag("clock", find("row-keyboard"), 0.8)
            compare(spy.last.center, ["weather"])
            compare(spy.last.right, ["network", "keyboard", "clock"])
        }

        function test_drag_to_hidden_and_back() {
            drag("weather", find("row-media"), 0.8)
            compare(spy.last.hidden, ["media", "weather"])
            // The rows are rebuilt after a change; let the old ones go first.
            wait(200)
            drag("media", find("row-menu"), 0.2)
            compare(spy.last.left, ["media", "menu", "workspaces"])
            compare(spy.last.hidden, ["weather"])
        }

        function test_drop_into_an_empty_group() {
            list.groups = { left: [], center: ["clock"], right: ["network"], hidden: [] }
            wait(50)
            const empty = findChild(list, "group-left")
            drag("clock", empty, 0.75)
            compare(spy.last.left, ["clock"])
            compare(spy.last.center, [])
        }

        function test_letting_go_over_nothing_changes_nothing() {
            const grip = find("grip-menu")
            const from = grip.mapToItem(top, grip.width / 2, grip.height / 2)
            mousePress(top, from.x, from.y)
            for (let i = 1; i <= 10; i++) { mouseMove(top, from.x + 0, from.y - 4 * i); wait(5) }
            mouseRelease(top, from.x, from.y - 40)
            wait(30)
            compare(spy.last, null)
        }

        function test_the_page_holds_still_under_a_drag() {
            const before = page.contentY
            drag("menu", find("row-workspaces"), 0.8)
            compare(page.contentY, before)
        }

        // The page scrolls with the wheel before a drag, and again after one.
        function test_the_page_scrolls_before_and_after_a_drag() {
            top.height = 300
            wait(50)
            page.contentY = 0
            verify(page.interactive, "scrollable at first")
            mouseWheel(top, 100, 150, 0, -360)
            wait(400)
            verify(page.contentY > 0, "the wheel scrolls before a drag: " + page.contentY)
            page.contentY = 0
            wait(30)
            drag("menu", find("row-workspaces"), 0.8)
            wait(100)
            compare(list.holding, false)
            verify(page.interactive, "scrollable after a drag")
            mouseWheel(top, 100, 150, 0, -360)
            wait(400)
            verify(page.contentY > 0, "the wheel scrolls after a drag: " + page.contentY)
            top.height = 900
        }

        function test_switch_hides_and_shows() {
            mouseClick(find("switch-weather"))
            compare(spy.last.hidden, ["media", "weather"])
            list.groups = spy.last
            wait(30)
            mouseClick(find("switch-media"))
            compare(spy.last.right, ["network", "keyboard", "media"])
        }

        // A short window scrolled to the bottom: holding a dragged row at the
        // top edge scrolls the page up until the first row is reachable.
        function test_holding_near_the_edge_scrolls_the_page() {
            top.height = 300
            wait(50)
            page.contentY = page.contentHeight - page.height
            wait(30)
            const startY = page.contentY
            verify(startY > 100, "the page needs to scroll for this test: " + startY)
            const grip = find("grip-media")
            const from = grip.mapToItem(top, grip.width / 2, grip.height / 2)
            mousePress(top, from.x, from.y)
            const steps = 20
            for (let i = 1; i <= steps; i++) { mouseMove(top, from.x, from.y + (10 - from.y) * i / steps); wait(5) }
            // Hold at the edge while the page scrolls up.
            for (let i = 0; i < 120 && page.contentY > 0; i++) { mouseMove(top, from.x, 10 + (i % 2)); wait(16) }
            verify(page.contentY < startY, "the page scrolled up")
            compare(page.contentY, 0)
            // Now over the first row's upper half.
            const first = find("row-menu").mapToItem(top, 0, find("row-menu").height * 0.25)
            for (let i = 1; i <= 10; i++) { mouseMove(top, from.x, 10 + (first.y - 10) * i / 10); wait(5) }
            mouseRelease(top, from.x, first.y)
            wait(30)
            top.height = 900
            compare(spy.last.left, ["media", "menu", "workspaces"])
        }

        function test_drags_in_a_row_each_land() {
            drag("menu", find("row-keyboard"), 0.8)
            compare(spy.last.right, ["network", "keyboard", "menu"])
            compare(spy.last.left, ["workspaces"])
            wait(100)
            drag("network", find("row-workspaces"), 0.2)
            compare(spy.last.left, ["network", "workspaces"])
            compare(spy.last.right, ["keyboard", "menu"])
            wait(100)
            drag("clock", find("row-media"), 0.8)
            compare(spy.last.hidden, ["media", "clock"])
            compare(spy.last.center, ["weather"])
            const all = [].concat(spy.last.left, spy.last.center, spy.last.right, spy.last.hidden).sort()
            compare(all, ["clock", "keyboard", "media", "menu", "network", "weather", "workspaces"])
        }
    }
}
