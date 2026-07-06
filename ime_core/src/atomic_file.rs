use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) struct AtomicFile {
    target_path: PathBuf,
    temp_path: PathBuf,
    file: Option<fs::File>,
    finished: bool,
}

impl AtomicFile {
    pub(crate) fn create(target_path: impl AsRef<Path>) -> io::Result<Self> {
        let target_path = target_path.as_ref().to_path_buf();
        if let Some(parent) = target_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let temp_path = unique_sibling_path(&target_path, "tmp");
        let file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp_path)?;

        Ok(Self {
            target_path,
            temp_path,
            file: Some(file),
            finished: false,
        })
    }

    pub(crate) fn finish(mut self) -> io::Result<()> {
        let Some(file) = self.file.take() else {
            return Err(io::Error::other("atomic file already closed"));
        };
        file.sync_all()?;
        drop(file);
        replace_file(&self.temp_path, &self.target_path)?;
        self.finished = true;
        Ok(())
    }
}

impl Write for AtomicFile {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.file
            .as_mut()
            .ok_or_else(|| io::Error::other("atomic file already closed"))?
            .write(buf)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file
            .as_mut()
            .ok_or_else(|| io::Error::other("atomic file already closed"))?
            .flush()
    }
}

impl Drop for AtomicFile {
    fn drop(&mut self) {
        if !self.finished {
            let _ = fs::remove_file(&self.temp_path);
        }
    }
}

#[cfg(not(windows))]
fn replace_file(temp_path: &Path, target_path: &Path) -> io::Result<()> {
    fs::rename(temp_path, target_path)
}

#[cfg(windows)]
fn replace_file(temp_path: &Path, target_path: &Path) -> io::Result<()> {
    match fs::rename(temp_path, target_path) {
        Ok(()) => return Ok(()),
        Err(error) if target_path.exists() => {
            if error.kind() != io::ErrorKind::AlreadyExists
                && error.kind() != io::ErrorKind::PermissionDenied
            {
                return Err(error);
            }
        }
        Err(error) => return Err(error),
    }

    let backup_path = unique_sibling_path(target_path, "bak");
    fs::rename(target_path, &backup_path)?;

    match fs::rename(temp_path, target_path) {
        Ok(()) => {
            let _ = fs::remove_file(&backup_path);
            Ok(())
        }
        Err(error) => {
            let _ = fs::rename(&backup_path, target_path);
            Err(error)
        }
    }
}

fn unique_sibling_path(target_path: &Path, extension: &str) -> PathBuf {
    let parent = target_path.parent().unwrap_or_else(|| Path::new("."));
    let file_name = target_path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("private_pinyin");
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();

    parent.join(format!(
        ".{file_name}.{}.{}.{extension}",
        std::process::id(),
        nonce
    ))
}
