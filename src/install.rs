//! Drives the theme's own `install.sh`, which stays the one place that changes
//! the system: this app only asks it what is installed and tells it what to do.

use std::collections::BTreeMap;
use std::env;
use std::fmt;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

/// Where the theme is downloaded from.
pub const REPO_URL: &str = "https://github.com/tsubaie/omarchy-macos-theme.git";

/// The pieces `install.sh --add` and `--remove` know, as its `FEATURES` lists them.
const PIECES: [&str; 11] = [
    "theme",
    "rows",
    "icons",
    "wide-menu",
    "dock",
    "switcher",
    "osd",
    "dictation-hud",
    "menubar",
    "lock",
    "widgets",
];

/// One piece of the theme, checked against the names `install.sh` accepts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Piece(&'static str);

impl TryFrom<&str> for Piece {
    type Error = anyhow::Error;

    fn try_from(name: &str) -> Result<Self> {
        PIECES
            .iter()
            .find(|piece| **piece == name)
            .map(|piece| Piece(piece))
            .with_context(|| format!("unknown piece {name:?}"))
    }
}

impl fmt::Display for Piece {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.0)
    }
}

/// A setting `install.sh --set` takes, with the range it accepts.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Setting {
    key: &'static str,
    value: f64,
}

impl Setting {
    /// Checks the key and that the value is in its range, as `install.sh` would.
    ///
    /// # Errors
    ///
    /// Fails for an unknown key or a value `install.sh` would refuse.
    pub fn try_new(key: &str, value: f64) -> Result<Self> {
        let (key, range): (&'static str, (f64, f64)) = match key {
            "glass" => ("glass", (0.5, 1.0)),
            "web-glass" => ("web-glass", (0.5, 1.0)),
            "magnification" => ("magnification", (1.0, 2.0)),
            "snapping" => ("snapping", (0.0, 1.0)),
            _ => bail!("unknown setting {key:?}"),
        };
        // Two decimals are all the sliders show; snapping is a switch, 0 or 1.
        let value = if key == "snapping" {
            value.round()
        } else {
            (value * 100.0).round() / 100.0
        };
        if !(range.0..=range.1).contains(&value) {
            bail!("{key} must be from {} to {}, not {value}", range.0, range.1);
        }
        Ok(Setting { key, value })
    }

    /// The `key=value` argument for `install.sh --set`. Whole numbers print
    /// without a decimal point, which `install.sh` needs for `snapping`.
    fn arg(&self) -> String {
        format!("{}={}", self.key, self.value)
    }
}

/// What `install.sh --status --json` reports.
#[derive(Debug, Clone, PartialEq, Default, Deserialize, Serialize)]
pub struct Status {
    /// Whether the macOS theme is the current Omarchy theme.
    pub active: bool,
    /// Each piece and whether it is installed.
    pub features: BTreeMap<String, bool>,
    /// Glass, web glass, snapping and the dock's magnification.
    pub settings: BTreeMap<String, f64>,
}

/// The theme's folder: `$OMARCHY_MACOS_THEME_DIR` when set (for working on a
/// checkout), else `omarchy-macos-theme` in the user's data folder, where
/// Omarchy Sync keeps it too.
pub fn theme_dir() -> PathBuf {
    if let Some(dir) = env::var_os("OMARCHY_MACOS_THEME_DIR") {
        return PathBuf::from(dir);
    }
    let data = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| Path::new(&home).join(".local/share")))
        .unwrap_or_else(|| PathBuf::from("."));
    data.join("omarchy-macos-theme")
}

/// Whether the theme has been downloaded to `dir`.
pub fn is_downloaded(dir: &Path) -> bool {
    dir.join("install.sh").is_file()
}

/// Reads what is installed.
///
/// # Errors
///
/// Fails when `install.sh` can't run or its report can't be read.
pub fn status(dir: &Path) -> Result<Status> {
    let report = run(dir, &["--status", "--json"])?;
    parse_status(&report)
}

fn parse_status(report: &str) -> Result<Status> {
    serde_json::from_str(report).context("reading the theme's status")
}

/// Changes waiting for Apply: pieces to add and remove, and settings to set.
/// They go to `install.sh` in one call, so the theme reloads once.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Changes {
    add: Vec<Piece>,
    remove: Vec<Piece>,
    set: Vec<Setting>,
}

/// The changes as the window sends them, before they are checked.
#[derive(Deserialize)]
struct RawChanges {
    #[serde(default)]
    add: Vec<String>,
    #[serde(default)]
    remove: Vec<String>,
    #[serde(default)]
    set: BTreeMap<String, f64>,
}

