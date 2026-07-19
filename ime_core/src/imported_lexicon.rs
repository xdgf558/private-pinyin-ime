use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::Path;

use crate::atomic_file::AtomicFile;
use crate::error::{ImeError, ImeResult};
use crate::lexicon::{Lexicon, LexiconEntry};
use crate::syllable::is_legal_syllable;

pub const MAX_RIME_SOURCE_BYTES: u64 = 16 * 1024 * 1024;
pub const MAX_IMPORTED_FILE_BYTES: u64 = 32 * 1024 * 1024;
pub const MAX_RIME_LINE_BYTES: usize = 4096;
pub const MAX_IMPORTED_ENTRIES: usize = 200_000;
const MAX_IMPORTED_PHRASE_CHARS: usize = 32;
const DEFAULT_IMPORTED_FREQUENCY: u32 = 1_000;
const MAX_IMPORTED_FREQUENCY: u32 = 1_000_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ImportedLexiconReport {
    pub accepted_rows: usize,
    pub skipped_rows: usize,
    pub total_entries: usize,
}

pub fn import_rime_file(
    source_path: impl AsRef<Path>,
    destination_path: impl AsRef<Path>,
) -> ImeResult<ImportedLexiconReport> {
    let metadata = fs::metadata(source_path.as_ref()).map_err(|_| ImeError::ImportedLexiconIo)?;
    if metadata.len() > MAX_RIME_SOURCE_BYTES {
        return Err(ImeError::ImportedLexiconLimit);
    }

    let source = read_utf8_file_bounded(source_path.as_ref(), MAX_RIME_SOURCE_BYTES)?;
    let (incoming, skipped_rows) = parse_rime_dictionary(&source)?;
    let accepted_rows = incoming.len();
    let destination_path = destination_path.as_ref();
    let existing = load_existing_entries(destination_path)?;
    let merged = merge_entries(existing, incoming)?;
    write_canonical_tsv(destination_path, &merged)?;

    Ok(ImportedLexiconReport {
        accepted_rows,
        skipped_rows,
        total_entries: merged.len(),
    })
}

pub fn clear_imported_file(path: impl AsRef<Path>) -> ImeResult<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(ImeError::ImportedLexiconIo),
    }
}

pub fn parse_rime_dictionary(input: &str) -> ImeResult<(Vec<LexiconEntry>, usize)> {
    let mut entries = Vec::new();
    let mut skipped_rows = 0;
    let mut in_yaml_header = false;

    for raw_line in input.lines() {
        if raw_line.len() > MAX_RIME_LINE_BYTES {
            return Err(ImeError::ImportedLexiconLimit);
        }

        let line = raw_line.trim();
        if line == "---" {
            in_yaml_header = true;
            continue;
        }
        if line == "..." {
            in_yaml_header = false;
            continue;
        }
        if line.is_empty() || line.starts_with('#') || in_yaml_header {
            continue;
        }

        let data = line.split_once(" #").map_or(line, |(data, _)| data);
        let mut fields = data.split('\t');
        let Some(phrase) = fields.next().map(str::trim) else {
            continue;
        };
        let Some(raw_pinyin) = fields.next().map(str::trim) else {
            skipped_rows += 1;
            continue;
        };
        let raw_frequency = fields.next().map(str::trim);

        let Some(pinyin) = normalize_explicit_pinyin(raw_pinyin) else {
            skipped_rows += 1;
            continue;
        };
        if !is_supported_phrase(phrase) {
            skipped_rows += 1;
            continue;
        }

        let frequency = parse_frequency(raw_frequency);
        entries.push(LexiconEntry {
            phrase: phrase.to_owned(),
            pinyin,
            frequency,
        });
        if entries.len() > MAX_IMPORTED_ENTRIES {
            return Err(ImeError::ImportedLexiconLimit);
        }
    }

    if entries.is_empty() {
        return Err(ImeError::ImportedLexiconParse);
    }

    Ok((deduplicate_entries(entries), skipped_rows))
}

