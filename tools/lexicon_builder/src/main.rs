use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::lexicon::Lexicon;
use ime_core::syllable::is_legal_syllable;
use serde::Serialize;

const GENERATED_BY: &str = "private-pinyin-lexicon";
const DEFAULT_IMPORTED_FREQUENCY: u32 = 1000;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args = CliArgs::parse(env::args().skip(1).collect())?;
    match args.command {
        Command::BuildBase(build_args) => build_base_lexicon(build_args),
    }
}

fn build_base_lexicon(args: BuildBaseArgs) -> Result<(), String> {
    let input = read_source_text(args.source_format, &args.input)?;
    let char_frequencies = match &args.char_frequency_input {
        Some(path) => Some(parse_char_frequency_tsv(
            &fs::read_to_string(path).map_err(|_| "Could not read character frequency input")?,
        )?),
        None => None,
    };
    let mut entries = match args.source_format {
        SourceFormat::PrivatePinyinTsv => parse_private_pinyin_tsv(&input)?,
        SourceFormat::CcCedict => parse_cc_cedict(&input, args.default_frequency)?,
        SourceFormat::PinyinData => {
            parse_pinyin_data(&input, args.default_frequency, char_frequencies.as_ref())?
        }
        SourceFormat::PhrasePinyinData => parse_phrase_pinyin_data(&input, args.default_frequency)?,
        SourceFormat::AospRawdict => parse_aosp_rawdict(&input, args.frequency_scale)?,
    };

    if let Some(path) = &args.supplemental_pinyin_data {
        let supplemental_input = read_source_text(SourceFormat::PinyinData, path)?;
        entries.extend(parse_pinyin_data(
            &supplemental_input,
            args.default_frequency,
            char_frequencies.as_ref(),
        )?);
        entries = dedup_and_sort(entries);
    }

    if let Some(path) = &args.supplemental_phrase_pinyin_data {
        let supplemental_input = read_source_text(SourceFormat::PhrasePinyinData, path)?;
        entries.extend(parse_phrase_pinyin_data(
            &supplemental_input,
            args.default_frequency,
        )?);
        entries = dedup_and_sort(entries);
    }

    if entries.is_empty() {
        return Err("Input lexicon produced no supported entries".to_owned());
    }

    let tsv = render_base_tsv(&entries);
    Lexicon::from_tsv(&tsv)
        .map_err(|error| format!("Generated lexicon failed validation: {error}"))?;
    write_text(&args.output, &tsv)?;

    let manifest = BuildManifest {
        version: "1.0",
        generated_by: GENERATED_BY,
        generated_at_unix: current_unix_time(),
        release_approved: args.release_approved,
        source: ManifestSource {
            format: args.source_format.as_str(),
            name: args.source_name,
            url: args.source_url,
            license: args.source_license,
            version: args.source_version,
            local_input: args.input.display().to_string(),
            frequency_scale: (args.source_format == SourceFormat::AospRawdict)
                .then_some(args.frequency_scale),
            char_frequency_input: args
                .char_frequency_input
                .as_ref()
                .map(|path| path.display().to_string()),
            supplemental_pinyin_data: args
                .supplemental_pinyin_data
                .as_ref()
                .map(|path| path.display().to_string()),
            supplemental_phrase_pinyin_data: args
                .supplemental_phrase_pinyin_data
                .as_ref()
                .map(|path| path.display().to_string()),
        },
        outputs: vec![ManifestOutput {
            file: args.output.display().to_string(),
            kind: "base_lexicon",
            entry_count: entries.len(),
        }],
        notes: if args.release_approved {
            "Owner marked this source as approved for release packaging."
        } else {
            "Not approved for public release packaging; use for local validation only."
        },
    };
    let manifest_json = serde_json::to_string_pretty(&manifest)
        .map_err(|_| "Could not serialize lexicon manifest")?;
    write_text(&args.manifest, &(manifest_json + "\n"))?;

    Ok(())
}