impl Changes {
    /// Reads `{"add": [..], "remove": [..], "set": {key: value}}` and checks
    /// every piece and setting.
    ///
    /// # Errors
    ///
    /// Fails on bad JSON, an unknown piece or setting, a value out of range,
    /// or a piece both added and removed.
    pub fn from_json(json: &str) -> Result<Self> {
        let raw: RawChanges = serde_json::from_str(json).context("reading the changes")?;
        let pieces = |names: &[String]| -> Result<Vec<Piece>> {
            names
                .iter()
                .map(|name| Piece::try_from(name.as_str()))
                .collect()
        };
        let changes = Changes {
            add: pieces(&raw.add)?,
            remove: pieces(&raw.remove)?,
            set: raw
                .set
                .iter()
                .map(|(key, value)| Setting::try_new(key, *value))
                .collect::<Result<_>>()?,
        };
        if let Some(piece) = changes
            .add
            .iter()
            .find(|piece| changes.remove.contains(piece))
        {
            bail!("{piece} is both added and removed");
        }
        Ok(changes)
    }

    /// Whether there is nothing to apply.
    pub fn is_empty(&self) -> bool {
        self.add.is_empty() && self.remove.is_empty() && self.set.is_empty()
    }

    /// The arguments for one `install.sh` call.
    fn args(&self) -> Vec<String> {
        let mut args = Vec::new();
        for piece in &self.remove {
            args.extend(["--remove".to_owned(), piece.to_string()]);
        }
        for piece in &self.add {
            args.extend(["--add".to_owned(), piece.to_string()]);
        }
        for setting in &self.set {
            args.extend(["--set".to_owned(), setting.arg()]);
        }
        args
    }
}

/// Applies the changes in one `install.sh` call.
///
/// # Errors
///
/// Fails with `install.sh`'s own message when it does.
pub fn apply(dir: &Path, changes: &Changes) -> Result<()> {
    if changes.is_empty() {
        return Ok(());
    }
    let args = changes.args();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    run(dir, &args).map(drop)
}

/// Downloads the theme into `dir`.
///
/// # Errors
///
/// Fails when `git` can't fetch it.
pub fn download(dir: &Path) -> Result<()> {
    if let Some(parent) = dir.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating {}", parent.display()))?;
    }
    let output = Command::new("git")
        .args(["clone", "--depth", "1", REPO_URL])
        .arg(dir)
        .output()
        .context("running git")?;
    if !output.status.success() {
        bail!(
            "{}",
            last_line(&output.stderr, "git could not download the theme")
        );
    }
    Ok(())
}

/// The theme's version: its last commit and that commit's date, such as
/// "43e4764, 2026-11-01". None when the folder isn't a git checkout.
pub fn version(dir: &Path) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["log", "-1", "--format=%h, %cs"])
        .output()
        .ok()?;
    let version = String::from_utf8(output.stdout).ok()?.trim().to_owned();
    (output.status.success() && !version.is_empty()).then_some(version)
}

/// A snapshot `install.sh` took, as `--backups --json` lists it.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct Backup {
    /// When it was taken, as `YYYYMMDD-HHMMSS`, which `--restore` takes.
    pub id: String,
    /// When it was taken, as ISO 8601.
    pub created: String,
    /// What changed after it, such as "Added dock".
    pub note: String,
    /// Kept for good: the first snapshot.
    pub pinned: bool,
    /// Taken before the theme changed anything.
    pub original: bool,
}

/// The snapshots, newest first.
///
/// # Errors
///
/// Fails when `install.sh` can't list them.
pub fn backups(dir: &Path) -> Result<Vec<Backup>> {
    let list = run(dir, &["--backups", "--json"])?;
    serde_json::from_str(&list).context("reading the backups")
}

/// Takes a snapshot now.
///
/// # Errors
///
/// Fails with `install.sh`'s own message when it does.
pub fn back_up(dir: &Path) -> Result<()> {
    run(dir, &["--backup"]).map(drop)
}

/// Checks a snapshot id: digits and dashes only, as `install.sh` makes them.
///
/// # Errors
///
/// Fails for anything else, so no other text reaches `install.sh`.
pub fn backup_id(id: &str) -> Result<String> {
    let valid = id.len() >= 15 && id.chars().all(|c| c.is_ascii_digit() || c == '-');
    if !valid {
        bail!("not a backup: {id:?}");
    }
    Ok(id.to_owned())
}

/// Puts a snapshot back; `install.sh` snapshots the present first.
///
/// # Errors
///
/// Fails with `install.sh`'s own message when it does.
pub fn restore(dir: &Path, id: &str) -> Result<()> {
    run(dir, &["--restore", id]).map(drop)
}

/// Writes the user's choices to `file`.
///
/// # Errors
///
/// Fails with `install.sh`'s own message when it does.
pub fn export(dir: &Path, file: &Path) -> Result<()> {
    let file = file.to_str().context("the file's name isn't text")?;
    run(dir, &["--export", file]).map(drop)
}

