//! Drives the theme's own `install.sh`, which stays the one place that changes
//! the system: this app only asks it what is installed and tells it what to do.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::env;
use std::fmt;
use std::fs;
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::{Arc, Mutex, PoisonError};
use std::thread;
use std::time::SystemTime;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

/// Where the theme is downloaded from.
pub const REPO_URL: &str = "https://github.com/tsubaie/omarchy-macos-theme.git";

/// The pieces `install.sh --add` and `--remove` know, as its `FEATURES` lists them.
const PIECES: [&str; 12] = [
    "theme",
    "rows",
    "icons",
    "wide-menu",
    "dock",
    "switcher",
    "osd",
    "dictation-hud",
    "menubar",
    "bar-icons",
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

/// The settings Studio sets, each with the range `install.sh --set` accepts
/// and whether it takes whole numbers only (a switch, a size in points).
const SETTINGS: [(&str, f64, f64, bool); 9] = [
    ("glass", 0.75, 1.0, false),
    ("web-glass", 0.5, 1.0, false),
    ("magnification", 1.0, 2.0, false),
    ("dock-size", 32.0, 80.0, true),
    ("snapping", 0.0, 1.0, true),
    ("title-bars", 0.0, 1.0, true),
    ("reduce-motion", 0.0, 1.0, true),
    ("traffic-lights", 10.0, 20.0, true),
    ("blur", 0.0, 20.0, true),
];

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
        let &(key, low, high, whole) = SETTINGS
            .iter()
            .find(|setting| setting.0 == key)
            .with_context(|| format!("unknown setting {key:?}"))?;
        // Two decimals are all the sliders show; the rest are whole numbers.
        let value = if whole {
            value.round()
        } else {
            (value * 100.0).round() / 100.0
        };
        if !(low..=high).contains(&value) {
            bail!("{key} must be from {low} to {high}, not {value}");
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
    /// Glass, web glass, snapping, blur, and the dock's magnification and size.
    pub settings: BTreeMap<String, f64>,
    /// Where the bar's clock sits: "left", "center" or "right". Older themes
    /// don't report it.
    #[serde(default)]
    pub clock: Option<String>,
    /// The other Omarchy themes, to switch to before removing this one while
    /// it is current. Older themes don't report them.
    #[serde(default)]
    pub themes: Vec<String>,
    /// The theme removing this one while it is current switches to: the one
    /// before it. Older themes, and a computer with no other, don't report one.
    #[serde(default, rename = "previous-theme")]
    pub previous_theme: Option<String>,
    /// The desktop widgets shown. Older themes don't report them.
    #[serde(default)]
    pub widgets: Option<Vec<String>>,
    /// Where the volume panel shows: "bottom" or "top". Older themes don't
    /// report it.
    #[serde(default, rename = "volume-hud")]
    pub volume_hud: Option<String>,
    /// The same for the dictation panel.
    #[serde(default, rename = "dictation-hud")]
    pub dictation_hud: Option<String>,
}

/// The bar's sections, as `install.sh --bar-layout` takes them.
const BAR_SECTIONS: [&str; 6] = [
    "left",
    "centerBegin",
    "center",
    "centerEnd",
    "right",
    "tray",
];

/// How the bar's items are to be shown, hidden and ordered:
/// `{"sections": {"right": ["omarchy.clock", …], …}, "hidden": [ids]}`.
#[derive(Debug, Clone, PartialEq, Default, Deserialize, Serialize)]
pub struct BarLayout {
    #[serde(default)]
    sections: BTreeMap<String, Vec<String>>,
    #[serde(default)]
    hidden: Vec<String>,
}

impl BarLayout {
    /// Checks the sections and that every id is a plain widget id, so nothing
    /// else reaches the installer, which checks them against the bar too.
    fn check(self) -> Result<Self> {
        if let Some(section) = self
            .sections
            .keys()
            .find(|s| !BAR_SECTIONS.contains(&s.as_str()))
        {
            bail!("the bar has no section {section:?}");
        }
        let plain = |id: &String| {
            !id.is_empty()
                && id
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || "._-".contains(c))
        };
        if let Some(id) = self
            .sections
            .values()
            .flatten()
            .chain(&self.hidden)
            .find(|id| !plain(id))
        {
            bail!("not a bar item: {id:?}");
        }
        Ok(self)
    }
}

/// The bar's items by section and the hidden ones, as `install.sh --bar
/// --json` lists them, passed on to the window as it comes.
///
/// # Errors
///
/// Fails when the installer can't list them, as one older than this does.
pub fn bar(dir: &Path) -> Result<String> {
    let json = run(dir, &["--bar", "--json"])?.out;
    serde_json::from_str::<serde_json::Value>(&json).context("reading the bar")?;
    Ok(json.trim().to_owned())
}

/// The desktop widgets, as `install.sh --show-widgets` takes them.
const DESKTOP_WIDGETS: [&str; 4] = ["clock", "calendar", "weather", "playing"];

/// The places the bar's clock can sit, as `install.sh --set clock=` takes them.
const CLOCK_POSITIONS: [&str; 3] = ["left", "center", "right"];

/// The panels that can show at the bottom or the top, as `install.sh --set
/// <panel>=<place>` takes them.
const PANELS: [&str; 2] = ["volume-hud", "dictation-hud"];
const PANEL_PLACES: [&str; 2] = ["bottom", "top"];

/// The theme's folder: `$OMARCHY_MACOS_THEME_DIR` when set (for working on a
/// checkout), else `omarchy-macos-theme` in the user's data folder, where
/// Omarchy Sync keeps it too.
///
/// # Errors
///
/// Fails with neither `$XDG_DATA_HOME` nor `$HOME` set, rather than putting
/// the theme wherever the app happened to start.
pub fn theme_dir() -> Result<PathBuf> {
    if let Some(dir) = env::var_os("OMARCHY_MACOS_THEME_DIR") {
        return Ok(PathBuf::from(dir));
    }
    let data = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| Path::new(&home).join(".local/share")))
        .context("neither XDG_DATA_HOME nor HOME is set, so there is nowhere to keep the theme")?;
    Ok(data.join("omarchy-macos-theme"))
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
    let report = run(dir, &["--status", "--json"])?.out;
    parse_status(&report)
}