#[derive(Debug)]
struct CliArgs {
    command: Command,
}

#[derive(Debug)]
enum Command {
    BuildBase(BuildBaseArgs),
}

#[derive(Debug)]
struct BuildBaseArgs {
    source_format: SourceFormat,
    input: PathBuf,
    output: PathBuf,
    manifest: PathBuf,
    source_name: String,
    source_url: String,
    source_license: String,
    source_version: String,
    default_frequency: u32,
    frequency_scale: f64,
    char_frequency_input: Option<PathBuf>,
    supplemental_pinyin_data: Option<PathBuf>,
    supplemental_phrase_pinyin_data: Option<PathBuf>,
    release_approved: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SourceFormat {
    PrivatePinyinTsv,
    CcCedict,
    PinyinData,
    PhrasePinyinData,
    AospRawdict,
}

impl SourceFormat {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "private-pinyin-tsv" => Ok(Self::PrivatePinyinTsv),
            "cc-cedict" => Ok(Self::CcCedict),
            "pinyin-data" => Ok(Self::PinyinData),
            "phrase-pinyin-data" => Ok(Self::PhrasePinyinData),
            "aosp-rawdict" => Ok(Self::AospRawdict),
            _ => Err("Unsupported --format; expected private-pinyin-tsv, cc-cedict, pinyin-data, phrase-pinyin-data, or aosp-rawdict".to_owned()),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::PrivatePinyinTsv => "private-pinyin-tsv",
            Self::CcCedict => "cc-cedict",
            Self::PinyinData => "pinyin-data",
            Self::PhrasePinyinData => "phrase-pinyin-data",
            Self::AospRawdict => "aosp-rawdict",
        }
    }
}

impl CliArgs {
    fn parse(args: Vec<String>) -> Result<Self, String> {
        let Some(command) = args.first() else {
            return Err(usage());
        };

        match command.as_str() {
            "build-base" => Ok(Self {
                command: Command::BuildBase(BuildBaseArgs::parse(&args[1..])?),
            }),
            _ => Err(usage()),
        }
    }
}

impl BuildBaseArgs {
    fn parse(args: &[String]) -> Result<Self, String> {
        let mut source_format = None;
        let mut input = None;
        let mut output = None;
        let mut manifest = None;
        let mut source_name = None;
        let mut source_url = None;
        let mut source_license = None;
        let mut source_version = None;
        let mut default_frequency = DEFAULT_IMPORTED_FREQUENCY;
        let mut frequency_scale = 1.0;
        let mut char_frequency_input = None;
        let mut supplemental_pinyin_data = None;
        let mut supplemental_phrase_pinyin_data = None;
        let mut release_approved = false;

        let mut index = 0;
        while index < args.len() {
            match args[index].as_str() {
                "--format" => {
                    source_format = Some(SourceFormat::parse(next_value(args, &mut index)?)?);
                }
                "--input" => input = Some(PathBuf::from(next_value(args, &mut index)?)),
                "--output" => output = Some(PathBuf::from(next_value(args, &mut index)?)),
                "--manifest" => manifest = Some(PathBuf::from(next_value(args, &mut index)?)),
                "--source-name" => source_name = Some(next_value(args, &mut index)?.to_owned()),
                "--source-url" => source_url = Some(next_value(args, &mut index)?.to_owned()),
                "--source-license" => {
                    source_license = Some(next_value(args, &mut index)?.to_owned())
                }
                "--source-version" => {
                    source_version = Some(next_value(args, &mut index)?.to_owned())
                }
                "--default-frequency" => {
                    default_frequency = next_value(args, &mut index)?
                        .parse::<u32>()
                        .map_err(|_| "--default-frequency must be a u32")?;
                }
                "--frequency-scale" => {
                    frequency_scale = next_value(args, &mut index)?
                        .parse::<f64>()
                        .map_err(|_| "--frequency-scale must be a finite positive number")?;
                    if !frequency_scale.is_finite() || frequency_scale <= 0.0 {
                        return Err("--frequency-scale must be a finite positive number".to_owned());
                    }
                }
                "--char-frequency-input" => {
                    char_frequency_input = Some(PathBuf::from(next_value(args, &mut index)?))
                }
                "--supplemental-pinyin-data" => {
                    supplemental_pinyin_data = Some(PathBuf::from(next_value(args, &mut index)?))
                }
                "--supplemental-phrase-pinyin-data" => {
                    supplemental_phrase_pinyin_data =
                        Some(PathBuf::from(next_value(args, &mut index)?))
                }
                "--release-approved" => release_approved = true,
                _ => return Err(usage()),
            }
            index += 1;
        }

        Ok(Self {
            source_format: source_format.ok_or_else(usage)?,
            input: input.ok_or_else(usage)?,
            output: output.ok_or_else(usage)?,
            manifest: manifest.ok_or_else(usage)?,
            source_name: source_name.ok_or_else(usage)?,
            source_url: source_url.unwrap_or_default(),
            source_license: source_license.ok_or_else(usage)?,
            source_version: source_version.unwrap_or_else(|| "unknown".to_owned()),
            default_frequency,
            frequency_scale,
            char_frequency_input,
            supplemental_pinyin_data,
            supplemental_phrase_pinyin_data,
            release_approved,
        })
    }
}

