# macOS Theme Settings

An app to install, remove and customize the [macOS theme for Omarchy](https://github.com/tsubaie/omarchy-macos-theme), shaped like macOS System Settings.

It is a thin front end: every change goes through the theme's own `install.sh` (`--status --json`, `--add`, `--remove`, `--set`), so the app and the script always agree. The theme is downloaded to `~/.local/share/omarchy-macos-theme`, where Omarchy Sync keeps it too.

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
