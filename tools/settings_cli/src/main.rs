use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use ime_core::{ImeEngine, ImeSettings};

fn main() -> ExitCode {
    match run() {
        Ok(message) => {
            println!("{message}");
            ExitCode::SUCCESS
        }
        Err(message) => {
            eprintln!("{message}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<String, String> {
    let mut args = env::args().skip(1);
    let Some(command) = args.next() else {
        return Err(usage());
    };

    let mut settings_path = None;
    let mut user_lexicon_path = None;
    let mut imported_lexicon_path = None;
    let mut export_path = None;
    let mut input_path = None;
    let mut enabled = None;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--settings" => settings_path = args.next().map(PathBuf::from),
            "--user-lexicon" => user_lexicon_path = args.next().map(PathBuf::from),
            "--imported-lexicon" => imported_lexicon_path = args.next().map(PathBuf::from),
            "--output" => export_path = args.next().map(PathBuf::from),
            "--input" => input_path = args.next().map(PathBuf::from),
            "--enabled" => enabled = args.next().map(|value| parse_bool(&value)),
            _ => return Err(usage()),
        }
    }

    match command.as_str() {
        "write-default" => {
            let path = required_path(settings_path, "--settings")?;
            let settings = ImeSettings {
                user_lexicon_path,
                imported_lexicon_path,
                ..ImeSettings::default()
            };
            settings
                .write_json_file(&path)
                .map_err(|error| error.code().to_owned())?;
            Ok(format!("wrote settings: {}", path.display()))
        }
        "set-strict-privacy" => {
            let path = required_path(settings_path, "--settings")?;
            let mut settings = ImeSettings::from_json_file_or_default(&path);
            settings.strict_privacy_mode = enabled
                .transpose()
                .map_err(|_| "expected --enabled true or false".to_owned())?
                .ok_or_else(usage)?;
            if settings.strict_privacy_mode {
                settings.enable_user_learning = false;
            }
            settings
                .write_json_file(&path)
                .map_err(|error| error.code().to_owned())?;
            Ok(format!("updated settings: {}", path.display()))
        }
        "clear-user-lexicon" => {
            let settings = settings_from_path(settings_path)?;
            ImeEngine::with_settings(settings)
                .and_then(|engine| engine.clear_user_lexicon())
                .map_err(|error| error.code().to_owned())?;
            Ok("cleared user lexicon".to_owned())
        }
        "export-user-lexicon" => {
            let settings = settings_from_path(settings_path)?;
            let path = required_path(export_path, "--output")?;
            let count = ImeEngine::with_settings(settings)
                .and_then(|engine| engine.export_user_lexicon(&path))
                .map_err(|error| error.code().to_owned())?;
            Ok(format!("exported {count} rows: {}", path.display()))
        }
        "import-rime-lexicon" => {
            let settings = settings_from_path(settings_path)?;
            let path = required_path(input_path, "--input")?;
            let report = ImeEngine::with_settings(settings)
                .and_then(|engine| engine.import_rime_lexicon(&path))
                .map_err(|error| error.code().to_owned())?;
            Ok(format!(
                "imported {} rows; {} total: {}",
                report.accepted_rows,
                report.total_entries,
                path.display()
            ))
        }
        "clear-imported-lexicon" => {
            let settings = settings_from_path(settings_path)?;
            ImeEngine::with_settings(settings)
                .and_then(|engine| engine.clear_imported_lexicon())
                .map_err(|error| error.code().to_owned())?;
            Ok("cleared imported lexicon".to_owned())
        }
        _ => Err(usage()),
    }
}

fn settings_from_path(settings_path: Option<PathBuf>) -> Result<ImeSettings, String> {
    Ok(ImeSettings::from_json_file_or_default(required_path(
        settings_path,
        "--settings",
    )?))
}

fn required_path(path: Option<PathBuf>, flag: &str) -> Result<PathBuf, String> {
    path.ok_or_else(|| format!("missing {flag}\n{}", usage()))
}

fn parse_bool(value: &str) -> Result<bool, ()> {
    match value {
        "true" | "1" | "yes" | "on" => Ok(true),
        "false" | "0" | "no" | "off" => Ok(false),
        _ => Err(()),
    }
}

fn usage() -> String {
    "usage:
  private-pinyin-settings write-default --settings PATH [--user-lexicon PATH] [--imported-lexicon PATH]
  private-pinyin-settings set-strict-privacy --settings PATH --enabled true|false
  private-pinyin-settings clear-user-lexicon --settings PATH
  private-pinyin-settings export-user-lexicon --settings PATH --output PATH
  private-pinyin-settings import-rime-lexicon --settings PATH --input PATH
  private-pinyin-settings clear-imported-lexicon --settings PATH"
        .to_owned()
}