fn next_value<'a>(args: &'a [String], index: &mut usize) -> Result<&'a str, String> {
    *index += 1;
    args.get(*index)
        .map(String::as_str)
        .ok_or_else(|| "Missing value for argument".to_owned())
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct BaseLexiconEntry {
    phrase: String,
    pinyin: String,
    frequency: u32,
}

fn read_source_text(source_format: SourceFormat, path: &Path) -> Result<String, String> {
    let bytes = fs::read(path).map_err(|_| "Could not read input lexicon")?;
    if source_format == SourceFormat::AospRawdict {
        return decode_utf_text(&bytes);
    }
    String::from_utf8(bytes).map_err(|_| "Input lexicon must be UTF-8".to_owned())
}

fn decode_utf_text(bytes: &[u8]) -> Result<String, String> {
    if bytes.starts_with(&[0xff, 0xfe]) {
        return decode_utf16_bytes(&bytes[2..], true);
    }
    if bytes.starts_with(&[0xfe, 0xff]) {
        return decode_utf16_bytes(&bytes[2..], false);
    }
    if bytes.iter().take(256).filter(|byte| **byte == 0).count() > 16 {
        return decode_utf16_bytes(bytes, true);
    }
    String::from_utf8(bytes.to_vec())
        .map_err(|_| "Input lexicon must be UTF-8 or UTF-16".to_owned())
}

fn decode_utf16_bytes(bytes: &[u8], little_endian: bool) -> Result<String, String> {
    if !bytes.len().is_multiple_of(2) {
        return Err("UTF-16 input has an odd byte count".to_owned());
    }
    let units = bytes.chunks_exact(2).map(|chunk| {
        if little_endian {
            u16::from_le_bytes([chunk[0], chunk[1]])
        } else {
            u16::from_be_bytes([chunk[0], chunk[1]])
        }
    });
    std::char::decode_utf16(units)
        .map(|item| item.map_err(|_| "UTF-16 input contains invalid data".to_owned()))
        .collect::<Result<String, String>>()
}

