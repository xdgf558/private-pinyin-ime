#![forbid(unsafe_code)]

pub mod api;
pub mod candidate;
pub mod error;
pub mod key_event;
pub mod lexicon;
pub mod logger;
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
pub use pinyin_parser::{PinyinParse, PinyinParser};
pub use session::InputSession;
pub use settings::{ImeMode, ImeSettings};
