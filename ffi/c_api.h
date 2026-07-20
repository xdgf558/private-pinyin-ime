#ifndef PRIVATE_PINYIN_IME_C_API_H
#define PRIVATE_PINYIN_IME_C_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ImeEngine ImeEngine;
typedef struct ImeSession ImeSession;

// Threading:
// - ImeEngine and ImeSession handles are not thread-safe.
// - Do not call any function concurrently with the same engine or session.
// - Create and use a session on one host thread at a time. Concurrent access to
//   the same handle is outside the ABI contract.
//
// Errors:
// - Pointer-returning functions return NULL for invalid handles, internal
//   errors, or caught Rust panics.
// - Hosts must check every returned pointer before reading it.
// - Free functions accept NULL and do nothing.
//
// Memory:
// - All strings are UTF-8 and owned by their containing ImeOutput.
// - Platform code must not mutate or free strings/candidate arrays directly.
// - Platform code must not cache pointers from ImeOutput after ime_output_free.

typedef enum {
  IME_MODE_CHINESE = 0,
  IME_MODE_ENGLISH = 1
} ImeMode;

typedef enum {
  IME_AI_PLATFORM_MACOS = 1,
  IME_AI_PLATFORM_WINDOWS = 2,
  IME_AI_PLATFORM_IOS = 3
} ImeAiPlatform;

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
  IME_KEY_DIGIT = 101,
  IME_KEY_NINE_KEY_DIGIT = 102
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

// Pass NULL for default settings. Non-NULL config_json_path must point to a
// UTF-8 JSON settings file. Missing, malformed, or invalid settings files fall
// back to built-in defaults; user lexicon database failures may still return
// NULL. The engine snapshots settings at creation time.
ImeEngine* ime_engine_new(const char* config_json_path);
// Optional local AI always falls back to the base engine on verification,
// hardware, queue, timeout, or provider failure. Call before ime_session_new.
// platform must be one of IME_AI_PLATFORM_MACOS, IME_AI_PLATFORM_WINDOWS, or
// IME_AI_PLATFORM_IOS. Returns 1 when enabled and 0 when unavailable.
int ime_engine_enable_local_ai(ImeEngine* engine, int platform,
                               uint64_t physical_memory_mb, int gpu_available);
// Compatibility alias retained for AI-07 desktop hosts.
int ime_engine_enable_desktop_ai(ImeEngine* engine, int platform,
                                 uint64_t physical_memory_mb, int gpu_available);
int ime_engine_clear_user_lexicon(ImeEngine* engine);
int ime_engine_export_user_lexicon(ImeEngine* engine, const char* export_tsv_path);
// Imports explicit-pinyin entries from a user-selected Rime YAML dictionary
// into the separately configured imported_lexicon_path. Returns the number of
// accepted source rows, or -1 on error. Hosts should recreate their engine and
// sessions after a successful import so the new snapshot becomes active.
int ime_engine_import_rime_lexicon(ImeEngine* engine, const char* source_path);
// Removes only the separately configured imported lexicon layer. The bundled
// base lexicon and learned user lexicon remain unchanged. Returns 1 on success.
int ime_engine_clear_imported_lexicon(ImeEngine* engine);
void ime_engine_free(ImeEngine* engine);

ImeSession* ime_session_new(ImeEngine* engine);
void ime_session_free(ImeSession* session);
// Secure fields disable and cancel optional AI work. Base IME input remains active.
int ime_session_set_secure_input(ImeSession* session, int secure_input);
// Overrides the candidate page size for this host session. Returns 1 on
// success; valid values are 1 through the core candidate limit.
int ime_session_set_candidate_page_size(ImeSession* session, int page_size);

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
