#include "candidate_window.h"

#include <algorithm>
#include <atomic>
#include <string>

#include "globals.h"

namespace private_pinyin {

namespace {

constexpr wchar_t kCandidateWindowClass[] = L"PrivatePinyinCandidateWindow";
constexpr int kRowHeight = 28;
constexpr int kWindowWidth = 280;
constexpr int kHorizontalPadding = 10;
constexpr int kVerticalPadding = 6;

std::atomic_bool g_candidate_window_class_registered = false;

std::wstring candidate_line(size_t index, const CandidateSnapshot& candidate) {
  return std::to_wstring(index + 1) + L". " + candidate.text + L"  " + candidate.pinyin;
}

bool register_candidate_window_class() {
  if (g_candidate_window_class_registered.load()) {
    return true;
  }

  WNDCLASSW window_class{};
  window_class.lpfnWndProc = CandidateWindow::window_proc;
  window_class.hInstance = g_module;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.lpszClassName = kCandidateWindowClass;

  const ATOM atom = RegisterClassW(&window_class);
  if (atom == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }

  g_candidate_window_class_registered = true;
  return true;
}

bool apps_use_dark_mode() {
  DWORD value = 1;
  DWORD bytes = sizeof(value);
  const LONG result = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &value, &bytes);
  return result == ERROR_SUCCESS && value == 0;
}

}  // namespace

CandidateWindow::~CandidateWindow() {
  if (hwnd_ != nullptr) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void CandidateWindow::show(const std::vector<CandidateSnapshot>& candidates,
                           const RECT* anchor_rect) {
  candidates_ = candidates;
  if (candidates_.empty()) {
    hide();
    return;
  }

  if (!ensure_window()) {
    return;
  }

  dpi_ = GetDpiForWindow(hwnd_);
  dark_mode_ = apps_use_dark_mode();
  const int visible_count = static_cast<int>(std::min<size_t>(candidates_.size(), 9));
  const int width = scale(kWindowWidth);
  const int height = scale(kVerticalPadding * 2) + visible_count * scale(kRowHeight);
  POINT anchor = anchor_point(anchor_rect);
  clamp_to_work_area(&anchor, width, height);

  SetWindowPos(hwnd_, HWND_TOPMOST, anchor.x, anchor.y, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void CandidateWindow::hide() {
  if (hwnd_ != nullptr) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

void CandidateWindow::unregister_window_class() {
  if (g_candidate_window_class_registered.exchange(false)) {
    UnregisterClassW(kCandidateWindowClass, g_module);
  }
}

bool CandidateWindow::ensure_window() {
  if (hwnd_ != nullptr) {
    return true;
  }

  if (!register_candidate_window_class()) {
    return false;
  }

  hwnd_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
                          kCandidateWindowClass, L"", WS_POPUP, 100, 100,
                          kWindowWidth, 120, nullptr, nullptr, g_module, this);
  return hwnd_ != nullptr;
}

POINT CandidateWindow::anchor_point(const RECT* anchor_rect) const {
  if (anchor_rect != nullptr) {
    return POINT{anchor_rect->left, anchor_rect->bottom + scale(4)};
  }

  POINT caret{scale(100), scale(100)};
  HWND focus = GetFocus();
  if (focus != nullptr && GetCaretPos(&caret)) {
    ClientToScreen(focus, &caret);
    caret.y += scale(24);
  }
  return caret;
}

void CandidateWindow::clamp_to_work_area(POINT* point, int width, int height) const {
  if (point == nullptr) {
    return;
  }

  HMONITOR monitor = MonitorFromPoint(*point, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    return;
  }

  const RECT& area = monitor_info.rcWork;
  point->x = std::clamp(point->x, area.left, std::max(area.left, area.right - width));
  point->y = std::clamp(point->y, area.top, std::max(area.top, area.bottom - height));
}

int CandidateWindow::scale(int value) const {
  return MulDiv(value, static_cast<int>(dpi_), USER_DEFAULT_SCREEN_DPI);
}

void CandidateWindow::paint() {
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(hwnd_, &paint);
  RECT rect{};
  GetClientRect(hwnd_, &rect);

  const COLORREF background = dark_mode_ ? RGB(32, 32, 32) : GetSysColor(COLOR_WINDOW);
  const COLORREF border = dark_mode_ ? RGB(82, 82, 82) : GetSysColor(COLOR_ACTIVEBORDER);
  const COLORREF text = dark_mode_ ? RGB(242, 242, 242) : GetSysColor(COLOR_WINDOWTEXT);

  HBRUSH background_brush = CreateSolidBrush(background);
  HBRUSH border_brush = CreateSolidBrush(border);
  FillRect(dc, &rect, background_brush);
  FrameRect(dc, &rect, border_brush);

  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, text);

  const size_t visible_count = std::min<size_t>(candidates_.size(), 9);
  for (size_t i = 0; i < visible_count; ++i) {
    RECT row{scale(kHorizontalPadding),
             scale(kVerticalPadding) + static_cast<LONG>(i * scale(kRowHeight)),
             rect.right - scale(kHorizontalPadding),
             scale(kVerticalPadding) + static_cast<LONG>((i + 1) * scale(kRowHeight))};
    std::wstring line = candidate_line(i, candidates_[i]);
    DrawTextW(dc, line.c_str(), static_cast<int>(line.size()), &row,
              DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS);
  }

  DeleteObject(border_brush);
  DeleteObject(background_brush);
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
