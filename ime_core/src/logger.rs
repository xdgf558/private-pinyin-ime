use crate::error::ImeError;

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
