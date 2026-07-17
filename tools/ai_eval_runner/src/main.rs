use std::env;
use std::path::PathBuf;

use ime_core::ImeEngine;
use private_pinyin_ai_eval::{
    evaluate, evaluate_ranker_package, evaluate_with_rules, load_cases, EvaluationGate,
    EvaluationReport, RankerEvaluationReport,
};

const DEFAULT_DATASET: &str = "ai/eval/baseline_cases.tsv";
const DEFAULT_RANKER_DATASET: &str = "ai/eval/ai06_ranker_cases.json";
const DEFAULT_RANKER_PACKAGE: &str = "ai/models/private-pinyin-ai-lite-ranker-v1";

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args = Args::parse(env::args().skip(1).collect())?;
    if args.ranker {
        let report = evaluate_ranker_package(&args.model_package, &args.ranker_dataset)?;
        match args.format {
            OutputFormat::Summary => print_ranker_summary(&report),
            OutputFormat::Json => println!(
                "{}",
                serde_json::to_string_pretty(&report)
                    .map_err(|error| format!("could not serialize ranker report: {error}"))?
            ),
        }
        if !report.passes(args.require_ranker_improvements) {
            return Err(format!(
                "AI-06 ranker gate failed: improvements={}/{}, regressions={}, gate_failures={}",
                report.improved_cases,
                args.require_ranker_improvements,
                report.regressed_cases,
                report.gate_failures
            ));
        }
        return Ok(());
    }

    let cases = load_cases(&args.dataset)?;
    let engine =
        ImeEngine::new().map_err(|error| format!("could not initialize engine: {error}"))?;
    let report = if args.rules {
        evaluate_with_rules(&engine, args.dataset.display().to_string(), &cases)
    } else {
        evaluate(&engine, args.dataset.display().to_string(), &cases)
    };

    match args.format {
        OutputFormat::Summary => print_summary(&report, args.rules),
        OutputFormat::Json => println!(
            "{}",
            serde_json::to_string_pretty(&report)
                .map_err(|error| format!("could not serialize report: {error}"))?
        ),
    }

    if report.has_required_failures() && !args.allow_required_failures {
        return Err(format!(
            "{} required baseline case(s) regressed",
            report.required_failures
        ));
    }
    if let Some(required) = args.require_observed_successes {
        if report.observed_successes < required {
            return Err(format!(
                "observed opportunity target not met: {}/{} required",
                report.observed_successes, required
            ));
        }
    }
    Ok(())
}

fn print_ranker_summary(report: &RankerEvaluationReport) {
    println!("AI-06 fixed-point Lite ranker evaluation");
    println!("dataset: {}", report.dataset);
    println!("model: {} {}", report.model_id, report.model_version);
    println!(
        "quality: {} improved, {} regressed, {} gate failures",
        report.improved_cases, report.regressed_cases, report.gate_failures
    );
    println!(
        "baseline: top-1 {}/{}, MRR {:.3}",
        report.baseline.top_1, report.baseline.cases, report.baseline.mean_reciprocal_rank
    );
    println!(
        "ranker: top-1 {}/{}, MRR {:.3}",
        report.ranker.top_1, report.ranker.cases, report.ranker.mean_reciprocal_rank
    );
    println!(
        "reference inference: max {} us, mean {:.1} us (not a cross-machine CI threshold)",
        report.maximum_inference_micros, report.mean_inference_micros
    );
    for result in &report.results {
        println!(
            "  {} [{:?}]: baseline {}, ranker {}, {}",
            result.id,
            result.gate,
            result.baseline_rank,
            result
                .ranker_rank
                .map(|rank| rank.to_string())
                .unwrap_or_else(|| "not found".to_owned()),
            if result.gate_passed { "pass" } else { "FAIL" }
        );
    }
}