fn parse_private_pinyin_tsv(input: &str) -> Result<Vec<BaseLexiconEntry>, String> {
    let mut entries = Vec::new();
    for (line_index, line) in input.lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        if line_index == 0 && line == "phrase\tpinyin\tfrequency" {
            continue;
        }

        let fields = line.split('\t').collect::<Vec<_>>();
        if fields.len() != 3 {
            return Err(format!(
                "Invalid TSV field count at line {}",
                line_index + 1
            ));
        }
        let frequency = fields[2]
            .parse::<u32>()
            .map_err(|_| format!("Invalid frequency at line {}", line_index + 1))?;
        let entry = BaseLexiconEntry {
            phrase: fields[0].to_owned(),
            pinyin: normalize_plain_pinyin(fields[1])
                .ok_or_else(|| format!("Invalid pinyin at line {}", line_index + 1))?,
            frequency,
        };
        validate_entry(&entry).map_err(|error| format!("{error} at line {}", line_index + 1))?;
        entries.push(entry);
    }
    Ok(dedup_and_sort(entries))
}

fn parse_pinyin_data(
    input: &str,
    default_frequency: u32,
    char_frequencies: Option<&BTreeMap<char, u32>>,
) -> Result<Vec<BaseLexiconEntry>, String> {
    let mut entries = Vec::new();
    for (line_index, line) in input.lines().enumerate() {
        let line = line
            .split_once('#')
            .map(|(head, _comment)| head)
            .unwrap_or(line)
            .trim();
        if line.is_empty() {
            continue;
        }

        let (codepoint, readings) = line
            .split_once(':')
            .ok_or_else(|| format!("Invalid pinyin-data line {}", line_index + 1))?;
        let codepoint = codepoint
            .trim()
            .strip_prefix("U+")
            .ok_or_else(|| format!("Invalid code point at line {}", line_index + 1))?;
        let scalar = u32::from_str_radix(codepoint, 16)
            .map_err(|_| format!("Invalid code point at line {}", line_index + 1))?;
        let Some(character) = char::from_u32(scalar) else {
            return Err(format!("Invalid Unicode scalar at line {}", line_index + 1));
        };
        let phrase = character.to_string();
        if !is_supported_han_phrase(&phrase) {
            continue;
        }

        let frequency = char_frequencies
            .and_then(|frequencies| frequencies.get(&character).copied())
            .unwrap_or(default_frequency);
        for reading in readings.split(',') {
            let Some(pinyin) = normalize_marked_pinyin(reading.trim()) else {
                continue;
            };
            let entry = BaseLexiconEntry {
                phrase: phrase.clone(),
                pinyin,
                frequency,
            };
            validate_entry(&entry)
                .map_err(|error| format!("{error} at line {}", line_index + 1))?;
            entries.push(entry);
        }
    }
    Ok(dedup_and_sort(entries))
}

fn parse_phrase_pinyin_data(
    input: &str,
    default_frequency: u32,
) -> Result<Vec<BaseLexiconEntry>, String> {
    let mut entries = Vec::new();
    for (line_index, line) in input.lines().enumerate() {
        let line = line
            .split_once('#')
            .map(|(head, _comment)| head)
            .unwrap_or(line)
            .trim();
        if line.is_empty() {
            continue;
        }

        let (phrase, reading) = line
            .split_once(':')
            .ok_or_else(|| format!("Invalid phrase-pinyin-data line {}", line_index + 1))?;
        let phrase = phrase.trim();
        if !is_supported_han_phrase(phrase) {
            continue;
        }
        let Some(pinyin) = normalize_marked_pinyin(reading.trim()) else {
            continue;
        };
        let entry = BaseLexiconEntry {
            phrase: phrase.to_owned(),
            pinyin,
            frequency: default_frequency,
        };
        validate_entry(&entry).map_err(|error| format!("{error} at line {}", line_index + 1))?;
        entries.push(entry);
    }
    Ok(dedup_and_sort(entries))
}

