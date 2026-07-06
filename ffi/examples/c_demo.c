#include "c_api.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static ImeKeyEvent text_event(const char* text) {
  ImeKeyEvent event;
  event.key_code = IME_KEY_UNKNOWN;
  event.text = text;
  event.shift = 0;
  event.ctrl = 0;
  event.alt = 0;
  event.meta = 0;
  event.is_repeat = 0;
  event.timestamp_ms = 0;
  return event;
}

int main(void) {
  ImeEngine* engine = ime_engine_new(NULL);
  if (engine == NULL) {
    fprintf(stderr, "failed to create engine\n");
    return 1;
  }

  ImeSession* session = ime_session_new(engine);
  if (session == NULL) {
    fprintf(stderr, "failed to create session\n");
    ime_engine_free(engine);
    return 1;
  }

  const char* keys[] = {"n", "i", "h", "a", "o"};
  ImeOutput* output = NULL;
  for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
    if (output != NULL) {
      ime_output_free(output);
    }
    output = ime_session_feed_key(session, text_event(keys[i]));
    if (output == NULL) {
      fprintf(stderr, "feed_key returned null\n");
      ime_session_free(session);
      ime_engine_free(engine);
      return 1;
    }
  }

  if (output->candidate_count <= 0 || output->candidates == NULL ||
      strcmp(output->candidates[0].text, "你好") != 0) {
    fprintf(stderr, "expected candidates for nihao\n");
    ime_output_free(output);
    ime_session_free(session);
    ime_engine_free(engine);
    return 1;
  }

  printf("first candidate: %s (%s)\n", output->candidates[0].text,
         output->candidates[0].pinyin);
  ime_output_free(output);

  output = ime_session_feed_key(session, text_event(" "));
  if (output == NULL || output->should_commit == 0 ||
      output->commit_text == NULL) {
    fprintf(stderr, "expected commit output\n");
    if (output != NULL) {
      ime_output_free(output);
    }
    ime_session_free(session);
    ime_engine_free(engine);
    return 1;
  }

  printf("commit: %s\n", output->commit_text);
  int ok = strcmp(output->commit_text, "你好") == 0;
  ime_output_free(output);
  ime_session_free(session);
  ime_engine_free(engine);

  return ok ? 0 : 1;
}
