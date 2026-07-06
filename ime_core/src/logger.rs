use std::sync::{Arc, OnceLock, RwLock};

use crate::error::ImeError;

pub type LogSink = Arc<dyn Fn(String) + Send + Sync + 'static>;

static LOG_SINK: OnceLock<RwLock<Option<LogSink>>> = OnceLock::new();

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LogEvent {
    ModuleStarted(&'static str),
    Error(ImeError),
    Timing {
        module: &'static str,
        operation: &'static str,
        elapsed_ms: u64,
    },
}

pub fn format_log_event(event: &LogEvent) -> String {
    match event {
        LogEvent::ModuleStarted(module) => format!("module_started module={module}"),
        LogEvent::Error(error) => format!("error code={}", error.code()),
        LogEvent::Timing {
            module,
            operation,
            elapsed_ms,
        } => format!("timing module={module} operation={operation} elapsed_ms={elapsed_ms}"),
    }
}

pub fn set_log_sink(sink: Option<LogSink>) {
    let lock = LOG_SINK.get_or_init(|| RwLock::new(None));
    if let Ok(mut writer) = lock.write() {
        *writer = sink;
    }
}

pub fn emit_log_event(event: LogEvent) {
    let message = format_log_event(&event);
    let lock = LOG_SINK.get_or_init(|| RwLock::new(None));
    if let Ok(reader) = lock.read() {
        if let Some(sink) = reader.as_ref() {
            sink(message);
        }
    }
}

pub fn emit_error(error: ImeError) {
    emit_log_event(LogEvent::Error(error));
}
