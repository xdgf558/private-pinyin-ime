#include "key_map.h"

#include <cctype>

namespace private_pinyin {

namespace {

bool is_down(int virtual_key) {
  return (GetKeyState(virtual_key) & 0x8000) != 0;
}

std::string ascii_text(char ch) {
  return std::string(1, ch);
}

}  // namespace

KeyMessage map_windows_key(WPARAM key, LPARAM flags) {
  KeyMessage message;
  message.shift = is_down(VK_SHIFT);
  message.ctrl = is_down(VK_CONTROL);
  message.alt = is_down(VK_MENU);
  message.meta = is_down(VK_LWIN) || is_down(VK_RWIN);
  message.is_repeat = (flags & (1LL << 30)) != 0;
  message.timestamp_ms = static_cast<long long>(GetTickCount64());

  if (message.ctrl && key == VK_SPACE) {
    message.key_code = IME_KEY_CTRL_SPACE;
    message.handled_by_ime = true;
    return message;
  }

  if (key >= 'A' && key <= 'Z') {
    message.key_code = IME_KEY_CHARACTER;
    message.text = ascii_text(static_cast<char>(std::tolower(static_cast<int>(key))));
    message.handled_by_ime = true;
    return message;
  }

  if (key >= '0' && key <= '9') {
    message.key_code = IME_KEY_DIGIT;
    message.text = ascii_text(static_cast<char>(key));
    message.handled_by_ime = true;
    return message;
  }

  switch (key) {
    case VK_SPACE:
      message.key_code = IME_KEY_SPACE;
      message.text = " ";
      message.handled_by_ime = true;
      break;
    case VK_ESCAPE:
      message.key_code = IME_KEY_ESCAPE;
      message.handled_by_ime = true;
      break;
    case VK_RETURN:
      message.key_code = IME_KEY_ENTER;
      message.text = "\n";
      message.handled_by_ime = true;
      break;
    case VK_BACK:
      message.key_code = IME_KEY_BACKSPACE;
      message.handled_by_ime = true;
      break;
    case VK_SHIFT:
      message.key_code = IME_KEY_SHIFT;
      message.handled_by_ime = true;
      break;
    case VK_OEM_COMMA:
      message.key_code = IME_KEY_COMMA;
      message.text = ",";
      message.handled_by_ime = true;
      break;
    case VK_OEM_PERIOD:
      message.key_code = IME_KEY_PERIOD;
      message.text = ".";
      message.handled_by_ime = true;
      break;
    case VK_OEM_MINUS:
      message.key_code = IME_KEY_MINUS;
      message.text = "-";
      message.handled_by_ime = true;
      break;
    case VK_OEM_PLUS:
      message.key_code = IME_KEY_EQUAL;
      message.text = "=";
      message.handled_by_ime = true;
      break;
    case VK_OEM_7:
      message.key_code = IME_KEY_APOSTROPHE;
      message.text = "'";
      message.handled_by_ime = true;
      break;
    case VK_OEM_1:
      message.key_code = IME_KEY_SEMICOLON;
      message.text = ";";
      message.handled_by_ime = true;
      break;
    case VK_PRIOR:
      message.key_code = IME_KEY_PAGE_UP;
      message.handled_by_ime = true;
      break;
    case VK_NEXT:
      message.key_code = IME_KEY_PAGE_DOWN;
      message.handled_by_ime = true;
      break;
    case VK_UP:
      message.key_code = IME_KEY_ARROW_UP;
      message.handled_by_ime = true;
      break;
    case VK_DOWN:
      message.key_code = IME_KEY_ARROW_DOWN;
      message.handled_by_ime = true;
      break;
    default:
      message.key_code = IME_KEY_UNKNOWN;
      message.handled_by_ime = false;
      break;
  }

  return message;
}

ImeKeyEvent to_ime_key_event(const KeyMessage& message) {
  return ImeKeyEvent{
      message.key_code,
      message.text.c_str(),
      message.shift ? 1 : 0,
      message.ctrl ? 1 : 0,
      message.alt ? 1 : 0,
      message.meta ? 1 : 0,
      message.is_repeat ? 1 : 0,
      message.timestamp_ms,
  };
}

}  // namespace private_pinyin
