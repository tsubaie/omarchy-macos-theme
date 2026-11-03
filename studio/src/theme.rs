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
        #[qproperty(bool, busy)]
        #[qproperty(bool, downloaded)]
        #[qproperty(QString, error)]
        #[qproperty(QString, warning)]
        #[qproperty(QString, theme_dir, cxx_name = "themeDir")]
        #[qproperty(QString, theme_version, cxx_name = "themeVersion")]
        #[qproperty(i32, updates, cxx_name = "updates")]
        // Why the last check for updates failed (offline, say); empty when it worked.
        #[qproperty(QString, update_error, cxx_name = "updateError")]
        #[qproperty(QString, app_version, cxx_name = "appVersion")]
        #[qproperty(QString, omarchy_version, cxx_name = "omarchyVersion")]
        #[qproperty(QString, omarchy_logo, cxx_name = "omarchyLogo")]
        type ThemeBackend = super::ThemeBackendRust;

        /// Reads what is installed again.
        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

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

        /// Downloads the theme, when it isn't there yet.
        #[qinvokable]
        fn download(self: Pin<&mut Self>);

        /// Minimizes the window into the dock; false when it should minimize
        /// the ordinary way instead.
        #[qinvokable]
        #[cxx_name = "minimizeWindow"]
        fn minimize_window(&self) -> bool;

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

use anyhow::Result;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::install::{self, Backup, Changes, Setting, Status};

/// The Rust side of [`qobject::ThemeBackend`].
pub struct ThemeBackendRust {
    status_json: QString,
    backups_json: QString,
    bar_json: QString,
    busy: bool,
    downloaded: bool,
    error: QString,
    warning: QString,
    theme_dir: QString,
    theme_version: QString,
    updates: i32,
    update_error: QString,
    app_version: QString,
    omarchy_version: QString,
    omarchy_logo: QString,
    dir: PathBuf,
    previews: Arc<Mutex<Previews>>,
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
            busy: false,
            downloaded: install::is_downloaded(&dir),
            error: QString::default(),
            warning: QString::default(),
            theme_dir: QString::from(dir.display().to_string().as_str()),
            theme_version: QString::default(),
            updates: 0,
            update_error: QString::default(),
            app_version: QString::from(env!("CARGO_PKG_VERSION")),
            omarchy_version: QString::from(install::omarchy_version().unwrap_or_default().as_str()),
            // Omarchy's own logo, read where Omarchy keeps it rather than
            // copied in, in its green.
            omarchy_logo: QString::from(install::green_omarchy_logo().unwrap_or_default().as_str()),
            dir,
            previews: Arc::default(),
        }
    }
}

/// What a finished job hands back to the Qt thread.
struct Outcome {
    status: Result<Status>,
    backups: Result<Vec<Backup>>,
    version: Option<String>,
    bar: Option<String>,
    updates: u32,
    error: Option<String>,
    warning: String,
}

impl qobject::ThemeBackend {
    /// Reads the status, then asks GitHub for the theme's new commits on a
    /// thread of its own, so a slow or absent network keeps nothing waiting.
    pub fn refresh(mut self: Pin<&mut Self>) {
        self.as_mut().run(|_| Ok(install::Warnings::new()));
        let dir = self.rust().dir.clone();
        let qt_thread = self.qt_thread();
        thread::spawn(move || {
            if !install::is_downloaded(&dir) {
                return;
            }
            let checked = install::fetch(&dir).map(|()| install::updates_behind(&dir));
            let queued = qt_thread.queue(move |mut backend| match checked {
                Ok(updates) => {
                    backend.as_mut().set_updates(i32::try_from(updates).unwrap_or(i32::MAX));
                    backend.as_mut().set_update_error(QString::default());
                }
                Err(error) => backend.as_mut().set_update_error(QString::from(format!("{error:#}").as_str())),
            });
            if let Err(error) = queued {
                eprintln!("the window closed before GitHub answered: {error}");
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

    pub fn download(self: Pin<&mut Self>) {
        self.run(install::download);
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
        self.as_mut().set_error(QString::default());
        self.as_mut().set_warning(QString::default());

        let dir = self.rust().dir.clone();
        let qt_thread = self.qt_thread();
        thread::spawn(move || {
            let (error, warning) = match job(&dir) {
                Ok(warning) => (None, warning),
                Err(error) => (Some(format!("{error:#}")), String::new()),
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
                updates: if downloaded {
                    install::updates_behind(&dir)
                } else {
                    0
                },
                error,
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

    fn finish(mut self: Pin<&mut Self>, outcome: Outcome) {
        self.as_mut()
            .set_updates(i32::try_from(outcome.updates).unwrap_or(i32::MAX));
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
        // A theme older than backups lists none; updating it brings them.
        let backups = outcome.backups.unwrap_or_default();
        let json = serde_json::to_string(&backups).unwrap_or_else(|_| "[]".to_owned());
        self.as_mut().set_backups_json(QString::from(json.as_str()));
        self.as_mut()
            .set_error(QString::from(error.unwrap_or_default().as_str()));
        self.as_mut()
            .set_warning(QString::from(outcome.warning.as_str()));
        self.as_mut().set_busy(false);
    }
}