/// The newest change to anything `install.sh --status`, `--bar` and the
/// backups read, by install.sh's own rules for where they are: Omarchy's
/// config with `shell.json` and the plugins, the installed theme, the
/// backups, Hyprland's and GTK's config, the current Omarchy theme and the
/// icons. A change there from outside Studio (a widget removed on the
/// desktop, a theme switched in Omarchy, install.sh run from a terminal)
/// moves it. Each folder and what's directly in it, followed through links.
// shortcut: only one level deep; a change deeper in (inside one plugin's folder, say) waits for the next action or launch.
#[must_use]
pub fn changed_outside() -> Option<SystemTime> {
    let home = PathBuf::from(env::var_os("HOME")?);
    let config = env::var_os("XDG_CONFIG_HOME").map_or_else(|| home.join(".config"), PathBuf::from);
    changed_under(&home, &config)
}

fn changed_under(home: &Path, config: &Path) -> Option<SystemTime> {
    let folders = [
        config.join("omarchy"),
        config.join("omarchy/plugins"),
        config.join("omarchy/themes/macos"),
        config.join("omarchy/macos-theme-backups"),
        config.join("hypr"),
        config.join("gtk-4.0"),
        home.join(".local/state/omarchy/current"),
        home.join(".local/share/icons"),
    ];
    let changed = |path: &Path| fs::metadata(path).and_then(|m| m.modified()).ok();
    folders
        .iter()
        .flat_map(|folder| {
            let inside = fs::read_dir(folder).into_iter().flatten().flatten().map(|entry| entry.path());
            std::iter::once(folder.clone()).chain(inside)
        })
        .filter_map(|path| changed(&path))
        .max()
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
    clock: Option<&'static str>,
    places: Vec<(&'static str, &'static str)>,
    bar: Option<BarLayout>,
    widgets: Option<Vec<&'static str>>,
    switch_to: Option<String>,
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
    #[serde(default)]
    clock: Option<String>,
    #[serde(default)]
    places: BTreeMap<String, String>,
    #[serde(default)]
    bar: Option<BarLayout>,
    #[serde(default)]
    widgets: Option<Vec<String>>,
    /// The theme to switch to first, when the current one is removed.
    #[serde(default, rename = "switchTo")]
    switch_to: Option<String>,
}

/// Checks a theme's name to switch to: a name as Omarchy lists them, not an
/// option or anything else for install.sh to read (which checks it exists).
fn theme_name(name: String) -> Result<String> {
    let plain = !name.is_empty() && name.len() <= 100 && !name.starts_with('-') && !name.chars().any(char::is_control);
    if !plain {
        bail!("not a theme's name: {name:?}");
    }
    Ok(name)
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
            clock: raw
                .clock
                .map(|place| {
                    CLOCK_POSITIONS
                        .iter()
                        .copied()
                        .find(|known| *known == place)
                        .with_context(|| format!("the clock can't go {place:?}"))
                })
                .transpose()?,
            places: raw
                .places
                .iter()
                .map(|(panel, place)| {
                    let known = |list: &[&'static str], name: &str| {
                        list.iter().copied().find(|k| *k == name)
                    };
                    Ok((
                        known(&PANELS, panel).with_context(|| format!("no panel {panel:?}"))?,
                        known(&PANEL_PLACES, place)
                            .with_context(|| format!("the {panel} can't go {place:?}"))?,
                    ))
                })
                .collect::<Result<_>>()?,
            bar: raw.bar.map(BarLayout::check).transpose()?,
            widgets: raw.widgets.map(shown_widgets).transpose()?,
            switch_to: raw.switch_to.map(theme_name).transpose()?,
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
        self.add.is_empty()
            && self.remove.is_empty()
            && self.set.is_empty()
            && self.clock.is_none()
            && self.places.is_empty()
            && self.bar.is_none()
            && self.widgets.is_none()
    }

    /// The arguments for one `install.sh` call.
    fn args(&self) -> Result<Vec<String>> {
        let mut args = Vec::new();
        if let Some(theme) = &self.switch_to {
            args.extend(["--switch-to".to_owned(), theme.clone()]);
        }
        for piece in &self.remove {
            args.extend(["--remove".to_owned(), piece.to_string()]);
        }
        for piece in &self.add {
            args.extend(["--add".to_owned(), piece.to_string()]);
        }
        for setting in &self.set {
            args.extend(["--set".to_owned(), setting.arg()]);
        }
        if let Some(place) = self.clock {
            args.extend(["--set".to_owned(), format!("clock={place}")]);
        }
        for (panel, place) in &self.places {
            args.extend(["--set".to_owned(), format!("{panel}={place}")]);
        }
        if let Some(bar) = &self.bar {
            let json = serde_json::to_string(bar).context("writing the bar layout")?;
            args.extend(["--bar-layout".to_owned(), json]);
        }
        if let Some(widgets) = &self.widgets {
            args.extend(["--show-widgets".to_owned(), widgets.join(",")]);
        }
        Ok(args)
    }
}

/// Checks the widgets to show: known ones, at least one, as the desktop
/// always keeps one.
fn shown_widgets(names: Vec<String>) -> Result<Vec<&'static str>> {
    if names.is_empty() {
        bail!("at least one desktop widget stays shown");
    }
    names
        .iter()
        .map(|name| {
            DESKTOP_WIDGETS
                .iter()
                .copied()
                .find(|known| known == name)
                .with_context(|| format!("unknown desktop widget {name:?}"))
        })
        .collect()
}

/// Applies the changes in one `install.sh` call, and returns its warnings.
///
/// # Errors
///
/// Fails with `install.sh`'s own message when it does.
pub fn apply(dir: &Path, changes: &Changes) -> Result<Warnings> {
    if changes.is_empty() {
        return Ok(Warnings::new());
    }
    let args = changes.args()?;
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    run(dir, &args).map(|ran| ran.warnings)
}

/// Downloads the theme into `dir`.
///
/// # Errors
///
/// Fails when `git` can't fetch it.
pub fn download(dir: &Path) -> Result<Warnings> {
    if let Some(parent) = dir.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating {}", parent.display()))?;
    }
    // Into a folder beside it, then renamed: a download cut short leaves no
    // half a theme that looks downloaded, nor a folder the next one can't use.
    let partial = dir.with_extension("download");
    let _ = std::fs::remove_dir_all(&partial);
    // An older version cloned straight into the folder; one cut short left
    // only .git there, which is safe to clear.
    let only_git = std::fs::read_dir(dir).is_ok_and(|entries| entries.flatten().all(|e| e.file_name() == ".git"));
    if only_git {
        std::fs::remove_dir_all(dir).with_context(|| format!("clearing {}", dir.display()))?;
    }
    // The newest release, or main before the theme had any.
    let tags = git(None, &["ls-remote", "--tags", "--refs", "--sort=-v:refname", REPO_URL, "v[0-9]*"], 30)
        .context("asking GitHub for the theme's releases")?;
    let release = newest(tags.lines().filter_map(|line| line.split("refs/tags/").nth(1)));
    let partial_dir = partial.to_string_lossy();
    let mut clone = vec!["clone", "--progress", "--depth", "1"];
    if let Some(tag) = &release {
        clone.extend(["--branch", tag.as_str()]);
    }
    clone.extend([REPO_URL, &partial_dir]);
    git(None, &clone, 300).context("downloading the theme")?;
    std::fs::rename(&partial, dir).with_context(|| format!("moving the theme into {}", dir.display()))?;
    Ok(Warnings::new())
}