fn parse_aosp_rawdict(input: &str, frequency_scale: f64) -> Result<Vec<BaseLexiconEntry>, String> {
    let mut entries = Vec::new();
    for (line_index, line) in input.lines().enumerate() {
        let line = line.trim().trim_start_matches('\u{feff}');
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        let fields = line.split_whitespace().collect::<Vec<_>>();
        if fields.len() < 4 {
            return Err(format!(
                "Invalid AOSP rawdict field count at line {}",
                line_index + 1
            ));
        }
        if !is_supported_han_phrase(fields[0]) {
            continue;
        }
        let Some(pinyin) = normalize_plain_pinyin(&fields[3..].join(" ")) else {
            continue;
        };
        let entry = BaseLexiconEntry {
            phrase: fields[0].to_owned(),
            pinyin,
            frequency: scaled_frequency(fields[1], frequency_scale, line_index + 1)?,
        };
        validate_entry(&entry).map_err(|error| format!("{error} at line {}", line_index + 1))?;
        entries.push(entry);
    }
    Ok(dedup_and_sort(entries))
}

fn parse_char_frequency_tsv(input: &str) -> Result<BTreeMap<char, u32>, String> {
    let mut frequencies = BTreeMap::new();
    for (line_index, line) in input.lines().enumerate() {
        let line = line.trim();
        if line.is_empty()
            || line.starts_with('#')
            || (line_index == 0 && line.eq_ignore_ascii_case("character\tfrequency"))
        {
            continue;
        }

        let fields = line.split_whitespace().collect::<Vec<_>>();
        if fields.len() != 2 {
            return Err(format!(
                "Invalid character frequency field count at line {}",
                line_index + 1
            ));
        }
        let mut chars = fields[0].chars();
        let Some(character) = chars.next() else {
            return Err(format!("Invalid character at line {}", line_index + 1));
        };
        if chars.next().is_some() {
            return Err(format!("Expected one character at line {}", line_index + 1));
        }
        if !is_supported_han_phrase(fields[0]) {
            continue;
        }
        let frequency = fields[1]
            .parse::<u32>()
            .map_err(|_| format!("Invalid character frequency at line {}", line_index + 1))?;
        frequencies.insert(character, frequency);
    }
    Ok(frequencies)
}

fn parse_cc_cedict(input: &str, default_frequency: u32) -> Result<Vec<BaseLexiconEntry>, String> {
    let mut entries = Vec::new();
    for line in input.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((phrase, pinyin)) = parse_cc_cedict_line(line) else {
            continue;
        };
        if !is_supported_han_phrase(&phrase) {
            continue;
        }
        let entry = BaseLexiconEntry {
            phrase,
            pinyin,
            frequency: default_frequency,
        };
        validate_entry(&entry)?;
        entries.push(entry);
    }
    Ok(dedup_and_sort(entries))
}

fn parse_cc_cedict_line(line: &str) -> Option<(String, String)> {
    let bracket_start = line.find('[')?;
    let bracket_end = line[bracket_start..].find(']')? + bracket_start;
    let head = line[..bracket_start].trim();
    let mut head_fields = head.split_whitespace();
    let _traditional = head_fields.next()?;
    let simplified = head_fields.next()?;
    let pinyin = normalize_numbered_pinyin(&line[(bracket_start + 1)..bracket_end])?;
    Some((simplified.to_owned(), pinyin))
}

fn normalize_plain_pinyin(value: &str) -> Option<String> {
    let syllables = value
        .split_whitespace()
        .map(|syllable| syllable.to_lowercase().replace("u:", "ü"))
        .collect::<Vec<_>>();
    validate_pinyin_syllables(&syllables)
}

fn normalize_numbered_pinyin(value: &str) -> Option<String> {
    let mut syllables = Vec::new();
    for raw_syllable in value.split_whitespace() {
        if raw_syllable == "," || raw_syllable == "·" {
            return None;
        }
        let normalized = raw_syllable
            .to_lowercase()
            .replace("u:", "ü")
            .chars()
            .filter(|ch| !ch.is_ascii_digit())
            .collect::<String>();
        syllables.push(normalized);
    }
    validate_pinyin_syllables(&syllables)
}

