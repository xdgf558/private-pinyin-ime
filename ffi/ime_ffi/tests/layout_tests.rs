use std::mem::{align_of, offset_of, size_of};

use private_pinyin_ime::{ImeCandidate, ImeKeyEvent, ImeMode, ImeOutput};

#[test]
fn ffi_struct_layout_matches_c_header_contract() {
    assert_eq!(size_of::<ImeMode>(), 4);
    assert_eq!(align_of::<ImeMode>(), 4);

    assert_eq!(size_of::<ImeKeyEvent>(), 48);
    assert_eq!(align_of::<ImeKeyEvent>(), 8);
    assert_eq!(offset_of!(ImeKeyEvent, key_code), 0);
    assert_eq!(offset_of!(ImeKeyEvent, text), 8);
    assert_eq!(offset_of!(ImeKeyEvent, shift), 16);
    assert_eq!(offset_of!(ImeKeyEvent, ctrl), 20);
    assert_eq!(offset_of!(ImeKeyEvent, alt), 24);
    assert_eq!(offset_of!(ImeKeyEvent, meta), 28);
    assert_eq!(offset_of!(ImeKeyEvent, is_repeat), 32);
    assert_eq!(offset_of!(ImeKeyEvent, timestamp_ms), 40);

    assert_eq!(size_of::<ImeCandidate>(), 32);
    assert_eq!(align_of::<ImeCandidate>(), 8);
    assert_eq!(offset_of!(ImeCandidate, text), 0);
    assert_eq!(offset_of!(ImeCandidate, pinyin), 8);
    assert_eq!(offset_of!(ImeCandidate, score), 16);
    assert_eq!(offset_of!(ImeCandidate, source), 24);

    assert_eq!(size_of::<ImeOutput>(), 48);
    assert_eq!(align_of::<ImeOutput>(), 8);
    assert_eq!(offset_of!(ImeOutput, preedit), 0);
    assert_eq!(offset_of!(ImeOutput, commit_text), 8);
    assert_eq!(offset_of!(ImeOutput, mode), 16);
    assert_eq!(offset_of!(ImeOutput, should_update_preedit), 20);
    assert_eq!(offset_of!(ImeOutput, should_commit), 24);
    assert_eq!(offset_of!(ImeOutput, should_show_candidates), 28);
    assert_eq!(offset_of!(ImeOutput, candidate_count), 32);
    assert_eq!(offset_of!(ImeOutput, candidates), 40);
}

#[test]
fn ffi_enum_values_match_c_header_contract() {
    assert_eq!(ImeMode::Chinese as i32, 0);
    assert_eq!(ImeMode::English as i32, 1);
}
