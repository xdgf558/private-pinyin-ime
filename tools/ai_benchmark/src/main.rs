use std::collections::BTreeMap;
use std::env;
use std::hint::black_box;
use std::path::PathBuf;
use std::time::Instant;

use ime_core::ImeEngine;
use private_pinyin_ai_eval::{candidates_for_case, load_cases, EvaluationCase};
use serde::Serialize;

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
    let initialization = benchmark_initialization(args.initialization_iterations)?;
    let engine =
        ImeEngine::new().map_err(|error| format!("could not initialize engine: {error}"))?;
    let lookups = benchmark_lookups(&engine, &cases, args.lookup_iterations);
    let report = BenchmarkReport {
        dataset: args.dataset.display().to_string(),
        initialization,
        lookup_iterations_per_case: args.lookup_iterations,
        lookups,
    };

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&report)
                .map_err(|error| format!("could not serialize benchmark: {error}"))?
        );
    } else {
        print_summary(&report);
    }
    Ok(())
}

fn benchmark_initialization(iterations: usize) -> Result<LatencySummary, String> {
    let mut samples = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let started = Instant::now();
        let engine =
            ImeEngine::new().map_err(|error| format!("could not initialize engine: {error}"))?;
        samples.push(elapsed_micros(started));
        black_box(engine);
    }
    Ok(LatencySummary::from_samples(samples))
}

fn benchmark_lookups(
    engine: &ImeEngine,
    cases: &[EvaluationCase],
    iterations: usize,
) -> BTreeMap<String, LatencySummary> {
    let mut samples = BTreeMap::<String, Vec<u64>>::new();
    for case in cases {
        for _ in 0..iterations {
            let started = Instant::now();
            let candidates = candidates_for_case(engine, case);
            samples
                .entry(case.feature.clone())
                .or_default()
                .push(elapsed_micros(started));
            black_box(candidates);
        }
    }
    samples
        .into_iter()
        .map(|(feature, samples)| (feature, LatencySummary::from_samples(samples)))
        .collect()
}

fn elapsed_micros(started: Instant) -> u64 {
    u64::try_from(started.elapsed().as_micros()).unwrap_or(u64::MAX)
}

fn print_summary(report: &BenchmarkReport) {
    println!("AI-01 reference benchmark (report-only, no CI latency gate)");
    println!("dataset: {}", report.dataset);
    println!(
        "engine initialization: p50 {:.2} ms, p95 {:.2} ms, max {:.2} ms ({} samples)",
        micros_to_millis(report.initialization.p50_us),
        micros_to_millis(report.initialization.p95_us),
        micros_to_millis(report.initialization.max_us),
        report.initialization.samples
    );
    for (feature, summary) in &report.lookups {
        println!(
            "  {feature}: p50 {:.2} ms, p95 {:.2} ms, p99 {:.2} ms, max {:.2} ms ({} samples)",
            micros_to_millis(summary.p50_us),
            micros_to_millis(summary.p95_us),
            micros_to_millis(summary.p99_us),
            micros_to_millis(summary.max_us),
            summary.samples
        );
    }
}

fn micros_to_millis(micros: u64) -> f64 {
    micros as f64 / 1_000.0
}

#[derive(Debug, Serialize)]
struct BenchmarkReport {
    dataset: String,
    initialization: LatencySummary,
    lookup_iterations_per_case: usize,
    lookups: BTreeMap<String, LatencySummary>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
struct LatencySummary {
    samples: usize,
    min_us: u64,
    p50_us: u64,
    p95_us: u64,
    p99_us: u64,
    max_us: u64,
}

impl LatencySummary {
    fn from_samples(mut samples: Vec<u64>) -> Self {
        samples.sort_unstable();
        Self {
            samples: samples.len(),
            min_us: samples.first().copied().unwrap_or_default(),
            p50_us: percentile(&samples, 50),
            p95_us: percentile(&samples, 95),
            p99_us: percentile(&samples, 99),
            max_us: samples.last().copied().unwrap_or_default(),
        }
    }
}

fn percentile(samples: &[u64], percentile: usize) -> u64 {
    if samples.is_empty() {
        return 0;
    }
    let percentile = percentile.clamp(1, 100);
    let rank = (samples.len() * percentile).div_ceil(100);
    let index = rank - 1;
    samples[index]
}

#[derive(Debug)]
struct Args {
    dataset: PathBuf,
    initialization_iterations: usize,
    lookup_iterations: usize,
    json: bool,
}

impl Args {
    fn parse(args: Vec<String>) -> Result<Self, String> {
        let mut parsed = Self {
            dataset: PathBuf::from(DEFAULT_DATASET),
            initialization_iterations: 3,
            lookup_iterations: 20,
            json: false,
        };
        let mut index = 0;
        while index < args.len() {
            match args[index].as_str() {
                "--dataset" => {
                    index += 1;
                    parsed.dataset = PathBuf::from(next_value(&args, index, "--dataset")?);
                }
                "--initialization-iterations" => {
                    index += 1;
                    parsed.initialization_iterations =
                        parse_positive(next_value(&args, index, "--initialization-iterations")?)?;
                }
                "--lookup-iterations" => {
                    index += 1;
                    parsed.lookup_iterations =
                        parse_positive(next_value(&args, index, "--lookup-iterations")?)?;
                }
                "--json" => parsed.json = true,
                "--help" | "-h" => return Err(usage()),
                argument => return Err(format!("unknown argument {argument:?}\n{}", usage())),
            }
            index += 1;
        }
        Ok(parsed)
    }
}

fn next_value<'a>(args: &'a [String], index: usize, flag: &str) -> Result<&'a str, String> {
    args.get(index)
        .map(String::as_str)
        .ok_or_else(|| format!("{flag} requires a value"))
}

fn parse_positive(value: &str) -> Result<usize, String> {
    let value = value
        .parse::<usize>()
        .map_err(|_| "iteration counts must be positive integers".to_owned())?;
    if value == 0 {
        Err("iteration counts must be greater than zero".to_owned())
    } else {
        Ok(value)
    }
}

fn usage() -> String {
    format!(
        "Usage: private-pinyin-ai-benchmark [--dataset PATH] [--initialization-iterations N] [--lookup-iterations N] [--json]\nDefault dataset: {DEFAULT_DATASET}"
    )
}

#[cfg(test)]
mod tests {
    use super::{percentile, LatencySummary};

    #[test]
    fn latency_summary_uses_stable_nearest_rank_indices() {
        let summary = LatencySummary::from_samples((1..=100).collect());

        assert_eq!(summary.p50_us, 50);
        assert_eq!(summary.p95_us, 95);
        assert_eq!(summary.p99_us, 99);
        assert_eq!(percentile(&[], 95), 0);
        assert_eq!(percentile(&[10, 20, 30], 95), 30);
    }
}
