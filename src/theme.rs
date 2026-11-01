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
        #[qproperty(bool, busy)]
        #[qproperty(bool, downloaded)]
        #[qproperty(QString, error)]
        #[qproperty(QString, theme_dir, cxx_name = "themeDir")]
        type ThemeBackend = super::ThemeBackendRust;

        /// Reads what is installed again.
        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        /// Applies the changes waiting in the window, as JSON:
        /// `{"add": [..], "remove": [..], "set": {key: value}}`, in one
        /// `install.sh` call so the theme reloads once.
        #[qinvokable]
        fn apply(self: Pin<&mut Self>, changes: &QString);

        /// Downloads the theme, when it isn't there yet.
        #[qinvokable]
        fn download(self: Pin<&mut Self>);

        /// Shows the lock screen without locking.
        #[qinvokable]
        #[cxx_name = "previewLock"]
        fn preview_lock(&self);
    }

    impl cxx_qt::Threading for ThemeBackend {}
}

use std::path::PathBuf;
use std::pin::Pin;
use std::process::Command;
use std::thread;

use anyhow::Result;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::install::{self, Changes, Status};

/// The Rust side of [`qobject::ThemeBackend`].
pub struct ThemeBackendRust {
    status_json: QString,
    busy: bool,
    downloaded: bool,
    error: QString,
    theme_dir: QString,
    dir: PathBuf,
}

impl Default for ThemeBackendRust {
    fn default() -> Self {
        let dir = install::theme_dir();
        Self {
            status_json: QString::from("{}"),
            busy: false,
            downloaded: install::is_downloaded(&dir),
            error: QString::default(),
            theme_dir: QString::from(dir.display().to_string().as_str()),
            dir,
        }
    }
}

/// What a finished job hands back to the Qt thread.
struct Outcome {
    status: Result<Status>,
    error: Option<String>,
}

impl qobject::ThemeBackend {
    pub fn refresh(self: Pin<&mut Self>) {
        self.run(|_| Ok(()));
    }

    pub fn apply(self: Pin<&mut Self>, changes: &QString) {
        match Changes::from_json(&changes.to_string()) {
            Ok(changes) => self.run(move |dir| install::apply(dir, &changes)),
            Err(error) => self.set_error(QString::from(format!("{error:#}").as_str())),
        }
    }

    pub fn download(self: Pin<&mut Self>) {
        self.run(install::download);
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
        F: FnOnce(&std::path::Path) -> Result<()> + Send + 'static,
    {
        if *self.busy() {
            return;
        }
        self.as_mut().set_busy(true);
        self.as_mut().set_error(QString::default());

        let dir = self.rust().dir.clone();
        let qt_thread = self.qt_thread();
        thread::spawn(move || {
            let error = job(&dir).err().map(|error| format!("{error:#}"));
            let downloaded = install::is_downloaded(&dir);
            let status = if downloaded {
                install::status(&dir)
            } else {
                Ok(Status::default())
            };
            let outcome = Outcome { status, error };
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
        self.as_mut()
            .set_error(QString::from(error.unwrap_or_default().as_str()));
        self.as_mut().set_busy(false);
    }
}
