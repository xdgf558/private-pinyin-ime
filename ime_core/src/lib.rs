#![forbid(unsafe_code)]

mod atomic_file;

pub mod api;
pub mod candidate;
pub mod candidate_stability;
pub mod error;
pub mod imported_lexicon;
pub mod key_event;
pub mod lexicon;
pub mod logger;
pub mod nine_key;
mod nine_key_correction;
pub mod pinyin_correction;
pub mod pinyin_parser;
pub mod predictor;
pub mod privacy;
pub mod ranker;
#[cfg(feature = "reviewed-rime-frost")]
pub mod reviewed_rime_frost;
pub mod session;
pub mod settings;
pub mod syllable;
pub mod tolerant_input;
pub mod user_lexicon;

pub use api::{ImeEngine, ImeOutput};
pub use candidate::{
    Candidate, CandidateCorrection, CandidateCorrectionConfidence, CandidateCorrectionKind,
    CandidateSource,
};
pub use candidate_stability::{stabilize_candidate_page_order, STABLE_DEFAULT_CANDIDATE_COUNT};
pub use error::{ImeError, ImeResult};
pub use imported_lexicon::ImportedLexiconReport;
pub use key_event::{KeyCode, KeyEvent, Modifiers};
pub use nine_key::pinyin_to_nine_key;
pub use pinyin_correction::{PinyinCorrectionSuggestion, PinyinCorrector};
pub use pinyin_parser::{PinyinParse, PinyinParser};
pub use session::InputSession;
pub use settings::{AiSettings, ImeMode, ImeSettings};
pub use tolerant_input::TolerantPinyinVariant;
