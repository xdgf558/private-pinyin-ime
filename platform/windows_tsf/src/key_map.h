#pragma once

#include <string>

#include <windows.h>

#include "c_api.h"

namespace private_pinyin {

struct KeyMessage {
  int key_code = IME_KEY_UNKNOWN;
  std::string text;
  bool shift = false;
  bool ctrl = false;
  bool alt = false;
  bool meta = false;
  bool is_repeat = false;
  long long timestamp_ms = 0;
  bool handled_by_ime = false;
};

KeyMessage map_windows_key(WPARAM key, LPARAM flags);
ImeKeyEvent to_ime_key_event(const KeyMessage& message);

}  // namespace private_pinyin
