use std::collections::HashMap;
use std::fmt;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock, Weak};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rusqlite::functions::FunctionFlags;
use rusqlite::{params, Connection, Error as SqliteError, ErrorCode};
use rusqlite::{Transaction, TransactionBehavior};

use crate::atomic_file::AtomicFile;
use crate::candidate::{Candidate, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::lexicon::MAX_LOOKUP_CANDIDATES;
use crate::nine_key::{is_valid_nine_key_input, pinyin_to_nine_key};
use crate::pinyin_parser::{compact_pinyin, compact_prefix_upper_bound, PinyinParse, PinyinParser};
use crate::ranker::{CandidateMatchKind, Ranker};

const EXPORT_HEADER: &[u8] = b"phrase\tpinyin\tfrequency\tupdated_at_ms\n";
const MAX_USER_BIGRAM_PHRASE_CHARS: usize = 8;
const MAX_USER_SHORT_PHRASE_CHARS: usize = 12;
const USER_SHORT_PHRASE_TOKEN_COUNT: i64 = 2;
const USER_LEARNING_HALF_LIFE_MS: f64 = 30.0 * 24.0 * 60.0 * 60.0 * 1_000.0;
const SQLITE_BUSY_RETRY_LIMIT: usize = 4;
const SQLITE_BUSY_RETRY_DELAY_MS: u64 = 10;
pub const MAX_USER_TRANSITION_SNAPSHOT: usize = 5_000;
pub type UserTransitionSnapshot = HashMap<String, HashMap<String, f64>>;
type UserLexiconWriteLocks = Mutex<HashMap<PathBuf, Weak<Mutex<()>>>>;

static USER_LEXICON_WRITE_LOCKS: OnceLock<UserLexiconWriteLocks> = OnceLock::new();

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UserLearningLimits {
    pub phrases: usize,
    pub bigrams: usize,
    pub short_phrases: usize,
    pub trigrams: usize,
}

impl Default for UserLearningLimits {
    fn default() -> Self {
        Self {
            phrases: 20_000,
            bigrams: 20_000,
            short_phrases: 10_000,
            trigrams: 20_000,
        }
    }
}

pub struct UserLexicon {
    db_path: PathBuf,
    connection: Mutex<Connection>,
    write_lock: Arc<Mutex<()>>,
    limits: UserLearningLimits,
}

impl fmt::Debug for UserLexicon {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserLexicon")
            .field("db_path", &self.db_path)
            .field("limits", &self.limits)
            .finish_non_exhaustive()
    }
}

impl UserLexicon {
    pub fn open(path: impl AsRef<Path>) -> ImeResult<Self> {
        Self::open_with_limits(path, UserLearningLimits::default())
    }

