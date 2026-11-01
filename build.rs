use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("org.omarchy.macossettings")
            .qml_file("qml/Main.qml")
            .qml_file("qml/MacSwitch.qml")
            .qml_file("qml/MacSlider.qml")
            .qml_file("qml/Group.qml")
            .qml_file("qml/SettingRow.qml")
            .qml_file("qml/SearchField.qml"),
    )
    .qrc_resources([
        "assets/icon-omarchy.svg",
        "assets/icons/general.svg",
        "assets/icons/dock.svg",
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
