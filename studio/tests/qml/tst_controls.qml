// The keyboard on Studio's controls: Tab reaches each one, and its keys do
// what a click or a drag would. Run with:
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
import QtQuick
import QtTest
import "../../qml"

Item {
    id: top
    width: 400
    height: 200

    Column {
        MacSwitch { id: toggle; onToggled: on => checked = on }
        MacSlider { id: slider; from: 0; to: 1; value: 0.5; step: 0.1; onMoved: v => value = v }
        MacSegmented {
            id: choice
            options: [{ value: "bottom", label: "Bottom" }, { value: "top", label: "Top" }]
            value: "bottom"
            onPicked: v => value = v
        }
        MacSwitch { id: off; enabled: false; reason: "Turn on the theme to change this" }
        SettingRow {
            id: row
            label: "Window glass"
            MacSwitch { id: marked; property bool changed: false }
        }
    }

    TestCase {
        name: "Controls"
        when: windowShown

        function test_tab_reaches_each_and_skips_a_disabled_one() {
            toggle.forceActiveFocus()
            keyClick(Qt.Key_Tab)
            verify(slider.activeFocus)
            keyClick(Qt.Key_Tab)
            verify(choice.activeFocus)
            keyClick(Qt.Key_Tab)
            verify(!off.activeFocus)
        }

        function test_space_flips_a_switch() {
            toggle.checked = false
            toggle.forceActiveFocus()
            keyClick(Qt.Key_Space)
            verify(toggle.checked)
            keyClick(Qt.Key_Return)
            verify(!toggle.checked)
        }

        function test_arrows_move_a_slider_within_its_range() {
            slider.value = 0.5
            slider.forceActiveFocus()
            keyClick(Qt.Key_Right)
            fuzzyCompare(slider.value, 0.6, 0.001)
            keyClick(Qt.Key_Left)
            keyClick(Qt.Key_Left)
            fuzzyCompare(slider.value, 0.4, 0.001)
            keyClick(Qt.Key_End)
            compare(slider.value, 1)
            keyClick(Qt.Key_Right)
            compare(slider.value, 1)
            keyClick(Qt.Key_Home)
            compare(slider.value, 0)
        }

        function test_arrows_pick_a_segment() {
            choice.value = "bottom"
            choice.forceActiveFocus()
            keyClick(Qt.Key_Right)
            compare(choice.value, "top")
            keyClick(Qt.Key_Right)
            compare(choice.value, "top")
            keyClick(Qt.Key_Left)
            compare(choice.value, "bottom")
        }

        function test_a_disabled_control_says_why() {
            verify(!off.enabled)
            compare(off.Accessible.description, "Turn on the theme to change this")
        }

        function test_a_row_marks_a_change_its_control_reports() {
            verify(!row.changed)
            marked.changed = true
            verify(row.changed)
        }
    }
}