fn normalize_marked_pinyin(value: &str) -> Option<String> {
    let mut syllables = Vec::new();
    for raw_syllable in value.split_whitespace() {
        let mut normalized = String::new();
        for ch in raw_syllable.chars() {
            if ch.is_ascii_digit() || matches!(ch, '\u{0300}'..='\u{036f}') {
                continue;
            }
            if let Some(replacement) = tone_mark_to_plain(ch) {
                normalized.push_str(replacement);
            } else if ch.is_ascii_alphabetic() {
                normalized.push(ch.to_ascii_lowercase());
            } else if ch == 'ü' || ch == 'Ü' {
                normalized.push('ü');
            } else if ch == ':' && normalized.ends_with('u') {
                normalized.pop();
                normalized.push('ü');
            } else {
                return None;
            }
        }
        syllables.push(normalized.replace('v', "ü"));
    }
    validate_pinyin_syllables(&syllables)
}

fn tone_mark_to_plain(ch: char) -> Option<&'static str> {
    match ch {
        'ā' | 'á' | 'ǎ' | 'à' | 'Ā' | 'Á' | 'Ǎ' | 'À' => Some("a"),
        'ē' | 'é' | 'ě' | 'è' | 'Ē' | 'É' | 'Ě' | 'È' => Some("e"),
        'ī' | 'í' | 'ǐ' | 'ì' | 'Ī' | 'Í' | 'Ǐ' | 'Ì' => Some("i"),
        'ō' | 'ó' | 'ǒ' | 'ò' | 'Ō' | 'Ó' | 'Ǒ' | 'Ò' => Some("o"),
        'ū' | 'ú' | 'ǔ' | 'ù' | 'Ū' | 'Ú' | 'Ǔ' | 'Ù' => Some("u"),
        'ǖ' | 'ǘ' | 'ǚ' | 'ǜ' | 'Ǖ' | 'Ǘ' | 'Ǚ' | 'Ǜ' => Some("ü"),
        'ń' | 'ň' | 'ǹ' | 'Ń' | 'Ň' | 'Ǹ' => Some("n"),
        'ḿ' | 'Ḿ' => Some("m"),
        'ê' | 'ế' | 'ề' | 'Ê' | 'Ế' | 'Ề' => Some("e"),
        _ => None,
    }
}

fn scaled_frequency(raw_frequency: &str, scale: f64, line_number: usize) -> Result<u32, String> {
    let frequency = raw_frequency
        .parse::<f64>()
        .map_err(|_| format!("Invalid AOSP frequency at line {line_number}"))?;
    if !frequency.is_finite() || frequency <= 0.0 {
        return Err(format!("Invalid AOSP frequency at line {line_number}"));
    }
    let scaled = (frequency * scale).round();
    if scaled <= 0.0 {
        return Ok(1);
    }
    if scaled >= u32::MAX as f64 {
        return Ok(u32::MAX);
    }
    Ok(scaled as u32)
}

fn validate_pinyin_syllables(syllables: &[String]) -> Option<String> {
    if syllables.is_empty()
        || syllables
            .iter()
            .any(|syllable| syllable.is_empty() || !is_legal_syllable(syllable))
    {
        return None;
    }
    Some(syllables.join(" "))
}

fn validate_entry(entry: &BaseLexiconEntry) -> Result<(), String> {
    if entry.phrase.trim().is_empty() || entry.phrase.contains('\t') || entry.phrase.contains('\n')
    {
        return Err("Invalid phrase".to_owned());
    }
    if entry.frequency == 0 {
        return Err("Frequency must be greater than zero".to_owned());
    }
    normalize_plain_pinyin(&entry.pinyin)
        .map(|_| ())
        .ok_or_else(|| "Invalid pinyin".to_owned())
}

