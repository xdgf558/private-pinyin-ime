use std::env;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use private_pinyin_ai_helper_protocol::{
    read_frame, write_frame, HelperFrame, HelperOpcode, WriterFeature, WriterRequest,
    WriterRequestIdentity,
};

const TOKEN: [u8; 32] = [0x51; 32];

fn main() {
    let helper = env::args().nth(1).expect("helper path");
    let home = env::args().nth(2).expect("isolated HOME path");
    let token_hex: String = TOKEN.iter().map(|byte| format!("{byte:02x}")).collect();
    let mut child = Command::new(helper)
        .arg("--stdio")
        .arg("--idle-timeout-ms")
        .arg("15000")
        .env("HOME", home)
        .env("PRIVATE_PINYIN_AI_HELPER_TOKEN", token_hex)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .expect("spawn helper");
    let mut stdin = child.stdin.take().expect("stdin");
    let mut stdout = child.stdout.take().expect("stdout");

    write_frame(
        &mut stdin,
        &HelperFrame::new(HelperOpcode::Authenticate, 0, TOKEN.to_vec()).expect("auth frame"),
    )
    .expect("authenticate");
    assert_eq!(
        read_frame(&mut stdout).expect("auth response").opcode,
        HelperOpcode::Authenticated
    );

    let prepare_started = Instant::now();
    write_frame(
        &mut stdin,
        &HelperFrame::empty(HelperOpcode::PrepareWriter, 1),
    )
    .expect("prepare Writer");
    let prepared = read_frame(&mut stdout).expect("prepare response");
    if prepared.opcode == HelperOpcode::Error {
        panic!(
            "Writer preparation returned error payload {:?}",
            prepared.payload()
        );
    }
    assert_eq!(prepared.opcode, HelperOpcode::WriterReady);
    let prepare_elapsed = prepare_started.elapsed();

    let request = WriterRequest::new(
        WriterRequestIdentity {
            session_id: 7,
            revision: 3,
            candidate_set_hash: 11,
        },
        WriterFeature::RewritePolite,
        true,
        Duration::from_secs(3),
        "zh-CN",
        "明天把报告发给我",
    )
    .expect("writer request");
    let inference_started = Instant::now();
    write_frame(
        &mut stdin,
        &HelperFrame::writer(2, &request).expect("writer frame"),
    )
    .expect("write request");
    let response = read_frame(&mut stdout).expect("writer response");
    if response.opcode == HelperOpcode::Error {
        panic!(
            "Writer helper returned error payload {:?}",
            response.payload()
        );
    }
    assert_eq!(response.opcode, HelperOpcode::WriterCompleted);
    let preview = response.writer_preview().expect("writer preview");
    assert!(preview.matches_request(&request));
    assert!(!preview.suggestions().is_empty());
    println!(
        "Writer smoke returned {} suggestion(s); prepare_ms={}, inference_ms={}.",
        preview.suggestions().len(),
        prepare_elapsed.as_millis(),
        inference_started.elapsed().as_millis()
    );

    write_frame(&mut stdin, &HelperFrame::empty(HelperOpcode::Shutdown, 3)).expect("shutdown");
    let _ = read_frame(&mut stdout).expect("shutdown response");
    drop(stdin);
    let _ = child.wait();
}
