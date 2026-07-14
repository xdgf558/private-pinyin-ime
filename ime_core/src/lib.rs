#![forbid(unsafe_code)]

mod atomic_file;

pub mod api;
pub mod candidate;
pub mod error;
pub mod key_event;
pub mod lexicon;
pub mod logger;
pub mod nine_key;
pub mod pinyin_parser;
pub mod predictor;
pub mod privacy;
pub mod ranker;
pub mod session;
pub mod settings;
pub mod syllable;
pub mod user_lexicon;

pub use api::{ImeEngine, ImeOutput};
pub use candidate::{Candidate, CandidateSource};
pub use error::{ImeError, ImeResult};
pub use key_event::{KeyCode, KeyEvent, Modifiers};
pub use nine_key::pinyin_to_nine_key;
pub use pinyin_parser::{PinyinParse, PinyinParser};
pub use session::InputSession;
pub use settings::{ImeMode, ImeSettings};