fn is_supported_han_phrase(phrase: &str) -> bool {
    !phrase.is_empty()
        && phrase.chars().all(|ch| {
            let codepoint = ch as u32;
            codepoint == 0x3007
                || (0x3400..=0x9fff).contains(&codepoint)
                || (0xf900..=0xfaff).contains(&codepoint)
                || (0x20000..=0x2a6df).contains(&codepoint)
                || (0x2a700..=0x2b73f).contains(&codepoint)
                || (0x2b740..=0x2b81f).contains(&codepoint)
                || (0x2b820..=0x2ceaf).contains(&codepoint)
                || (0x2ceb0..=0x2ebef).contains(&codepoint)
                || (0x30000..=0x323af).contains(&codepoint)
        })
}

fn dedup_and_sort(entries: Vec<BaseLexiconEntry>) -> Vec<BaseLexiconEntry> {
    let mut deduped = BTreeMap::<(String, String), u32>::new();
    for entry in entries {
        deduped
            .entry((entry.phrase, entry.pinyin))
            .and_modify(|frequency| *frequency = (*frequency).max(entry.frequency))
            .or_insert(entry.frequency);
    }

    let mut entries = deduped
        .into_iter()
        .map(|((phrase, pinyin), frequency)| BaseLexiconEntry {
            phrase,
            pinyin,
            frequency,
        })
        .collect::<Vec<_>>();
    entries.sort_by(|left, right| {
        right
            .frequency
            .cmp(&left.frequency)
            .then_with(|| left.pinyin.cmp(&right.pinyin))
            .then_with(|| left.phrase.cmp(&right.phrase))
    });
    entries
}

fn render_base_tsv(entries: &[BaseLexiconEntry]) -> String {
    let mut output = String::from("phrase\tpinyin\tfrequency\n");
    for entry in entries {
        output.push_str(&entry.phrase);
        output.push('\t');
        output.push_str(&entry.pinyin);
        output.push('\t');
        output.push_str(&entry.frequency.to_string());
        output.push('\n');
    }
    output
}

fn write_text(path: &Path, contents: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|_| "Could not create output directory")?;
    }
    fs::write(path, contents).map_err(|_| "Could not write output file".to_owned())
}

fn current_unix_time() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or_default()
}

fn usage() -> String {
    "Usage: private-pinyin-lexicon build-base --format <private-pinyin-tsv|cc-cedict|pinyin-data|phrase-pinyin-data|aosp-rawdict> --input <path> --output <path> --manifest <path> --source-name <name> --source-license <license> [--source-url <url>] [--source-version <version>] [--default-frequency <u32>] [--frequency-scale <number>] [--char-frequency-input <path>] [--supplemental-pinyin-data <path>] [--supplemental-phrase-pinyin-data <path>] [--release-approved]".to_owned()
}

#[derive(Serialize)]
struct BuildManifest<'a> {
    version: &'a str,
    generated_by: &'a str,
    generated_at_unix: u64,
    release_approved: bool,
    source: ManifestSource,
    outputs: Vec<ManifestOutput>,
    notes: &'a str,
}

#[derive(Serialize)]
struct ManifestSource {
    format: &'static str,
    name: String,
    url: String,
    license: String,
    version: String,
    local_input: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    frequency_scale: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    char_frequency_input: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    supplemental_pinyin_data: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    supplemental_phrase_pinyin_data: Option<String>,
}

#[derive(Serialize)]
struct ManifestOutput {
    file: String,
    kind: &'static str,
    entry_count: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_tsv_import_sorts_and_deduplicates() {
        let entries = parse_private_pinyin_tsv(
            "phrase\tpinyin\tfrequency\n你好\tni hao\t1\n你好\tni hao\t9\n中国\tzhong guo\t5\n",
        )
        .expect("private TSV imports");

        assert_eq!(
            entries,
            vec![
                BaseLexiconEntry {
                    phrase: "你好".to_owned(),
                    pinyin: "ni hao".to_owned(),
                    frequency: 9,
                },
                BaseLexiconEntry {
                    phrase: "中国".to_owned(),
                    pinyin: "zhong guo".to_owned(),
                    frequency: 5,
                },
            ]
        );
    }

