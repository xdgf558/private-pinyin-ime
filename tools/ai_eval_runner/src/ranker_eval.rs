use std::collections::HashSet;
use std::fs;
use std::path::Path;

use private_pinyin_local_ai_core::{
    AiBudget, AiCandidateInput, AiCandidateSetHash, AiCompositionRevision, AiFeature,
    AiFeaturePolicy, AiLiteCandidateFeatures, AiLiteRanker, AiRequestBuilder, AiRequestId,
    AiRequestIdentity, AiSessionId, HardwareProfile, HardwareTier, LocalAiProvider, ModelManifest,
    ModelPackageVerifier, ModelPlatform, PrivacyGuard,
};
use serde::{Deserialize, Serialize};

const RANKER_DATASET_SCHEMA_VERSION: u32 = 1;
const MAX_RANKER_CASES: usize = 128;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RankerGate {
    Improve,
    Preserve,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
struct RankerDataset {
    schema_version: u32,
    dataset_id: String,
    provenance: Vec<String>,
    contains_user_data: bool,
    contains_real_application_context: bool,
    contains_prompts_or_model_outputs: bool,
    network_required: bool,
    cases: Vec<RankerCase>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
struct RankerCase {
    id: String,
    gate: RankerGate,
    expected_text: String,
    candidates: Vec<RankerCandidate>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
struct RankerCandidate {
    text: String,
    pinyin: String,
    base_rank: usize,
    base_score: i64,
    features: RankerFeatures,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
struct RankerFeatures {
    frequency: u16,
    segmentation: u16,
    bigram: u16,
    trigram: u16,
    typo_correction: u16,
    term_preservation: u16,
}

impl RankerFeatures {
    fn into_core(self) -> Result<AiLiteCandidateFeatures, String> {
        AiLiteCandidateFeatures::new(
            self.frequency,
            self.segmentation,
            self.bigram,
            self.trigram,
            self.typo_correction,
            self.term_preservation,
        )
        .map_err(|error| format!("ranker feature is outside its approved range: {error}"))
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize)]
pub struct RankerMetrics {
    pub cases: usize,
    pub found: usize,
    pub top_1: usize,
    pub mean_reciprocal_rank: f64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RankerCaseResult {
    pub id: String,
    pub gate: RankerGate,
    pub baseline_rank: usize,
    pub ranker_rank: Option<usize>,
    pub improved: bool,
    pub regressed: bool,
    pub gate_passed: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RankerEvaluationReport {
    pub dataset: String,
    pub model_id: String,
    pub model_version: String,
    pub total_cases: usize,
    pub improved_cases: usize,
    pub regressed_cases: usize,
    pub gate_failures: usize,
    pub maximum_inference_micros: u128,
    pub mean_inference_micros: f64,
    pub baseline: RankerMetrics,
    pub ranker: RankerMetrics,
    pub results: Vec<RankerCaseResult>,
}

impl RankerEvaluationReport {
    pub fn passes(&self, required_improvements: usize) -> bool {
        self.improved_cases >= required_improvements
            && self.regressed_cases == 0
            && self.gate_failures == 0
            && self.ranker.top_1 > self.baseline.top_1
            && self.ranker.mean_reciprocal_rank > self.baseline.mean_reciprocal_rank
    }
}

pub fn load_ranker_cases(path: impl AsRef<Path>) -> Result<usize, String> {
    load_ranker_dataset(path.as_ref()).map(|dataset| dataset.cases.len())
}

pub fn evaluate_ranker_package(
    package_root: impl AsRef<Path>,
    dataset_path: impl AsRef<Path>,
) -> Result<RankerEvaluationReport, String> {
    let package_root = package_root.as_ref();
    let dataset_path = dataset_path.as_ref();
    let manifest_json = fs::read_to_string(package_root.join("manifest.json"))
        .map_err(|error| format!("could not read ranker manifest: {error}"))?;
    let manifest = ModelManifest::from_json(&manifest_json)
        .map_err(|error| format!("could not parse ranker manifest: {error}"))?;
    let verified = ModelPackageVerifier::new(
        ModelPlatform::Macos,
        HardwareProfile::from_memory_gib(16, false),
    )
    .map_err(|error| format!("could not initialize model verifier: {error}"))?
    .verify(package_root, &manifest)
    .map_err(|error| format!("could not verify ranker package: {error}"))?;
    let ranker = AiLiteRanker::from_verified_package(&verified)
        .map_err(|error| format!("could not load ranker: {error}"))?;
    let dataset = load_ranker_dataset(dataset_path)?;

    let mut baseline_accumulator = RankerMetricsAccumulator::default();
    let mut ranker_accumulator = RankerMetricsAccumulator::default();
    let mut results = Vec::with_capacity(dataset.cases.len());
    let mut maximum_inference_micros = 0_u128;
    let mut total_inference_nanos = 0_u128;
    for (case_index, case) in dataset.cases.iter().enumerate() {
        let base_candidates = case
            .candidates
            .iter()
            .map(|candidate| {
                Ok(AiCandidateInput::new(&candidate.text, candidate.base_rank)
                    .with_pinyin(&candidate.pinyin)
                    .with_base_score(candidate.base_score)
                    .with_lite_features(candidate.features.into_core()?))
            })
            .collect::<Result<Vec<_>, String>>()?;
        let identity = AiRequestIdentity::new(
            AiSessionId::from_u128(0xA106),
            AiRequestId::new(case_index as u64 + 1),
            AiCompositionRevision::new(1),
            AiCandidateSetHash::from_ordered_texts(
                base_candidates.iter().map(AiCandidateInput::text),
            ),
        );
        let request = AiRequestBuilder::new(
            identity,
            AiFeature::CandidateRerank,
            "zh-Hans",
            HardwareTier::Tier1,
            AiBudget::for_feature(AiFeature::CandidateRerank),
        )
        .with_base_candidates(base_candidates)
        .build(&PrivacyGuard, AiFeaturePolicy::approved_model_enabled(true))
        .map_err(|error| format!("case {} was rejected: {error}", case.id))?;
        let response = ranker
            .infer(&request)
            .map_err(|error| format!("case {} inference failed: {error}", case.id))?;
        maximum_inference_micros = maximum_inference_micros.max(response.elapsed().as_micros());
        total_inference_nanos = total_inference_nanos.saturating_add(response.elapsed().as_nanos());

        let baseline_rank = case
            .candidates
            .iter()
            .position(|candidate| candidate.text == case.expected_text)
            .map(|index| index + 1)
            .ok_or_else(|| format!("case {} expected text is not a candidate", case.id))?;
        let ranker_rank = response
            .candidates()
            .iter()
            .position(|candidate| candidate.text() == case.expected_text)
            .map(|index| index + 1);
        baseline_accumulator.record(Some(baseline_rank));
        ranker_accumulator.record(ranker_rank);

        let improved = ranker_rank.is_some_and(|rank| rank < baseline_rank);
        let regressed = ranker_rank.is_none_or(|rank| rank > baseline_rank);
        let gate_passed = match case.gate {
            RankerGate::Improve => improved,
            RankerGate::Preserve => baseline_rank == 1 && ranker_rank == Some(1),
        };
        results.push(RankerCaseResult {
            id: case.id.clone(),
            gate: case.gate,
            baseline_rank,
            ranker_rank,
            improved,
            regressed,
            gate_passed,
        });
    }

    Ok(RankerEvaluationReport {
        dataset: dataset.dataset_id,
        model_id: ranker.model_id().to_owned(),
        model_version: ranker.model_version().to_owned(),
        total_cases: results.len(),
        improved_cases: results.iter().filter(|result| result.improved).count(),
        regressed_cases: results.iter().filter(|result| result.regressed).count(),
        gate_failures: results.iter().filter(|result| !result.gate_passed).count(),
        maximum_inference_micros,
        mean_inference_micros: total_inference_nanos as f64 / results.len() as f64 / 1_000.0,
        baseline: baseline_accumulator.finish(),
        ranker: ranker_accumulator.finish(),
        results,
    })
}

fn load_ranker_dataset(path: &Path) -> Result<RankerDataset, String> {
    let contents = fs::read_to_string(path)
        .map_err(|error| format!("could not read {}: {error}", path.display()))?;
    let dataset = serde_json::from_str::<RankerDataset>(&contents)
        .map_err(|error| format!("could not parse {}: {error}", path.display()))?;
    validate_ranker_dataset(&dataset)?;
    Ok(dataset)
}

fn validate_ranker_dataset(dataset: &RankerDataset) -> Result<(), String> {
    if dataset.schema_version != RANKER_DATASET_SCHEMA_VERSION
        || dataset.dataset_id.is_empty()
        || dataset.provenance.is_empty()
        || dataset.contains_user_data
        || dataset.contains_real_application_context
        || dataset.contains_prompts_or_model_outputs
        || dataset.network_required
        || dataset.cases.is_empty()
        || dataset.cases.len() > MAX_RANKER_CASES
    {
        return Err("ranker dataset policy declaration is invalid".to_owned());
    }
    let mut ids = HashSet::new();
    for case in &dataset.cases {
        if case.id.is_empty()
            || !ids.insert(case.id.as_str())
            || case.expected_text.is_empty()
            || !(2..=32).contains(&case.candidates.len())
        {
            return Err(format!("ranker case {} is invalid", case.id));
        }
        let expected_count = case
            .candidates
            .iter()
            .filter(|candidate| candidate.text == case.expected_text)
            .count();
        if expected_count != 1 {
            return Err(format!(
                "ranker case {} must contain its expected text exactly once",
                case.id
            ));
        }
        for (index, candidate) in case.candidates.iter().enumerate() {
            if candidate.text.is_empty()
                || candidate.pinyin.is_empty()
                || candidate.base_rank != index
                || candidate.features.into_core().is_err()
            {
                return Err(format!("ranker case {} candidate is invalid", case.id));
            }
        }
        if case.gate == RankerGate::Preserve && case.candidates[0].text != case.expected_text {
            return Err(format!(
                "ranker preservation case {} must start at top-1",
                case.id
            ));
        }
    }
    Ok(())
}

#[derive(Default)]
struct RankerMetricsAccumulator {
    cases: usize,
    found: usize,
    top_1: usize,
    reciprocal_rank_sum: f64,
}

impl RankerMetricsAccumulator {
    fn record(&mut self, rank: Option<usize>) {
        self.cases += 1;
        if let Some(rank) = rank {
            self.found += 1;
            self.top_1 += usize::from(rank == 1);
            self.reciprocal_rank_sum += 1.0 / rank as f64;
        }
    }

    fn finish(self) -> RankerMetrics {
        RankerMetrics {
            cases: self.cases,
            found: self.found,
            top_1: self.top_1,
            mean_reciprocal_rank: self.reciprocal_rank_sum / self.cases as f64,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn approved_ai06_package_improves_targets_without_regressions() {
        let repository_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let report = evaluate_ranker_package(
            repository_root.join("ai/models/private-pinyin-ai-lite-ranker-v1"),
            repository_root.join("ai/eval/ai06_ranker_cases.json"),
        )
        .expect("evaluate checked-in AI-06 package");

        assert!(report.passes(8));
        assert_eq!(report.improved_cases, 8);
        assert_eq!(report.regressed_cases, 0);
        assert_eq!(report.gate_failures, 0);
    }

    #[test]
    fn dataset_parser_rejects_user_data_declarations() {
        let dataset = RankerDataset {
            schema_version: 1,
            dataset_id: "invalid".to_owned(),
            provenance: vec!["user export".to_owned()],
            contains_user_data: true,
            contains_real_application_context: false,
            contains_prompts_or_model_outputs: false,
            network_required: false,
            cases: Vec::new(),
        };
        assert!(validate_ranker_dataset(&dataset).is_err());
    }
}
