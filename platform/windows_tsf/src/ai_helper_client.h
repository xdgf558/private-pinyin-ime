#pragma once

#include <filesystem>

namespace private_pinyin {

// Blocking AI-09 lifecycle probe for a controlled helper process.
//
// This method is intentionally not called from the TSF edit-session path. AI-10/11
// must invoke persistent helper operations only through a bounded background worker.
// Failure always means "optional enhancement unavailable"; it must never affect the
// ordinary Rust candidate pipeline.
class AiHelperClient final {
 public:
  static bool run_mock_probe(const std::filesystem::path& helper_executable);
};

}  // namespace private_pinyin
