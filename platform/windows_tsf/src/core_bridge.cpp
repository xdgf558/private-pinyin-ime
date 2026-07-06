#include "core_bridge.h"

#include <windows.h>

namespace private_pinyin {

CoreBridge::~CoreBridge() {
  reset();
}

bool CoreBridge::initialize() {
  reset();
  engine_ = ime_engine_new(nullptr);
  if (engine_ == nullptr) {
    return false;
  }

  session_ = ime_session_new(engine_);
  if (session_ == nullptr) {
    reset();
    return false;
  }

  return true;
}

void CoreBridge::reset() {
  if (session_ != nullptr) {
    ime_session_free(session_);
    session_ = nullptr;
  }
  if (engine_ != nullptr) {
    ime_engine_free(engine_);
    engine_ = nullptr;
  }
}

void CoreBridge::reset_session() {
  if (session_ == nullptr) {
    return;
  }
  (void)take_output(ime_session_reset(session_));
}

std::optional<OutputSnapshot> CoreBridge::feed_key(const ImeKeyEvent& event) {
  if (session_ == nullptr) {
    return std::nullopt;
  }
  return take_output(ime_session_feed_key(session_, event));
}

std::optional<OutputSnapshot> CoreBridge::commit_candidate(int index) {
  if (session_ == nullptr) {
    return std::nullopt;
  }
  return take_output(ime_session_commit_candidate(session_, index));
}

std::optional<OutputSnapshot> CoreBridge::toggle_mode() {
  if (session_ == nullptr) {
    return std::nullopt;
  }
  return take_output(ime_session_toggle_mode(session_));
}

std::optional<OutputSnapshot> CoreBridge::take_output(ImeOutput* output) {
  if (output == nullptr) {
    return std::nullopt;
  }

  OutputSnapshot snapshot;
  snapshot.preedit = utf8_to_wide(output->preedit);
  snapshot.commit_text = utf8_to_wide(output->commit_text);
  snapshot.should_update_preedit = output->should_update_preedit != 0;
  snapshot.should_commit = output->should_commit != 0;
  snapshot.should_show_candidates = output->should_show_candidates != 0;

  if (output->candidate_count > 0 && output->candidates != nullptr) {
    snapshot.candidates.reserve(static_cast<size_t>(output->candidate_count));
    for (int i = 0; i < output->candidate_count; ++i) {
      const ImeCandidate& candidate = output->candidates[i];
      snapshot.candidates.push_back({
          utf8_to_wide(candidate.text),
          utf8_to_wide(candidate.pinyin),
          candidate.score,
          utf8_to_wide(candidate.source),
      });
    }
  }

  ime_output_free(output);
  return snapshot;
}

std::wstring utf8_to_wide(const char* value) {
  if (value == nullptr || value[0] == '\0') {
    return {};
  }

  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, nullptr, 0);
  if (length <= 1) {
    return {};
  }

  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result.data(), length);
  result.resize(static_cast<size_t>(length - 1));
  return result;
}

}  // namespace private_pinyin