fn print_summary(report: &EvaluationReport, rules: bool) {
    println!(
        "{}",
        if rules {
            "AI-04 rules-first evaluation"
        } else {
            "AI-01 baseline evaluation"
        }
    );
    println!("dataset: {}", report.dataset);
    println!(
        "required: {}/{} passed; observed opportunities: {}/{} currently meet target",
        report.required_cases - report.required_failures,
        report.required_cases,
        report.observed_successes,
        report.observed_cases
    );
    println!(
        "overall: top-1 {}/{}, found {}/{}, MRR {:.3}",
        report.overall.top_1,
        report.overall.cases,
        report.overall.found,
        report.overall.cases,
        report.overall.mean_reciprocal_rank
    );
    for (feature, metrics) in &report.by_feature {
        println!(
            "  {feature}: target {}/{}, top-1 {}/{}, MRR {:.3}",
            metrics.within_target_rank,
            metrics.cases,
            metrics.top_1,
            metrics.cases,
            metrics.mean_reciprocal_rank
        );
    }

    let misses = report
        .results
        .iter()
        .filter(|result| !result.within_target_rank)
        .collect::<Vec<_>>();
    if !misses.is_empty() {
        println!("misses:");
        for result in misses {
            let gate = match result.gate {
                EvaluationGate::Required => "required",
                EvaluationGate::Observe => "observe",
            };
            let rank = result
                .rank
                .map(|rank| rank.to_string())
                .unwrap_or_else(|| "not found".to_owned());
            println!(
                "  {} [{}]: expected {}, rank {rank}",
                result.id,
                gate,
                result.expected_texts.join(" or ")
            );
        }
    }
}

#[derive(Debug)]
struct Args {
    dataset: PathBuf,
    format: OutputFormat,
    allow_required_failures: bool,
    rules: bool,
    require_observed_successes: Option<usize>,
    ranker: bool,
    ranker_dataset: PathBuf,
    model_package: PathBuf,
    require_ranker_improvements: usize,
}

impl Args {
    fn parse(args: Vec<String>) -> Result<Self, String> {
        let mut dataset = PathBuf::from(DEFAULT_DATASET);
        let mut format = OutputFormat::Summary;
        let mut allow_required_failures = false;
        let mut rules = false;
        let mut require_observed_successes = None;
        let mut ranker = false;
        let mut ranker_dataset = PathBuf::from(DEFAULT_RANKER_DATASET);
        let mut model_package = PathBuf::from(DEFAULT_RANKER_PACKAGE);
        let mut require_ranker_improvements = 1;
        let mut index = 0;

        while index < args.len() {
            match args[index].as_str() {
                "--dataset" => {
                    index += 1;
                    dataset = PathBuf::from(
                        args.get(index)
                            .ok_or_else(|| "--dataset requires a path".to_owned())?,
                    );
                }
                "--json" => format = OutputFormat::Json,
                "--allow-required-failures" => allow_required_failures = true,
                "--rules" => rules = true,
                "--ranker" => ranker = true,
                "--ranker-dataset" => {
                    index += 1;
                    ranker_dataset = PathBuf::from(
                        args.get(index)
                            .ok_or_else(|| "--ranker-dataset requires a path".to_owned())?,
                    );
                }
                "--model-package" => {
                    index += 1;
                    model_package = PathBuf::from(
                        args.get(index)
                            .ok_or_else(|| "--model-package requires a path".to_owned())?,
                    );
                }
                "--require-ranker-improvements" => {
                    index += 1;
                    require_ranker_improvements = args
                        .get(index)
                        .ok_or_else(|| {
                            "--require-ranker-improvements requires a number".to_owned()
                        })?
                        .parse::<usize>()
                        .map_err(|_| "--require-ranker-improvements must be a number".to_owned())?;
                }
                "--require-observed-successes" => {
                    index += 1;
                    require_observed_successes = Some(
                        args.get(index)
                            .ok_or_else(|| {
                                "--require-observed-successes requires a number".to_owned()
                            })?
                            .parse::<usize>()
                            .map_err(|_| {
                                "--require-observed-successes must be a number".to_owned()
                            })?,
                    );
                }
                "--help" | "-h" => return Err(usage()),
                argument => return Err(format!("unknown argument {argument:?}\n{}", usage())),
            }
            index += 1;
        }

        if ranker && rules {
            return Err("--ranker and --rules cannot be combined".to_owned());
        }

        Ok(Self {
            dataset,
            format,
            allow_required_failures,
            rules,
            require_observed_successes,
            ranker,
            ranker_dataset,
            model_package,
            require_ranker_improvements,
        })
    }
}

#[derive(Debug, Clone, Copy)]
enum OutputFormat {
    Summary,
    Json,
}

fn usage() -> String {
    format!(
        "Usage: private-pinyin-ai-eval [--dataset PATH] [--json] [--rules] [--require-observed-successes N] [--allow-required-failures]\n       private-pinyin-ai-eval --ranker [--ranker-dataset PATH] [--model-package DIR] [--require-ranker-improvements N] [--json]\nDefault dataset: {DEFAULT_DATASET}\nDefault ranker dataset: {DEFAULT_RANKER_DATASET}\nDefault ranker package: {DEFAULT_RANKER_PACKAGE}"
    )
}
