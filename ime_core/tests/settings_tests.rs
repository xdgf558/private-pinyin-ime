use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::{ImeMode, ImeSettings};

#[test]
fn settings_loads_json_snapshot() {
    let settings = ImeSettings::from_json_str(
        r#"{
  "default_mode": "English",
  "toggle_key": "CtrlSpace",
  "candidate_page_size": 9,
  "enable_prediction": false,
  "enable_user_learning": true,
  "strict_privacy_mode": true,
  "user_lexicon_path": "/tmp/private-pinyin-test.sqlite",
  "fuzzy_pinyin": {
    "zh_z": true,
    "in_ing": true
  },
  "theme": "dark",
  "candidate_font_size": 18
}"#,
    )
    .expect("settings parse");

    assert_eq!(settings.default_mode, ImeMode::English);
    assert_eq!(settings.candidate_page_size, 9);
    assert!(!settings.enable_prediction);
    assert!(!settings.enable_user_learning);
    assert!(settings.strict_privacy_mode);
    assert!(settings.fuzzy_pinyin.zh_z);
    assert!(settings.fuzzy_pinyin.in_ing);
    assert_eq!(settings.theme, "dark");
    assert_eq!(settings.candidate_font_size, 18);
}

#[test]
fn malformed_settings_file_can_fallback_to_default() {
    let path = temp_path("settings_malformed", "json");
    std::fs::write(&path, "{not json").expect("write malformed settings");

    let settings = ImeSettings::from_json_file_or_default(&path);

    assert_eq!(settings, ImeSettings::default());
}

#[test]
fn invalid_numeric_settings_are_clamped_without_losing_other_fields() {
    let settings = ImeSettings::from_json_str(
        r#"{
  "candidate_page_size": 0,
  "candidate_font_size": 0,
  "strict_privacy_mode": true,
  "enable_prediction": false,
  "theme": ""
}"#,
    )
    .expect("settings normalize");

    assert_eq!(settings.candidate_page_size, 5);
    assert_eq!(settings.candidate_font_size, 14);
    assert!(settings.strict_privacy_mode);
    assert!(!settings.enable_user_learning);
    assert!(!settings.enable_prediction);
    assert_eq!(settings.theme, "system");
}

#[test]
fn settings_write_uses_atomic_target_file() {
    let path = temp_path("settings_write", "json");
    let settings = ImeSettings {
        default_mode: ImeMode::English,
        ..ImeSettings::default()
    };

    settings.write_json_file(&path).expect("write settings");
    let loaded = ImeSettings::from_json_file(&path).expect("load settings");

    assert_eq!(loaded.default_mode, ImeMode::English);
    assert!(!path.with_extension("tmp").exists());
}

fn temp_path(name: &str, extension: &str) -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    let path = std::env::temp_dir().join(format!(
        "private_pinyin_{name}_{}_{}.{extension}",
        std::process::id(),
        unique
    ));
    let _ = std::fs::remove_file(&path);
    path
}
