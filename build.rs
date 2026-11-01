use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("org.omarchy.macosstudio")
            .qml_file("qml/Main.qml")
            .qml_file("qml/MacSwitch.qml")
            .qml_file("qml/MacSlider.qml")
            .qml_file("qml/Group.qml")
            .qml_file("qml/SettingRow.qml")
            .qml_file("qml/SearchField.qml")
            .qml_file("qml/TrafficLights.qml")
            .qml_file("qml/BarItems.qml"),
    )
    // Logic the QML imports, next to it, so node can test it too.
    .qrc_resources(["qml/BarModel.js"])
    .qrc_resources([
        "assets/icon-omarchy.svg",
        "assets/icons/general.svg",
        "assets/icons/dock.svg",
        "assets/icons/windows.svg",
        "assets/icons/lock.svg",
        "assets/icons/widgets.svg",
        "assets/icons/menubar.svg",
        "assets/icons/backups.svg",
        "assets/icons/about.svg",
        "assets/icons/search.svg",
        "assets/icons/clear.svg",
    ])
    .qt_module("Network")
    .files(["src/theme.rs"])
    .build();
}
