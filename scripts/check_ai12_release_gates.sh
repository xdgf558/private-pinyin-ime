#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  "ai/eval/ai12_release_gate.json"
  "ai/models/private-pinyin-ai-lite-ranker-v1/MODEL_NOTICE.md"
  "ai/writer_feasibility/QWEN_MODEL_NOTICE.md"
  "ai/writer_feasibility/QWEN_1_5B_MODEL_NOTICE.md"
  "ai/eval/privacy_cases/password.json"
  "ai/eval/privacy_cases/token.json"
  "ai/eval/privacy_cases/id_card.json"
  "ai/eval/privacy_cases/phone.json"
  "ai/eval/privacy_cases/payment.json"
  "ai/eval/privacy_cases/false_positive.json"
)
for file in "${required_files[@]}"; do
  test -f "$file"
done

python3 - <<'PY'
import json
from pathlib import Path

report = json.loads(Path("ai/eval/ai12_release_gate.json").read_text())
assert report["stage"] == "AI-12"
assert report["release_profile"] == "ai_lite_with_dormant_writer"
assert report["contains_user_data"] is False
assert report["evidence_semantics"] == "declarative_expectations_only"

equivalence = report["ai_off_equivalence"]
assert equivalence["expected_outcome"] == "base_engine_exact_match"
assert equivalence["executable_test"] == (
    "ai_disabled_or_privacy_blocked_output_matches_the_base_engine_exactly"
)
assert set(equivalence["platform_features"]) == {
    "desktop-ai", "ios-ai"
}
assert set(equivalence["ci_steps"]) == {
    "Run desktop AI FFI tests", "Run iOS AI FFI tests"
}

expected_categories = {
    "password", "token", "id_card", "phone", "payment", "false_positive"
}
fixtures = {}
total_cases = 0
for path in sorted(Path("ai/eval/privacy_cases").glob("*.json")):
    data = json.loads(path.read_text())
    category = data["category"]
    assert category not in fixtures
    assert data["cases"]
    fixtures[category] = data["cases"]
    total_cases += len(data["cases"])
assert set(fixtures) == expected_categories
privacy = report["privacy_regression"]
assert privacy["expected_outcome"] == (
    "sensitive_cases_rejected_and_false_positives_allowed"
)
assert privacy["executable_test_module"] == "private_pinyin_local_ai_core::privacy_tests"
assert set(privacy["categories"]) == expected_categories
assert privacy["case_count"] == total_cases
assert privacy["false_positive_case_count"] == len(
    fixtures["false_positive"]
)

faults = report["helper_fault_injection"]
assert faults["portable"]["expected_outcome"] == "tests_pass"
assert faults["macos"]["expected_outcome"] == "tests_pass"
assert faults["windows"]["expected_outcome"] == "ci_tests_pass"
assert faults["macos"]["signed_package_identity_smoke"] == "pending_owner_hardware"
assert faults["windows"]["signed_installer_identity_smoke"] == "pending_owner_hardware"

decisions = report["release_decisions"]
assert decisions["ai_lite"] == "go"
assert decisions["writer"] == "no_go"
assert set(decisions["writer_reasons"]) == {
    "candidate_not_owner_approved",
    "redistribution_not_approved",
    "warm_latency_evidence_missing",
    "native_windows_rss_evidence_missing",
    "signed_package_identity_smoke_missing",
}
for notice in report["model_notices"]:
    assert Path(notice).is_file()
PY

grep -Fq "ai_disabled_or_privacy_blocked_output_matches_the_base_engine_exactly" \
  ffi/ime_ffi/tests/c_api_tests.rs
grep -Fq "maximum_sized_frame_round_trips_at_the_exact_boundary" \
  ai/helper_protocol/src/lib.rs
grep -Fq "maximum_frame_and_queue_saturation_fail_safely" \
  ai/helper/private_pinyin_ai_helper/tests/process_lifecycle.rs
grep -Fq "PrivatePinyinAIHelperRestartBudget" \
  platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift
grep -Fq "kPipeWriteTimeoutMilliseconds" \
  platform/windows_tsf/src/ai_helper_client.cpp
grep -Fq "expect_error" platform/windows_tsf/src/ai_helper_client.cpp
grep -Fq "kMaximumActiveRequests" platform/windows_tsf/src/ai_helper_client.cpp

echo "AI-12 declarative release contract is valid; executable pass/fail remains owned by CI test steps."
