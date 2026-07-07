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
    let input = fs::read_to_string(&args.input).map_err(|_| "Could not read input lexicon")?;
    let entries = match args.source_format {
        SourceFormat::PrivatePinyinTsv => parse_private_pinyin_tsv(&input)?,
        SourceFormat::CcCedict => parse_cc_cedict(&input, args.default_frequency)?,
    };

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
    release_approved: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SourceFormat {
    PrivatePinyinTsv,
    CcCedict,
}

impl SourceFormat {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "private-pinyin-tsv" => Ok(Self::PrivatePinyinTsv),
            "cc-cedict" => Ok(Self::CcCedict),
            _ => Err("Unsupported --format; expected private-pinyin-tsv or cc-cedict".to_owned()),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::PrivatePinyinTsv => "private-pinyin-tsv",
            Self::CcCedict => "cc-cedict",
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
            (0x3400..=0x9fff).contains(&codepoint) || (0xf900..=0xfaff).contains(&codepoint)
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
    "Usage: private-pinyin-lexicon build-base --format <private-pinyin-tsv|cc-cedict> --input <path> --output <path> --manifest <path> --source-name <name> --source-license <license> [--source-url <url>] [--source-version <version>] [--default-frequency <u32>] [--release-approved]".to_owned()
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
    fn cc_cedict_import_skips_entries_with_punctuation_pinyin() {
        let entries =
            parse_cc_cedict("人為財死，鳥為食亡 人为财死，鸟为食亡 [ren2 wei4 cai2 si3 , niao3 wei4 shi2 wang2] /proverb/\n", 7)
                .expect("CC-CEDICT imports");

        assert!(entries.is_empty());
    }
}
