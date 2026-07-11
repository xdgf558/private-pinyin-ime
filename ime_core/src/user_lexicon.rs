use std::collections::HashMap;
use std::fmt;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};

use crate::atomic_file::AtomicFile;
use crate::candidate::{Candidate, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::lexicon::MAX_LOOKUP_CANDIDATES;
use crate::pinyin_parser::{compact_pinyin, compact_prefix_upper_bound, PinyinParse, PinyinParser};
use crate::ranker::{CandidateMatchKind, Ranker};

const EXPORT_HEADER: &[u8] = b"phrase\tpinyin\tfrequency\tupdated_at_ms\n";
const MAX_USER_BIGRAM_PHRASE_CHARS: usize = 8;
const MAX_USER_SHORT_PHRASE_CHARS: usize = 12;
const USER_SHORT_PHRASE_TOKEN_COUNT: i64 = 2;
pub const MAX_USER_TRANSITION_SNAPSHOT: usize = 5_000;
pub type UserTransitionSnapshot = HashMap<String, HashMap<String, u32>>;

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
        configure_connection(&connection)?;
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

        let mut exact_candidates = Vec::new();
        let mut prefix_candidates = Vec::new();
        let mut seen_phrases = std::collections::HashSet::new();

        let connection = self.connection()?;
        for exact_pinyin in &exact_pinyins {
            let rows = {
                let mut statement = connection
                    .prepare(
                        "SELECT phrase, pinyin, frequency
                         FROM user_phrases
                         WHERE pinyin = ?1
                         ORDER BY frequency DESC, updated_at_ms DESC, phrase ASC
                         LIMIT ?2",
                    )
                    .map_err(|_| ImeError::UserLexiconDatabase)?;
                let mapped_rows = statement
                    .query_map(params![exact_pinyin, MAX_LOOKUP_CANDIDATES as i64], |row| {
                        let phrase: String = row.get(0)?;
                        let pinyin: String = row.get(1)?;
                        let frequency: i64 = row.get(2)?;
                        Ok((phrase, pinyin, frequency))
                    })
                    .map_err(|_| ImeError::UserLexiconDatabase)?;
                collect_user_rows(mapped_rows)?
            };

            for (phrase, pinyin, frequency) in rows {
                if seen_phrases.insert(phrase.clone()) {
                    exact_candidates.push(user_candidate(
                        phrase,
                        pinyin,
                        frequency,
                        CandidateMatchKind::Exact,
                    ));
                }
            }
        }

        let upper_bound = compact_prefix_upper_bound(&normalized_input);
        let rows = {
            let mut statement = connection
                .prepare(
                    "SELECT phrase, pinyin, frequency
                     FROM user_phrases
                     WHERE compact_pinyin >= ?1 AND compact_pinyin < ?2
                     ORDER BY frequency DESC, updated_at_ms DESC, phrase ASC
                     LIMIT ?3",
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            let mapped_rows = statement
                .query_map(
                    params![normalized_input, upper_bound, MAX_LOOKUP_CANDIDATES as i64],
                    |row| {
                        let phrase: String = row.get(0)?;
                        let pinyin: String = row.get(1)?;
                        let frequency: i64 = row.get(2)?;
                        Ok((phrase, pinyin, frequency))
                    },
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            collect_user_rows(mapped_rows)?
        };

        for (phrase, pinyin, frequency) in rows {
            if !exact_pinyins.contains(&pinyin) && seen_phrases.insert(phrase.clone()) {
                prefix_candidates.push(user_candidate(
                    phrase,
                    pinyin,
                    frequency,
                    CandidateMatchKind::Prefix,
                ));
            }
        }

        Ranker::sort_candidates(&mut exact_candidates);
        Ranker::sort_candidates(&mut prefix_candidates);
        exact_candidates.extend(prefix_candidates);
        exact_candidates.truncate(MAX_LOOKUP_CANDIDATES);
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

    pub fn record_transition(&self, left: &str, right: &str, right_pinyin: &str) -> ImeResult<()> {
        if left.is_empty()
            || right.is_empty()
            || right_pinyin.is_empty()
            || exceeds_user_bigram_phrase_limit(left)
            || exceeds_user_bigram_phrase_limit(right)
        {
            return Ok(());
        }

        let connection = self.connection()?;
        connection
            .execute(
                "INSERT INTO user_bigrams
                   (left_phrase, right_phrase, right_pinyin, frequency, updated_at_ms)
                 VALUES (?1, ?2, ?3, 1, ?4)
                 ON CONFLICT(left_phrase, right_phrase) DO UPDATE SET
                   right_pinyin = excluded.right_pinyin,
                   frequency = frequency + 1,
                   updated_at_ms = excluded.updated_at_ms",
                params![left, right, right_pinyin, now_ms()],
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        Ok(())
    }

    pub fn predict_next(&self, left: &str) -> ImeResult<Vec<Candidate>> {
        if left.is_empty() {
            return Ok(Vec::new());
        }

        let connection = self.connection()?;
        let rows = {
            let mut statement = connection
                .prepare(
                    "SELECT right_phrase, right_pinyin, frequency
                     FROM user_bigrams
                     WHERE left_phrase = ?1
                     ORDER BY frequency DESC, updated_at_ms DESC, right_phrase ASC
                     LIMIT ?2",
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            let mapped_rows = statement
                .query_map(params![left, MAX_LOOKUP_CANDIDATES as i64], |row| {
                    let phrase: String = row.get(0)?;
                    let pinyin: String = row.get(1)?;
                    let frequency: i64 = row.get(2)?;
                    Ok((phrase, pinyin, frequency))
                })
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            collect_user_rows(mapped_rows)?
        };

        let mut candidates = rows
            .into_iter()
            .map(user_prediction_candidate)
            .collect::<Vec<_>>();
        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(MAX_LOOKUP_CANDIDATES);
        Ok(candidates)
    }

    pub fn transition_snapshot(&self) -> ImeResult<UserTransitionSnapshot> {
        let connection = self.connection()?;
        let mut statement = connection
            .prepare(
                "SELECT left_phrase, right_phrase, frequency
                 FROM user_bigrams
                 ORDER BY frequency DESC, updated_at_ms DESC
                 LIMIT ?1",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map(params![MAX_USER_TRANSITION_SNAPSHOT as i64], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut snapshot = UserTransitionSnapshot::new();
        for row in rows {
            let (left, right, frequency) = row.map_err(|_| ImeError::UserLexiconDatabase)?;
            snapshot
                .entry(left)
                .or_default()
                .insert(right, u32::try_from(frequency).unwrap_or(u32::MAX));
        }
        Ok(snapshot)
    }

    pub fn record_short_phrase_prediction(
        &self,
        left: &str,
        phrase: &str,
        token_count: i64,
    ) -> ImeResult<()> {
        if left.is_empty()
            || phrase.is_empty()
            || token_count < USER_SHORT_PHRASE_TOKEN_COUNT
            || exceeds_user_bigram_phrase_limit(left)
            || exceeds_user_short_phrase_limit(phrase)
        {
            return Ok(());
        }

        let connection = self.connection()?;
        connection
            .execute(
                "INSERT INTO user_short_phrases
                   (left_phrase, phrase, token_count, frequency, updated_at_ms)
                 VALUES (?1, ?2, ?3, 1, ?4)
                 ON CONFLICT(left_phrase, phrase) DO UPDATE SET
                   token_count = excluded.token_count,
                   frequency = frequency + 1,
                   updated_at_ms = excluded.updated_at_ms",
                params![left, phrase, token_count, now_ms()],
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        Ok(())
    }

    pub fn predict_short_phrases(&self, left: &str) -> ImeResult<Vec<Candidate>> {
        if left.is_empty() {
            return Ok(Vec::new());
        }

        let connection = self.connection()?;
        let mut statement = connection
            .prepare(
                "SELECT phrase, frequency
                 FROM user_short_phrases
                 WHERE left_phrase = ?1
                 ORDER BY frequency DESC, updated_at_ms DESC, phrase ASC
                 LIMIT ?2",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map(params![left, MAX_LOOKUP_CANDIDATES as i64], |row| {
                let phrase: String = row.get(0)?;
                let frequency: i64 = row.get(1)?;
                Ok((phrase, frequency))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut candidates = Vec::new();
        for row in rows {
            let (phrase, frequency) = row.map_err(|_| ImeError::UserLexiconDatabase)?;
            candidates.push(user_short_prediction_candidate(phrase, frequency));
        }

        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(MAX_LOOKUP_CANDIDATES);
        Ok(candidates)
    }

    pub fn clear(&self) -> ImeResult<()> {
        let connection = self.connection()?;
        connection
            .execute_batch(
                "DELETE FROM user_phrases;
                 DELETE FROM user_bigrams;
                 DELETE FROM user_short_phrases;",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        Ok(())
    }

    pub fn export_tsv(&self, path: impl AsRef<Path>) -> ImeResult<usize> {
        let path = path.as_ref();
        let mut file = create_export_file(path)?;

        let connection = self.connection()?;
        let mut statement = connection
            .prepare(
                "SELECT phrase, pinyin, frequency, updated_at_ms
                 FROM user_phrases
                 ORDER BY updated_at_ms DESC, frequency DESC, phrase ASC",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut count = 0;
        for row in rows {
            let (phrase, pinyin, frequency, updated_at_ms) =
                row.map_err(|_| ImeError::UserLexiconDatabase)?;
            writeln!(file, "{phrase}\t{pinyin}\t{frequency}\t{updated_at_ms}")
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            count += 1;
        }

        let mut statement = connection
            .prepare(
                "SELECT left_phrase, phrase, token_count, frequency, updated_at_ms
                 FROM user_short_phrases
                 ORDER BY updated_at_ms DESC, frequency DESC, left_phrase ASC, phrase ASC",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                ))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut wrote_short_phrase_header = false;
        for row in rows {
            let (left_phrase, phrase, token_count, frequency, updated_at_ms) =
                row.map_err(|_| ImeError::UserLexiconDatabase)?;
            if !wrote_short_phrase_header {
                writeln!(file, "\n# user_short_phrases")
                    .map_err(|_| ImeError::UserLexiconDatabase)?;
                writeln!(
                    file,
                    "left_phrase\tphrase\ttoken_count\tfrequency\tupdated_at_ms"
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
                wrote_short_phrase_header = true;
            }
            writeln!(
                file,
                "{left_phrase}\t{phrase}\t{token_count}\t{frequency}\t{updated_at_ms}"
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
            count += 1;
        }

        let mut statement = connection
            .prepare(
                "SELECT left_phrase, right_phrase, right_pinyin, frequency, updated_at_ms
                 FROM user_bigrams
                 ORDER BY updated_at_ms DESC, frequency DESC, left_phrase ASC, right_phrase ASC",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                ))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut wrote_bigram_header = false;
        for row in rows {
            let (left_phrase, right_phrase, right_pinyin, frequency, updated_at_ms) =
                row.map_err(|_| ImeError::UserLexiconDatabase)?;
            if !wrote_bigram_header {
                writeln!(file, "\n# user_bigrams").map_err(|_| ImeError::UserLexiconDatabase)?;
                writeln!(
                    file,
                    "left_phrase\tright_phrase\tright_pinyin\tfrequency\tupdated_at_ms"
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
                wrote_bigram_header = true;
            }
            writeln!(
                file,
                "{left_phrase}\t{right_phrase}\t{right_pinyin}\t{frequency}\t{updated_at_ms}"
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
            count += 1;
        }

        finish_export_file(path, file)?;
        Ok(count)
    }

    pub fn export_empty_tsv(path: impl AsRef<Path>) -> ImeResult<usize> {
        let path = path.as_ref();
        let file = create_export_file(path)?;
        finish_export_file(path, file)?;
        Ok(0)
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

    pub fn bigram_count(&self) -> ImeResult<usize> {
        let connection = self.connection()?;
        let count = connection
            .query_row("SELECT COUNT(*) FROM user_bigrams", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        usize::try_from(count).map_err(|_| ImeError::UserLexiconDatabase)
    }

    pub fn short_phrase_count(&self) -> ImeResult<usize> {
        let connection = self.connection()?;
        let count = connection
            .query_row("SELECT COUNT(*) FROM user_short_phrases", [], |row| {
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
                 CREATE INDEX IF NOT EXISTS idx_user_phrases_pinyin
                   ON user_phrases(pinyin);
                 CREATE INDEX IF NOT EXISTS idx_user_phrases_compact_pinyin
                   ON user_phrases(compact_pinyin);
                 CREATE TABLE IF NOT EXISTS user_bigrams (
                   left_phrase TEXT NOT NULL,
                   right_phrase TEXT NOT NULL,
                   right_pinyin TEXT NOT NULL,
                   frequency INTEGER NOT NULL,
                   updated_at_ms INTEGER NOT NULL,
                   PRIMARY KEY (left_phrase, right_phrase)
                 );
                 CREATE INDEX IF NOT EXISTS idx_user_bigrams_left_phrase
                   ON user_bigrams(left_phrase, frequency DESC, updated_at_ms DESC);
                 CREATE TABLE IF NOT EXISTS user_short_phrases (
                   left_phrase TEXT NOT NULL,
                   phrase TEXT NOT NULL,
                   token_count INTEGER NOT NULL,
                   frequency INTEGER NOT NULL,
                   updated_at_ms INTEGER NOT NULL,
                   PRIMARY KEY (left_phrase, phrase)
                 );
                 CREATE INDEX IF NOT EXISTS idx_user_short_phrases_left_phrase
                   ON user_short_phrases(left_phrase, frequency DESC, updated_at_ms DESC);",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)
    }

    fn connection(&self) -> ImeResult<MutexGuard<'_, Connection>> {
        self.connection
            .lock()
            .map_err(|_| ImeError::UserLexiconDatabase)
    }
}

fn create_export_file(path: &Path) -> ImeResult<AtomicFile> {
    let mut file = AtomicFile::create(path).map_err(|_| ImeError::UserLexiconDatabase)?;
    file.write_all(EXPORT_HEADER)
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    Ok(file)
}

fn finish_export_file(_path: &Path, file: AtomicFile) -> ImeResult<()> {
    file.finish().map_err(|_| ImeError::UserLexiconDatabase)?;
    Ok(())
}

fn configure_connection(connection: &Connection) -> ImeResult<()> {
    connection
        .busy_timeout(Duration::from_millis(250))
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    connection
        .execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA busy_timeout=250;",
        )
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    Ok(())
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or_default()
}

fn user_candidate(
    phrase: String,
    pinyin: String,
    frequency: i64,
    match_kind: CandidateMatchKind,
) -> Candidate {
    let frequency = u32::try_from(frequency).unwrap_or(u32::MAX);
    Candidate::new(phrase, pinyin, CandidateSource::User)
        .with_score(Ranker::score(frequency))
        .with_rank_score(Ranker::score_match(
            frequency,
            match_kind,
            CandidateSource::User,
        ))
}

fn user_prediction_candidate((phrase, pinyin, frequency): (String, String, i64)) -> Candidate {
    let frequency = u32::try_from(frequency).unwrap_or(u32::MAX);
    Candidate::new(phrase, pinyin, CandidateSource::Prediction)
        .with_score(Ranker::score(frequency))
        .with_rank_score(Ranker::score_user_prediction(frequency))
}

fn user_short_prediction_candidate(phrase: String, frequency: i64) -> Candidate {
    let frequency = u32::try_from(frequency).unwrap_or(u32::MAX);
    Candidate::new(phrase, "", CandidateSource::Prediction)
        .with_score(Ranker::score(frequency))
        .with_rank_score(Ranker::score_user_short_prediction(frequency))
}

fn exceeds_user_bigram_phrase_limit(phrase: &str) -> bool {
    phrase.chars().count() > MAX_USER_BIGRAM_PHRASE_CHARS
}

fn exceeds_user_short_phrase_limit(phrase: &str) -> bool {
    phrase.chars().count() > MAX_USER_SHORT_PHRASE_CHARS
}

fn collect_user_rows(
    rows: rusqlite::MappedRows<
        '_,
        impl FnMut(&rusqlite::Row<'_>) -> rusqlite::Result<(String, String, i64)>,
    >,
) -> ImeResult<Vec<(String, String, i64)>> {
    let mut collected = Vec::new();
    for row in rows {
        collected.push(row.map_err(|_| ImeError::UserLexiconDatabase)?);
    }
    Ok(collected)
}
