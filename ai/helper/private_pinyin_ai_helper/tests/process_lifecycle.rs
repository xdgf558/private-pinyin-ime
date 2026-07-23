use std::io::Write;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use private_pinyin_ai_helper_protocol::{
    read_frame, write_frame, HelperErrorCode, HelperFrame, HelperOpcode, WriterFeature,
    WriterRequest, WriterRequestIdentity, HELPER_AUTH_TOKEN_BYTES, MAX_HELPER_ACTIVE_REQUESTS,
    MAX_HELPER_PAYLOAD_BYTES,
};

const TOKEN: [u8; HELPER_AUTH_TOKEN_BYTES] = [0x2c; HELPER_AUTH_TOKEN_BYTES];

fn token_hex() -> String {
    TOKEN.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn spawn_helper(idle_timeout_ms: u64) -> (Child, ChildStdin, ChildStdout) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_private_pinyin_ai_helper"))
        .arg("--stdio")
        .arg("--idle-timeout-ms")
        .arg(idle_timeout_ms.to_string())
        .env("PRIVATE_PINYIN_AI_HELPER_TOKEN", token_hex())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn helper");
    let stdin = child.stdin.take().expect("helper stdin");
    let stdout = child.stdout.take().expect("helper stdout");
    (child, stdin, stdout)
}

fn authenticate(stdin: &mut ChildStdin, stdout: &mut ChildStdout) {
    write_frame(
        stdin,
        &HelperFrame::new(HelperOpcode::Authenticate, 0, TOKEN.to_vec()).expect("auth frame"),
    )
    .expect("write auth");
    let response = read_frame(stdout).expect("read auth response");
    assert_eq!(response.opcode, HelperOpcode::Authenticated);
}

#[test]
fn health_mock_cancel_and_shutdown_round_trip() {
    let (mut child, mut stdin, mut stdout) = spawn_helper(5_000);
    authenticate(&mut stdin, &mut stdout);

    write_frame(&mut stdin, &HelperFrame::empty(HelperOpcode::Health, 1)).expect("write health");
    let health = read_frame(&mut stdout).expect("read health");
    assert_eq!(
        (health.opcode, health.request_id),
        (HelperOpcode::Healthy, 1)
    );

    write_frame(
        &mut stdin,
        &HelperFrame::mock(2, Duration::from_millis(500)).expect("mock frame"),
    )
    .expect("write mock");
    write_frame(&mut stdin, &HelperFrame::cancel(3, 2)).expect("write cancel");
    let cancelled = read_frame(&mut stdout).expect("read cancelled");
    let acknowledged = read_frame(&mut stdout).expect("read cancel acknowledgement");
    assert_eq!(
        (cancelled.opcode, cancelled.request_id),
        (HelperOpcode::Cancelled, 2)
    );
    assert_eq!(
        (acknowledged.opcode, acknowledged.request_id),
        (HelperOpcode::Acknowledged, 3)
    );

    write_frame(&mut stdin, &HelperFrame::empty(HelperOpcode::Health, 4))
        .expect("write post-cancel health");
    let health = read_frame(&mut stdout).expect("read post-cancel health");
    assert_eq!(
        (health.opcode, health.request_id),
        (HelperOpcode::Healthy, 4)
    );

    write_frame(&mut stdin, &HelperFrame::empty(HelperOpcode::Shutdown, 5))
        .expect("write shutdown");
    let shutdown = read_frame(&mut stdout).expect("read shutdown acknowledgement");
    assert_eq!(
        (shutdown.opcode, shutdown.request_id),
        (HelperOpcode::Acknowledged, 5)
    );
    drop(stdin);
    assert!(child.wait().expect("wait for shutdown").success());
}

#[test]
fn unauthenticated_requests_fail_closed() {
    let (mut child, mut stdin, mut stdout) = spawn_helper(5_000);
    write_frame(&mut stdin, &HelperFrame::empty(HelperOpcode::Health, 8))
        .expect("write unauthenticated health");
    let response = read_frame(&mut stdout).expect("read authentication failure");
    assert_eq!(response.opcode, HelperOpcode::Error);
    drop(stdin);
    assert!(!child.wait().expect("wait for auth failure").success());
}

