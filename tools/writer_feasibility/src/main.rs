use std::env;
use std::path::PathBuf;

use private_pinyin_writer_feasibility::{run_feasibility, validate_inputs, RunPaths};

fn main() {
    if let Err(error) = run() {
        eprintln!("{}", error.code());
        std::process::exit(1);
    }
}

fn run() -> Result<(), private_pinyin_writer_feasibility::ProbeError> {
    let args = Args::parse(env::args().skip(1).collect())?;
    let paths = RunPaths {
        candidate: args.candidate,
        dataset: args.dataset,
        model: args.model,
        runtime: args.runtime,
    };

    match args.command {
        Command::Validate => {
            let validated = validate_inputs(&paths)?;
            println!(
                "Writer inputs valid: candidate={} runtime={} cases={}",
                validated.candidate.model.id,
                validated.candidate.runtime.release_tag,
                validated.dataset.cases.len()
            );
        }
        Command::Run => {
            let report_path = args.report.ok_or_else(|| {
                private_pinyin_writer_feasibility::ProbeError::argument("report_required")
            })?;
            let report = run_feasibility(&paths)?;
            report.write_json(&report_path)?;
            println!(
                "{} technical gates: {}; release decision: {:?}; report={}",
                report.stage,
                if report.technical_passed {
                    "passed"
                } else {
                    "failed"
                },
                report.release_decision,
                report_path.display()
            );
        }
    }
    Ok(())
}

#[derive(Debug, Clone, Copy)]
enum Command {
    Validate,
    Run,
}

#[derive(Debug)]
struct Args {
    command: Command,
    candidate: PathBuf,
    dataset: PathBuf,
    model: PathBuf,
    runtime: PathBuf,
    report: Option<PathBuf>,
}

impl Args {
    fn parse(args: Vec<String>) -> Result<Self, private_pinyin_writer_feasibility::ProbeError> {
        let command = match args.first().map(String::as_str) {
            Some("validate") => Command::Validate,
            Some("run") => Command::Run,
            _ => {
                return Err(private_pinyin_writer_feasibility::ProbeError::argument(
                    "command_required",
                ))
            }
        };
        let mut candidate = None;
        let mut dataset = None;
        let mut model = None;
        let mut runtime = None;
        let mut report = None;
        let mut index = 1;
        while index < args.len() {
            let flag = args[index].as_str();
            index += 1;
            let value = args.get(index).ok_or_else(|| {
                private_pinyin_writer_feasibility::ProbeError::argument("flag_value_missing")
            })?;
            match flag {
                "--candidate" => candidate = Some(PathBuf::from(value)),
                "--dataset" => dataset = Some(PathBuf::from(value)),
                "--model" => model = Some(PathBuf::from(value)),
                "--runtime" => runtime = Some(PathBuf::from(value)),
                "--report" => report = Some(PathBuf::from(value)),
                _ => {
                    return Err(private_pinyin_writer_feasibility::ProbeError::argument(
                        "unknown_argument",
                    ))
                }
            }
            index += 1;
        }

        Ok(Self {
            command,
            candidate: candidate.ok_or_else(|| {
                private_pinyin_writer_feasibility::ProbeError::argument("candidate_required")
            })?,
            dataset: dataset.ok_or_else(|| {
                private_pinyin_writer_feasibility::ProbeError::argument("dataset_required")
            })?,
            model: model.ok_or_else(|| {
                private_pinyin_writer_feasibility::ProbeError::argument("model_required")
            })?,
            runtime: runtime.ok_or_else(|| {
                private_pinyin_writer_feasibility::ProbeError::argument("runtime_required")
            })?,
            report,
        })
    }
}
