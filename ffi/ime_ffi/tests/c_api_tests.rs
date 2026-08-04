use std::ffi::{CStr, CString};
use std::path::PathBuf;
use std::ptr;
use std::time::{SystemTime, UNIX_EPOCH};

#[cfg(feature = "desktop-ai")]
use private_pinyin_ime::ime_engine_enable_desktop_ai;
use private_pinyin_ime::{
    ime_engine_clear_imported_lexicon, ime_engine_clear_user_lexicon,
    ime_engine_export_user_lexicon, ime_engine_free, ime_engine_import_rime_lexicon,
    ime_engine_new, ime_output_free, ime_session_commit_candidate, ime_session_feed_key,
    ime_session_free, ime_session_new, ime_session_set_candidate_page_size, ImeKeyEvent,
};
#[cfg(feature = "local-ai")]
use private_pinyin_ime::{
    ime_engine_enable_local_ai, ime_session_set_optional_ai_suspended,
    ime_session_set_secure_input, ImeMode,
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
fn c_api_preserves_blind_typing_space_number_enter_and_escape_semantics() {
    unsafe {
        let engine = ime_engine_new(ptr::null());
        assert!(!engine.is_null());

        let space_session = ime_session_new(engine);
        assert!(!space_session.is_null());
        let mut final_output = ptr::null_mut();
        for (index, ch) in ["n", "i", "h", "a", "o"].into_iter().enumerate() {
            let text = CString::new(ch).unwrap();
            final_output = ime_session_feed_key(space_session, key_event(text.as_ptr()));
            assert!(!final_output.is_null());
            if index < 4 {
                ime_output_free(final_output);
            }
        }
        assert!((*final_output).candidate_count > 0);
        assert!(!(*final_output).candidates.is_null());
        let expected_default = CStr::from_ptr((*(*final_output).candidates).text)
            .to_string_lossy()
            .into_owned();
        ime_output_free(final_output);
        let commit = ime_session_feed_key(space_session, command_event(1));
        assert!(!commit.is_null());
        assert_eq!(
            CStr::from_ptr((*commit).commit_text).to_string_lossy(),
            expected_default
        );
        assert_eq!((*commit).should_commit, 1);
        ime_output_free(commit);
        ime_session_free(space_session);

        let number_session = ime_session_new(engine);
        assert!(!number_session.is_null());
        let mut final_output = ptr::null_mut();
        for (index, ch) in ["n", "i"].into_iter().enumerate() {
            let text = CString::new(ch).unwrap();
            final_output = ime_session_feed_key(number_session, key_event(text.as_ptr()));
            assert!(!final_output.is_null());
            if index == 0 {
                ime_output_free(final_output);
            }
        }
        assert!((*final_output).candidate_count >= 2);
        assert!(!(*final_output).candidates.is_null());
        let candidates = std::slice::from_raw_parts(
            (*final_output).candidates,
            (*final_output).candidate_count as usize,
        );
        let expected_second = CStr::from_ptr(candidates[1].text)
            .to_string_lossy()
            .into_owned();
        ime_output_free(final_output);
        let digit = CString::new("2").unwrap();
        let commit = ime_session_feed_key(number_session, digit_event(digit.as_ptr()));
        assert!(!commit.is_null());
        assert_eq!(
            CStr::from_ptr((*commit).commit_text).to_string_lossy(),
            expected_second
        );
        ime_output_free(commit);
        ime_session_free(number_session);

        let prediction_session = ime_session_new(engine);
        assert!(!prediction_session.is_null());
        for ch in ["j", "i", "n", "t", "i", "a", "n"] {
            let text = CString::new(ch).unwrap();
            let output = ime_session_feed_key(prediction_session, key_event(text.as_ptr()));
            assert!(!output.is_null());
            ime_output_free(output);
        }
        let predicted = ime_session_feed_key(prediction_session, command_event(1));
        assert!(!predicted.is_null());
        assert_eq!((*predicted).should_commit, 1);
        assert!((*predicted).candidate_count > 0);
        assert!(!(*predicted).candidates.is_null());
        let expected_prediction = CStr::from_ptr((*(*predicted).candidates).text)
            .to_string_lossy()
            .into_owned();
        ime_output_free(predicted);
        let digit = CString::new("1").unwrap();
        let passthrough = ime_session_feed_key(prediction_session, digit_event(digit.as_ptr()));
        assert!(!passthrough.is_null());
        assert_eq!((*passthrough).should_commit, 0);
        assert_eq!((*passthrough).should_update_preedit, 0);
        assert_eq!((*passthrough).candidate_count, 0);
        ime_output_free(passthrough);
        let explicit_prediction = ime_session_commit_candidate(prediction_session, 0);
        assert!(!explicit_prediction.is_null());
        assert_eq!(
            CStr::from_ptr((*explicit_prediction).commit_text).to_string_lossy(),
            expected_prediction
        );
        ime_output_free(explicit_prediction);
        ime_session_free(prediction_session);

        let enter_session = ime_session_new(engine);
        assert!(!enter_session.is_null());
        for ch in ["a", "b", "c"] {
            let text = CString::new(ch).unwrap();
            let output = ime_session_feed_key(enter_session, key_event(text.as_ptr()));
            assert!(!output.is_null());
            ime_output_free(output);
        }
        let raw_commit = ime_session_feed_key(enter_session, command_event(2));
        assert!(!raw_commit.is_null());
        assert_eq!(
            CStr::from_ptr((*raw_commit).commit_text).to_string_lossy(),
            "abc"
        );
        ime_output_free(raw_commit);
        ime_session_free(enter_session);

        let escape_session = ime_session_new(engine);
        assert!(!escape_session.is_null());
        let text = CString::new("n").unwrap();
        let output = ime_session_feed_key(escape_session, key_event(text.as_ptr()));
        assert!(!output.is_null());
        ime_output_free(output);
        let cancelled = ime_session_feed_key(escape_session, command_event(4));
        assert!(!cancelled.is_null());
        assert_eq!((*cancelled).should_commit, 0);
        assert_eq!(CStr::from_ptr((*cancelled).preedit).to_string_lossy(), "");
        assert_eq!((*cancelled).candidate_count, 0);
        ime_output_free(cancelled);
        ime_session_free(escape_session);

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
fn c_api_ios_page_size_keeps_mao_candidate_on_first_nine_key_page() {
    unsafe {
        let engine = ime_engine_new(ptr::null());
        assert!(!engine.is_null());
        let session = ime_session_new(engine);
        assert!(!session.is_null());
        assert_eq!(ime_session_set_candidate_page_size(session, 9), 1);
        assert_eq!(ime_session_set_candidate_page_size(session, 0), 0);
        assert_eq!(ime_session_set_candidate_page_size(session, 1_000), 0);

        let mut output = ptr::null_mut();
        for (index, digit) in ["6", "2", "6"].into_iter().enumerate() {
            let text = CString::new(digit).unwrap();
            output = ime_session_feed_key(session, nine_key_event(text.as_ptr()));
            assert!(!output.is_null());
            if index < 2 {
                ime_output_free(output);
            }
        }

        let output_ref = &*output;
        assert_eq!(output_ref.candidate_count, 9);
        let candidates =
            std::slice::from_raw_parts(output_ref.candidates, output_ref.candidate_count as usize);
        let first_page = candidates
            .iter()
            .map(|candidate| CStr::from_ptr(candidate.text).to_str().unwrap().to_owned())
            .collect::<Vec<_>>();
        assert!(candidates
            .iter()
            .any(|candidate| { CStr::from_ptr(candidate.text).to_str().unwrap() == "猫" }));

        ime_output_free(output);
        let output = ime_session_feed_key(session, command_event(15));
        assert!(!output.is_null());
        let output_ref = &*output;
        assert!(output_ref.candidate_count > 0);
        let second_page =
            std::slice::from_raw_parts(output_ref.candidates, output_ref.candidate_count as usize);
        assert!(second_page.iter().all(|candidate| {
            let text = CStr::from_ptr(candidate.text).to_str().unwrap();
            !first_page.iter().any(|first| first == text)
        }));

        ime_output_free(output);
        ime_session_free(session);
        ime_engine_free(engine);
    }
}

#[test]
fn c_api_can_feed_mixed_full_pinyin_and_initials() {
    unsafe {
        let engine = ime_engine_new(ptr::null());
        assert!(!engine.is_null());
        let session = ime_session_new(engine);
        assert!(!session.is_null());

        let mut output = ptr::null_mut();
        for (index, ch) in ["w", "o", "j", "t"].into_iter().enumerate() {
            let text = CString::new(ch).unwrap();
            output = ime_session_feed_key(session, key_event(text.as_ptr()));
            assert!(!output.is_null());
            if index < 3 {
                ime_output_free(output);
            }
        }

        let first_candidate = &*(*output).candidates;
        assert_eq!(
            CStr::from_ptr(first_candidate.text).to_str().unwrap(),
            "我今天"
        );
        assert_eq!(
            CStr::from_ptr(first_candidate.pinyin).to_str().unwrap(),
            "wo jin tian"
        );
        ime_output_free(output);
        ime_session_free(session);
        ime_engine_free(engine);
    }
}

#[cfg(feature = "desktop-ai")]
#[test]
fn desktop_ai_never_blocks_base_input_and_secure_mode_cancels_optional_work() {
    unsafe {
        let engine = ime_engine_new(ptr::null());
        assert!(!engine.is_null());
        assert_eq!(ime_engine_enable_desktop_ai(engine, 1, 8 * 1024, 0), 1);
        let session = ime_session_new(engine);
        assert!(!session.is_null());

        assert_eq!(ime_session_set_secure_input(session, 1), 1);
        let text = CString::new("n").unwrap();
        let output = ime_session_feed_key(session, key_event(text.as_ptr()));
        assert!(!output.is_null());
        assert_eq!(CStr::from_ptr((*output).preedit).to_str().unwrap(), "n");
        ime_output_free(output);

        assert_eq!(ime_session_set_secure_input(session, 0), 1);
        let text = CString::new("i").unwrap();
        let output = ime_session_feed_key(session, key_event(text.as_ptr()));
        assert!(!output.is_null());
        assert!((*output).candidate_count > 0);
        ime_output_free(output);

        ime_session_free(session);
        ime_engine_free(engine);
    }
}

#[cfg(feature = "local-ai")]
#[test]
fn ios_ai_uses_the_approved_model_and_falls_back_below_the_memory_gate() {
    unsafe {
        let enabled_engine = ime_engine_new(ptr::null());
        assert!(!enabled_engine.is_null());
        assert_eq!(
            ime_engine_enable_local_ai(enabled_engine, 3, 8 * 1024, 0),
            1
        );
        let session = ime_session_new(enabled_engine);
        assert!(!session.is_null());

        assert_eq!(ime_session_set_optional_ai_suspended(session, 1), 1);
        let text = CString::new("n").unwrap();
        let output = ime_session_feed_key(session, key_event(text.as_ptr()));
        assert!(!output.is_null());
        assert_eq!(CStr::from_ptr((*output).preedit).to_str().unwrap(), "n");
        ime_output_free(output);

        assert_eq!(ime_session_set_optional_ai_suspended(session, 0), 1);
        assert_eq!(ime_session_set_secure_input(session, 1), 1);
        let text = CString::new("i").unwrap();
        let output = ime_session_feed_key(session, key_event(text.as_ptr()));
        assert!(!output.is_null());
        assert_eq!(CStr::from_ptr((*output).preedit).to_str().unwrap(), "ni");
        ime_output_free(output);
        ime_session_free(session);
        ime_engine_free(enabled_engine);

        let fallback_engine = ime_engine_new(ptr::null());
        assert!(!fallback_engine.is_null());
        assert_eq!(
            ime_engine_enable_local_ai(fallback_engine, 3, 4 * 1024, 0),
            0
        );
        assert_eq!(
            ime_engine_enable_local_ai(fallback_engine, 99, 8 * 1024, 0),
            0
        );
        let fallback_session = ime_session_new(fallback_engine);
        assert!(!fallback_session.is_null());
        let text = CString::new("n").unwrap();
        let output = ime_session_feed_key(fallback_session, key_event(text.as_ptr()));
        assert!(!output.is_null());
        assert_eq!(CStr::from_ptr((*output).preedit).to_str().unwrap(), "n");
        ime_output_free(output);
        ime_session_free(fallback_session);
        ime_engine_free(fallback_engine);
    }
}

#[cfg(feature = "local-ai")]
#[test]
fn ai_disabled_or_privacy_blocked_output_matches_the_base_engine_exactly() {
    unsafe {
        let base_engine = ime_engine_new(ptr::null());
        let ai_engine = ime_engine_new(ptr::null());
        assert!(!base_engine.is_null());
        assert!(!ai_engine.is_null());

        #[cfg(feature = "desktop-ai")]
        assert_eq!(ime_engine_enable_desktop_ai(ai_engine, 1, 8 * 1024, 0), 1);
        #[cfg(all(feature = "ios-ai", not(feature = "desktop-ai")))]
        assert_eq!(ime_engine_enable_local_ai(ai_engine, 3, 8 * 1024, 0), 1);

        let base_session = ime_session_new(base_engine);
        let ai_session = ime_session_new(ai_engine);
        assert!(!base_session.is_null());
        assert!(!ai_session.is_null());
        assert_eq!(ime_session_set_secure_input(ai_session, 1), 1);

        let assert_character = |ch: &str| {
            let text = CString::new(ch).unwrap();
            let base =
                take_output_snapshot(ime_session_feed_key(base_session, key_event(text.as_ptr())));
            let guarded =
                take_output_snapshot(ime_session_feed_key(ai_session, key_event(text.as_ptr())));
            assert_eq!(guarded, base, "AI-off equivalence failed after {ch}");
        };
        let assert_command = |key_code: i32, label: &str| {
            let base =
                take_output_snapshot(ime_session_feed_key(base_session, command_event(key_code)));
            let guarded =
                take_output_snapshot(ime_session_feed_key(ai_session, command_event(key_code)));
            assert_eq!(guarded, base, "AI-off equivalence failed after {label}");
        };
        let assert_commit = |index: i32, label: &str| {
            let base = take_output_snapshot(ime_session_commit_candidate(base_session, index));
            let guarded = take_output_snapshot(ime_session_commit_candidate(ai_session, index));
            assert_eq!(guarded, base, "AI-off equivalence failed after {label}");
        };

        for ch in ["n", "i", "h", "a", "x"] {
            assert_character(ch);
        }
        assert_command(3, "backspace");
        assert_character("o");
        assert_command(15, "page down");
        assert_command(14, "page up");
        assert_commit(0, "first candidate commit");

        for ch in ["j", "i", "n", "t", "i", "a", "n"] {
            assert_character(ch);
        }
        assert_commit(0, "second candidate commit");

        ime_session_free(base_session);
        ime_session_free(ai_session);
        ime_engine_free(base_engine);
        ime_engine_free(ai_engine);
    }
}

#[test]
fn c_api_null_handles_are_safe_noops() {
    assert!(ime_session_new(ptr::null_mut()).is_null());
    assert!(ime_session_feed_key(ptr::null_mut(), key_event(ptr::null())).is_null());
    assert_eq!(ime_engine_clear_user_lexicon(ptr::null_mut()), 0);
    assert_eq!(
        ime_engine_import_rime_lexicon(ptr::null_mut(), ptr::null()),
        -1
    );
    assert_eq!(ime_engine_clear_imported_lexicon(ptr::null_mut()), 0);
    assert_eq!(
        private_pinyin_ime::ime_session_set_optional_ai_suspended(ptr::null_mut(), 1),
        0
    );
    ime_output_free(ptr::null_mut());
    ime_session_free(ptr::null_mut());
    ime_engine_free(ptr::null_mut());
}

#[test]
fn c_api_imports_and_clears_a_separate_rime_lexicon() {
    let imported_path = temp_path("ffi_imported_lexicon", "tsv");
    let source_path = temp_path("ffi_rime_source", "dict.yaml");
    let settings_path = temp_path("ffi_imported_lexicon_settings", "json");
    std::fs::write(
        &source_path,
        "---\nname: demo\n...\n测试词条\tce shi ci tiao\t500\n",
    )
    .expect("write Rime fixture");
    std::fs::write(
        &settings_path,
        format!(
            r#"{{
  "imported_lexicon_path": "{}"
}}"#,
            imported_path.to_string_lossy().replace('\\', "/")
        ),
    )
    .expect("write settings");
    let settings_path = CString::new(settings_path.to_string_lossy().as_bytes()).unwrap();
    let source_path = CString::new(source_path.to_string_lossy().as_bytes()).unwrap();

    let engine = ime_engine_new(settings_path.as_ptr());
    assert!(!engine.is_null());
    assert_eq!(
        ime_engine_import_rime_lexicon(engine, source_path.as_ptr()),
        1
    );
    assert!(std::fs::read_to_string(&imported_path)
        .expect("read imported lexicon")
        .contains("测试词条\tce shi ci tiao\t500"));
    assert_eq!(ime_engine_clear_imported_lexicon(engine), 1);
    assert!(!imported_path.exists());
    ime_engine_free(engine);
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

fn digit_event(text: *const std::os::raw::c_char) -> ImeKeyEvent {
    ImeKeyEvent {
        key_code: 101,
        text,
        shift: 0,
        ctrl: 0,
        alt: 0,
        meta: 0,
        is_repeat: 0,
        timestamp_ms: 0,
    }
}

fn command_event(key_code: i32) -> ImeKeyEvent {
    ImeKeyEvent {
        key_code,
        text: ptr::null(),
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

#[cfg(feature = "local-ai")]
#[derive(Debug, PartialEq, Eq)]
struct OutputSnapshot {
    preedit: String,
    commit_text: String,
    mode: ImeMode,
    should_update_preedit: i32,
    should_commit: i32,
    should_show_candidates: i32,
    candidates: Vec<(String, String, u64, String)>,
}

#[cfg(feature = "local-ai")]
unsafe fn take_output_snapshot(output: *mut private_pinyin_ime::ImeOutput) -> OutputSnapshot {
    assert!(!output.is_null());
    let output_ref = &*output;
    let candidates = std::slice::from_raw_parts(
        output_ref.candidates,
        output_ref.candidate_count.max(0) as usize,
    )
    .iter()
    .map(|candidate| {
        (
            CStr::from_ptr(candidate.text)
                .to_string_lossy()
                .into_owned(),
            CStr::from_ptr(candidate.pinyin)
                .to_string_lossy()
                .into_owned(),
            candidate.score.to_bits(),
            CStr::from_ptr(candidate.source)
                .to_string_lossy()
                .into_owned(),
        )
    })
    .collect();
    let snapshot = OutputSnapshot {
        preedit: CStr::from_ptr(output_ref.preedit)
            .to_string_lossy()
            .into_owned(),
        commit_text: CStr::from_ptr(output_ref.commit_text)
            .to_string_lossy()
            .into_owned(),
        mode: output_ref.mode,
        should_update_preedit: output_ref.should_update_preedit,
        should_commit: output_ref.should_commit,
        should_show_candidates: output_ref.should_show_candidates,
        candidates,
    };
    ime_output_free(output);
    snapshot
}
