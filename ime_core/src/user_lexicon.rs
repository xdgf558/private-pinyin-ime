use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};

use crate::candidate::{Candidate, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::pinyin_parser::{PinyinParse, PinyinParser};
use crate::ranker::Ranker;

pub struct UserLexicon {
    db_path: PathBuf,
    connection: Mutex<Connection>,
}

impl fmt::Debug for UserLexicon {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserLexicon")
            .field("db_path", &self.db_path)
            .finish_non_exhaustive()
    }
}

impl UserLexicon {
    pub fn open(path: impl AsRef<Path>) -> ImeResult<Self> {
        let db_path = path.as_ref().to_path_buf();
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).map_err(|_| ImeError::UserLexiconDatabase)?;
        }

        let connection = Connection::open(&db_path).map_err(|_| ImeError::UserLexiconDatabase)?;
        let lexicon = Self {
            db_path,
            connection: Mutex::new(connection),
        };
        lexicon.ensure_schema()?;
        Ok(lexicon)
    }

    pub fn lookup(&self, raw_input: &str, parses: &[PinyinParse]) -> ImeResult<Vec<Candidate>> {
        if raw_input.trim().is_empty() {
            return Ok(Vec::new());
        }

        let normalized_input = PinyinParser::normalize_raw(raw_input).replace('\'', "");
        let exact_pinyins = parses
            .iter()
            .filter(|parse| parse.is_complete())
            .map(PinyinParse::pinyin_string)
            .collect::<std::collections::HashSet<_>>();

        let connection = self.connection()?;
        let mut statement = connection
            .prepare(
                "SELECT phrase, pinyin, frequency
                 FROM user_phrases
                 WHERE compact_pinyin LIKE ?1
                 ORDER BY frequency DESC, updated_at_ms DESC, phrase ASC
                 LIMIT 50",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let like_pattern = format!("{normalized_input}%");
        let rows = statement
            .query_map(params![like_pattern], |row| {
                let phrase: String = row.get(0)?;
                let pinyin: String = row.get(1)?;
                let frequency: i64 = row.get(2)?;
                Ok((phrase, pinyin, frequency))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut exact_candidates = Vec::new();
        let mut prefix_candidates = Vec::new();

        for row in rows {
            let (phrase, pinyin, frequency) = row.map_err(|_| ImeError::UserLexiconDatabase)?;
            let exact_match = exact_pinyins.contains(&pinyin);
            let frequency = u32::try_from(frequency).unwrap_or(u32::MAX);
            let candidate = Candidate::new(phrase, pinyin, CandidateSource::User)
                .with_score(Ranker::score(frequency));

            if exact_match {
                exact_candidates.push(candidate);
            } else {
                prefix_candidates.push(candidate);
            }
        }

        Ranker::sort_candidates(&mut exact_candidates);
        Ranker::sort_candidates(&mut prefix_candidates);
        exact_candidates.extend(prefix_candidates);
        Ok(exact_candidates)
    }

    pub fn record_selection(&self, text: &str, pinyin: &str) -> ImeResult<()> {
        if text.is_empty() || pinyin.is_empty() {
            return Ok(());
        }

        let connection = self.connection()?;
        connection
            .execute(
                "INSERT INTO user_phrases
                   (phrase, pinyin, compact_pinyin, frequency, updated_at_ms)
                 VALUES (?1, ?2, ?3, 1, ?4)
                 ON CONFLICT(phrase, pinyin) DO UPDATE SET
                   frequency = frequency + 1,
                   compact_pinyin = excluded.compact_pinyin,
                   updated_at_ms = excluded.updated_at_ms",
                params![text, pinyin, compact_pinyin(pinyin), now_ms()],
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        Ok(())
    }

    pub fn entry_count(&self) -> ImeResult<usize> {
        let connection = self.connection()?;
        let count = connection
            .query_row("SELECT COUNT(*) FROM user_phrases", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        usize::try_from(count).map_err(|_| ImeError::UserLexiconDatabase)
    }

    fn ensure_schema(&self) -> ImeResult<()> {
        let connection = self.connection()?;
        connection
            .execute_batch(
                "CREATE TABLE IF NOT EXISTS user_phrases (
                   phrase TEXT NOT NULL,
                   pinyin TEXT NOT NULL,
                   compact_pinyin TEXT NOT NULL,
                   frequency INTEGER NOT NULL,
                   updated_at_ms INTEGER NOT NULL,
                   PRIMARY KEY (phrase, pinyin)
                 );
                 CREATE INDEX IF NOT EXISTS idx_user_phrases_compact_pinyin
                   ON user_phrases(compact_pinyin);",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)
    }

    fn connection(&self) -> ImeResult<MutexGuard<'_, Connection>> {
        self.connection
            .lock()
            .map_err(|_| ImeError::UserLexiconDatabase)
    }
}

fn compact_pinyin(pinyin: &str) -> String {
    pinyin.split_whitespace().collect::<String>()
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or_default()
}
