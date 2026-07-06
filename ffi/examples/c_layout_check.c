#include "c_api.h"

#include <stddef.h>

_Static_assert(sizeof(ImeMode) == 4, "ImeMode size drifted");
_Static_assert(_Alignof(ImeMode) == 4, "ImeMode alignment drifted");

_Static_assert(sizeof(ImeKeyEvent) == 48, "ImeKeyEvent size drifted");
_Static_assert(_Alignof(ImeKeyEvent) == 8, "ImeKeyEvent alignment drifted");
_Static_assert(offsetof(ImeKeyEvent, key_code) == 0, "ImeKeyEvent.key_code offset drifted");
_Static_assert(offsetof(ImeKeyEvent, text) == 8, "ImeKeyEvent.text offset drifted");
_Static_assert(offsetof(ImeKeyEvent, shift) == 16, "ImeKeyEvent.shift offset drifted");
_Static_assert(offsetof(ImeKeyEvent, ctrl) == 20, "ImeKeyEvent.ctrl offset drifted");
_Static_assert(offsetof(ImeKeyEvent, alt) == 24, "ImeKeyEvent.alt offset drifted");
_Static_assert(offsetof(ImeKeyEvent, meta) == 28, "ImeKeyEvent.meta offset drifted");
_Static_assert(offsetof(ImeKeyEvent, is_repeat) == 32, "ImeKeyEvent.is_repeat offset drifted");
_Static_assert(offsetof(ImeKeyEvent, timestamp_ms) == 40, "ImeKeyEvent.timestamp_ms offset drifted");

_Static_assert(sizeof(ImeCandidate) == 32, "ImeCandidate size drifted");
_Static_assert(_Alignof(ImeCandidate) == 8, "ImeCandidate alignment drifted");
_Static_assert(offsetof(ImeCandidate, text) == 0, "ImeCandidate.text offset drifted");
_Static_assert(offsetof(ImeCandidate, pinyin) == 8, "ImeCandidate.pinyin offset drifted");
_Static_assert(offsetof(ImeCandidate, score) == 16, "ImeCandidate.score offset drifted");
_Static_assert(offsetof(ImeCandidate, source) == 24, "ImeCandidate.source offset drifted");

_Static_assert(sizeof(ImeOutput) == 48, "ImeOutput size drifted");
_Static_assert(_Alignof(ImeOutput) == 8, "ImeOutput alignment drifted");
_Static_assert(offsetof(ImeOutput, preedit) == 0, "ImeOutput.preedit offset drifted");
_Static_assert(offsetof(ImeOutput, commit_text) == 8, "ImeOutput.commit_text offset drifted");
_Static_assert(offsetof(ImeOutput, mode) == 16, "ImeOutput.mode offset drifted");
_Static_assert(offsetof(ImeOutput, should_update_preedit) == 20, "ImeOutput.should_update_preedit offset drifted");
_Static_assert(offsetof(ImeOutput, should_commit) == 24, "ImeOutput.should_commit offset drifted");
_Static_assert(offsetof(ImeOutput, should_show_candidates) == 28, "ImeOutput.should_show_candidates offset drifted");
_Static_assert(offsetof(ImeOutput, candidate_count) == 32, "ImeOutput.candidate_count offset drifted");
_Static_assert(offsetof(ImeOutput, candidates) == 40, "ImeOutput.candidates offset drifted");

int main(void) {
  return 0;
}
