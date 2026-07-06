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

  void show(const std::vector<CandidateSnapshot>& candidates, const RECT* anchor_rect = nullptr);
  void hide();
  static void unregister_window_class();
  static LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool ensure_window();
  POINT anchor_point(const RECT* anchor_rect) const;
  void clamp_to_work_area(POINT* point, int width, int height) const;
  int scale(int value) const;
  void paint();

  HWND hwnd_ = nullptr;
  UINT dpi_ = USER_DEFAULT_SCREEN_DPI;
  bool dark_mode_ = false;
  std::vector<CandidateSnapshot> candidates_;
};

}  // namespace private_pinyin
