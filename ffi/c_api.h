#ifndef PRIVATE_PINYIN_IME_C_API_H
#define PRIVATE_PINYIN_IME_C_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ImeEngine ImeEngine;
typedef struct ImeSession ImeSession;

typedef enum {
  IME_MODE_CHINESE = 0,
  IME_MODE_ENGLISH = 1
} ImeMode;

typedef enum {
  IME_KEY_UNKNOWN = 0,
  IME_KEY_SPACE = 1,
  IME_KEY_ENTER = 2,
  IME_KEY_BACKSPACE = 3,
  IME_KEY_ESCAPE = 4,
  IME_KEY_SHIFT = 5,
  IME_KEY_CTRL_SPACE = 6,
  IME_KEY_CAPS_LOCK = 7,
  IME_KEY_COMMA = 8,
  IME_KEY_PERIOD = 9,
  IME_KEY_MINUS = 10,
  IME_KEY_EQUAL = 11,
  IME_KEY_APOSTROPHE = 12,
  IME_KEY_SEMICOLON = 13,
  IME_KEY_PAGE_UP = 14,
  IME_KEY_PAGE_DOWN = 15,
  IME_KEY_ARROW_UP = 16,
  IME_KEY_ARROW_DOWN = 17,
  IME_KEY_CHARACTER = 100,
  IME_KEY_DIGIT = 101
} ImeKeyCode;

typedef struct {
  int key_code;
  const char* text;
  int shift;
  int ctrl;
  int alt;
  int meta;
  int is_repeat;
  int64_t timestamp_ms;
} ImeKeyEvent;

typedef struct {
  const char* text;
  const char* pinyin;
  double score;
  const char* source;
} ImeCandidate;

typedef struct {
  const char* preedit;
  const char* commit_text;
  ImeMode mode;
  int should_update_preedit;
  int should_commit;
  int should_show_candidates;
  int candidate_count;
  ImeCandidate* candidates;
} ImeOutput;

// Pass NULL for config_json_path in stage 03. Non-NULL config paths are reserved
// for a later settings loader and are currently ignored.
ImeEngine* ime_engine_new(const char* config_json_path);
void ime_engine_free(ImeEngine* engine);

ImeSession* ime_session_new(ImeEngine* engine);
void ime_session_free(ImeSession* session);

ImeOutput* ime_session_feed_key(ImeSession* session, ImeKeyEvent event);
ImeOutput* ime_session_commit_candidate(ImeSession* session, int index);
ImeOutput* ime_session_toggle_mode(ImeSession* session);
ImeOutput* ime_session_reset(ImeSession* session);

// Frees an output and all strings/candidate memory owned by it. Platform code
// must not cache pointers from ImeOutput after calling this function.
void ime_output_free(ImeOutput* output);

#ifdef __cplusplus
}
#endif

#endif
