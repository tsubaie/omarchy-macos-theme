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
    .qrc_resources(["assets/icon.svg"])
    .qt_module("Network")
    .files(["src/theme.rs"])
    .build();
}
