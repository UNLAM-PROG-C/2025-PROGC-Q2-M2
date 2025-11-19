use chrono::Local;
use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::Path,
    sync::{Mutex, OnceLock},
};

struct Logger {
    file: Mutex<std::fs::File>,
}

impl Logger {
    fn new(path: &Path) -> io::Result<Self> {
        if let Err(err) = fs::remove_file(path)
            && err.kind() != io::ErrorKind::NotFound
        {
            return Err(err);
        }

        let file = OpenOptions::new().create(true).append(true).open(path)?;

        Ok(Self {
            file: Mutex::new(file),
        })
    }

    fn log_line(&self, message: &str) {
        let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
        let line = format!("[{timestamp}] {message}");
        println!("{}", line);

        if let Ok(mut file) = self.file.lock() {
            if writeln!(file, "{}", line).is_err() {
                eprintln!("Failed to write to log file");
            } else if file.flush().is_err() {
                eprintln!("Failed to flush log file");
            }
        } else {
            eprintln!("Failed to acquire log file lock");
        }
    }
}

static LOGGER: OnceLock<Logger> = OnceLock::new();

pub fn init() -> io::Result<()> {
    let logger = Logger::new(Path::new("server.log"))?;
    LOGGER
        .set(logger)
        .map_err(|_| io::Error::new(io::ErrorKind::AlreadyExists, "Logger already initialized"))?;
    log("Logger initialized");
    Ok(())
}

pub fn log(message: &str) {
    if let Some(logger) = LOGGER.get() {
        logger.log_line(message);
    } else {
        println!("{message}");
    }
}