    pub fn open_with_limits(path: impl AsRef<Path>, limits: UserLearningLimits) -> ImeResult<Self> {
        let db_path = path.as_ref().to_path_buf();
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).map_err(|_| ImeError::UserLexiconDatabase)?;
        }

        let write_lock = shared_user_lexicon_write_lock(&db_path)?;
        let connection = Connection::open(&db_path).map_err(|_| ImeError::UserLexiconDatabase)?;
        {
            let _write_guard = write_lock
                .lock()
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            configure_connection(&connection)?;
        }
        let lexicon = Self {
            db_path,
            connection: Mutex::new(connection),
            write_lock,
            limits,
        };
        lexicon.ensure_schema()?;
        lexicon.enforce_capacity_limits()?;
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
        let reference_time_ms = now_ms();

        let connection = self.connection()?;
        for exact_pinyin in &exact_pinyins {
            let rows = {
                let mut statement = connection
                    .prepare(
                        "SELECT phrase, pinyin, weight, updated_at_ms
                         FROM user_phrases
                         WHERE pinyin = ?1
                         ORDER BY updated_at_ms DESC, frequency DESC, phrase ASC",
                    )
                    .map_err(|_| ImeError::UserLexiconDatabase)?;
                let mapped_rows = statement
                    .query_map(params![exact_pinyin], |row| {
                        let phrase: String = row.get(0)?;
                        let pinyin: String = row.get(1)?;
                        let weight: f64 = row.get(2)?;
                        let updated_at_ms: i64 = row.get(3)?;
                        Ok((phrase, pinyin, weight, updated_at_ms))
                    })
                    .map_err(|_| ImeError::UserLexiconDatabase)?;
                collect_user_lookup_rows(mapped_rows)?
            };

            for (phrase, pinyin, weight, updated_at_ms) in rows {
                if seen_phrases.insert(phrase.clone()) {
                    exact_candidates.push(user_candidate(
                        phrase,
                        pinyin,
                        weight,
                        updated_at_ms,
                        reference_time_ms,
                        CandidateMatchKind::Exact,
                    ));
                }
            }
        }

        let upper_bound = compact_prefix_upper_bound(&normalized_input);
        let rows = {
            let mut statement = connection
                .prepare(
                    "SELECT phrase, pinyin, weight, updated_at_ms
                     FROM user_phrases
                     WHERE compact_pinyin >= ?1 AND compact_pinyin < ?2
                     ORDER BY updated_at_ms DESC, frequency DESC, phrase ASC",
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            let mapped_rows = statement
                .query_map(params![normalized_input, upper_bound], |row| {
                    let phrase: String = row.get(0)?;
                    let pinyin: String = row.get(1)?;
                    let weight: f64 = row.get(2)?;
                    let updated_at_ms: i64 = row.get(3)?;
                    Ok((phrase, pinyin, weight, updated_at_ms))
                })
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            collect_user_lookup_rows(mapped_rows)?
        };

        for (phrase, pinyin, weight, updated_at_ms) in rows {
            if !exact_pinyins.contains(&pinyin) && seen_phrases.insert(phrase.clone()) {
                prefix_candidates.push(user_candidate(
                    phrase,
                    pinyin,
                    weight,
                    updated_at_ms,
                    reference_time_ms,
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

    pub fn lookup_nine_key(&self, digits: &str) -> ImeResult<Vec<Candidate>> {
        if !is_valid_nine_key_input(digits) {
            return Ok(Vec::new());
        }

        let upper_bound = compact_prefix_upper_bound(digits);
        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let rows = {
            let mut statement = connection
                .prepare(
                    "SELECT phrase, pinyin, weight, updated_at_ms
                     FROM user_phrases
                     WHERE nine_key >= ?1 AND nine_key < ?2
                     ORDER BY updated_at_ms DESC, frequency DESC, phrase ASC",
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            let mapped_rows = statement
                .query_map(params![digits, upper_bound], |row| {
                    let phrase: String = row.get(0)?;
                    let pinyin: String = row.get(1)?;
                    let weight: f64 = row.get(2)?;
                    let updated_at_ms: i64 = row.get(3)?;
                    Ok((phrase, pinyin, weight, updated_at_ms))
                })
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            collect_user_lookup_rows(mapped_rows)?
        };

        let mut exact_candidates = Vec::new();
        let mut prefix_candidates = Vec::new();
        let mut seen_phrases = std::collections::HashSet::new();
        for (phrase, pinyin, weight, updated_at_ms) in rows {
            if !seen_phrases.insert(phrase.clone()) {
                continue;
            }
            let match_kind = if pinyin_to_nine_key(&pinyin) == digits {
                CandidateMatchKind::Exact
            } else {
                CandidateMatchKind::Prefix
            };
            let candidate = user_candidate(
                phrase,
                pinyin,
                weight,
                updated_at_ms,
                reference_time_ms,
                match_kind,
            );
            if match_kind == CandidateMatchKind::Exact {
                exact_candidates.push(candidate);
            } else {
                prefix_candidates.push(candidate);
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

        let _write_guard = self.write_guard()?;
        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let is_new = connection
            .query_row(
                "SELECT NOT EXISTS(
                   SELECT 1 FROM user_phrases WHERE phrase = ?1 AND pinyin = ?2
                 )",
                params![text, pinyin],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        with_sqlite_busy_retry(|| {
            connection.execute(
                "INSERT INTO user_phrases
                   (phrase, pinyin, compact_pinyin, nine_key, frequency, weight, updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4, 1, 1.0, ?5)
                 ON CONFLICT(phrase, pinyin) DO UPDATE SET
                   frequency = frequency + 1,
                   weight = private_pinyin_decay_weight(
                     weight,
                     updated_at_ms,
                     excluded.updated_at_ms
                   ) + 1.0,
                   compact_pinyin = excluded.compact_pinyin,
                   nine_key = excluded.nine_key,
                   updated_at_ms = excluded.updated_at_ms",
                params![
                    text,
                    pinyin,
                    compact_pinyin(pinyin),
                    pinyin_to_nine_key(pinyin),
                    reference_time_ms
                ],
            )
        })
        .map_err(|_| ImeError::UserLexiconDatabase)?;
        if is_new {
            prune_table_to_limit(&connection, LearningTable::Phrases, self.limits.phrases)?;
        }
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

        let _write_guard = self.write_guard()?;
        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let is_new = connection
            .query_row(
                "SELECT NOT EXISTS(
                   SELECT 1 FROM user_bigrams
                   WHERE left_phrase = ?1 AND right_phrase = ?2
                 )",
                params![left, right],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        with_sqlite_busy_retry(|| {
            connection.execute(
                "INSERT INTO user_bigrams
                   (left_phrase, right_phrase, right_pinyin, frequency, weight, updated_at_ms)
                 VALUES (?1, ?2, ?3, 1, 1.0, ?4)
                 ON CONFLICT(left_phrase, right_phrase) DO UPDATE SET
                   right_pinyin = excluded.right_pinyin,
                   frequency = frequency + 1,
                   weight = private_pinyin_decay_weight(
                     weight,
                     updated_at_ms,
                     excluded.updated_at_ms
                   ) + 1.0,
                   updated_at_ms = excluded.updated_at_ms",
                params![left, right, right_pinyin, reference_time_ms],
            )
        })
        .map_err(|_| ImeError::UserLexiconDatabase)?;
        if is_new {
            prune_table_to_limit(&connection, LearningTable::Bigrams, self.limits.bigrams)?;
        }
        Ok(())
    }

    pub fn predict_next(&self, left: &str) -> ImeResult<Vec<Candidate>> {
        if left.is_empty() {
            return Ok(Vec::new());
        }

        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let rows = {
            let mut statement = connection
                .prepare(
                    "SELECT right_phrase, right_pinyin, weight, updated_at_ms
                     FROM user_bigrams
                     WHERE left_phrase = ?1
                     ORDER BY updated_at_ms DESC, frequency DESC, right_phrase ASC",
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            let mapped_rows = statement
                .query_map(params![left], |row| {
                    let phrase: String = row.get(0)?;
                    let pinyin: String = row.get(1)?;
                    let weight: f64 = row.get(2)?;
                    let updated_at_ms: i64 = row.get(3)?;
                    Ok((phrase, pinyin, weight, updated_at_ms))
                })
                .map_err(|_| ImeError::UserLexiconDatabase)?;
            collect_user_lookup_rows(mapped_rows)?
        };

        let mut candidates = rows
            .into_iter()
            .map(|row| user_prediction_candidate(row, reference_time_ms))
            .collect::<Vec<_>>();
        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(MAX_LOOKUP_CANDIDATES);
        Ok(candidates)
    }

    pub fn transition_snapshot(&self) -> ImeResult<UserTransitionSnapshot> {
        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let mut statement = connection
            .prepare(
                "SELECT left_phrase, right_phrase, weight, updated_at_ms
                 FROM user_bigrams
                 ORDER BY updated_at_ms DESC, frequency DESC",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, f64>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut weighted_rows = Vec::new();
        for row in rows {
            let (left, right, weight, updated_at_ms) =
                row.map_err(|_| ImeError::UserLexiconDatabase)?;
            weighted_rows.push((
                left,
                right,
                decayed_weight(weight, updated_at_ms, reference_time_ms),
            ));
        }
        weighted_rows.sort_by(|left, right| right.2.total_cmp(&left.2));
        weighted_rows.truncate(MAX_USER_TRANSITION_SNAPSHOT);

        let mut snapshot = UserTransitionSnapshot::new();
        for (left, right, weight) in weighted_rows {
            snapshot.entry(left).or_default().insert(right, weight);
        }
        Ok(snapshot)
    }

    pub fn record_trigram(
        &self,
        first: &str,
        second: &str,
        next: &str,
        next_pinyin: &str,
    ) -> ImeResult<()> {
        if first.is_empty()
            || second.is_empty()
            || next.is_empty()
            || next_pinyin.is_empty()
            || exceeds_user_bigram_phrase_limit(first)
            || exceeds_user_bigram_phrase_limit(second)
            || exceeds_user_bigram_phrase_limit(next)
        {
            return Ok(());
        }

        let _write_guard = self.write_guard()?;
        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let is_new = connection
            .query_row(
                "SELECT NOT EXISTS(
                   SELECT 1 FROM user_trigrams
                   WHERE first_phrase = ?1 AND second_phrase = ?2 AND next_phrase = ?3
                 )",
                params![first, second, next],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        with_sqlite_busy_retry(|| {
            connection.execute(
                "INSERT INTO user_trigrams
                   (first_phrase, second_phrase, next_phrase, next_pinyin, frequency, weight, updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4, 1, 1.0, ?5)
                 ON CONFLICT(first_phrase, second_phrase, next_phrase) DO UPDATE SET
                   next_pinyin = excluded.next_pinyin,
                   frequency = frequency + 1,
                   weight = private_pinyin_decay_weight(
                     weight,
                     updated_at_ms,
                     excluded.updated_at_ms
                   ) + 1.0,
                   updated_at_ms = excluded.updated_at_ms",
                params![first, second, next, next_pinyin, reference_time_ms],
            )
        })
        .map_err(|_| ImeError::UserLexiconDatabase)?;
        if is_new {
            prune_table_to_limit(&connection, LearningTable::Trigrams, self.limits.trigrams)?;
        }
        Ok(())
    }

    pub fn predict_trigram(&self, first: &str, second: &str) -> ImeResult<Vec<Candidate>> {
        if first.is_empty() || second.is_empty() {
            return Ok(Vec::new());
        }

        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let mut statement = connection
            .prepare(
                "SELECT next_phrase, next_pinyin, weight, updated_at_ms
                 FROM user_trigrams
                 WHERE first_phrase = ?1 AND second_phrase = ?2
                 ORDER BY updated_at_ms DESC, frequency DESC, next_phrase ASC",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map(params![first, second], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, f64>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut candidates = Vec::new();
        for row in rows {
            let row = row.map_err(|_| ImeError::UserLexiconDatabase)?;
            candidates.push(user_trigram_prediction_candidate(row, reference_time_ms));
        }
        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(MAX_LOOKUP_CANDIDATES);
        Ok(candidates)
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

        let _write_guard = self.write_guard()?;
        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let is_new = connection
            .query_row(
                "SELECT NOT EXISTS(
                   SELECT 1 FROM user_short_phrases
                   WHERE left_phrase = ?1 AND phrase = ?2
                 )",
                params![left, phrase],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        with_sqlite_busy_retry(|| {
            connection.execute(
                "INSERT INTO user_short_phrases
                   (left_phrase, phrase, token_count, frequency, weight, updated_at_ms)
                 VALUES (?1, ?2, ?3, 1, 1.0, ?4)
                 ON CONFLICT(left_phrase, phrase) DO UPDATE SET
                   token_count = excluded.token_count,
                   frequency = frequency + 1,
                   weight = private_pinyin_decay_weight(
                     weight,
                     updated_at_ms,
                     excluded.updated_at_ms
                   ) + 1.0,
                   updated_at_ms = excluded.updated_at_ms",
                params![left, phrase, token_count, reference_time_ms],
            )
        })
        .map_err(|_| ImeError::UserLexiconDatabase)?;
        if is_new {
            prune_table_to_limit(
                &connection,
                LearningTable::ShortPhrases,
                self.limits.short_phrases,
            )?;
        }
        Ok(())
    }

    pub fn predict_short_phrases(&self, left: &str) -> ImeResult<Vec<Candidate>> {
        if left.is_empty() {
            return Ok(Vec::new());
        }

        let reference_time_ms = now_ms();
        let connection = self.connection()?;
        let mut statement = connection
            .prepare(
                "SELECT phrase, weight, updated_at_ms
                 FROM user_short_phrases
                 WHERE left_phrase = ?1
                 ORDER BY updated_at_ms DESC, frequency DESC, phrase ASC",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map(params![left], |row| {
                let phrase: String = row.get(0)?;
                let weight: f64 = row.get(1)?;
                let updated_at_ms: i64 = row.get(2)?;
                Ok((phrase, weight, updated_at_ms))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut candidates = Vec::new();
        for row in rows {
            let (phrase, weight, updated_at_ms) = row.map_err(|_| ImeError::UserLexiconDatabase)?;
            candidates.push(user_short_prediction_candidate(
                phrase,
                weight,
                updated_at_ms,
                reference_time_ms,
            ));
        }

        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(MAX_LOOKUP_CANDIDATES);
        Ok(candidates)
    }

    pub fn clear(&self) -> ImeResult<()> {
        let _write_guard = self.write_guard()?;
        let connection = self.connection()?;
        connection
            .execute_batch(
                "DELETE FROM user_phrases;
                 DELETE FROM user_bigrams;
                 DELETE FROM user_short_phrases;
                 DELETE FROM user_trigrams;",
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
                "SELECT first_phrase, second_phrase, next_phrase, next_pinyin, frequency, updated_at_ms
                 FROM user_trigrams
                 ORDER BY updated_at_ms DESC, frequency DESC,
                          first_phrase ASC, second_phrase ASC, next_phrase ASC",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(5)?,
                ))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;

        let mut wrote_trigram_header = false;
        for row in rows {
            let (first, second, next, next_pinyin, frequency, updated_at_ms) =
                row.map_err(|_| ImeError::UserLexiconDatabase)?;
            if !wrote_trigram_header {
                writeln!(file, "\n# user_trigrams").map_err(|_| ImeError::UserLexiconDatabase)?;
                writeln!(
                    file,
                    "first_phrase\tsecond_phrase\tnext_phrase\tnext_pinyin\tfrequency\tupdated_at_ms"
                )
                .map_err(|_| ImeError::UserLexiconDatabase)?;
                wrote_trigram_header = true;
            }
            writeln!(
                file,
                "{first}\t{second}\t{next}\t{next_pinyin}\t{frequency}\t{updated_at_ms}"
            )
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

    pub fn trigram_count(&self) -> ImeResult<usize> {
        let connection = self.connection()?;
        let count = connection
            .query_row("SELECT COUNT(*) FROM user_trigrams", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        usize::try_from(count).map_err(|_| ImeError::UserLexiconDatabase)
    }

    fn ensure_schema(&self) -> ImeResult<()> {
        let _write_guard = self.write_guard()?;
        let connection = self.connection()?;
        connection
            .execute_batch(
                "CREATE TABLE IF NOT EXISTS user_phrases (
                   phrase TEXT NOT NULL,
                   pinyin TEXT NOT NULL,
                   compact_pinyin TEXT NOT NULL,
                   nine_key TEXT NOT NULL DEFAULT '',
                   frequency INTEGER NOT NULL,
                   weight REAL NOT NULL DEFAULT 1.0,
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
                   weight REAL NOT NULL DEFAULT 1.0,
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
                   weight REAL NOT NULL DEFAULT 1.0,
                   updated_at_ms INTEGER NOT NULL,
                   PRIMARY KEY (left_phrase, phrase)
                 );
                 CREATE INDEX IF NOT EXISTS idx_user_short_phrases_left_phrase
                   ON user_short_phrases(left_phrase, frequency DESC, updated_at_ms DESC);
                 CREATE TABLE IF NOT EXISTS user_trigrams (
                   first_phrase TEXT NOT NULL,
                   second_phrase TEXT NOT NULL,
                   next_phrase TEXT NOT NULL,
                   next_pinyin TEXT NOT NULL,
                   frequency INTEGER NOT NULL,
                   weight REAL NOT NULL DEFAULT 1.0,
                   updated_at_ms INTEGER NOT NULL,
                   PRIMARY KEY (first_phrase, second_phrase, next_phrase)
                 );
                 CREATE INDEX IF NOT EXISTS idx_user_trigrams_context
                   ON user_trigrams(
                     first_phrase,
                     second_phrase,
                     frequency DESC,
                     updated_at_ms DESC
                   );",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        for table in [
            LearningTable::Phrases,
            LearningTable::Bigrams,
            LearningTable::ShortPhrases,
            LearningTable::Trigrams,
        ] {
            ensure_weight_column(&connection, table)?;
        }
        ensure_nine_key_column(&connection)?;
        connection
            .execute_batch(
                "CREATE INDEX IF NOT EXISTS idx_user_phrases_nine_key
                   ON user_phrases(nine_key);",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        Ok(())
    }

    fn enforce_capacity_limits(&self) -> ImeResult<()> {
        let _write_guard = self.write_guard()?;
        let connection = self.connection()?;
        prune_table_to_limit(&connection, LearningTable::Phrases, self.limits.phrases)?;
        prune_table_to_limit(&connection, LearningTable::Bigrams, self.limits.bigrams)?;
        prune_table_to_limit(
            &connection,
            LearningTable::ShortPhrases,
            self.limits.short_phrases,
        )?;
        prune_table_to_limit(&connection, LearningTable::Trigrams, self.limits.trigrams)
    }

    fn connection(&self) -> ImeResult<MutexGuard<'_, Connection>> {
        self.connection
            .lock()
            .map_err(|_| ImeError::UserLexiconDatabase)
    }

    fn write_guard(&self) -> ImeResult<MutexGuard<'_, ()>> {
        self.write_lock
            .lock()
            .map_err(|_| ImeError::UserLexiconDatabase)
    }
}

fn shared_user_lexicon_write_lock(path: &Path) -> ImeResult<Arc<Mutex<()>>> {
    let registry = USER_LEXICON_WRITE_LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut locks = registry.lock().map_err(|_| ImeError::UserLexiconDatabase)?;
    locks.retain(|_, lock| lock.strong_count() > 0);

    if let Some(lock) = locks.get(path).and_then(Weak::upgrade) {
        return Ok(lock);
    }

    let lock = Arc::new(Mutex::new(()));
    locks.insert(path.to_path_buf(), Arc::downgrade(&lock));
    Ok(lock)
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
        .create_scalar_function(
            "private_pinyin_decay_weight",
            3,
            FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
            |context| {
                let stored_weight = context.get::<f64>(0)?;
                let updated_at_ms = context.get::<i64>(1)?;
                let reference_time_ms = context.get::<i64>(2)?;
                Ok(decayed_weight(
                    stored_weight,
                    updated_at_ms,
                    reference_time_ms,
                ))
            },
        )
        .map_err(|_| ImeError::UserLexiconDatabase)?;
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

fn with_sqlite_busy_retry<T>(
    mut operation: impl FnMut() -> rusqlite::Result<T>,
) -> rusqlite::Result<T> {
    let mut retry_count = 0;
    loop {
        match operation() {
            Err(error)
                if is_sqlite_busy_or_locked(&error) && retry_count < SQLITE_BUSY_RETRY_LIMIT =>
            {
                retry_count += 1;
                std::thread::sleep(Duration::from_millis(
                    SQLITE_BUSY_RETRY_DELAY_MS * retry_count as u64,
                ));
            }
            result => return result,
        }
    }
}

fn is_sqlite_busy_or_locked(error: &SqliteError) -> bool {
    matches!(
        error,
        SqliteError::SqliteFailure(sqlite_error, _)
            if matches!(
                sqlite_error.code,
                ErrorCode::DatabaseBusy | ErrorCode::DatabaseLocked
            )
    )
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
    stored_weight: f64,
    updated_at_ms: i64,
    reference_time_ms: i64,
    match_kind: CandidateMatchKind,
) -> Candidate {
    let weight = decayed_weight(stored_weight, updated_at_ms, reference_time_ms);
    Candidate::new(phrase, pinyin, CandidateSource::User)
        .with_score(Ranker::score_weight(weight))
        .with_rank_score(Ranker::score_user_match(weight, match_kind))
}

fn user_prediction_candidate(
    (phrase, pinyin, stored_weight, updated_at_ms): (String, String, f64, i64),
    reference_time_ms: i64,
) -> Candidate {
    let weight = decayed_weight(stored_weight, updated_at_ms, reference_time_ms);
    Candidate::new(phrase, pinyin, CandidateSource::Prediction)
        .with_score(Ranker::score_weight(weight))
        .with_rank_score(Ranker::score_user_prediction_weight(weight))
}

fn user_short_prediction_candidate(
    phrase: String,
    stored_weight: f64,
    updated_at_ms: i64,
    reference_time_ms: i64,
) -> Candidate {
    let weight = decayed_weight(stored_weight, updated_at_ms, reference_time_ms);
    Candidate::new(phrase, "", CandidateSource::Prediction)
        .with_score(Ranker::score_weight(weight))
        .with_rank_score(Ranker::score_user_short_prediction_weight(weight))
}

fn user_trigram_prediction_candidate(
    (phrase, pinyin, stored_weight, updated_at_ms): (String, String, f64, i64),
    reference_time_ms: i64,
) -> Candidate {
    let weight = decayed_weight(stored_weight, updated_at_ms, reference_time_ms);
    Candidate::new(phrase, pinyin, CandidateSource::Prediction)
        .with_score(Ranker::score_weight(weight))
        .with_rank_score(Ranker::score_user_trigram_prediction_weight(weight))
}

fn exceeds_user_bigram_phrase_limit(phrase: &str) -> bool {
    phrase.chars().count() > MAX_USER_BIGRAM_PHRASE_CHARS
}

fn exceeds_user_short_phrase_limit(phrase: &str) -> bool {
    phrase.chars().count() > MAX_USER_SHORT_PHRASE_CHARS
}

fn collect_user_lookup_rows(
    rows: rusqlite::MappedRows<
        '_,
        impl FnMut(&rusqlite::Row<'_>) -> rusqlite::Result<(String, String, f64, i64)>,
    >,
) -> ImeResult<Vec<(String, String, f64, i64)>> {
    let mut collected = Vec::new();
    for row in rows {
        collected.push(row.map_err(|_| ImeError::UserLexiconDatabase)?);
    }
    Ok(collected)
}

#[derive(Debug, Clone, Copy)]
enum LearningTable {
    Phrases,
    Bigrams,
    ShortPhrases,
    Trigrams,
}

impl LearningTable {
    fn name(self) -> &'static str {
        match self {
            Self::Phrases => "user_phrases",
            Self::Bigrams => "user_bigrams",
            Self::ShortPhrases => "user_short_phrases",
            Self::Trigrams => "user_trigrams",
        }
    }
}

fn ensure_nine_key_column(connection: &Connection) -> ImeResult<()> {
    let transaction = Transaction::new_unchecked(connection, TransactionBehavior::Immediate)
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    if !table_has_column(&transaction, "user_phrases", "nine_key")? {
        transaction
            .execute_batch(
                "ALTER TABLE user_phrases
                   ADD COLUMN nine_key TEXT NOT NULL DEFAULT '';",
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
    }

    let rows = {
        let mut statement = transaction
            .prepare("SELECT rowid, pinyin FROM user_phrases WHERE nine_key = ''")
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let mapped = statement
            .query_map([], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let mut rows = Vec::new();
        for row in mapped {
            rows.push(row.map_err(|_| ImeError::UserLexiconDatabase)?);
        }
        rows
    };
    for (rowid, pinyin) in rows {
        transaction
            .execute(
                "UPDATE user_phrases SET nine_key = ?1 WHERE rowid = ?2",
                params![pinyin_to_nine_key(&pinyin), rowid],
            )
            .map_err(|_| ImeError::UserLexiconDatabase)?;
    }
    transaction
        .commit()
        .map_err(|_| ImeError::UserLexiconDatabase)
}

fn ensure_weight_column(connection: &Connection, table: LearningTable) -> ImeResult<()> {
    if table_has_weight_column(connection, table)? {
        return Ok(());
    }

    let transaction = Transaction::new_unchecked(connection, TransactionBehavior::Immediate)
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    if !table_has_weight_column(&transaction, table)? {
        let table_name = table.name();
        let alter_sql =
            format!("ALTER TABLE {table_name} ADD COLUMN weight REAL NOT NULL DEFAULT 1.0");
        transaction
            .execute_batch(&alter_sql)
            .map_err(|_| ImeError::UserLexiconDatabase)?;
        let migrate_sql = format!("UPDATE {table_name} SET weight = CAST(frequency AS REAL)");
        transaction
            .execute(&migrate_sql, [])
            .map_err(|_| ImeError::UserLexiconDatabase)?;
    }
    transaction
        .commit()
        .map_err(|_| ImeError::UserLexiconDatabase)
}

fn table_has_weight_column(connection: &Connection, table: LearningTable) -> ImeResult<bool> {
    table_has_column(connection, table.name(), "weight")
}

fn table_has_column(
    connection: &Connection,
    table_name: &str,
    column_name: &str,
) -> ImeResult<bool> {
    let pragma_sql = format!("PRAGMA table_info({table_name})");
    let mut statement = connection
        .prepare(&pragma_sql)
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    let columns = statement
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    for column in columns {
        if column.map_err(|_| ImeError::UserLexiconDatabase)? == column_name {
            return Ok(true);
        }
    }
    Ok(false)
}

fn decayed_weight(stored_weight: f64, updated_at_ms: i64, reference_time_ms: i64) -> f64 {
    let stored_weight = stored_weight.max(0.0);
    let age_ms = reference_time_ms.saturating_sub(updated_at_ms).max(0) as f64;
    stored_weight * 2.0_f64.powf(-age_ms / USER_LEARNING_HALF_LIFE_MS)
}

fn prune_table_to_limit(
    connection: &Connection,
    table: LearningTable,
    limit: usize,
) -> ImeResult<()> {
    let table_name = table.name();
    let count_sql = format!("SELECT COUNT(*) FROM {table_name}");
    let count = connection
        .query_row(&count_sql, [], |row| row.get::<_, i64>(0))
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    let count = usize::try_from(count).map_err(|_| ImeError::UserLexiconDatabase)?;
    if count <= limit {
        return Ok(());
    }

    let target = limit.saturating_sub(limit / 10);
    let remove_count = count.saturating_sub(target);
    let reference_time_ms = now_ms();
    let select_sql = format!("SELECT rowid, weight, updated_at_ms FROM {table_name}");
    let mut statement = connection
        .prepare(&select_sql)
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    let rows = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, f64>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .map_err(|_| ImeError::UserLexiconDatabase)?;

    let mut entries = Vec::with_capacity(count);
    for row in rows {
        let (rowid, stored_weight, updated_at_ms) =
            row.map_err(|_| ImeError::UserLexiconDatabase)?;
        entries.push((
            rowid,
            decayed_weight(stored_weight, updated_at_ms, reference_time_ms),
            updated_at_ms,
        ));
    }
    entries.sort_by(|left, right| {
        left.1
            .total_cmp(&right.1)
            .then_with(|| left.2.cmp(&right.2))
            .then_with(|| left.0.cmp(&right.0))
    });

    let delete_sql = format!("DELETE FROM {table_name} WHERE rowid = ?1");
    let mut delete_statement = connection
        .prepare_cached(&delete_sql)
        .map_err(|_| ImeError::UserLexiconDatabase)?;
    for (rowid, _, _) in entries.into_iter().take(remove_count) {
        delete_statement
            .execute(params![rowid])
            .map_err(|_| ImeError::UserLexiconDatabase)?;
    }
    Ok(())
}
