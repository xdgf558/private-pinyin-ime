use std::ffi::{CStr, CString};
use std::ptr;

use private_pinyin_ime::{
    ime_engine_free, ime_engine_new, ime_output_free, ime_session_commit_candidate,
    ime_session_feed_key, ime_session_free, ime_session_new, ImeKeyEvent,
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
fn c_api_null_handles_are_safe_noops() {
    assert!(ime_session_new(ptr::null_mut()).is_null());
    assert!(ime_session_feed_key(ptr::null_mut(), key_event(ptr::null())).is_null());
    ime_output_free(ptr::null_mut());
    ime_session_free(ptr::null_mut());
    ime_engine_free(ptr::null_mut());
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