/// Runs git, in `dir` when given, for `seconds` at most, and never stopping
/// to ask for a password (there is no terminal to ask in).
fn git(dir: Option<&Path>, args: &[&str], seconds: u32) -> Result<String> {
    let mut command = Command::new("timeout");
    command.arg(seconds.to_string()).arg("git");
    if let Some(dir) = dir {
        command.arg("-C").arg(dir);
    }
    command.args(args).env("GIT_TERMINAL_PROMPT", "0");
    let output = watched_output(command, None, Some(git_progress)).context("running git")?;
    match output.status.code() {
        Some(0) => Ok(String::from_utf8_lossy(&output.stdout).into_owned()),
        // What `timeout` exits with when it stopped the command.
        Some(124) => bail!("git took over {seconds} seconds; is the network down?"),
        _ => Err(Failed::new(&output.stderr, "git failed").into()),
    }
}

/// How far a download is, from git's progress: "Downloading… 3.20 MiB".
fn git_progress(line: &str) -> Option<String> {
    let size = line.strip_prefix("Receiving objects:")?.split(',').nth(1)?.split('|').next()?.trim();
    (!size.is_empty()).then(|| format!("Downloading… {size}"))
}

/// Asks GitHub for the theme's new commits.
///
/// # Errors
///
/// Fails offline, or when GitHub doesn't answer in time.
pub fn fetch(dir: &Path) -> Result<()> {
    git(Some(dir), &["fetch", "--quiet", "--tags"], 30).map(drop).context("couldn't check for updates")
}

/// Left in .git while an update has pulled but not installed yet, so the
/// update stays offered until an install goes through.
fn needs_install(dir: &Path) -> PathBuf {
    dir.join(".git/studio-needs-install")
}

/// The first release among tag names, newest first: a `vX.Y.Z` tag, not a
/// pre-release such as `v2.0.0-rc1`.
fn newest<'a>(mut tags: impl Iterator<Item = &'a str>) -> Option<String> {
    tags.find(|tag| tag.strip_prefix('v').is_some_and(|v| v.split('.').all(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))))
        .map(str::to_owned)
}

/// The newest release here, as last fetched.
fn newest_release(dir: &Path) -> Option<String> {
    let output = Command::new("git").arg("-C").arg(dir).args(["tag", "-l", "v[0-9]*", "--sort=-v:refname"]).output().ok()?;
    newest(String::from_utf8_lossy(&output.stdout).lines())
}

/// Where Update goes: the newest release, or, before the theme had any, the
/// branch it follows.
fn update_target(dir: &Path) -> String {
    newest_release(dir).unwrap_or_else(|| "@{upstream}".to_owned())
}

/// Whether `target` comes after what is here, so going there loses nothing.
fn is_ahead(dir: &Path, target: &str) -> bool {
    Command::new("git").arg("-C").arg(dir).args(["merge-base", "--is-ancestor", "HEAD", target])
        .output().is_ok_and(|output| output.status.success())
}

/// What Update brings in, as last fetched: its commits' subjects, newest
/// first. Commits that touch only Studio, which lives in the same repository,
/// are left out: they change nothing installed. None when the newest release
/// is older than what is here (a download from before releases, ahead of it).
pub fn incoming(dir: &Path) -> Vec<String> {
    let target = update_target(dir);
    let mut subjects: Vec<String> = if is_ahead(dir, &target) {
        Command::new("git")
            .arg("-C")
            .arg(dir)
            .args(["log", "--format=%s", &format!("HEAD..{target}"), "--", ".", ":(exclude)studio"])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).lines().map(str::to_owned).collect())
            .unwrap_or_default()
    } else {
        Vec::new()
    };
    // Pulled but not installed: the update isn't done, so it is still offered.
    if subjects.is_empty() && needs_install(dir).exists() {
        subjects.push("The last update, downloaded but not installed yet".to_owned());
    }
    subjects
}

/// Pieces an update reinstalls: what is installed, but not the MacTahoe
/// icons, which come from their own project rather than the theme.
fn reinstall(status: &Status) -> Vec<Piece> {
    status
        .features
        .iter()
        .filter(|(name, on)| **on && name.as_str() != "icons")
        .filter_map(|(name, _)| Piece::try_from(name.as_str()).ok())
        .collect()
}

/// Brings the theme up to date: goes to its newest release (or, before it had
/// releases, the newest main), then installs the pieces in use again, in one
/// `install.sh` call that backs up first and reloads once.
///
/// # Errors
///
/// Fails when git can't fetch or move there (such as when the folder has
/// changes of its own), when the newest release is older than what is here,
/// or with `install.sh`'s own message.
pub fn update(dir: &Path) -> Result<Warnings> {
    let installed = reinstall(&status(dir)?);
    git(Some(dir), &["fetch", "--progress", "--tags"], 120).context("updating the theme")?;
    // The newest release, never one older than what is here.
    let target = update_target(dir);
    if !is_ahead(dir, &target) {
        bail!("The theme here is newer than its newest release, {target}");
    }
    // A release is checked out; before releases, main is fast-forwarded,
    // staying on the branch so the next update can follow it too.
    let go = if target.starts_with('v') {
        ["-c", "advice.detachedHead=false", "checkout", "--quiet", target.as_str()]
    } else {
        ["merge", "--ff-only", "--quiet", "--no-stat", target.as_str()]
    };
    git(Some(dir), &go, 60).context("updating the theme")?;
    // Until the install goes through, the update stays offered, so a failed
    // one can be tried again rather than vanishing with the pulled commits.
    let marker = needs_install(dir);
    let _ = std::fs::write(&marker, "");
    let warnings = apply(
        dir,
        &Changes {
            add: installed,
            ..Changes::default()
        },
    )?;
    let _ = std::fs::remove_file(&marker);
    Ok(warnings)
}

/// Where `studio/get.sh` puts Studio, and where it is reopened from.
pub fn studio_binary() -> Option<PathBuf> {
    env::var_os("XDG_BIN_HOME")
        .filter(|dir| !dir.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| Path::new(&home).join(".local/bin")))
        .map(|dir| dir.join("omarchy-macos-studio"))
}

