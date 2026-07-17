use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::Path;

use ime_core::{Candidate, CandidateSource, ImeEngine};
use private_pinyin_local_ai_core::{EnglishTermPreserver, PinyinCorrector};
use serde::Serialize;

const EXPECTED_HEADER: &str =
    "id\tfeature\tinput_kind\tinput\texpected_texts\tmax_rank\tgate\tprovenance";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum InputKind {
    RawPinyin,
    NineKey,
}

impl InputKind {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "raw_pinyin" => Ok(Self::RawPinyin),
            "nine_key" => Ok(Self::NineKey),
            _ => Err(format!(
                "unsupported input_kind {value:?}; expected raw_pinyin or nine_key"
            )),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EvaluationGate {
    Required,
    Observe,
}

impl EvaluationGate {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "required" => Ok(Self::Required),
            "observe" => Ok(Self::Observe),
            _ => Err(format!(
                "unsupported gate {value:?}; expected required or observe"
            )),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CaseProvenance {
    ProjectRegression,
    Synthetic,
}

impl CaseProvenance {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "project_regression" => Ok(Self::ProjectRegression),
            "synthetic" => Ok(Self::Synthetic),
            _ => Err(format!(
                "unsupported provenance {value:?}; AI evaluation data must be project_regression or synthetic"
            )),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct EvaluationCase {
    pub id: String,
    pub feature: String,
    pub input_kind: InputKind,
    pub input: String,
    pub expected_texts: Vec<String>,
    pub max_rank: usize,
    pub gate: EvaluationGate,
    pub provenance: CaseProvenance,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CaseResult {
    pub id: String,
    pub feature: String,
    pub gate: EvaluationGate,
    pub expected_texts: Vec<String>,
    pub rank: Option<usize>,
    pub within_target_rank: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct FeatureMetrics {
    pub cases: usize,
    pub found: usize,
    pub top_1: usize,
    pub within_target_rank: usize,
    pub mean_reciprocal_rank: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct EvaluationReport {
    pub dataset: String,
    pub total_cases: usize,
    pub required_cases: usize,
    pub required_failures: usize,
    pub observed_cases: usize,
    pub observed_successes: usize,
    pub overall: FeatureMetrics,
    pub by_feature: BTreeMap<String, FeatureMetrics>,
    pub results: Vec<CaseResult>,
}

impl EvaluationReport {
    pub fn has_required_failures(&self) -> bool {
        self.required_failures > 0
    }
}

pub fn load_cases(path: impl AsRef<Path>) -> Result<Vec<EvaluationCase>, String> {
    let path = path.as_ref();
    let contents = fs::read_to_string(path)
        .map_err(|error| format!("could not read {}: {error}", path.display()))?;
    parse_cases(&contents)
}

pub fn parse_cases(contents: &str) -> Result<Vec<EvaluationCase>, String> {
    let mut lines = contents
        .lines()
        .enumerate()
        .filter(|(_, line)| !line.trim().is_empty() && !line.trim_start().starts_with('#'));

    let Some((header_index, header)) = lines.next() else {
        return Err("evaluation dataset is empty".to_owned());
    };
    if header != EXPECTED_HEADER {
        return Err(format!(
            "line {} has an unexpected header; expected {EXPECTED_HEADER:?}",
            header_index + 1
        ));
    }

    let mut cases = Vec::new();
    let mut ids = HashSet::new();
    for (line_index, line) in lines {
        let fields = line.split('\t').collect::<Vec<_>>();
        if fields.len() != 8 {
            return Err(format!(
                "line {} must contain exactly 8 tab-separated fields",
                line_index + 1
            ));
        }

        let id = required_field(fields[0], line_index, "id")?;
        if !ids.insert(id.to_owned()) {
            return Err(format!("line {} repeats id {id:?}", line_index + 1));
        }
        let feature = required_field(fields[1], line_index, "feature")?;
        if !feature
            .chars()
            .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_')
        {
            return Err(format!(
                "line {} feature must use lowercase ASCII snake_case",
                line_index + 1
            ));
        }

        let input_kind = InputKind::parse(fields[2])?;
        let input = required_field(fields[3], line_index, "input")?;
        let expected_texts = fields[4]
            .split('|')
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .collect::<Vec<_>>();
        if expected_texts.is_empty() {
            return Err(format!(
                "line {} expected_texts must contain at least one value",
                line_index + 1
            ));
        }
        let max_rank = fields[5].parse::<usize>().map_err(|_| {
            format!(
                "line {} max_rank must be a positive integer",
                line_index + 1
            )
        })?;
        if max_rank == 0 {
            return Err(format!(
                "line {} max_rank must be greater than zero",
                line_index + 1
            ));
        }

        cases.push(EvaluationCase {
            id: id.to_owned(),
            feature: feature.to_owned(),
            input_kind,
            input: input.to_owned(),
            expected_texts,
            max_rank,
            gate: EvaluationGate::parse(fields[6])?,
            provenance: CaseProvenance::parse(fields[7])?,
        });
    }

    if cases.is_empty() {
        return Err("evaluation dataset contains no cases".to_owned());
    }
    Ok(cases)
}

pub fn evaluate(
    engine: &ImeEngine,
    dataset_name: impl Into<String>,
    cases: &[EvaluationCase],
) -> EvaluationReport {
    let results = cases
        .iter()
        .map(|case| {
            let candidates = candidates_for_case(engine, case);
            evaluate_candidates(case, &candidates)
        })
        .collect::<Vec<_>>();
    build_report(dataset_name.into(), cases, results)
}

pub fn evaluate_with_rules(
    engine: &ImeEngine,
    dataset_name: impl Into<String>,
    cases: &[EvaluationCase],
) -> EvaluationReport {
    let corrector = PinyinCorrector::embedded();
    let term_preserver = EnglishTermPreserver::embedded();
    let results = cases
        .iter()
        .map(|case| {
            let candidates =
                candidates_for_case_with_rules(engine, case, &corrector, &term_preserver);
            evaluate_candidates(case, &candidates)
        })
        .collect::<Vec<_>>();
    build_report(dataset_name.into(), cases, results)
}

pub fn candidates_for_case(engine: &ImeEngine, case: &EvaluationCase) -> Vec<Candidate> {
    match case.input_kind {
        InputKind::RawPinyin => engine.candidates_for_raw(&case.input),
        InputKind::NineKey => engine.candidates_for_nine_key(&case.input),
    }
}

fn candidates_for_case_with_rules(
    engine: &ImeEngine,
    case: &EvaluationCase,
    corrector: &PinyinCorrector,
    term_preserver: &EnglishTermPreserver,
) -> Vec<Candidate> {
    match case.feature.as_str() {
        "pinyin_correction" if case.input_kind == InputKind::RawPinyin => {
            let suggestions = corrector.suggest_with_validator(&case.input, |corrected| {
                !engine.candidates_for_raw(corrected).is_empty()
            });
            let mut candidates = Vec::new();
            for suggestion in suggestions {
                if let Some(candidate) = engine
                    .candidates_for_raw(suggestion.corrected_pinyin())
                    .into_iter()
                    .next()
                {
                    push_unique_candidate(&mut candidates, candidate);
                }
            }
            for candidate in candidates_for_case(engine, case) {
                push_unique_candidate(&mut candidates, candidate);
            }
            candidates
        }
        "mixed_english" if case.input_kind == InputKind::RawPinyin => {
            let mut candidates = Vec::new();
            if let Some(text) = term_preserver
                .segment(&case.input)
                .and_then(|segmentation| {
                    segmentation.render_with(|pinyin| {
                        engine
                            .candidates_for_raw(pinyin)
                            .first()
                            .map(|candidate| candidate.text.clone())
                    })
                })
            {
                candidates.push(Candidate::new(text, &case.input, CandidateSource::Raw));
            }
            for candidate in candidates_for_case(engine, case) {
                push_unique_candidate(&mut candidates, candidate);
            }
            candidates
        }
        _ => candidates_for_case(engine, case),
    }
}

fn push_unique_candidate(candidates: &mut Vec<Candidate>, candidate: Candidate) {
    if !candidates
        .iter()
        .any(|existing| existing.text == candidate.text)
    {
        candidates.push(candidate);
    }
}

pub fn evaluate_candidates(case: &EvaluationCase, candidates: &[Candidate]) -> CaseResult {
    let rank = candidates
        .iter()
        .position(|candidate| {
            case.expected_texts
                .iter()
                .any(|expected| expected == &candidate.text)
        })
        .map(|index| index + 1);
    CaseResult {
        id: case.id.clone(),
        feature: case.feature.clone(),
        gate: case.gate,
        expected_texts: case.expected_texts.clone(),
        rank,
        within_target_rank: rank.is_some_and(|rank| rank <= case.max_rank),
    }
}

fn build_report(
    dataset: String,
    cases: &[EvaluationCase],
    results: Vec<CaseResult>,
) -> EvaluationReport {
    let mut overall_accumulator = MetricsAccumulator::default();
    let mut feature_accumulators = BTreeMap::<String, MetricsAccumulator>::new();

    for result in &results {
        overall_accumulator.record(result);
        feature_accumulators
            .entry(result.feature.clone())
            .or_default()
            .record(result);
    }

    let required_cases = cases
        .iter()
        .filter(|case| case.gate == EvaluationGate::Required)
        .count();
    let observed_cases = cases.len() - required_cases;
    let required_failures = results
        .iter()
        .filter(|result| result.gate == EvaluationGate::Required && !result.within_target_rank)
        .count();
    let observed_successes = results
        .iter()
        .filter(|result| result.gate == EvaluationGate::Observe && result.within_target_rank)
        .count();

    EvaluationReport {
        dataset,
        total_cases: cases.len(),
        required_cases,
        required_failures,
        observed_cases,
        observed_successes,
        overall: overall_accumulator.finish(),
        by_feature: feature_accumulators
            .into_iter()
            .map(|(feature, accumulator)| (feature, accumulator.finish()))
            .collect(),
        results,
    }
}

fn required_field<'a>(value: &'a str, line_index: usize, name: &str) -> Result<&'a str, String> {
    if value.is_empty() {
        Err(format!("line {} {name} must not be empty", line_index + 1))
    } else {
        Ok(value)
    }
}

#[derive(Debug, Default)]
struct MetricsAccumulator {
    cases: usize,
    found: usize,
    top_1: usize,
    within_target_rank: usize,
    reciprocal_rank_sum: f64,
}

impl MetricsAccumulator {
    fn record(&mut self, result: &CaseResult) {
        self.cases += 1;
        if let Some(rank) = result.rank {
            self.found += 1;
            self.top_1 += usize::from(rank == 1);
            self.reciprocal_rank_sum += 1.0 / rank as f64;
        }
        self.within_target_rank += usize::from(result.within_target_rank);
    }

    fn finish(self) -> FeatureMetrics {
        FeatureMetrics {
            cases: self.cases,
            found: self.found,
            top_1: self.top_1,
            within_target_rank: self.within_target_rank,
            mean_reciprocal_rank: if self.cases == 0 {
                0.0
            } else {
                self.reciprocal_rank_sum / self.cases as f64
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use ime_core::{Candidate, CandidateSource, ImeEngine};

    use super::{
        build_report, evaluate_candidates, evaluate_with_rules, parse_cases, CaseProvenance,
        CaseResult, EvaluationGate, InputKind,
    };

    const HEADER: &str =
        "id\tfeature\tinput_kind\tinput\texpected_texts\tmax_rank\tgate\tprovenance";

    #[test]
    fn parses_first_party_evaluation_cases() {
        let contents = format!(
            "{HEADER}\nnormal_nihao\tcore\traw_pinyin\tnihao\t你好\t1\trequired\tproject_regression\n"
        );
        let cases = parse_cases(&contents).expect("dataset parses");

        assert_eq!(cases.len(), 1);
        assert_eq!(cases[0].input_kind, InputKind::RawPinyin);
        assert_eq!(cases[0].gate, EvaluationGate::Required);
        assert_eq!(cases[0].provenance, CaseProvenance::ProjectRegression);
    }

    #[test]
    fn rejects_unapproved_or_user_data_provenance() {
        let contents = format!(
            "{HEADER}\nprivate_case\tcore\traw_pinyin\tnihao\t你好\t1\tobserve\tuser_export\n"
        );
        let error = parse_cases(&contents).expect_err("user provenance is rejected");

        assert!(error.contains("must be project_regression or synthetic"));
    }

    #[test]
    fn rejects_duplicate_case_ids() {
        let contents = format!(
            "{HEADER}\nsame\tcore\traw_pinyin\tnihao\t你好\t1\trequired\tsynthetic\nsame\tcore\traw_pinyin\tzhongguo\t中国\t1\trequired\tsynthetic\n"
        );

        assert!(parse_cases(&contents)
            .expect_err("duplicate ids fail")
            .contains("repeats id"));
    }

    #[test]
    fn candidate_evaluation_tracks_rank_without_exposing_other_candidates() {
        let contents = format!(
            "{HEADER}\nnormal_nihao\tcore\traw_pinyin\tnihao\t你好|你好啊\t2\trequired\tsynthetic\n"
        );
        let case = parse_cases(&contents).expect("dataset parses").remove(0);
        let candidates = vec![
            Candidate::new("你号", "ni hao", CandidateSource::Base),
            Candidate::new("你好", "ni hao", CandidateSource::Base),
        ];
        let result = evaluate_candidates(&case, &candidates);

        assert_eq!(result.rank, Some(2));
        assert!(result.within_target_rank);
    }

    #[test]
    fn report_separates_required_failures_from_observed_opportunities() {
        let contents = format!(
            "{HEADER}\nrequired_pass\tcore\traw_pinyin\tnihao\t你好\t1\trequired\tsynthetic\nrequired_miss\tcore\traw_pinyin\tganma\t干嘛\t1\trequired\tsynthetic\nobserved_pass\tcorrection\traw_pinyin\tnhao\t你好\t2\tobserve\tsynthetic\n"
        );
        let cases = parse_cases(&contents).expect("dataset parses");
        let results = vec![
            CaseResult {
                id: "required_pass".to_owned(),
                feature: "core".to_owned(),
                gate: EvaluationGate::Required,
                expected_texts: vec!["你好".to_owned()],
                rank: Some(1),
                within_target_rank: true,
            },
            CaseResult {
                id: "required_miss".to_owned(),
                feature: "core".to_owned(),
                gate: EvaluationGate::Required,
                expected_texts: vec!["干嘛".to_owned()],
                rank: None,
                within_target_rank: false,
            },
            CaseResult {
                id: "observed_pass".to_owned(),
                feature: "correction".to_owned(),
                gate: EvaluationGate::Observe,
                expected_texts: vec!["你好".to_owned()],
                rank: Some(2),
                within_target_rank: true,
            },
        ];

        let report = build_report("unit-test".to_owned(), &cases, results);

        assert_eq!(report.required_cases, 2);
        assert_eq!(report.required_failures, 1);
        assert_eq!(report.observed_cases, 1);
        assert_eq!(report.observed_successes, 1);
        assert_eq!(report.overall.top_1, 1);
        assert_eq!(report.overall.found, 2);
        assert_eq!(report.overall.within_target_rank, 2);
        assert!((report.overall.mean_reciprocal_rank - 0.5).abs() < f64::EPSILON);
    }

    #[test]
    fn rules_first_evaluation_improves_p0_cases_without_required_regression() {
        let cases = parse_cases(include_str!("../../../ai/eval/baseline_cases.tsv"))
            .expect("baseline dataset parses");
        let engine = ImeEngine::new().expect("embedded engine");
        let report = evaluate_with_rules(&engine, "ai-04-unit", &cases);

        assert_eq!(report.required_failures, 0);
        assert_eq!(report.observed_successes, report.observed_cases);
        assert_eq!(report.observed_cases, 7);
    }
}
