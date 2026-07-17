use std::collections::HashSet;
use std::fmt;

const ENGLISH_TERMS_TSV: &str = include_str!("../../assets/english_terms.tsv");
const ENGLISH_TERMS_HEADER: &str = "match_key\tdisplay\tpriority\tprovenance";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MixedInputSegmentKind {
    Pinyin,
    EnglishTerm,
}

#[derive(Clone, PartialEq, Eq)]
pub struct MixedInputSegment {
    kind: MixedInputSegmentKind,
    value: String,
}

impl MixedInputSegment {
    pub const fn kind(&self) -> MixedInputSegmentKind {
        self.kind
    }

    pub fn value(&self) -> &str {
        &self.value
    }
}

impl fmt::Debug for MixedInputSegment {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("MixedInputSegment")
            .field("kind", &self.kind)
            .field("value", &"<redacted>")
            .finish()
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct MixedInputSegmentation {
    segments: Vec<MixedInputSegment>,
}

impl MixedInputSegmentation {
    pub fn segments(&self) -> &[MixedInputSegment] {
        &self.segments
    }

    pub fn render_with<F>(&self, mut decode_pinyin: F) -> Option<String>
    where
        F: FnMut(&str) -> Option<String>,
    {
        let mut rendered = Vec::<RenderedSegment>::with_capacity(self.segments.len());
        for segment in &self.segments {
            let text = match segment.kind {
                MixedInputSegmentKind::Pinyin => decode_pinyin(&segment.value)?,
                MixedInputSegmentKind::EnglishTerm => segment.value.clone(),
            };
            if text.is_empty() {
                return None;
            }
            rendered.push(RenderedSegment {
                kind: segment.kind,
                text,
            });
        }

        let mut output = String::new();
        for (index, segment) in rendered.iter().enumerate() {
            if index > 0
                && (segment.kind == MixedInputSegmentKind::EnglishTerm
                    || rendered[index - 1].kind == MixedInputSegmentKind::EnglishTerm)
            {
                output.push(' ');
            }
            output.push_str(&segment.text);
        }
        Some(output)
    }
}

impl fmt::Debug for MixedInputSegmentation {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("MixedInputSegmentation")
            .field("segment_count", &self.segments.len())
            .field(
                "english_term_count",
                &self
                    .segments
                    .iter()
                    .filter(|segment| segment.kind == MixedInputSegmentKind::EnglishTerm)
                    .count(),
            )
            .finish()
    }
}

#[derive(Debug)]
struct RenderedSegment {
    kind: MixedInputSegmentKind,
    text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct EnglishTerm {
    match_key: String,
    display: String,
    priority: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnglishTermPreserver {
    terms: Vec<EnglishTerm>,
}

impl EnglishTermPreserver {
    pub fn embedded() -> Self {
        Self::from_tsv(ENGLISH_TERMS_TSV).unwrap_or_else(|_| Self { terms: Vec::new() })
    }

    pub fn from_tsv(contents: &str) -> Result<Self, EnglishTermDataError> {
        let mut lines = contents.lines().filter(|line| !line.trim().is_empty());
        if lines.next() != Some(ENGLISH_TERMS_HEADER) {
            return Err(EnglishTermDataError::InvalidHeader);
        }

        let mut terms = Vec::new();
        let mut keys = HashSet::new();
        for line in lines {
            let fields = line.split('\t').collect::<Vec<_>>();
            if fields.len() != 4
                || !is_match_key(fields[0])
                || !is_display_term(fields[1])
                || fields[3] != "first_party"
            {
                return Err(EnglishTermDataError::InvalidRow);
            }
            if !keys.insert(fields[0].to_owned()) {
                return Err(EnglishTermDataError::DuplicateKey);
            }
            terms.push(EnglishTerm {
                match_key: fields[0].to_owned(),
                display: fields[1].to_owned(),
                priority: fields[2]
                    .parse::<u16>()
                    .map_err(|_| EnglishTermDataError::InvalidRow)?,
            });
        }
        if terms.is_empty() {
            return Err(EnglishTermDataError::EmptyData);
        }
        terms.sort_by(|left, right| {
            right
                .match_key
                .len()
                .cmp(&left.match_key.len())
                .then_with(|| right.priority.cmp(&left.priority))
                .then_with(|| left.match_key.cmp(&right.match_key))
        });
        Ok(Self { terms })
    }

    pub fn segment(&self, raw_input: &str) -> Option<MixedInputSegmentation> {
        if raw_input.is_empty() || !raw_input.bytes().all(|byte| byte.is_ascii_alphabetic()) {
            return None;
        }
        let normalized = raw_input.to_ascii_lowercase();
        let mut cursor = 0;
        let mut segments = Vec::new();
        let mut english_terms = 0;

        while cursor < normalized.len() {
            let next = self.next_match(&normalized, cursor);
            let Some(term_match) = next else {
                push_pinyin_segment(&mut segments, &normalized[cursor..]);
                break;
            };
            if term_match.start > cursor {
                push_pinyin_segment(&mut segments, &normalized[cursor..term_match.start]);
            }
            segments.push(MixedInputSegment {
                kind: MixedInputSegmentKind::EnglishTerm,
                value: term_match.term.display.clone(),
            });
            english_terms += 1;
            cursor = term_match.end;
        }

        (english_terms > 0 && !segments.is_empty()).then_some(MixedInputSegmentation { segments })
    }

    fn next_match<'a>(&'a self, input: &str, cursor: usize) -> Option<TermMatch<'a>> {
        self.terms
            .iter()
            .filter_map(|term| {
                input[cursor..].find(&term.match_key).map(|relative_start| {
                    let start = cursor + relative_start;
                    TermMatch {
                        start,
                        end: start + term.match_key.len(),
                        term,
                    }
                })
            })
            .min_by(|left, right| {
                left.start
                    .cmp(&right.start)
                    .then_with(|| right.term.match_key.len().cmp(&left.term.match_key.len()))
                    .then_with(|| right.term.priority.cmp(&left.term.priority))
                    .then_with(|| left.term.match_key.cmp(&right.term.match_key))
            })
    }
}

impl Default for EnglishTermPreserver {
    fn default() -> Self {
        Self::embedded()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnglishTermDataError {
    InvalidHeader,
    InvalidRow,
    DuplicateKey,
    EmptyData,
}

#[derive(Debug)]
struct TermMatch<'a> {
    start: usize,
    end: usize,
    term: &'a EnglishTerm,
}

fn push_pinyin_segment(segments: &mut Vec<MixedInputSegment>, value: &str) {
    if !value.is_empty() {
        segments.push(MixedInputSegment {
            kind: MixedInputSegmentKind::Pinyin,
            value: value.to_owned(),
        });
    }
}

fn is_match_key(value: &str) -> bool {
    value.len() >= 2 && value.bytes().all(|byte| byte.is_ascii_lowercase())
}

fn is_display_term(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .chars()
            .any(|character| character.is_ascii_alphabetic())
        && value.chars().all(|character| {
            character.is_ascii_alphanumeric()
                || matches!(character, ' ' | '-' | '_' | '.' | '+' | '#')
        })
}
