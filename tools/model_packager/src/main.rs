use std::env;
use std::path::PathBuf;

use private_pinyin_model_packager::package_model;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let arguments = Arguments::parse(env::args().skip(1).collect())?;
    let summary = package_model(
        &arguments.template,
        &arguments.package_root,
        &arguments.output,
    )?;
    println!(
        "packaged model_id={} version={} artifacts={} approval_fingerprint_sha256={}",
        summary.model_id(),
        summary.version(),
        summary.artifact_count(),
        summary.approval_fingerprint_sha256()
    );
    Ok(())
}

struct Arguments {
    template: PathBuf,
    package_root: PathBuf,
    output: PathBuf,
}

impl Arguments {
    fn parse(arguments: Vec<String>) -> Result<Self, String> {
        if arguments.first().map(String::as_str) != Some("pack") {
            return Err(usage());
        }
        let mut template = None;
        let mut package_root = None;
        let mut output = None;
        let mut index = 1;
        while index < arguments.len() {
            match arguments[index].as_str() {
                "--template" => template = Some(next_path(&arguments, &mut index)?),
                "--package-root" => package_root = Some(next_path(&arguments, &mut index)?),
                "--output" => output = Some(next_path(&arguments, &mut index)?),
                "--help" | "-h" => return Err(usage()),
                _ => return Err(usage()),
            }
            index += 1;
        }
        Ok(Self {
            template: template.ok_or_else(usage)?,
            package_root: package_root.ok_or_else(usage)?,
            output: output.ok_or_else(usage)?,
        })
    }
}

fn next_path(arguments: &[String], index: &mut usize) -> Result<PathBuf, String> {
    *index += 1;
    arguments.get(*index).map(PathBuf::from).ok_or_else(usage)
}

fn usage() -> String {
    "Usage: private-pinyin-model-packager pack --template PATH --package-root DIR --output PATH"
        .to_owned()
}
