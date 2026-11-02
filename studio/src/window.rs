//! The window's own controls under Hyprland. The app draws its traffic lights
//! in the sidebar, as macOS does, so it asks Hyprland not to draw a title bar
//! above it, and minimizes and zooms its own window, found by its process id.

use std::env;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use serde_json::Value;

/// The window class the app runs under, as Hyprland matches it.
const CLASS: &str = "omarchy-macos-studio";

fn hyprland() -> bool {
    env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some()
}

/// Asks Hyprland's title bar plugin to leave this app's windows without a bar.
/// It lasts until Hyprland's config reloads; the theme's look.lua keeps it
/// after that. Without the plugin the rule is ignored.
pub fn hide_title_bar() {
    if !hyprland() {
        return;
    }
    let rule = format!(
        r#"hl.window_rule({{ name = "{CLASS}-no-bar", match = {{ class = "^{CLASS}$" }}, ["hyprbars:no_bar"] = true }})"#
    );
    // Waited for, so the rule is in place before the window opens.
    let _ = Command::new("hyprctl")
        .args(["eval", &rule])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// This process's window address in Hyprland, such as "0x5640642f0a10".
fn own_address() -> Option<String> {
    let output = Command::new("hyprctl")
        .args(["clients", "-j"])
        .output()
        .ok()?;
    let clients: Value = serde_json::from_slice(&output.stdout).ok()?;
    let pid = u64::from(std::process::id());
    clients
        .as_array()?
        .iter()
        .find(|client| client["pid"].as_u64() == Some(pid))
        .and_then(|client| client["address"].as_str())
        .map(str::to_owned)
}

fn dispatch(call: &str) {
    let _ = Command::new("hyprctl")
        .args(["dispatch", call])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

/// Minimizes the window into the dock with the theme's genie when the theme is
/// current, as its yellow button does elsewhere. Returns false when that isn't
/// possible, so the window can minimize the ordinary way instead.
pub fn minimize() -> bool {
    let Some(address) = own_address() else {
        return false;
    };
    let script = env::var_os("HOME")
        .map(PathBuf::from)
        .map(|home| home.join(".local/state/omarchy/current/theme/minimize.sh"));
    match script {
        Some(script) if script.is_file() => Command::new("bash")
            .arg(script)
            .arg(&address)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .is_ok(),
        _ => false,
    }
}

/// Fills the screen and back, as the green button and a double click on the
/// title bar do on macOS.
pub fn zoom() {
    if let Some(address) = own_address() {
        dispatch(&format!(
            r#"hl.dsp.window.fullscreen({{ mode = "maximized", action = "toggle", window = "address:{address}" }})"#
        ));
    }
}