/// Puts Studio's newest release in place of this one, with the theme's own
/// `studio/get.sh`, as it was installed. The running program carries on
/// until it is reopened.
///
/// # Errors
///
/// Fails when the theme here is too old to have `studio/get.sh`, or with
/// its own message (offline, say).
pub fn update_studio(dir: &Path) -> Result<Warnings> {
    if !dir.join("studio/get.sh").is_file() {
        bail!("Update the theme first: this copy of it is too old to update Studio");
    }
    // get.sh says what it is doing in plain lines; curl's progress bar goes to stderr.
    run_script(dir, "studio/get.sh", &[], |line| {
        let line = line.trim();
        (!line.is_empty()).then(|| line.to_owned())
    })
    .map(|ran| ran.warnings)
}

/// Where Omarchy is installed: `$OMARCHY_PATH`, else `/usr/share/omarchy`.
pub fn omarchy_dir() -> PathBuf {
    env::var_os("OMARCHY_PATH").map_or_else(|| PathBuf::from("/usr/share/omarchy"), PathBuf::from)
}

/// Omarchy's own green, the color of its icon.
pub const OMARCHY_GREEN: &str = "#9ECE6A";

/// Omarchy's logo recolored from its black to its green, as a `data:` URL the
/// window shows as it is: no file written anywhere. None when the logo can't
/// be read.
pub fn green_omarchy_logo() -> Option<String> {
    let logo = std::fs::read_to_string(omarchy_dir().join("logo.svg")).ok()?;
    Some(data_url(&recolor_logo(&logo)))
}

/// An SVG as a `data:` URL, escaped byte by byte where a URL needs it.
fn data_url(svg: &str) -> String {
    let mut url = String::from("data:image/svg+xml;charset=utf-8,");
    for byte in svg.bytes() {
        if byte.is_ascii_alphanumeric() || b"-_.~ =:/;,'()".contains(&byte) {
            url.push(char::from(byte));
        } else {
            url.push_str(&format!("%{byte:02X}"));
        }
    }
    url
}

/// The logo with its black fills in Omarchy's green; anything else unchanged.
fn recolor_logo(svg: &str) -> String {
    ["fill=\"#000\"", "fill=\"#000000\"", "fill=\"black\""]
        .iter()
        .fold(svg.to_owned(), |svg, black| {
            svg.replace(black, &format!("fill=\"{OMARCHY_GREEN}\""))
        })
}

/// Omarchy's version, such as "4.0.0.alpha", when it can be read.
pub fn omarchy_version() -> Option<String> {
    let version = std::fs::read_to_string(omarchy_dir().join("version")).ok()?;
    let version = version.trim();
    (!version.is_empty()).then(|| version.to_owned())
}

/// The theme's version: its release, or else its last commit, and that
/// commit's date, such as "v1.2.0, 2026-11-01" or "43e4764, 2026-11-01". None
/// when the folder isn't a git checkout.
pub fn version(dir: &Path) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["log", "-1", "--format=%h, %cs"])
        .output()
        .ok()?;
    let version = String::from_utf8(output.stdout).ok()?.trim().to_owned();
    if !output.status.success() || version.is_empty() {
        return None;
    }
    let release = Command::new("git").arg("-C").arg(dir)
        .args(["describe", "--tags", "--exact-match", "--match", "v[0-9]*"])
        .output().ok().filter(|output| output.status.success())
        .and_then(|output| newest(String::from_utf8_lossy(&output.stdout).lines()));
    Some(match (release, version.split_once(", ")) {
        (Some(release), Some((_, date))) => format!("{release}, {date}"),
        _ => version,
    })
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
    let list = run(dir, &["--backups", "--json"])?.out;
    serde_json::from_str(&list).context("reading the backups")
}

/// Takes a snapshot now.
///
/// # Errors
///
/// Fails with `install.sh`'s own message when it does.
pub fn back_up(dir: &Path) -> Result<Warnings> {
    run(dir, &["--backup"]).map(|ran| ran.warnings)
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
pub fn restore(dir: &Path, id: &str) -> Result<Warnings> {
    run(dir, &["--restore", id]).map(|ran| ran.warnings)
}

/// Writes the user's choices to `file`.
///
/// # Errors
///
/// Fails with `install.sh`'s own message when it does.
pub fn export(dir: &Path, file: &Path) -> Result<Warnings> {
    let file = file.to_str().context("the file's name isn't text")?;
    run(dir, &["--export", file]).map(|ran| ran.warnings)
}

/// Applies an export; `install.sh` snapshots the present first.
///
/// # Errors
///
/// Fails when the file is missing, or with `install.sh`'s own message.
pub fn import(dir: &Path, file: &Path) -> Result<Warnings> {
    if !file.is_file() {
        bail!("no file {}", file.display());
    }
    let file = file.to_str().context("the file's name isn't text")?;
    run(dir, &["--import", file]).map(|ran| ran.warnings)
}

/// Shows settings at once, for a slider being dragged: `install.sh --preview`
/// writes them with no snapshot or theme refresh. Apply sets them properly.
///
/// # Errors
///
/// Fails when `install.sh` refuses them or can't run.
pub fn preview(dir: &Path, settings: &[Setting]) -> Result<()> {
    let args: Vec<String> = settings.iter().flat_map(|s| ["--set".to_owned(), s.arg()]).collect();
    let mut all = vec!["--preview"];
    all.extend(args.iter().map(String::as_str));
    run(dir, &all).map(drop)
}

/// What `install.sh` warned about on a run that still succeeded: a piece it
/// skipped, a font that's missing. One per line; empty when it didn't.
pub type Warnings = String;

/// A run of `install.sh` that succeeded.
struct Ran {
    out: String,
    warnings: Warnings,
}

/// Runs `install.sh`. It writes what it did to stdout, and warnings and
/// errors to stderr, so stderr on success is its warnings.
fn run(dir: &Path, args: &[&str]) -> Result<Ran> {
    run_script(dir, "install.sh", args, install_step)
}

/// Runs a script of the theme's, `install.sh` or `studio/get.sh`, the same way.
fn run_script(dir: &Path, script: &str, args: &[&str], progress: Progress) -> Result<Ran> {
    let script = dir.join(script);
    let mut command = Command::new("bash");
    command.arg(&script).args(args).current_dir(dir);
    let output = watched_output(command, Some(progress), None)
        .with_context(|| format!("running {}", script.display()))?;
    if !output.status.success() {
        let name = script.file_name().map_or_else(|| "it".into(), |n| n.to_string_lossy());
        return Err(Failed::new(&output.stderr, &format!("{name} failed")).into());
    }
    Ok(Ran {
        out: String::from_utf8(output.stdout).context("install.sh printed something that isn't text")?,
        warnings: warnings(&output.stderr),
    })
}

/// What install.sh says it is doing: its "==> " lines, without their bold.
fn install_step(line: &str) -> Option<String> {
    let step = line.split("==>").nth(1)?.trim_start_matches("\u{1b}[0m").trim();
    (!step.is_empty()).then(|| step.to_owned())
}

/// A command that failed: why, in its last line, and all it wrote, for a
/// "Show details".
#[derive(Debug)]
pub struct Failed {
    why: String,
    /// Everything the command wrote to stderr.
    pub output: String,
}

impl Failed {
    fn new(stderr: &[u8], fallback: &str) -> Self {
        Self { why: last_line(stderr, fallback), output: warnings(stderr) }
    }
}

impl fmt::Display for Failed {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.why)
    }
}

