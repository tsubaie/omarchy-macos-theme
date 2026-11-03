//! The object QML talks to: what is installed, and the actions that change it.
//! Every action runs `install.sh` on a worker thread, so the window never stalls,
//! and reports back on the Qt thread.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        /// Qt's string type.
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        /// The theme's state and actions, as `ThemeBackend` in QML.
        #[qobject]
        #[qml_element]
        #[qproperty(QString, status_json, cxx_name = "statusJson")]
        #[qproperty(QString, backups_json, cxx_name = "backupsJson")]
        #[qproperty(QString, bar_json, cxx_name = "barJson")]
        // The one showing, yours and the theme's, as install.sh --backgrounds lists them.
        #[qproperty(QString, backgrounds_json, cxx_name = "backgroundsJson")]
        #[qproperty(bool, busy)]
        #[qproperty(bool, downloaded)]
        // Asking GitHub whether the theme has new commits, right now.
        #[qproperty(bool, checking)]
        #[qproperty(QString, error)]
        // All a failed command wrote, for "Show Details"; empty when there is no more to it.
        #[qproperty(QString, error_details, cxx_name = "errorDetails")]
        #[qproperty(QString, warning)]
        // What the running action is doing now, in install.sh's or git's words.
        #[qproperty(QString, stage)]
        #[qproperty(QString, theme_dir, cxx_name = "themeDir")]
        #[qproperty(QString, theme_version, cxx_name = "themeVersion")]
        #[qproperty(i32, updates, cxx_name = "updates")]
        // What an update brings in: its commits' subjects, one per line.
        #[qproperty(QString, update_notes, cxx_name = "updateNotes")]
        // Why the last check for updates failed (offline, say); empty when it worked.
        #[qproperty(QString, update_error, cxx_name = "updateError")]
        #[qproperty(QString, app_version, cxx_name = "appVersion")]
        #[qproperty(QString, omarchy_version, cxx_name = "omarchyVersion")]
        #[qproperty(QString, omarchy_logo, cxx_name = "omarchyLogo")]
        type ThemeBackend = super::ThemeBackendRust;

        /// Reads what is installed again, and checks the theme for updates.
        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        /// Reads what is installed, the bar and the backups again when
        /// something they come from changed outside Studio (a widget removed
        /// on the desktop, say), without touching what an action shows;
        /// cheap to call often.
        #[qinvokable]
        #[cxx_name = "rereadIfChanged"]
        fn reread_if_changed(self: Pin<&mut Self>);

        /// Asks GitHub whether the theme has new commits; `checking` while it does.
        #[qinvokable]
        #[cxx_name = "checkTheme"]
        fn check_theme(self: Pin<&mut Self>);

        /// Applies the changes waiting in the window, as JSON:
        /// `{"add": [..], "remove": [..], "set": {key: value}}`, in one
        /// `install.sh` call so the theme reloads once.
        #[qinvokable]
        fn apply(self: Pin<&mut Self>, changes: &QString);

        /// Shows a setting at once while its slider is dragged, without
        /// waiting for Apply; the newest value wins.
        #[qinvokable]
        fn preview(self: Pin<&mut Self>, key: &QString, value: f64);

        /// Pulls the theme's new commits and installs the pieces in use again.
        #[qinvokable]
        fn update(self: Pin<&mut Self>);

        /// Takes a snapshot now.
        #[qinvokable]
        #[cxx_name = "backUp"]
        fn back_up(self: Pin<&mut Self>);

        /// Puts a snapshot back, by its id; the present is snapshotted first.
        #[qinvokable]
        fn restore(self: Pin<&mut Self>, id: &QString);

        /// Writes the user's choices to a file, for another computer or a new install.
        #[qinvokable]
        #[cxx_name = "exportTo"]
        fn export_to(self: Pin<&mut Self>, file: &QString);

        /// Applies an export; the present is snapshotted first.
        #[qinvokable]
        #[cxx_name = "importFrom"]
        fn import_from(self: Pin<&mut Self>, file: &QString);

        /// Shows a background and has the theme remember it; snapshotted first.
        #[qinvokable]
        #[cxx_name = "setBackground"]
        fn set_background(self: Pin<&mut Self>, file: &QString);

        /// Sets the bar's logo to one of the theme's, by name.
        #[qinvokable]
        #[cxx_name = "setLogo"]
        fn set_logo(self: Pin<&mut Self>, name: &QString);

        /// Sets the bar's logo to your own SVG or PNG.
        #[qinvokable]
        #[cxx_name = "setLogoFile"]
        fn set_logo_file(self: Pin<&mut Self>, file: &QString);

        /// Copies pictures into the user's backgrounds folder, given as a
        /// JSON array of paths.
        #[qinvokable]
        #[cxx_name = "addBackgrounds"]
        fn add_backgrounds(self: Pin<&mut Self>, files: &QString);

        /// Downloads the theme, when it isn't there yet.
        #[qinvokable]
        fn download(self: Pin<&mut Self>);

        /// Undoes a theme update: restores the backup it took, by its id, and
        /// keeps the update offered.
        #[qinvokable]
        #[cxx_name = "undoUpdate"]
        fn undo_update(self: Pin<&mut Self>, id: &QString);

        /// Puts Studio's newest release in place of this one.
        #[qinvokable]
        #[cxx_name = "updateStudio"]
        fn update_studio(self: Pin<&mut Self>);

        /// Opens Studio again, from where its updates go; the window then quits.
        #[qinvokable]
        fn reopen(&self) -> bool;

        /// Stops the running action: its command, and what that started.
        #[qinvokable]
        fn cancel(self: Pin<&mut Self>);

        /// Minimizes the window into the dock; false when it should minimize
        /// the ordinary way instead.
        #[qinvokable]
        #[cxx_name = "minimizeWindow"]
        fn minimize_window(&self) -> bool;

        /// Makes a folder (and those above it) if it isn't there, so it can be
        /// opened: the one your own desktop widgets go in.
        #[qinvokable]
        #[cxx_name = "makeFolder"]
        fn make_folder(&self, path: &QString) -> bool;

        /// Fills the screen with the window, or puts it back.
        #[qinvokable]
        #[cxx_name = "zoomWindow"]
        fn zoom_window(&self);

        /// Shows the lock screen without locking.
        #[qinvokable]
        #[cxx_name = "previewLock"]
        fn preview_lock(&self);
    }

    impl cxx_qt::Threading for ThemeBackend {}
}

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::pin::Pin;
use std::process::Command;
use std::sync::{Arc, Mutex, PoisonError};
use std::thread;
use std::time::SystemTime;