/// Applies an export; `install.sh` snapshots the present first.
///
/// # Errors
///
/// Fails when the file is missing, or with `install.sh`'s own message.
pub fn import(dir: &Path, file: &Path) -> Result<()> {
    if !file.is_file() {
        bail!("no file {}", file.display());
    }
    let file = file.to_str().context("the file's name isn't text")?;
    run(dir, &["--import", file]).map(drop)
}

fn run(dir: &Path, args: &[&str]) -> Result<String> {
    let script = dir.join("install.sh");
    let output = Command::new("bash")
        .arg(&script)
        .args(args)
        .current_dir(dir)
        .output()
        .with_context(|| format!("running {}", script.display()))?;
    if !output.status.success() {
        bail!("{}", last_line(&output.stderr, "install.sh failed"));
    }
    String::from_utf8(output.stdout).context("install.sh printed something that isn't text")
}

/// The last line a command wrote to stderr, which is where `install.sh` says why.
fn last_line(stderr: &[u8], fallback: &str) -> String {
    String::from_utf8_lossy(stderr)
        .lines()
        .rev()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or(fallback)
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pieces_are_the_ones_install_sh_knows() {
        assert_eq!(
            Piece::try_from("dock")
                .expect("dock is a piece")
                .to_string(),
            "dock"
        );
        assert!(Piece::try_from("everything").is_err());
        assert!(Piece::try_from("dock; rm -rf ~").is_err());
    }

    #[test]
    fn settings_are_checked_and_formatted_for_install_sh() {
        let arg = |key, value| Setting::try_new(key, value).map(|s| s.arg());
        assert_eq!(arg("glass", 0.849_999).expect("in range"), "glass=0.85");
        assert_eq!(
            arg("magnification", 2.0).expect("in range"),
            "magnification=2"
        );
        assert_eq!(arg("snapping", 1.0).expect("in range"), "snapping=1");
        assert_eq!(arg("snapping", 0.2).expect("rounds to off"), "snapping=0");
        assert!(arg("glass", 0.2).is_err());
        assert!(arg("web-glass", 1.5).is_err());
        assert!(arg("size", 1.0).is_err());
    }

    #[test]
    fn status_reads_install_sh_json() {
        let report = r#"{"active":true,"features":{"theme":true,"dock":false},"settings":{"glass":0.7,"web-glass":1,"snapping":1,"magnification":1.75}}"#;
        let status = parse_status(report).expect("valid report");
        assert!(status.active);
        assert_eq!(status.features.get("dock"), Some(&false));
        assert_eq!(status.settings.get("magnification"), Some(&1.75));
        assert!(parse_status("not json").is_err());
    }

    #[test]
    fn changes_become_one_install_sh_call() {
        let changes = Changes::from_json(
            r#"{"add":["dock","widgets"],"remove":["osd"],"set":{"glass":0.8,"snapping":0}}"#,
        )
        .expect("valid changes");
        assert_eq!(
            changes.args(),
            [
                "--remove",
                "osd",
                "--add",
                "dock",
                "--add",
                "widgets",
                "--set",
                "glass=0.8",
                "--set",
                "snapping=0"
            ]
        );
        assert!(Changes::from_json("{}").expect("nothing to do").is_empty());
    }

    #[test]
    fn bad_changes_are_refused_before_install_sh_runs() {
        assert!(Changes::from_json(r#"{"add":["everything"]}"#).is_err());
        assert!(Changes::from_json(r#"{"set":{"glass":3}}"#).is_err());
        assert!(Changes::from_json(r#"{"add":["dock"],"remove":["dock"]}"#).is_err());
        assert!(Changes::from_json("not json").is_err());
    }

    #[test]
    fn only_snapshot_ids_reach_restore() {
        assert_eq!(
            backup_id("20261101-140755").expect("an id"),
            "20261101-140755"
        );
        assert_eq!(
            backup_id("20261101-140755-4242").expect("an id"),
            "20261101-140755-4242"
        );
        assert!(backup_id("../../etc").is_err());
        assert!(backup_id("--uninstall").is_err());
        assert!(backup_id("2026").is_err());
    }

    #[test]
    fn backups_read_install_sh_json() {
        let list = r#"[{"id":"20261101-140755","created":"2026-11-01T14:07:55+03:00","note":"Backed up by hand","theme":"Macos","pinned":true,"original":false}]"#;
        let backups: Vec<Backup> = serde_json::from_str(list).expect("valid list");
        assert_eq!(backups[0].id, "20261101-140755");
        assert!(backups[0].pinned);
    }

    #[test]
    fn last_line_is_the_reason() {
        assert_eq!(
            last_line(b"==> step\nSwitch to another theme first\n\n", "x"),
            "Switch to another theme first"
        );
        assert_eq!(last_line(b"", "fallback"), "fallback");
    }
}
