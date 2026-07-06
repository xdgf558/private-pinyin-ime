#pragma once

#include <string>
#include <vector>

#include <windows.h>

#include "core_bridge.h"

namespace private_pinyin {

class CandidateWindow {
 public:
  CandidateWindow() = default;
  CandidateWindow(const CandidateWindow&) = delete;
  CandidateWindow& operator=(const CandidateWindow&) = delete;
  ~CandidateWindow();

  void show(const std::vector<CandidateSnapshot>& candidates);
  void hide();

 private:
  bool ensure_window();
  void paint();
  static LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  HWND hwnd_ = nullptr;
  std::vector<CandidateSnapshot> candidates_;
};

}  // namespace private_pinyin