use anyhow::Result;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::install::{self, Backup, Changes, Setting, Status};

/// The Rust side of [`qobject::ThemeBackend`].
pub struct ThemeBackendRust {
    status_json: QString,
    backups_json: QString,
    bar_json: QString,
    backgrounds_json: QString,
    busy: bool,
    downloaded: bool,
    checking: bool,
    error: QString,
    error_details: QString,
    warning: QString,
    stage: QString,
    theme_dir: QString,
    theme_version: QString,
    updates: i32,
    update_notes: QString,
    update_error: QString,
    app_version: QString,
    omarchy_version: QString,
    omarchy_logo: QString,
    dir: PathBuf,
    previews: Arc<Mutex<Previews>>,
    watch: Arc<Mutex<install::Watch>>,
    /// The newest change outside Studio, as last looked at.
    outside_seen: Option<SystemTime>,
    /// Hyprland's workspaces, as last looked at.
    workspaces_seen: Vec<i64>,
    rereading: bool,
    /// Actions started, so a reread an action overtook is dropped.
    runs: u64,
}

/// Settings waiting to be previewed, newest value per key, and whether a
/// worker is showing them: one `install.sh --preview` at a time.
#[derive(Default)]
struct Previews {
    waiting: BTreeMap<String, Setting>,
    running: bool,
}

impl Default for ThemeBackendRust {
    fn default() -> Self {
        // main() has checked there is one, and exits if not.
        let dir = install::theme_dir().unwrap_or_default();
        Self {
            status_json: QString::from("{}"),
            backups_json: QString::from("[]"),
            bar_json: QString::from("{}"),
            backgrounds_json: QString::from("{}"),
            busy: false,
            downloaded: install::is_downloaded(&dir),
            checking: false,
            error: QString::default(),
            error_details: QString::default(),
            warning: QString::default(),
            stage: QString::default(),
            theme_dir: QString::from(dir.display().to_string().as_str()),
            theme_version: QString::default(),
            updates: 0,
            update_notes: QString::default(),
            update_error: QString::default(),
            // A release build carries its release's date name (from CI); a local
            // build, Cargo's version.
            app_version: QString::from(option_env!("STUDIO_RELEASE").unwrap_or(env!("CARGO_PKG_VERSION"))),
            omarchy_version: QString::from(install::omarchy_version().unwrap_or_default().as_str()),
            // Omarchy's own logo, read where Omarchy keeps it rather than
            // copied in, in its green.
            omarchy_logo: QString::from(install::green_omarchy_logo().unwrap_or_default().as_str()),
            dir,
            previews: Arc::default(),
            watch: Arc::default(),
            outside_seen: install::changed_outside(),
            workspaces_seen: install::workspace_ids(),
            rereading: false,
            runs: 0,
        }
    }
}