fn load_existing_entries(path: &Path) -> ImeResult<Vec<LexiconEntry>> {
    match fs::metadata(path) {
        Ok(metadata) if metadata.len() > MAX_IMPORTED_FILE_BYTES => {
            return Err(ImeError::ImportedLexiconLimit)
        }
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(_) => return Err(ImeError::ImportedLexiconIo),
    }
    let contents = read_utf8_file_bounded(path, MAX_IMPORTED_FILE_BYTES)?;
    let lexicon = Lexicon::from_tsv(&contents).map_err(|_| ImeError::ImportedLexiconParse)?;
    validate_imported_entries(lexicon.entries())?;
    Ok(lexicon.entries().to_vec())
}

pub(crate) fn read_utf8_file_bounded(path: &Path, max_bytes: u64) -> ImeResult<String> {
    let file = File::open(path).map_err(|_| ImeError::ImportedLexiconIo)?;
    let mut contents = String::new();
    file.take(max_bytes.saturating_add(1))
        .read_to_string(&mut contents)
        .map_err(|_| ImeError::ImportedLexiconIo)?;
    if contents.len() as u64 > max_bytes {
        return Err(ImeError::ImportedLexiconLimit);
    }
    Ok(contents)
}

fn merge_entries(
    mut existing: Vec<LexiconEntry>,
    incoming: Vec<LexiconEntry>,
) -> ImeResult<Vec<LexiconEntry>> {
    existing.extend(incoming);
    let merged = deduplicate_entries(existing);
    if merged.len() > MAX_IMPORTED_ENTRIES {
        return Err(ImeError::ImportedLexiconLimit);
    }
    Ok(merged)
}

fn deduplicate_entries(entries: Vec<LexiconEntry>) -> Vec<LexiconEntry> {
    let mut by_identity = HashMap::<(String, String), u32>::new();
    for entry in entries {
        let key = (entry.phrase, entry.pinyin);
        by_identity
            .entry(key)
            .and_modify(|frequency| *frequency = (*frequency).max(entry.frequency))
            .or_insert(entry.frequency);
    }

    let mut entries = by_identity
        .into_iter()
        .map(|((phrase, pinyin), frequency)| LexiconEntry {
            phrase,
            pinyin,
            frequency,
        })
        .collect::<Vec<_>>();
    entries.sort_unstable_by(|left, right| {
        left.pinyin
            .cmp(&right.pinyin)
            .then_with(|| right.frequency.cmp(&left.frequency))
            .then_with(|| left.phrase.cmp(&right.phrase))
    });
    entries
}

fn write_canonical_tsv(path: &Path, entries: &[LexiconEntry]) -> ImeResult<()> {
    validate_imported_entries(entries)?;
    ensure_canonical_size(entries.iter().map(canonical_row_size))?;

    let mut file = AtomicFile::create(path).map_err(|_| ImeError::ImportedLexiconIo)?;
    file.write_all(b"phrase\tpinyin\tfrequency\n")
        .map_err(|_| ImeError::ImportedLexiconIo)?;
    for entry in entries {
        writeln!(
            file,
            "{}\t{}\t{}",
            entry.phrase, entry.pinyin, entry.frequency
        )
        .map_err(|_| ImeError::ImportedLexiconIo)?;
    }
    file.finish().map_err(|_| ImeError::ImportedLexiconIo)
}

pub(crate) fn validate_imported_entries(entries: &[LexiconEntry]) -> ImeResult<()> {
    if entries.len() > MAX_IMPORTED_ENTRIES {
        return Err(ImeError::ImportedLexiconLimit);
    }

    for entry in entries {
        let mut syllable_count = 0;
        let mut invalid_syllable = false;
        for syllable in entry.pinyin.split_whitespace() {
            syllable_count += 1;
            invalid_syllable |= !is_legal_syllable(syllable);
        }
        if !is_supported_phrase(&entry.phrase)
            || entry.pinyin.len() > MAX_RIME_LINE_BYTES
            || syllable_count == 0
            || syllable_count > MAX_IMPORTED_PHRASE_CHARS
            || invalid_syllable
        {
            return Err(ImeError::ImportedLexiconParse);
        }
    }
    Ok(())
}

fn canonical_row_size(entry: &LexiconEntry) -> u64 {
    entry.phrase.len() as u64
        + 1
        + entry.pinyin.len() as u64
        + 1
        + decimal_digits(entry.frequency)
        + 1
}

fn decimal_digits(value: u32) -> u64 {
    if value == 0 {
        1
    } else {
        u64::from(value.ilog10()) + 1
    }
}

