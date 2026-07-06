#include "candidate_window.h"

#include <algorithm>
#include <string>

#include "globals.h"

namespace private_pinyin {

namespace {

constexpr wchar_t kCandidateWindowClass[] = L"PrivatePinyinCandidateWindow";
constexpr int kRowHeight = 28;
constexpr int kWindowWidth = 280;

std::wstring candidate_line(size_t index, const CandidateSnapshot& candidate) {
  return std::to_wstring(index + 1) + L". " + candidate.text + L"  " + candidate.pinyin;
}

}  // namespace

CandidateWindow::~CandidateWindow() {
  if (hwnd_ != nullptr) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void CandidateWindow::show(const std::vector<CandidateSnapshot>& candidates) {
  candidates_ = candidates;
  if (candidates_.empty()) {
    hide();
    return;
  }

  if (!ensure_window()) {
    return;
  }

  POINT caret{100, 100};
  HWND focus = GetFocus();
  if (focus != nullptr && GetCaretPos(&caret)) {
    ClientToScreen(focus, &caret);
  }

  const int visible_count = static_cast<int>(std::min<size_t>(candidates_.size(), 9));
  const int height = 8 + visible_count * kRowHeight;
  SetWindowPos(hwnd_, HWND_TOPMOST, caret.x, caret.y + 24, kWindowWidth, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void CandidateWindow::hide() {
  if (hwnd_ != nullptr) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

bool CandidateWindow::ensure_window() {
  if (hwnd_ != nullptr) {
    return true;
  }

  WNDCLASSW window_class{};
  window_class.lpfnWndProc = CandidateWindow::window_proc;
  window_class.hInstance = g_module;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.lpszClassName = kCandidateWindowClass;
  RegisterClassW(&window_class);

  hwnd_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
                          kCandidateWindowClass, L"", WS_POPUP | WS_BORDER, 100, 100,
                          kWindowWidth, 120, nullptr, nullptr, window_class.hInstance, this);
  return hwnd_ != nullptr;
}

void CandidateWindow::paint() {
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(hwnd_, &paint);
  RECT rect{};
  GetClientRect(hwnd_, &rect);
  FillRect(dc, &rect, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));

  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));

  const size_t visible_count = std::min<size_t>(candidates_.size(), 9);
  for (size_t i = 0; i < visible_count; ++i) {
    RECT row{8, 4 + static_cast<LONG>(i * kRowHeight), kWindowWidth - 8,
             4 + static_cast<LONG>((i + 1) * kRowHeight)};
    std::wstring line = candidate_line(i, candidates_[i]);
    DrawTextW(dc, line.c_str(), static_cast<int>(line.size()), &row,
              DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS);
  }

  EndPaint(hwnd_, &paint);
}

LRESULT CALLBACK CandidateWindow::window_proc(HWND hwnd, UINT message, WPARAM wparam,
                                              LPARAM lparam) {
  auto* window = reinterpret_cast<CandidateWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    window = static_cast<CandidateWindow*>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window));
  }

  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_PAINT:
      if (window != nullptr) {
        window->paint();
        return 0;
      }
      break;
    default:
      break;
  }

  return DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace private_pinyin