/// What a finished job hands back to the Qt thread.
struct Outcome {
    status: Result<Status>,
    backups: Result<Vec<Backup>>,
    version: Option<String>,
    bar: Option<String>,
    backgrounds: Option<String>,
    incoming: Vec<String>,
    error: Option<String>,
    error_details: String,
    warning: String,
}

impl qobject::ThemeBackend {
    /// Reads the status, then asks GitHub for the theme's new commits on a
    /// thread of its own, so a slow or absent network keeps nothing waiting.
    pub fn refresh(mut self: Pin<&mut Self>) {
        self.as_mut().run(|_| Ok(install::Warnings::new()));
        self.check_theme();
    }

    pub fn check_theme(mut self: Pin<&mut Self>) {
        let dir = self.rust().dir.clone();
        if *self.checking() || !install::is_downloaded(&dir) {
            return;
        }
        self.as_mut().set_checking(true);
        let qt_thread = self.qt_thread();
        thread::spawn(move || {
            let checked = install::fetch(&dir).map(|()| install::incoming(&dir));
            let queued = qt_thread.queue(move |mut backend| {
                match checked {
                    Ok(incoming) => {
                        backend.as_mut().set_incoming(&incoming);
                        backend.as_mut().set_update_error(QString::default());
                    }
                    Err(error) => backend.as_mut().set_update_error(QString::from(format!("{error:#}").as_str())),
                }
                backend.as_mut().set_checking(false);
            });
            if let Err(error) = queued {
                eprintln!("the window closed before GitHub answered: {error}");
            }
        });
    }

    pub fn reread_if_changed(mut self: Pin<&mut Self>) {
        if *self.busy() || self.rust().rereading {
            return;
        }
        // Downloaded from a terminal while Studio waited on its Download screen.
        if !*self.downloaded() {
            if install::is_downloaded(&self.rust().dir) {
                self.refresh();
            }
            return;
        }
        let changed = install::changed_outside();
        let workspaces = install::workspace_ids();
        if changed == self.rust().outside_seen && workspaces == self.rust().workspaces_seen {
            return;
        }
        let runs = self.rust().runs;
        let mut rust = self.as_mut().rust_mut();
        rust.outside_seen = changed;
        rust.workspaces_seen = workspaces;
        rust.rereading = true;
        let dir = self.rust().dir.clone();
        let qt_thread = self.qt_thread();
        thread::spawn(move || {
            let status = install::status(&dir);
            let bar = install::bar(&dir).ok();
            let backups = install::backups(&dir).ok();
            let backgrounds = install::backgrounds(&dir).ok();
            let queued = qt_thread.queue(move |mut backend| {
                backend.as_mut().rust_mut().rereading = false;
                // An action since reads it again itself, and newer.
                if *backend.busy() || backend.rust().runs != runs {
                    return;
                }
                // shortcut: a failed reread is dropped quietly; the next change or action tries again.
                if let Ok(status) = status {
                    let json = serde_json::to_string(&status).unwrap_or_else(|_| "{}".to_owned());
                    backend.as_mut().set_status_json(QString::from(json.as_str()));
                }
                if let Some(bar) = bar {
                    backend.as_mut().set_bar_json(QString::from(bar.as_str()));
                }
                if let Some(json) = backups.and_then(|b| serde_json::to_string(&b).ok()) {
                    backend.as_mut().set_backups_json(QString::from(json.as_str()));
                }
                if let Some(backgrounds) = backgrounds {
                    backend.as_mut().set_backgrounds_json(QString::from(backgrounds.as_str()));
                }
            });
            if let Err(error) = queued {
                eprintln!("the window closed before the theme answered: {error}");
            }
        });
    }

    pub fn update(self: Pin<&mut Self>) {
        self.run(install::update);
    }

    pub fn apply(self: Pin<&mut Self>, changes: &QString) {
        match Changes::from_json(&changes.to_string()) {
            Ok(changes) => self.run(move |dir| install::apply(dir, &changes)),
            Err(error) => self.set_error(QString::from(format!("{error:#}").as_str())),
        }
    }

