# macOS Theme Settings

An app to install, remove and customize the [macOS theme for Omarchy](https://github.com/tsubaie/omarchy-macos-theme), shaped like macOS System Settings.

It is a thin front end: every change goes through the theme's own `install.sh` (`--status --json`, `--add`, `--remove`, `--set`), so the app and the script always agree. The theme is downloaded to `~/.local/share/omarchy-macos-theme`, where Omarchy Sync keeps it too.

## What it changes

Nothing until you press **Apply**; then every change goes to the theme's installer in one call, so the theme reloads once (the bar and dock blink; windows stay open). Before each change the installer backs up what it touches, which you can restore from **Backups**:

- `~/.config/omarchy/shell.json`: Omarchy's bar, dock and plugin settings
- `~/.config/hypr/looknfeel.lua`: one line that loads the theme's look
- `~/.config/gtk-4.0/gtk.css`: blur and the Files rows
- `~/.config/omarchy/themes/macos`: the theme
- the theme's own plugins in `~/.config/omarchy/plugins`

Other plugins, your keybindings, your apps and their settings, and your terminal font are never touched.

Not affiliated with Apple or Omarchy. macOS is a trademark of Apple Inc. The Omarchy logo on the Overview page is read from your Omarchy install, not shipped with this app.

Built with Rust and [CXX-Qt](https://github.com/KDAB/cxx-qt): the window is QML, the logic Rust.

## Build and run

Needs Rust (`sudo pacman -S rust`) and Qt 6, which Omarchy already has.

```bash
cargo run --release
```

To work against a checkout of the theme instead of the downloaded copy:

```bash
OMARCHY_MACOS_THEME_DIR=~/Projects/omarchy-macos-theme cargo run
```

## Checks

```bash
cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
```