impl std::error::Error for Failed {}

/// Why a job ended early: the user stopped it.
pub const STOPPED: &str = "Stopped";

/// The command a job is running, so Stop can end it, and whether it was stopped.
#[derive(Debug, Default)]
pub struct Watch {
    group: Option<u32>,
    stopped: bool,
}

impl Watch {
    /// Whether the job was stopped.
    #[must_use]
    pub fn stopped(&self) -> bool {
        self.stopped
    }
}

/// Where a job's progress goes.
pub type Report = Arc<dyn Fn(&str) + Send + Sync>;

thread_local! {
    /// The job this worker thread runs, if any: where its progress goes, and
    /// its watch. Previews and the update check run on threads without one,
    /// so they are neither reported nor stopped.
    static JOB: RefCell<Option<(Report, Arc<Mutex<Watch>>)>> = const { RefCell::new(None) };
}

/// Runs `job` on this thread with its commands reporting what they do to
/// `report` and stoppable through `watch`.
pub fn watched<T>(report: Report, watch: Arc<Mutex<Watch>>, job: impl FnOnce() -> T) -> T {
    JOB.with(|cell| *cell.borrow_mut() = Some((report, watch)));
    let result = job();
    JOB.with(|cell| *cell.borrow_mut() = None);
    result
}

/// Stops the job `watch` belongs to: its command and everything it started,
/// and any command it would start next.
pub fn stop(watch: &Mutex<Watch>) {
    let mut watch = watch.lock().unwrap_or_else(PoisonError::into_inner);
    watch.stopped = true;
    if let Some(group) = watch.group {
        let _ = Command::new("kill").args(["-TERM", "--", &format!("-{group}")]).status();
    }
}

/// A line-reader: what to report for a line, if anything.
type Progress = fn(&str) -> Option<String>;

/// Runs a command to the end, as `Command::output` does, in a process group
/// of its own so a stop ends what it started too. Inside a job, each line of
/// stdout (or stderr) that `progress_out` (or `progress_err`) makes something
/// of is reported as it comes, and the job's watch can stop it.
fn watched_output(mut command: Command, progress_out: Option<Progress>, progress_err: Option<Progress>) -> Result<Output> {
    let job = JOB.with(|cell| cell.borrow().clone());
    if let Some((_, watch)) = &job {
        if watch.lock().unwrap_or_else(PoisonError::into_inner).stopped {
            bail!(STOPPED);
        }
    }
    command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0);
    let mut child = command.spawn()?;
    if let Some((_, watch)) = &job {
        watch.lock().unwrap_or_else(PoisonError::into_inner).group = Some(child.id());
    }
    let report = job.as_ref().map(|(report, _)| Arc::clone(report));
    let out = pump(child.stdout.take(), report.clone().zip(progress_out));
    let err = pump(child.stderr.take(), report.zip(progress_err));
    let status = child.wait()?;
    let (stdout, stderr) = (out.join().unwrap_or_default(), err.join().unwrap_or_default());
    if let Some((_, watch)) = &job {
        let mut watch = watch.lock().unwrap_or_else(PoisonError::into_inner);
        watch.group = None;
        if watch.stopped {
            bail!(STOPPED);
        }
    }
    Ok(Output { status, stdout, stderr })
}

/// Reads a stream to its end on a thread of its own and hands back all of it,
/// reporting each line (ended by a newline or, as git's progress is, a
/// carriage return) the progress function makes something of.
fn pump(stream: Option<impl Read + Send + 'static>, progress: Option<(Report, Progress)>) -> thread::JoinHandle<Vec<u8>> {
    thread::spawn(move || {
        let mut all = Vec::new();
        let Some(mut stream) = stream else { return all };
        let mut chunk = [0u8; 4096];
        let mut line_start = 0;
        while let Ok(read) = stream.read(&mut chunk) {
            if read == 0 {
                break;
            }
            all.extend_from_slice(&chunk[..read]);
            let Some((report, progress)) = &progress else { continue };
            while let Some(end) = all[line_start..].iter().position(|&b| b == b'\n' || b == b'\r') {
                let line = String::from_utf8_lossy(&all[line_start..line_start + end]).into_owned();
                if let Some(said) = progress(&line) {
                    report(&said);
                }
                line_start += end + 1;
            }
        }
        all
    })
}

