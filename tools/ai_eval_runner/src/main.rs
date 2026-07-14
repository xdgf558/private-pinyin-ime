use std::env;
use std::path::PathBuf;

use ime_core::ImeEngine;
use private_pinyin_ai_eval::{evaluate, load_cases, EvaluationGate, EvaluationReport};

const DEFAULT_DATASET: &str = "ai/eval/baseline_cases.tsv";

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args = Args::parse(env::args().skip(1).collect())?;
    let cases = load_cases(&args.dataset)?;
    let engine =
        ImeEngine::new().map_err(|error| format!("could not initialize engine: {error}"))?;
    let report = evaluate(&engine, args.dataset.display().to_string(), &cases);

    match args.format {
        OutputFormat::Summary => print_summary(&report),
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
    Ok(())
}

fn print_summary(report: &EvaluationReport) {
    println!("AI-01 baseline evaluation");
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
}

impl Args {
    fn parse(args: Vec<String>) -> Result<Self, String> {
        let mut dataset = PathBuf::from(DEFAULT_DATASET);
        let mut format = OutputFormat::Summary;
        let mut allow_required_failures = false;
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
                "--help" | "-h" => return Err(usage()),
                argument => return Err(format!("unknown argument {argument:?}\n{}", usage())),
            }
            index += 1;
        }

        Ok(Self {
            dataset,
            format,
            allow_required_failures,
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
        "Usage: private-pinyin-ai-eval [--dataset PATH] [--json] [--allow-required-failures]\nDefault dataset: {DEFAULT_DATASET}"
    )
}
