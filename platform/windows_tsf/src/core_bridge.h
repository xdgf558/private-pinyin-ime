#pragma once

#include <optional>
#include <string>
#include <vector>

#include "c_api.h"

namespace private_pinyin {

struct CandidateSnapshot {
  std::wstring text;
  std::wstring pinyin;
  double score = 0.0;
  std::wstring source;
};

struct OutputSnapshot {
  std::wstring preedit;
  std::wstring commit_text;
  bool should_update_preedit = false;
  bool should_commit = false;
  bool should_show_candidates = false;
  std::vector<CandidateSnapshot> candidates;
};

class CoreBridge {
 public:
  CoreBridge() = default;
  CoreBridge(const CoreBridge&) = delete;
  CoreBridge& operator=(const CoreBridge&) = delete;
  ~CoreBridge();

  bool initialize();
  void reset();

  std::optional<OutputSnapshot> feed_key(const ImeKeyEvent& event);
  std::optional<OutputSnapshot> commit_candidate(int index);
  std::optional<OutputSnapshot> toggle_mode();

 private:
  std::optional<OutputSnapshot> take_output(ImeOutput* output);

  ImeEngine* engine_ = nullptr;
  ImeSession* session_ = nullptr;
};

std::wstring utf8_to_wide(const char* value);

}  // namespace private_pinyin