    #[test]
    fn cc_cedict_import_strips_tones_and_prefers_simplified_phrase() {
        let entries = parse_cc_cedict(
            "中國 中国 [Zhong1 guo2] /China/\n女兒 女儿 [nu:3 er2] /daughter/\n",
            7,
        )
        .expect("CC-CEDICT imports");

        assert_eq!(
            entries,
            vec![
                BaseLexiconEntry {
                    phrase: "女儿".to_owned(),
                    pinyin: "nü er".to_owned(),
                    frequency: 7,
                },
                BaseLexiconEntry {
                    phrase: "中国".to_owned(),
                    pinyin: "zhong guo".to_owned(),
                    frequency: 7,
                },
            ]
        );
    }

    #[test]
    fn phrase_pinyin_data_imports_marked_multi_character_readings() {
        let entries =
            parse_phrase_pinyin_data("# version: test\n头发: tóu fà\n面条: miàn tiáo\n", 25)
                .expect("phrase pinyin data imports");

        assert!(entries.iter().any(|entry| {
            entry.phrase == "头发" && entry.pinyin == "tou fa" && entry.frequency == 25
        }));
        assert!(entries.iter().any(|entry| {
            entry.phrase == "面条" && entry.pinyin == "mian tiao" && entry.frequency == 25
        }));
    }

    #[test]
    fn cc_cedict_import_skips_entries_with_punctuation_pinyin() {
        let entries =
            parse_cc_cedict("人為財死，鳥為食亡 人为财死，鸟为食亡 [ren2 wei4 cai2 si3 , niao3 wei4 shi2 wang2] /proverb/\n", 7)
                .expect("CC-CEDICT imports");

        assert!(entries.is_empty());
    }

    #[test]
    fn pinyin_data_imports_marked_multi_reading_characters() {
        let frequencies = parse_char_frequency_tsv("character\tfrequency\n行\t42\n")
            .expect("character frequencies import");
        let entries = parse_pinyin_data(
            "U+884C: xíng,háng  # 行\nU+0041: ēi # A\n",
            7,
            Some(&frequencies),
        )
        .expect("pinyin-data imports");

        assert_eq!(
            entries,
            vec![
                BaseLexiconEntry {
                    phrase: "行".to_owned(),
                    pinyin: "hang".to_owned(),
                    frequency: 42,
                },
                BaseLexiconEntry {
                    phrase: "行".to_owned(),
                    pinyin: "xing".to_owned(),
                    frequency: 42,
                },
            ]
        );
    }

    #[test]
    fn aosp_rawdict_imports_phrases_and_scales_float_frequency() {
        let entries = parse_aosp_rawdict("干嘛 17002.7639686 0 gan ma\nabc 9 0 a b c\n", 10.0)
            .expect("AOSP rawdict imports");

        assert_eq!(
            entries,
            vec![BaseLexiconEntry {
                phrase: "干嘛".to_owned(),
                pinyin: "gan ma".to_owned(),
                frequency: 170028,
            }]
        );
    }

    #[test]
    fn aosp_rawdict_input_can_be_utf16() {
        let mut bytes = vec![0xff, 0xfe];
        for unit in "什么 12.5 0 shen me\n".encode_utf16() {
            bytes.extend_from_slice(&unit.to_le_bytes());
        }

        let decoded = decode_utf_text(&bytes).expect("UTF-16 rawdict decodes");
        let entries = parse_aosp_rawdict(&decoded, 1.0).expect("AOSP rawdict imports");

        assert_eq!(
            entries,
            vec![BaseLexiconEntry {
                phrase: "什么".to_owned(),
                pinyin: "shen me".to_owned(),
                frequency: 13,
            }]
        );
    }
}