    pub fn preview(self: Pin<&mut Self>, key: &QString, value: f64) {
        // Not while Apply, Update or a restore writes the theme: a preview
        // then could land between their writes. The slider shows again once
        // they are done.
        if *self.busy() {
            return;
        }
        let setting = match Setting::try_new(&key.to_string(), value) {
            Ok(setting) => setting,
            Err(error) => return eprintln!("not previewing: {error:#}"),
        };
        let previews = Arc::clone(&self.rust().previews);
        {
            let mut queue = previews.lock().unwrap_or_else(PoisonError::into_inner);
            queue.waiting.insert(key.to_string(), setting);
            if queue.running {
                return;
            }
            queue.running = true;
        }
        let dir = self.rust().dir.clone();
        thread::spawn(move || loop {
            let batch: Vec<Setting> = {
                let mut queue = previews.lock().unwrap_or_else(PoisonError::into_inner);
                if queue.waiting.is_empty() {
                    queue.running = false;
                    return;
                }
                std::mem::take(&mut queue.waiting).into_values().collect()
            };
            if let Err(error) = install::preview(&dir, &batch) {
                eprintln!("could not preview: {error:#}");
            }
        });
    }

    pub fn back_up(self: Pin<&mut Self>) {
        self.run(install::back_up);
    }

    pub fn restore(self: Pin<&mut Self>, id: &QString) {
        match install::backup_id(&id.to_string()) {
            Ok(id) => self.run(move |dir| install::restore(dir, &id)),
            Err(error) => self.set_error(QString::from(format!("{error:#}").as_str())),
        }
    }

    pub fn export_to(self: Pin<&mut Self>, file: &QString) {
        let file = PathBuf::from(file.to_string());
        self.run(move |dir| install::export(dir, &file));
    }

    pub fn import_from(self: Pin<&mut Self>, file: &QString) {
        let file = PathBuf::from(file.to_string());
        self.run(move |dir| install::import(dir, &file));
    }

    pub fn set_background(self: Pin<&mut Self>, file: &QString) {
        let file = PathBuf::from(file.to_string());
        self.run(move |dir| install::set_background(dir, &file));
    }

    pub fn set_logo(self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        self.run(move |dir| install::set_logo(dir, &name));
    }

    pub fn set_logo_file(self: Pin<&mut Self>, file: &QString) {
        let file = PathBuf::from(file.to_string());
        self.run(move |dir| install::set_logo_file(dir, &file));
    }

    pub fn add_backgrounds(self: Pin<&mut Self>, files: &QString) {
        match serde_json::from_str::<Vec<PathBuf>>(&files.to_string()) {
            Ok(files) => self.run(move |dir| install::add_backgrounds(dir, &files)),
            Err(error) => self.set_error(QString::from(format!("reading the pictures to add: {error}").as_str())),
        }
    }

    pub fn download(self: Pin<&mut Self>) {
        self.run(install::download);
    }

    pub fn undo_update(self: Pin<&mut Self>, id: &QString) {
        match install::backup_id(&id.to_string()) {
            Ok(id) => self.run(move |dir| install::undo_update(dir, &id)),
            Err(error) => self.set_error(QString::from(format!("{error:#}").as_str())),
        }
    }

    pub fn update_studio(self: Pin<&mut Self>) {
        self.run(install::update_studio);
    }

    pub fn reopen(&self) -> bool {
        let Some(binary) = install::studio_binary() else { return false };
        // On the page shown now, as it was left.
        match Command::new(&binary).spawn() {
            Ok(_) => true,
            Err(error) => {
                eprintln!("could not reopen {}: {error}", binary.display());
                false
            }
        }
    }

    pub fn cancel(self: Pin<&mut Self>) {
        if *self.busy() {
            install::stop(&self.rust().watch);
        }
    }

    pub fn make_folder(&self, path: &QString) -> bool {
        std::fs::create_dir_all(path.to_string()).is_ok()
    }

    pub fn minimize_window(&self) -> bool {
        crate::window::minimize()
    }

    pub fn zoom_window(&self) {
        crate::window::zoom();
    }

    pub fn preview_lock(&self) {
        // Fire and forget: the shell shows it, and a click closes it.
        if let Err(error) = Command::new("omarchy-shell")
            .args(["lock", "preview"])
            .spawn()
        {
            eprintln!("could not preview the lock screen: {error}");
        }
    }