#[test]
fn writer_request_fails_closed_when_the_approved_model_is_absent() {
    let (mut child, mut stdin, mut stdout) = spawn_helper(5_000);
    authenticate(&mut stdin, &mut stdout);
    let request = WriterRequest::new(
        WriterRequestIdentity {
            session_id: 1,
            revision: 1,
            candidate_set_hash: 1,
        },
        WriterFeature::RewritePolite,
        true,
        Duration::from_secs(2),
        "zh-CN",
        "请帮我确认明天的会议时间",
    )
    .expect("writer request");
    write_frame(
        &mut stdin,
        &HelperFrame::writer(9, &request).expect("writer frame"),
    )
    .expect("write writer request");
    let response = read_frame(&mut stdout).expect("read unavailable response");
    assert_eq!(
        (response.opcode, response.request_id),
        (HelperOpcode::Error, 9)
    );
    assert_eq!(
        response.payload(),
        &(HelperErrorCode::ModelUnavailable as u16).to_le_bytes()
    );

    write_frame(&mut stdin, &HelperFrame::empty(HelperOpcode::Shutdown, 10))
        .expect("write shutdown");
    let _ = read_frame(&mut stdout).expect("read shutdown");
    drop(stdin);
    assert!(child.wait().expect("wait for shutdown").success());
}

#[test]
fn helper_exits_after_bounded_idle_timeout() {
    let (mut child, mut stdin, mut stdout) = spawn_helper(80);
    authenticate(&mut stdin, &mut stdout);
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        if let Some(status) = child.try_wait().expect("poll idle helper") {
            assert!(status.success());
            break;
        }
        assert!(Instant::now() < deadline, "helper did not exit when idle");
        thread::sleep(Duration::from_millis(20));
    }
    let _ = stdin.flush();
}

#[test]
fn maximum_frame_and_queue_saturation_fail_safely() {
    let (mut child, mut stdin, mut stdout) = spawn_helper(15_000);
    authenticate(&mut stdin, &mut stdout);

    let maximum = HelperFrame::new(
        HelperOpcode::Health,
        50,
        vec![0x5a; MAX_HELPER_PAYLOAD_BYTES],
    )
    .expect("maximum frame");
    write_frame(&mut stdin, &maximum).expect("write maximum frame");
    let health = read_frame(&mut stdout).expect("read maximum-frame response");
    assert_eq!(
        (health.opcode, health.request_id),
        (HelperOpcode::Healthy, 50)
    );

    for offset in 0..MAX_HELPER_ACTIVE_REQUESTS as u64 {
        write_frame(
            &mut stdin,
            &HelperFrame::mock(100 + offset, Duration::from_secs(5)).expect("long mock"),
        )
        .expect("fill helper queue");
    }
    write_frame(
        &mut stdin,
        &HelperFrame::mock(200, Duration::from_secs(5)).expect("overflow mock"),
    )
    .expect("write overflow mock");
    let overflow = read_frame(&mut stdout).expect("read queue-full response");
    assert_eq!(
        (overflow.opcode, overflow.request_id),
        (HelperOpcode::Error, 200)
    );
    assert_eq!(
        overflow.payload(),
        &(HelperErrorCode::QueueFull as u16).to_le_bytes()
    );

    for offset in 0..MAX_HELPER_ACTIVE_REQUESTS as u64 {
        let request_id = 300 + offset;
        write_frame(&mut stdin, &HelperFrame::cancel(request_id, 100 + offset))
            .expect("cancel saturated request");
        let cancelled = read_frame(&mut stdout).expect("read cancelled request");
        let acknowledged = read_frame(&mut stdout).expect("read cancel acknowledgement");
        assert_eq!(
            (cancelled.opcode, cancelled.request_id),
            (HelperOpcode::Cancelled, 100 + offset)
        );
        assert_eq!(
            (acknowledged.opcode, acknowledged.request_id),
            (HelperOpcode::Acknowledged, request_id)
        );
    }

    write_frame(&mut stdin, &HelperFrame::empty(HelperOpcode::Shutdown, 400))
        .expect("write shutdown");
    let shutdown = read_frame(&mut stdout).expect("read shutdown acknowledgement");
    assert_eq!(
        (shutdown.opcode, shutdown.request_id),
        (HelperOpcode::Acknowledged, 400)
    );
    drop(stdin);
    assert!(child.wait().expect("wait for shutdown").success());
}
