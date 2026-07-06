use std::io::{self, Read};

use ime_core::ImeEngine;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let raw_input = read_raw_input()?;
    let engine = ImeEngine::new()?;
    let candidates = engine.candidates_for_raw(&raw_input);

    println!("Input: {}", raw_input.trim());
    if candidates.is_empty() {
        println!("No candidates");
        return Ok(());
    }

    for (index, candidate) in candidates.iter().enumerate() {
        println!(
            "{}. {}\t{}\t{:.0}\t{}",
            index + 1,
            candidate.text,
            candidate.pinyin,
            candidate.score,
            candidate.source
        );
    }

    Ok(())
}

fn read_raw_input() -> io::Result<String> {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    if !args.is_empty() {
        // Pinyin smoke input is intentionally compact: `test_cli xi an` means `xian`.
        return Ok(args.join(""));
    }

    let mut buffer = String::new();
    io::stdin().read_to_string(&mut buffer)?;
    Ok(buffer.trim().to_owned())
}
