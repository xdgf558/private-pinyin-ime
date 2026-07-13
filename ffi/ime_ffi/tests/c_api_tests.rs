use std::ffi::{CStr, CString};
use std::path::PathBuf;
use std::ptr;
use std::time::{SystemTime, UNIX_EPOCH};

use private_pinyin_ime::{
    ime_engine_clear_user_lexicon, ime_engine_export_user_lexicon, ime_engine_free, ime_engine_new,
    ime_output_free, ime_session_commit_candidate, ime_session_feed_key, ime_session_free,
    ime_session_new, ImeKeyEvent,
};

#[test]
fn c_api_can_create_engine_feed_nihao_and_commit_candidate() {
    unsafe {
        let engine = ime_engine_new(ptr::null());
        assert!(!engine.is_null());

        let session = ime_session_new(engine);
        assert!(!session.is_null());

        let mut output = ptr::null_mut();
        for ch in ["n", "i", "h", "a", "o"] {
            let text = CString::new(ch).unwrap();
            output = ime_session_feed_key(session, key_event(text.as_ptr()));
            assert!(!output.is_null());
            if ch != "o" {
                ime_output_free(output);
            }
        }

        let output_ref = &*output;
        assert!(output_ref.candidate_count > 0);
        let first_candidate = &*output_ref.candidates;
        assert_eq!(
            CStr::from_ptr(first_candidate.text).to_str().unwrap(),
            "你好"
        );
        assert_eq!(
            CStr::from_ptr(first_candidate.pinyin).to_str().unwrap(),
            "ni hao"
        );
        ime_output_free(output);

        let commit_output = ime_session_commit_candidate(session, 0);
        assert!(!commit_output.is_null());
        assert_eq!(
            CStr::from_ptr((*commit_output).commit_text)
                .to_str()
                .unwrap(),
            "你好"
        );
        ime_output_free(commit_output);

        ime_session_free(session);
        ime_engine_free(engine);
    }
}

#[test]
fn c_api_can_feed_nine_key_nihao() {
    unsafe {
        let engine = ime_engine_new(ptr::null());
        assert!(!engine.is_null());
        let session = ime_session_new(engine);
        assert!(!session.is_null());

        let mut output = ptr::null_mut();
        for (index, digit) in ["6", "4", "4", "2", "6"].into_iter().enumerate() {
            let text = CString::new(digit).unwrap();
            output = ime_session_feed_key(session, nine_key_event(text.as_ptr()));
            assert!(!output.is_null());
            if index < 4 {
                ime_output_free(output);
            }
        }

        let first_candidate = &*(*output).candidates;
        assert_eq!(
            CStr::from_ptr(first_candidate.text).to_str().unwrap(),
            "你好"
        );
        ime_output_free(output);
        ime_session_free(session);
        ime_engine_free(engine);
    }
}

#[test]
fn c_api_null_handles_are_safe_noops() {
    assert!(ime_session_new(ptr::null_mut()).is_null());
    assert!(ime_session_feed_key(ptr::null_mut(), key_event(ptr::null())).is_null());
    assert_eq!(ime_engine_clear_user_lexicon(ptr::null_mut()), 0);
    ime_output_free(ptr::null_mut());
    ime_session_free(ptr::null_mut());
    ime_engine_free(ptr::null_mut());
}

#[test]
fn c_api_uses_settings_path_for_engine_creation() {
    let settings_path = temp_path("settings_path", "json");
    std::fs::write(
        &settings_path,
        r#"{
  "default_mode": "English",
  "toggle_key": "CtrlSpace",
  "candidate_page_size": 7,
  "enable_prediction": false,
  "enable_user_learning": false,
  "strict_privacy_mode": true
}"#,
    )
    .expect("write settings");
    let settings_path = CString::new(settings_path.to_string_lossy().as_bytes()).unwrap();
    let text = CString::new("n").unwrap();

    unsafe {
        let engine = ime_engine_new(settings_path.as_ptr());
        assert!(!engine.is_null());
        let session = ime_session_new(engine);
        assert!(!session.is_null());

        let output = ime_session_feed_key(session, key_event(text.as_ptr()));
        assert!(!output.is_null());
        assert_eq!(CStr::from_ptr((*output).commit_text).to_str().unwrap(), "n");
        ime_output_free(output);
        ime_session_free(session);
        ime_engine_free(engine);
    }
}

#[test]
fn c_api_can_clear_and_export_user_lexicon() {
    let db_path = temp_path("ffi_user_lexicon", "sqlite");
    let export_path = temp_path("ffi_user_lexicon_export", "tsv");
    let settings_path = temp_path("ffi_user_lexicon_settings", "json");
    std::fs::write(
        &settings_path,
        format!(
            r#"{{
  "user_lexicon_path": "{}"
}}"#,
            db_path.to_string_lossy().replace('\\', "/")
        ),
    )
    .expect("write settings");
    let settings_path = CString::new(settings_path.to_string_lossy().as_bytes()).unwrap();
    let export_path_c = CString::new(export_path.to_string_lossy().as_bytes()).unwrap();

    let engine = ime_engine_new(settings_path.as_ptr());
    assert!(!engine.is_null());
    let session = ime_session_new(engine);
    assert!(!session.is_null());

    for ch in ["n", "i", "h", "a", "o"] {
        let text = CString::new(ch).unwrap();
        let output = ime_session_feed_key(session, key_event(text.as_ptr()));
        assert!(!output.is_null());
        ime_output_free(output);
    }
    let commit_output = ime_session_commit_candidate(session, 0);
    assert!(!commit_output.is_null());
    ime_output_free(commit_output);

    assert_eq!(
        ime_engine_export_user_lexicon(engine, export_path_c.as_ptr()),
        1
    );
    let exported = std::fs::read_to_string(&export_path).expect("read export");
    assert!(exported.contains("phrase\tpinyin\tfrequency\tupdated_at_ms"));
    assert!(exported.contains("你好\tni hao\t1\t"));

    assert_eq!(ime_engine_clear_user_lexicon(engine), 1);
    assert_eq!(
        ime_engine_export_user_lexicon(engine, export_path_c.as_ptr()),
        1
    );
    let exported = std::fs::read_to_string(&export_path).expect("read export after clear");
    assert!(!exported.contains("你好\tni hao"));

    ime_session_free(session);
    ime_engine_free(engine);
}

fn key_event(text: *const std::os::raw::c_char) -> ImeKeyEvent {
    ImeKeyEvent {
        key_code: 0,
        text,
        shift: 0,
        ctrl: 0,
        alt: 0,
        meta: 0,
        is_repeat: 0,
        timestamp_ms: 0,
    }
}

fn nine_key_event(text: *const std::os::raw::c_char) -> ImeKeyEvent {
    ImeKeyEvent {
        key_code: 102,
        text,
        shift: 0,
        ctrl: 0,
        alt: 0,
        meta: 0,
        is_repeat: 0,
        timestamp_ms: 0,
    }
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
