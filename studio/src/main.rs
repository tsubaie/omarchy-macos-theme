//! macOS Theme Studio: install, remove and customize the macOS theme for
//! Omarchy, in a window shaped like macOS System Settings.

mod install;
mod theme;
mod window;

use cxx_qt_lib::{QFont, QGuiApplication, QQmlApplicationEngine, QString, QUrl};

/// The window, compiled into the binary by `build.rs`.
const MAIN_QML: &str = "qrc:/qt/qml/org/omarchy/macosstudio/qml/Main.qml";

fn main() {
    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut()
            .set_application_name(&QString::from("macOS Theme Studio"));
        // Where the app keeps its own small state, such as the last pane.
        app.as_mut()
            .set_organization_name(&QString::from("omarchy"));
        // Inter is the theme's stand-in for Apple's SF Pro; Qt falls back to
        // the system sans when it isn't installed.
        let mut font = QFont::default();
        font.set_family(&QString::from("Inter"));
        app.as_mut().set_application_font(&font);
    }

    // The traffic lights are drawn in the sidebar, as macOS apps do; no
    // title bar above the window.
    window::hide_title_bar();

    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from(MAIN_QML));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