fn ensure_canonical_size(row_sizes: impl IntoIterator<Item = u64>) -> ImeResult<()> {
    let mut size = b"phrase\tpinyin\tfrequency\n".len() as u64;
    for row_size in row_sizes {
        size = size
            .checked_add(row_size)
            .ok_or(ImeError::ImportedLexiconLimit)?;
        if size > MAX_IMPORTED_FILE_BYTES {
            return Err(ImeError::ImportedLexiconLimit);
        }
    }
    Ok(())
}

fn normalize_explicit_pinyin(value: &str) -> Option<String> {
    let normalized = value
        .trim()
        .to_lowercase()
        .replace("u:", "ü")
        .replace('v', "ü")
        .replace('\'', " ");
    let syllables = normalized
        .split_whitespace()
        .map(normalize_syllable)
        .collect::<Option<Vec<_>>>()?;
    if syllables.is_empty()
        || syllables
            .iter()
            .any(|syllable| !is_legal_syllable(syllable))
    {
        return None;
    }
    Some(syllables.join(" "))
}

fn normalize_syllable(value: &str) -> Option<String> {
    let mut output = String::new();
    for ch in value.chars() {
        let normalized = match ch {
            'ā' | 'á' | 'ǎ' | 'à' => 'a',
            'ē' | 'é' | 'ě' | 'è' => 'e',
            'ī' | 'í' | 'ǐ' | 'ì' => 'i',
            'ō' | 'ó' | 'ǒ' | 'ò' => 'o',
            'ū' | 'ú' | 'ǔ' | 'ù' => 'u',
            'ǖ' | 'ǘ' | 'ǚ' | 'ǜ' => 'ü',
            '1'..='5' => continue,
            'a'..='z' | 'ü' => ch,
            _ => return None,
        };
        output.push(normalized);
    }
    (!output.is_empty()).then_some(output)
}

fn parse_frequency(value: Option<&str>) -> u32 {
    value
        .and_then(|value| value.trim_end_matches('%').parse::<f64>().ok())
        .filter(|value| value.is_finite() && *value > 0.0)
        .map(|value| value.round().clamp(1.0, f64::from(MAX_IMPORTED_FREQUENCY)) as u32)
        .unwrap_or(DEFAULT_IMPORTED_FREQUENCY)
}

fn is_supported_phrase(phrase: &str) -> bool {
    let length = phrase.chars().count();
    length > 0
        && length <= MAX_IMPORTED_PHRASE_CHARS
        && phrase.chars().all(|ch| {
            ch == '〇'
                || ('\u{3400}'..='\u{4dbf}').contains(&ch)
                || ('\u{4e00}'..='\u{9fff}').contains(&ch)
                || ('\u{f900}'..='\u{faff}').contains(&ch)
                || ('\u{20000}'..='\u{323af}').contains(&ch)
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_rime_yaml_with_explicit_pinyin_and_skips_unannotated_rows() {
        let source = "---\nname: demo\nversion: 1\n...\n你好\tni3 hao3\t1200\n女儿\tnǚ'ér\t80%\n自动注音\t\n英文\tenglish\t3\n";
        let (entries, skipped) = parse_rime_dictionary(source).expect("dictionary parses");

        assert_eq!(entries.len(), 2);
        assert_eq!(skipped, 2);
        assert!(entries
            .iter()
            .any(|entry| entry.phrase == "你好" && entry.pinyin == "ni hao"));
        assert!(entries
            .iter()
            .any(|entry| entry.phrase == "女儿" && entry.pinyin == "nü er"));
    }

    #[test]
    fn deduplicates_rows_and_keeps_the_highest_frequency() {
        let (entries, _) = parse_rime_dictionary("你好\tni hao\t10\n你好\tni hao\t30\n")
            .expect("dictionary parses");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].frequency, 30);
    }

    #[test]
    fn rejects_a_dictionary_without_usable_explicit_pinyin() {
        assert_eq!(
            parse_rime_dictionary("---\nname: empty\n...\n自动注音\n"),
            Err(ImeError::ImportedLexiconParse)
        );
    }

    #[test]
    fn rejects_a_canonical_file_that_would_exceed_the_runtime_limit() {
        assert_eq!(
            ensure_canonical_size([MAX_IMPORTED_FILE_BYTES]),
            Err(ImeError::ImportedLexiconLimit)
        );
    }
}