/// The lines of stderr that say something, trimmed.
fn warnings(stderr: &[u8]) -> Warnings {
    String::from_utf8_lossy(stderr)
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
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
    fn a_change_outside_studio_is_seen() {
        let home = env::temp_dir().join(format!("studio-outside-{}", std::process::id()));
        let _ = fs::remove_dir_all(&home);
        let config = home.join(".config");
        fs::create_dir_all(config.join("omarchy/plugins")).expect("a throwaway config");
        let shell = config.join("omarchy/shell.json");
        fs::write(&shell, "{}").expect("shell.json");
        let set = |path: &Path, at: SystemTime| {
            fs::File::open(path).and_then(|f| f.set_modified(at)).expect("a change time");
        };
        let before = changed_under(&home, &config).expect("a change time to start from");

        // A widget removed on the desktop rewrites shell.json.
        let later = before + std::time::Duration::from_secs(10);
        set(&shell, later);
        assert_eq!(changed_under(&home, &config), Some(later));

        // A plugin added from a terminal.
        let plugin = config.join("omarchy/plugins/someone.else");
        fs::create_dir(&plugin).expect("a plugin");
        let latest = later + std::time::Duration::from_secs(10);
        set(&plugin, latest);
        assert_eq!(changed_under(&home, &config), Some(latest));

        // Folders that aren't there are no reason to fail.
        assert_eq!(changed_under(&home.join("none"), &home.join("none")), None);
        let _ = fs::remove_dir_all(&home);
    }

    #[test]
    fn progress_is_read_from_git_and_install_sh() {
        assert_eq!(
            git_progress("Receiving objects:  45% (100/220), 3.20 MiB | 1.20 MiB/s").as_deref(),
            Some("Downloading… 3.20 MiB")
        );
        assert_eq!(git_progress("Resolving deltas: 100% (5/5), done."), None);
        assert_eq!(install_step("\u{1b}[1m==>\u{1b}[0m Installed the dock").as_deref(), Some("Installed the dock"));
        assert_eq!(install_step("    MacTahoe icons stay"), None);
    }

    #[test]
    fn a_stopped_job_ends_its_command_and_what_it_started() {
        let watch = Arc::new(Mutex::new(Watch::default()));
        let said = Arc::new(Mutex::new(Vec::<String>::new()));
        let heard = Arc::clone(&said);
        let report: Report = Arc::new(move |stage| heard.lock().expect("the stages").push(stage.to_owned()));
        let stopper = {
            let watch = Arc::clone(&watch);
            thread::spawn(move || {
                thread::sleep(std::time::Duration::from_millis(400));
                stop(&watch);
            })
        };
        let started = std::time::Instant::now();
        // A child that started one of its own, which holds stdout open: only
        // stopping the whole group lets the read end.
        let mut command = Command::new("sh");
        command.args(["-c", "echo '==> Working'; sleep 30 & wait"]);
        let result = watched(Arc::clone(&report), Arc::clone(&watch), || watched_output(command, Some(install_step), None));
        stopper.join().expect("the stopper");
        assert_eq!(result.expect_err("stopped").to_string(), STOPPED);
        assert!(started.elapsed() < std::time::Duration::from_secs(5), "the stop ended it");
        assert_eq!(*said.lock().expect("the stages"), ["Working"]);
        assert!(watch.lock().expect("the watch").stopped());
        // Nor does the job start another command once stopped.
        let next = watched(report, watch, || watched_output(Command::new("true"), None, None));
        assert_eq!(next.expect_err("stopped").to_string(), STOPPED);
    }

    #[test]
    fn a_failure_keeps_all_install_sh_said() {
        let dir = env::temp_dir().join(format!("studio-failed-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("the folder");
        std::fs::write(dir.join("install.sh"), "echo 'first, the detail' >&2\necho 'then why' >&2\nexit 1\n").expect("the script");
        let error = run(&dir, &["--add", "dock"]).map(drop).expect_err("it fails");
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(error.to_string(), "then why");
        let failed = error.downcast_ref::<Failed>().expect("the whole output");
        assert_eq!(failed.output, "first, the detail\nthen why");
    }

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
        assert_eq!(arg("blur", 14.6).expect("in range"), "blur=15");
        assert_eq!(arg("blur", 0.0).expect("off"), "blur=0");
        assert!(arg("blur", 21.0).is_err());
        assert_eq!(arg("dock-size", 55.6).expect("in range"), "dock-size=56");
        assert_eq!(arg("title-bars", 0.0).expect("off"), "title-bars=0");
        assert_eq!(arg("traffic-lights", 16.4).expect("in range"), "traffic-lights=16");
        assert!(arg("traffic-lights", 21.0).is_err());
        assert!(arg("dock-size", 31.0).is_err());
        assert!(arg("dock-size", 81.0).is_err());
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
            changes.args().expect("args"),
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
    fn a_bar_layout_is_checked_and_passed_whole() {
        let changes = Changes::from_json(
            r#"{"bar":{"sections":{"right":["omarchy.clock","netmojo.omdrop"]},"hidden":["omarchy.weather"]}}"#,
        )
        .expect("a layout");
        assert_eq!(
            changes.args().expect("args"),
            [
                "--bar-layout",
                r#"{"sections":{"right":["omarchy.clock","netmojo.omdrop"]},"hidden":["omarchy.weather"]}"#
            ]
        );
        assert!(
            Changes::from_json(r#"{"bar":{"sections":{"middle":["omarchy.clock"]}}}"#).is_err()
        );
        assert!(Changes::from_json(r#"{"bar":{"sections":{"right":["a b"]}}}"#).is_err());
        assert!(Changes::from_json(r#"{"bar":{"hidden":["--uninstall;x"]}}"#).is_err());
    }

    #[test]
    fn each_panel_goes_to_the_bottom_or_the_top() {
        let changes =
            Changes::from_json(r#"{"places":{"volume-hud":"top","dictation-hud":"bottom"}}"#)
                .expect("places");
        assert_eq!(
            changes.args().expect("args"),
            ["--set", "dictation-hud=bottom", "--set", "volume-hud=top"]
        );
        assert!(Changes::from_json(r#"{"places":{"volume-hud":"middle"}}"#).is_err());
        assert!(Changes::from_json(r#"{"places":{"dock":"top"}}"#).is_err());
        assert!(Changes::from_json(r#"{"places":{"volume-hud":"top; rm -rf ~"}}"#).is_err());
        let status = parse_status(
            r#"{"active":true,"features":{},"settings":{},"volume-hud":"top","dictation-hud":"bottom"}"#,
        )
        .expect("a status");
        assert_eq!(status.volume_hud.as_deref(), Some("top"));
        assert_eq!(status.dictation_hud.as_deref(), Some("bottom"));
    }

    #[test]
    fn the_clock_goes_to_one_of_three_places() {
        let changes = Changes::from_json(r#"{"clock":"center"}"#).expect("a place");
        assert_eq!(changes.args().expect("args"), ["--set", "clock=center"]);
        assert!(!changes.is_empty());
        assert!(Changes::from_json(r#"{"clock":"top; rm -rf ~"}"#).is_err());
        let status = parse_status(r#"{"active":true,"features":{},"settings":{},"clock":"left"}"#)
            .expect("valid");
        assert_eq!(status.clock.as_deref(), Some("left"));
        let older = parse_status(r#"{"active":true,"features":{},"settings":{}}"#).expect("valid");
        assert_eq!(older.clock, None);
    }

    #[test]
    fn the_shown_widgets_are_checked_and_passed_together() {
        let changes = Changes::from_json(r#"{"widgets":["clock","playing"]}"#).expect("widgets");
        assert_eq!(changes.args().expect("args"), ["--show-widgets", "clock,playing"]);
        assert!(!changes.is_empty());
        assert!(Changes::from_json(r#"{"widgets":[]}"#).is_err());
        assert!(Changes::from_json(r#"{"widgets":["clock,dock"]}"#).is_err());
        let status =
            parse_status(r#"{"active":true,"features":{},"settings":{},"widgets":["weather"]}"#)
                .expect("valid");
        assert_eq!(status.widgets, Some(vec!["weather".to_owned()]));
        let older = parse_status(r#"{"active":true,"features":{},"settings":{}}"#).expect("valid");
        assert_eq!(older.widgets, None);
    }

    #[test]
    fn bad_changes_are_refused_before_install_sh_runs() {
        assert!(Changes::from_json(r#"{"add":["everything"]}"#).is_err());
        assert!(Changes::from_json(r#"{"set":{"glass":3}}"#).is_err());
        assert!(Changes::from_json(r#"{"add":["dock"],"remove":["dock"]}"#).is_err());
        assert!(Changes::from_json("not json").is_err());
        for bad in ["", "--uninstall", "Tokyo\nNight"] {
            let json = serde_json::json!({"remove": ["theme"], "switchTo": bad}).to_string();
            assert!(Changes::from_json(&json).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn removing_the_current_theme_switches_first() {
        let changes = Changes::from_json(r#"{"remove":["theme"],"switchTo":"Tokyo Night"}"#).expect("valid");
        assert_eq!(changes.args().expect("args")[..4], ["--switch-to", "Tokyo Night", "--remove", "theme"]);
        let status = parse_status(r#"{"active":true,"features":{},"settings":{},"themes":["Tokyo Night"]}"#).expect("valid");
        assert_eq!(status.themes, ["Tokyo Night"]);
        let older = parse_status(r#"{"active":true,"features":{},"settings":{}}"#).expect("older");
        assert!(older.themes.is_empty());
        assert_eq!(older.previous_theme, None);
        let status = parse_status(r#"{"active":true,"features":{},"settings":{},"previous-theme":"Nord"}"#).expect("valid");
        assert_eq!(status.previous_theme.as_deref(), Some("Nord"));
    }

    #[test]
    fn studio_updates_need_the_themes_get_sh() {
        let dir = env::temp_dir().join(format!("studio-no-get-sh-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("a folder");
        let error = update_studio(&dir).expect_err("no get.sh to run");
        assert!(error.to_string().contains("Update the theme first"), "{error}");
        let _ = std::fs::remove_dir_all(&dir);
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
    fn the_logo_turns_green_and_nothing_else_changes() {
        let logo =
            r##"<svg fill="none"><g fill="#000"><path d="m1 1"/></g><path fill="black"/></svg>"##;
        assert_eq!(
            recolor_logo(logo),
            r##"<svg fill="none"><g fill="#9ECE6A"><path d="m1 1"/></g><path fill="#9ECE6A"/></svg>"##
        );
    }

    #[test]
    fn an_update_reinstalls_what_is_in_use_but_not_the_icons() {
        let status = parse_status(r#"{"active":true,"features":{"theme":true,"icons":true,"dock":true,"lock":false},"settings":{}}"#)
            .expect("valid report");
        let names: Vec<String> = reinstall(&status).iter().map(ToString::to_string).collect();
        assert_eq!(names, ["dock", "theme"]);
    }

    #[test]
    fn the_logo_is_a_data_url_with_what_urls_need_escaped() {
        let url = data_url("<svg fill=\"#9ECE6A\">100%\n</svg>");
        assert_eq!(url, "data:image/svg+xml;charset=utf-8,%3Csvg fill=%22%239ECE6A%22%3E100%25%0A%3C/svg%3E");
        assert!(!url.contains('#'), "a # would end the URL there");
    }

    #[test]
    fn an_update_pulled_but_not_installed_stays_offered() {
        let dir = env::temp_dir().join(format!("studio-marker-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        assert!(Command::new("git").args(["init", "-q"]).arg(&dir).status().expect("git").success());
        assert!(incoming(&dir).is_empty());
        std::fs::write(needs_install(&dir), "").expect("the marker");
        assert_eq!(incoming(&dir).len(), 1);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn releases_are_tags_and_never_older_than_what_is_here() {
        assert_eq!(newest(["v2.0.0-rc1", "v1.10.0", "v1.9.0", "latest"].into_iter()), Some("v1.10.0".to_owned()));
        assert_eq!(newest(["v", "nightly"].into_iter()), None);

        let root = env::temp_dir().join(format!("studio-releases-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (origin, here) = (root.join("origin"), root.join("here"));
        let run = |dir: &Path, args: &[&str]| {
            let ok = Command::new("git").arg("-C").arg(dir)
                .args(["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false"])
                .args(args).output().expect("git").status.success();
            assert!(ok, "git {args:?}");
        };
        std::fs::create_dir_all(origin.join("studio")).expect("the origin");
        run(&origin, &["init", "-q", "-b", "main"]);
        let commit = |file: &str, subject: &str| {
            std::fs::write(origin.join(file), subject).expect("a file");
            run(&origin, &["add", "-A"]);
            run(&origin, &["commit", "-q", "-m", subject]);
        };
        commit("theme.txt", "The first theme");
        run(&origin, &["tag", "v1.0.0"]);
        let url = format!("file://{}", origin.display());
        run(&root, &["clone", "-q", "--depth", "1", "--branch", "v1.0.0", &url, "here"]);
        assert!(incoming(&here).is_empty(), "nothing newer yet");
        assert!(version(&here).is_some_and(|v| v.starts_with("v1.0.0, ")), "{:?}", version(&here));

        commit("studio/app.txt", "Only Studio");
        commit("theme.txt", "A better dock");
        run(&origin, &["tag", "v1.1.0"]);
        commit("theme.txt", "Not released yet");
        fetch(&here).expect("the fetch");
        assert_eq!(incoming(&here), ["A better dock"], "up to the release, without Studio's");

        // A download from before releases, on main past the newest one, isn't
        // offered an older theme.
        let _ = std::fs::remove_dir_all(&here);
        run(&root, &["clone", "-q", &url, "here"]);
        assert!(incoming(&here).is_empty());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn warnings_are_stderr_lines_that_say_something() {
        assert_eq!(
            warnings(b"    Could not patch the menu\n\n    Install Inter\n"),
            "Could not patch the menu\nInstall Inter"
        );
        assert_eq!(warnings(b"\n  \n"), "");
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

/// Studio against the real `install.sh` next to it, in a throwaway home with
/// a fake `omarchy`: the names, ranges and arguments Studio sends are ones the
/// installer takes, and what the installer prints is what Studio reads. A
/// change to either side that breaks the other fails here.
#[cfg(test)]
mod contract {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::process::Output;

    struct Home(PathBuf);

    impl Drop for Home {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    impl Home {
        fn new() -> Self {
            let home = env::temp_dir().join(format!("studio-contract-{}", std::process::id()));
            let _ = fs::remove_dir_all(&home);
            let bin = home.join("bin");
            fs::create_dir_all(&bin).expect("a throwaway home");
            // Every call succeeds quietly and nothing reaches the real desktop;
            // bar moves are logged, so the test sees what was asked of the bar.
            let fakes = [
                ("omarchy", "#!/bin/sh\n[ \"$1 $2\" = \"theme current\" ] && echo Other\n[ \"$1 $2\" = \"theme list\" ] && printf 'Macos\\nOther\\n'\n[ \"$1 $2\" = \"bar move\" ] && echo \"$*\" >> \"$HOME/bar.log\"\nexit 0\n"),
                ("hyprctl", "#!/bin/sh\nexit 0\n"),
                ("omarchy-shell", "#!/bin/sh\nexit 0\n"),
                ("fc-list", "#!/bin/sh\necho Inter\n"),
            ];
            for (name, script) in fakes {
                let file = bin.join(name);
                fs::write(&file, script).expect("a fake command");
                fs::set_permissions(&file, fs::Permissions::from_mode(0o755)).expect("executable");
            }
            // Omarchy's own default shell.json, the one file of it the
            // installer reads, as an empty one: the same here as in CI.
            let defaults = home.join("omarchy/config/omarchy");
            fs::create_dir_all(&defaults).expect("Omarchy's defaults");
            fs::write(defaults.join("shell.json"), "{}").expect("Omarchy's default shell.json");
            Home(home)
        }

        fn install_sh(&self, args: &[&str]) -> Output {
            let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
            let path = format!("{}:{}", self.0.join("bin").display(), env::var("PATH").unwrap_or_default());
            Command::new("bash")
                .arg(repo.join("install.sh"))
                .args(args)
                .env("HOME", &self.0)
                .env("XDG_CONFIG_HOME", self.0.join(".config"))
                .env("PATH", path)
                .env("USER", "studio")
                .env("OMARCHY_PATH", self.0.join("omarchy"))
                .env_remove("MACOS_THEME_NO_SNAPSHOT")
                .output()
                .expect("bash runs install.sh")
        }

        fn ok(&self, args: &[&str]) -> String {
            let out = self.install_sh(args);
            assert!(out.status.success(), "install.sh {args:?}: {}", String::from_utf8_lossy(&out.stderr));
            String::from_utf8(out.stdout).expect("text")
        }
    }

    /// A list `install.sh` keeps as `NAME="a b c"`.
    fn install_sh_list(name: &str) -> Vec<String> {
        let script = fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("../install.sh")).expect("install.sh");
        let line = script
            .lines()
            .find_map(|line| line.strip_prefix(&format!("{name}=\"")))
            .unwrap_or_else(|| panic!("install.sh has no {name}"));
        line.trim_end_matches('"').split_whitespace().map(str::to_owned).collect()
    }

    #[test]
    fn studio_knows_the_installer_lists() {
        assert_eq!(install_sh_list("FEATURES"), PIECES);
        assert_eq!(install_sh_list("DESKTOP_WIDGETS"), DESKTOP_WIDGETS);
        assert_eq!(install_sh_list("BAR_SECTIONS"), BAR_SECTIONS);
    }

    #[test]
    fn the_installer_takes_what_studio_sends_and_studio_reads_what_it_says() {
        let home = Home::new();
        home.ok(&["--add", "theme"]);

        // Every setting's range: its ends are taken, a step past them refused.
        for (key, low, high, whole) in SETTINGS {
            let step = if whole { 1.0 } else { 0.01 };
            for value in [low, high] {
                home.ok(&["--set", &Setting::try_new(key, value).expect("in range").arg()]);
            }
            for value in [low - step, high + step] {
                let arg = format!("{key}={}", (value * 100.0).round() / 100.0);
                assert!(!home.install_sh(&["--set", &arg]).status.success(), "install.sh took {arg}");
            }
        }

        // An Apply as the window sends one, every kind of change in it.
        let changes = Changes::from_json(
            r#"{"add": ["dock", "widgets"], "remove": ["rows"],
                "set": {"glass": 0.8, "magnification": 1.5, "dock-size": 56, "blur": 12},
                "clock": "center", "places": {"volume-hud": "top", "dictation-hud": "bottom"},
                "widgets": ["clock", "weather"]}"#,
        )
        .expect("changes the window can send");
        let args = changes.args().expect("args");
        home.ok(&args.iter().map(String::as_str).collect::<Vec<_>>());

        // What it reports back, read by Studio's own readers.
        let status = parse_status(&home.ok(&["--status", "--json"])).expect("a status Studio reads");
        assert_eq!(status.features.keys().map(String::as_str).collect::<Vec<_>>(), {
            let mut pieces = PIECES.to_vec();
            pieces.sort_unstable();
            pieces
        });
        for (key, ..) in SETTINGS {
            assert!(status.settings.contains_key(key), "the status leaves out {key}");
        }
        assert_eq!(status.settings.get("glass"), Some(&0.8));
        // The clock moves through Omarchy's bar, which the fake only logs.
        let bar_log = fs::read_to_string(home.0.join("bar.log")).unwrap_or_default();
        assert!(bar_log.contains("bar move omarchy.clock --section center"), "{bar_log}");
        assert_eq!(status.volume_hud.as_deref(), Some("top"));
        assert_eq!(status.widgets, Some(vec!["clock".to_owned(), "weather".to_owned()]));
        assert!(status.features["dock"]);

        home.ok(&["--backup"]);
        let backups: Vec<Backup> = serde_json::from_str(&home.ok(&["--backups", "--json"])).expect("backups Studio reads");
        assert!(backups.len() >= 2, "{backups:?}");
        assert!(backup_id(&backups[0].id).is_ok(), "an id Studio would restore: {}", backups[0].id);
        serde_json::from_str::<serde_json::Value>(&home.ok(&["--bar", "--json"])).expect("a bar Studio reads");
        assert_eq!(status.previous_theme.as_deref(), Some("Other"));

        // Remove macOS Theme, as the About page sends it: every piece off at once.
        let all: Vec<String> = PIECES.iter().map(|p| format!("\"{p}\"")).collect();
        let changes = Changes::from_json(&format!(r#"{{"remove": [{}]}}"#, all.join(","))).expect("the removal");
        home.ok(&changes.args().expect("args").iter().map(String::as_str).collect::<Vec<_>>());
        let status = parse_status(&home.ok(&["--status", "--json"])).expect("a status Studio reads");
        assert!(status.features.values().all(|on| !on), "{:?}", status.features);
    }
}