    /// Runs `job` on a worker thread, then reads the status again, and shows
    /// both on the Qt thread. One job at a time: a click while busy is ignored.
    fn run<F>(mut self: Pin<&mut Self>, job: F)
    where
        F: FnOnce(&std::path::Path) -> Result<install::Warnings> + Send + 'static,
    {
        if *self.busy() {
            return;
        }
        self.as_mut().set_busy(true);
        self.as_mut().rust_mut().runs += 1;
        self.as_mut().set_error(QString::default());
        self.as_mut().set_error_details(QString::default());
        self.as_mut().set_warning(QString::default());
        self.as_mut().set_stage(QString::default());

        let dir = self.rust().dir.clone();
        let qt_thread = self.qt_thread();
        let watch = Arc::clone(&self.rust().watch);
        *watch.lock().unwrap_or_else(PoisonError::into_inner) = install::Watch::default();
        // What its commands say they are doing, shown as it happens.
        let stages = qt_thread.clone();
        let report: install::Report = Arc::new(move |stage: &str| {
            let stage = QString::from(stage);
            let _ = stages.queue(move |backend| backend.set_stage(stage));
        });
        thread::spawn(move || {
            let done = install::watched(report, Arc::clone(&watch), || job(&dir));
            let stopped = watch.lock().unwrap_or_else(PoisonError::into_inner).stopped();
            let (error, error_details, warning) = match done {
                Ok(warning) => (None, String::new(), warning),
                // Stopped by the user: said plainly, not as a failure. A run
                // of install.sh backs up first, so what it did can be undone.
                Err(_) if stopped => (None, String::new(),
                    "Stopped before it finished. If it had begun changing the theme, Backups has how it was before.".to_owned()),
                Err(error) => {
                    let details = error.chain().find_map(|cause| cause.downcast_ref::<install::Failed>())
                        .map(|failed| failed.output.clone()).unwrap_or_default();
                    (Some(format!("{error:#}")), details, String::new())
                }
            };
            let downloaded = install::is_downloaded(&dir);
            let (status, backups) = if downloaded {
                (install::status(&dir), install::backups(&dir))
            } else {
                (Ok(Status::default()), Ok(Vec::new()))
            };
            let outcome = Outcome {
                status,
                backups,
                version: install::version(&dir),
                bar: downloaded.then(|| install::bar(&dir).ok()).flatten(),
                backgrounds: downloaded.then(|| install::backgrounds(&dir).ok()).flatten(),
                incoming: if downloaded { install::incoming(&dir) } else { Vec::new() },
                error,
                error_details,
                warning,
            };
            let queued = qt_thread.queue(move |mut backend| {
                backend.as_mut().set_downloaded(downloaded);
                backend.as_mut().finish(outcome);
            });
            if let Err(error) = queued {
                eprintln!("the window closed before the theme answered: {error}");
            }
        });
    }

    /// What an update would bring in: how many changes, and what they are.
    fn set_incoming(mut self: Pin<&mut Self>, incoming: &[String]) {
        self.as_mut().set_updates(i32::try_from(incoming.len()).unwrap_or(i32::MAX));
        self.as_mut().set_update_notes(QString::from(incoming.join("\n").as_str()));
    }

    fn finish(mut self: Pin<&mut Self>, outcome: Outcome) {
        // What the action itself changed was just read; no need to read it again.
        self.as_mut().rust_mut().outside_seen = install::changed_outside();
        self.as_mut().rust_mut().workspaces_seen = install::workspace_ids();
        self.as_mut().set_incoming(&outcome.incoming);
        self.as_mut()
            .set_theme_version(QString::from(outcome.version.unwrap_or_default().as_str()));
        let mut error = outcome.error;
        match outcome.status {
            Ok(status) => {
                let json = serde_json::to_string(&status).unwrap_or_else(|_| "{}".to_owned());
                self.as_mut().set_status_json(QString::from(json.as_str()));
            }
            Err(status_error) => {
                error.get_or_insert_with(|| format!("{status_error:#}"));
            }
        }
        // A theme older than the bar settings lists no bar; updating brings it.
        self.as_mut().set_bar_json(QString::from(
            outcome.bar.unwrap_or_else(|| "{}".to_owned()).as_str(),
        ));
        // Likewise a theme older than the Backgrounds page lists none.
        self.as_mut().set_backgrounds_json(QString::from(
            outcome.backgrounds.unwrap_or_else(|| "{}".to_owned()).as_str(),
        ));
        // A theme older than backups lists none; updating it brings them.
        let backups = outcome.backups.unwrap_or_default();
        let json = serde_json::to_string(&backups).unwrap_or_else(|_| "[]".to_owned());
        self.as_mut().set_backups_json(QString::from(json.as_str()));
        self.as_mut()
            .set_error(QString::from(error.unwrap_or_default().as_str()));
        self.as_mut()
            .set_error_details(QString::from(outcome.error_details.as_str()));
        self.as_mut().set_stage(QString::default());
        self.as_mut()
            .set_warning(QString::from(outcome.warning.as_str()));
        self.as_mut().set_busy(false);
    }
}
