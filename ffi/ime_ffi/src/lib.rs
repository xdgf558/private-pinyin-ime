#![allow(unsafe_code)]
#![allow(clippy::not_unsafe_ptr_arg_deref)]

#[cfg(feature = "local-ai")]
mod local_ai;

use std::ffi::{CStr, CString};
use std::marker::PhantomData;
use std::os::raw::{c_char, c_double, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::rc::Rc;

use ime_core::{
    ImeEngine as CoreImeEngine, ImeMode as CoreImeMode, ImeOutput as CoreImeOutput, InputSession,
    KeyCode, KeyEvent, Modifiers,
};

#[cfg(feature = "local-ai")]
use local_ai::{LocalAiRuntime, LocalAiSession};
#[cfg(feature = "local-ai")]
use private_pinyin_local_ai_core::ModelPlatform;

const IME_KEY_UNKNOWN: c_int = 0;
const IME_KEY_SPACE: c_int = 1;
const IME_KEY_ENTER: c_int = 2;
const IME_KEY_BACKSPACE: c_int = 3;
const IME_KEY_ESCAPE: c_int = 4;
const IME_KEY_SHIFT: c_int = 5;
const IME_KEY_CTRL_SPACE: c_int = 6;
const IME_KEY_CAPS_LOCK: c_int = 7;
const IME_KEY_COMMA: c_int = 8;
const IME_KEY_PERIOD: c_int = 9;
const IME_KEY_MINUS: c_int = 10;
const IME_KEY_EQUAL: c_int = 11;
const IME_KEY_APOSTROPHE: c_int = 12;
const IME_KEY_SEMICOLON: c_int = 13;
const IME_KEY_PAGE_UP: c_int = 14;
const IME_KEY_PAGE_DOWN: c_int = 15;
const IME_KEY_ARROW_UP: c_int = 16;
const IME_KEY_ARROW_DOWN: c_int = 17;
const IME_KEY_CHARACTER: c_int = 100;
const IME_KEY_DIGIT: c_int = 101;
const IME_KEY_NINE_KEY_DIGIT: c_int = 102;

pub struct ImeEngine {
    inner: CoreImeEngine,
    #[cfg(feature = "local-ai")]
    local_ai: Option<std::sync::Arc<LocalAiRuntime>>,
    _not_thread_safe: PhantomData<Rc<()>>,
}

pub struct ImeSession {
    inner: InputSession,
    #[cfg(feature = "local-ai")]
    local_ai: Option<LocalAiSession>,
    _not_thread_safe: PhantomData<Rc<()>>,
}

#[cfg(feature = "local-ai")]
const IME_AI_PLATFORM_MACOS: c_int = 1;
#[cfg(feature = "local-ai")]
const IME_AI_PLATFORM_WINDOWS: c_int = 2;
#[cfg(feature = "local-ai")]
const IME_AI_PLATFORM_IOS: c_int = 3;

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImeMode {
    Chinese = 0,
    English = 1,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ImeKeyEvent {
    pub key_code: c_int,
    pub text: *const c_char,
    pub shift: c_int,
    pub ctrl: c_int,
    pub alt: c_int,
    pub meta: c_int,
    pub is_repeat: c_int,
    pub timestamp_ms: i64,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ImeCandidate {
    pub text: *const c_char,
    pub pinyin: *const c_char,
    pub score: c_double,
    pub source: *const c_char,
}

#[repr(C)]
#[derive(Debug)]
pub struct ImeOutput {
    pub preedit: *const c_char,
    pub commit_text: *const c_char,
    pub mode: ImeMode,
    pub should_update_preedit: c_int,
    pub should_commit: c_int,
    pub should_show_candidates: c_int,
    pub candidate_count: c_int,
    pub candidates: *mut ImeCandidate,
}

#[repr(C)]
struct OwnedImeOutput {
    output: ImeOutput,
    candidates: Box<[ImeCandidate]>,
    strings: Box<[CString]>,
}

#[no_mangle]
pub extern "C" fn ime_engine_new(config_json_path: *const c_char) -> *mut ImeEngine {
    catch_ptr(|| {
        let config_json_path = read_c_string(config_json_path);
        let inner = if config_json_path.is_empty() {
            CoreImeEngine::new().ok()?
        } else {
            CoreImeEngine::from_settings_path(config_json_path).ok()?
        };
        Some(Box::into_raw(Box::new(ImeEngine {
            inner,
            #[cfg(feature = "local-ai")]
            local_ai: None,
            _not_thread_safe: PhantomData,
        })))
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_enable_desktop_ai(
    engine: *mut ImeEngine,
    platform: c_int,
    physical_memory_mb: u64,
    gpu_available: c_int,
) -> c_int {
    ime_engine_enable_local_ai(engine, platform, physical_memory_mb, gpu_available)
}

#[no_mangle]
pub extern "C" fn ime_engine_enable_local_ai(
    engine: *mut ImeEngine,
    platform: c_int,
    physical_memory_mb: u64,
    gpu_available: c_int,
) -> c_int {
    catch_status(|| {
        let engine = unsafe { engine.as_mut()? };
        #[cfg(feature = "local-ai")]
        {
            let platform = match platform {
                IME_AI_PLATFORM_MACOS => ModelPlatform::Macos,
                IME_AI_PLATFORM_WINDOWS => ModelPlatform::Windows,
                IME_AI_PLATFORM_IOS => ModelPlatform::Ios,
                _ => return None,
            };
            engine.local_ai = LocalAiRuntime::new(platform, physical_memory_mb, gpu_available != 0);
            engine.local_ai.as_ref()?;
            Some(())
        }
        #[cfg(not(feature = "local-ai"))]
        {
            let _ = (engine, platform, physical_memory_mb, gpu_available);
            None
        }
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_clear_user_lexicon(engine: *mut ImeEngine) -> c_int {
    catch_status(|| {
        let engine = unsafe { engine.as_ref()? };
        engine.inner.clear_user_lexicon().ok()?;
        Some(())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_export_user_lexicon(
    engine: *mut ImeEngine,
    export_tsv_path: *const c_char,
) -> c_int {
    catch_status(|| {
        let engine = unsafe { engine.as_ref()? };
        let export_tsv_path = read_c_string(export_tsv_path);
        if export_tsv_path.is_empty() {
            return None;
        }
        engine.inner.export_user_lexicon(export_tsv_path).ok()?;
        Some(())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_import_rime_lexicon(
    engine: *mut ImeEngine,
    source_path: *const c_char,
) -> c_int {
    catch_unwind(AssertUnwindSafe(|| {
        let engine = unsafe { engine.as_ref()? };
        let source_path = read_c_string(source_path);
        if source_path.is_empty() {
            return None;
        }
        let report = engine.inner.import_rime_lexicon(source_path).ok()?;
        c_int::try_from(report.accepted_rows).ok()
    }))
    .ok()
    .flatten()
    .unwrap_or(-1)
}

#[no_mangle]
pub extern "C" fn ime_engine_clear_imported_lexicon(engine: *mut ImeEngine) -> c_int {
    catch_status(|| {
        let engine = unsafe { engine.as_ref()? };
        engine.inner.clear_imported_lexicon().ok()?;
        Some(())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_free(engine: *mut ImeEngine) {
    catch_unit(|| {
        if !engine.is_null() {
            unsafe {
                drop(Box::from_raw(engine));
            }
        }
    });
}

#[no_mangle]
pub extern "C" fn ime_session_new(engine: *mut ImeEngine) -> *mut ImeSession {
    catch_ptr(|| {
        let engine = unsafe { engine.as_ref()? };
        let inner = engine.inner.create_session();
        Some(Box::into_raw(Box::new(ImeSession {
            inner,
            #[cfg(feature = "local-ai")]
            local_ai: engine
                .local_ai
                .as_ref()
                .map(|runtime| LocalAiSession::new(std::sync::Arc::clone(runtime))),
            _not_thread_safe: PhantomData,
        })))
    })
}

#[no_mangle]
pub extern "C" fn ime_session_free(session: *mut ImeSession) {
    catch_unit(|| {
        if !session.is_null() {
            unsafe {
                drop(Box::from_raw(session));
            }
        }
    });
}

#[no_mangle]
pub extern "C" fn ime_session_feed_key(
    session: *mut ImeSession,
    event: ImeKeyEvent,
) -> *mut ImeOutput {
    catch_ptr(|| {
        let session = unsafe { session.as_mut()? };
        let output = session.inner.feed_key(to_core_key_event(event));
        Some(alloc_session_output(session, output))
    })
}

#[no_mangle]
pub extern "C" fn ime_session_set_secure_input(
    session: *mut ImeSession,
    secure_input: c_int,
) -> c_int {
    catch_status(|| {
        let session = unsafe { session.as_mut()? };
        #[cfg(feature = "local-ai")]
        if let Some(local_ai) = session.local_ai.as_mut() {
            local_ai.set_secure_input(secure_input != 0);
        }
        #[cfg(not(feature = "local-ai"))]
        let _ = (session, secure_input);
        Some(())
    })
}

#[no_mangle]
pub extern "C" fn ime_session_set_candidate_page_size(
    session: *mut ImeSession,
    page_size: c_int,
) -> c_int {
    catch_status(|| {
        let session = unsafe { session.as_mut()? };
        if page_size <= 0 || !session.inner.set_candidate_page_size(page_size as usize) {
            return None;
        }
        Some(())
    })
}

#[no_mangle]
pub extern "C" fn ime_session_commit_candidate(
    session: *mut ImeSession,
    index: c_int,
) -> *mut ImeOutput {
    catch_ptr(|| {
        let session = unsafe { session.as_mut()? };
        let output = if index < 0 {
            CoreImeOutput::idle(session.inner.mode())
        } else {
            session.inner.commit_candidate(index as usize)
        };
        Some(alloc_session_output(session, output))
    })
}

#[no_mangle]
pub extern "C" fn ime_session_toggle_mode(session: *mut ImeSession) -> *mut ImeOutput {
    catch_ptr(|| {
        let session = unsafe { session.as_mut()? };
        let output = session.inner.toggle_mode();
        Some(alloc_session_output(session, output))
    })
}

#[no_mangle]
pub extern "C" fn ime_session_reset(session: *mut ImeSession) -> *mut ImeOutput {
    catch_ptr(|| {
        let session = unsafe { session.as_mut()? };
        let output = session.inner.reset();
        Some(alloc_session_output(session, output))
    })
}

#[no_mangle]
pub extern "C" fn ime_output_free(output: *mut ImeOutput) {
    catch_unit(|| {
        if !output.is_null() {
            unsafe {
                drop(Box::from_raw(output as *mut OwnedImeOutput));
            }
        }
    });
}

fn catch_ptr<T>(f: impl FnOnce() -> Option<*mut T>) -> *mut T {
    catch_unwind(AssertUnwindSafe(f))
        .ok()
        .flatten()
        .unwrap_or(ptr::null_mut())
}

fn catch_status(f: impl FnOnce() -> Option<()>) -> c_int {
    c_int::from(catch_unwind(AssertUnwindSafe(f)).ok().flatten().is_some())
}

fn catch_unit(f: impl FnOnce()) {
    let _ = catch_unwind(AssertUnwindSafe(f));
}

#[cfg(feature = "local-ai")]
fn alloc_session_output(session: &mut ImeSession, mut output: CoreImeOutput) -> *mut ImeOutput {
    if let Some(local_ai) = session.local_ai.as_mut() {
        local_ai.process_output(&mut session.inner, &mut output);
    }
    alloc_output(output)
}

#[cfg(not(feature = "local-ai"))]
fn alloc_session_output(_session: &mut ImeSession, output: CoreImeOutput) -> *mut ImeOutput {
    alloc_output(output)
}

fn alloc_output(output: CoreImeOutput) -> *mut ImeOutput {
    let mut strings = Vec::new();
    let preedit = push_c_string(&mut strings, &output.preedit);
    let commit_text = push_c_string(&mut strings, &output.commit_text);

    let mut candidates = Vec::with_capacity(output.candidates.len());
    for candidate in &output.candidates {
        let text = push_c_string(&mut strings, &candidate.text);
        let pinyin = push_c_string(&mut strings, &candidate.pinyin);
        let source = push_c_string(&mut strings, &candidate.source.to_string());
        candidates.push(ImeCandidate {
            text,
            pinyin,
            score: candidate.score,
            source,
        });
    }

    let candidate_count = candidates.len().min(c_int::MAX as usize) as c_int;
    let mut candidates = candidates.into_boxed_slice();
    let candidates_ptr = if candidates.is_empty() {
        ptr::null_mut()
    } else {
        candidates.as_mut_ptr()
    };

    let owned = OwnedImeOutput {
        output: ImeOutput {
            preedit,
            commit_text,
            mode: ImeMode::from(output.mode),
            should_update_preedit: c_int::from(output.should_update_preedit),
            should_commit: c_int::from(output.should_commit),
            should_show_candidates: c_int::from(output.should_show_candidates),
            candidate_count,
            candidates: candidates_ptr,
        },
        candidates,
        strings: strings.into_boxed_slice(),
    };

    Box::into_raw(Box::new(owned)) as *mut ImeOutput
}

fn push_c_string(strings: &mut Vec<CString>, value: &str) -> *const c_char {
    strings.push(safe_c_string(value));
    strings.last().map_or(ptr::null(), |value| value.as_ptr())
}

fn safe_c_string(value: &str) -> CString {
    let bytes = value
        .as_bytes()
        .iter()
        .copied()
        .filter(|byte| *byte != 0)
        .collect::<Vec<_>>();
    CString::new(bytes).unwrap_or_else(|_| CString::new("").expect("empty CString is valid"))
}

fn to_core_key_event(event: ImeKeyEvent) -> KeyEvent {
    let text = read_c_string(event.text);
    let mut core_event = match event.key_code {
        IME_KEY_SPACE => KeyEvent::new(KeyCode::Space),
        IME_KEY_ENTER => KeyEvent::new(KeyCode::Enter),
        IME_KEY_BACKSPACE => KeyEvent::new(KeyCode::Backspace),
        IME_KEY_ESCAPE => KeyEvent::new(KeyCode::Escape),
        IME_KEY_SHIFT => KeyEvent::new(KeyCode::Shift),
        IME_KEY_CTRL_SPACE => KeyEvent::new(KeyCode::CtrlSpace),
        IME_KEY_CAPS_LOCK => KeyEvent::new(KeyCode::CapsLock),
        IME_KEY_COMMA => KeyEvent::new(KeyCode::Comma),
        IME_KEY_PERIOD => KeyEvent::new(KeyCode::Period),
        IME_KEY_MINUS => KeyEvent::new(KeyCode::Minus),
        IME_KEY_EQUAL => KeyEvent::new(KeyCode::Equal),
        IME_KEY_APOSTROPHE => KeyEvent::new(KeyCode::Apostrophe),
        IME_KEY_SEMICOLON => KeyEvent::new(KeyCode::Semicolon),
        IME_KEY_PAGE_UP => KeyEvent::new(KeyCode::PageUp),
        IME_KEY_PAGE_DOWN => KeyEvent::new(KeyCode::PageDown),
        IME_KEY_ARROW_UP => KeyEvent::new(KeyCode::ArrowUp),
        IME_KEY_ARROW_DOWN => KeyEvent::new(KeyCode::ArrowDown),
        IME_KEY_DIGIT => digit_event(&text),
        IME_KEY_NINE_KEY_DIGIT => nine_key_digit_event(&text),
        IME_KEY_CHARACTER => character_event(&text),
        IME_KEY_UNKNOWN => text_event(&text),
        _ => text_event(&text),
    };

    core_event.text = text;
    core_event.modifiers = Modifiers {
        shift: event.shift != 0,
        ctrl: event.ctrl != 0,
        alt: event.alt != 0,
        meta: event.meta != 0,
    };
    core_event.is_repeat = event.is_repeat != 0;
    core_event.timestamp_ms = event.timestamp_ms;
    core_event
}

fn digit_event(text: &str) -> KeyEvent {
    text.chars()
        .next()
        .filter(|ch| ch.is_ascii_digit())
        .map(KeyEvent::from_char)
        .unwrap_or_else(|| KeyEvent::new(KeyCode::Unknown))
}

fn character_event(text: &str) -> KeyEvent {
    text.chars()
        .next()
        .filter(char::is_ascii_alphabetic)
        .map(KeyEvent::from_char)
        .unwrap_or_else(|| KeyEvent::new(KeyCode::Unknown))
}

fn nine_key_digit_event(text: &str) -> KeyEvent {
    text.chars()
        .next()
        .and_then(|ch| ch.to_digit(10))
        .map(|digit| KeyEvent::new(KeyCode::NineKeyDigit(digit as u8)))
        .unwrap_or_else(|| KeyEvent::new(KeyCode::Unknown))
}

fn text_event(text: &str) -> KeyEvent {
    text.chars()
        .next()
        .map(KeyEvent::from_char)
        .unwrap_or_else(|| KeyEvent::new(KeyCode::Unknown))
}

fn read_c_string(value: *const c_char) -> String {
    if value.is_null() {
        return String::new();
    }

    unsafe { CStr::from_ptr(value) }
        .to_string_lossy()
        .into_owned()
}

impl From<CoreImeMode> for ImeMode {
    fn from(mode: CoreImeMode) -> Self {
        match mode {
            CoreImeMode::Chinese => Self::Chinese,
            CoreImeMode::English => Self::English,
        }
    }
}
