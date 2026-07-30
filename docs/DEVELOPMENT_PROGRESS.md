# Development Progress

Last updated: 2026-07-31
Current stage: iOS 0.1.31 (27) TestFlight release preparation
Current status: Release metadata now includes the stable-height and safe-document-identity work from PR #64. Archive, upload, processing, and exact physical-device X Publish/Send verification remain in progress.

## iOS 0.1.31 (27) TestFlight Release Preparation (2026-07-31)

- Advanced both the container App and Keyboard Extension from `0.1.30 (26)` to
  `0.1.31 (27)`.
- Updated the in-App About page to describe safe nullable document identity,
  non-empty delayed-callback matching, one stable portrait height across the
  four primary keyboard surfaces, and the retained 44-point minimum touch
  target.
- Exact X Publish/Send behavior remains a physical-device TestFlight gate and
  is not inferred from the equivalent Simulator diagnostic flow.

## iOS Stable-Height Transition and Callback Regression (2026-07-30)

- Traced one remaining source of host movement to the extension's own portrait
  height contract: QWERTY requested `278` points while nine-key and expanded
  candidates requested `310`. QWERTY, nine-key, symbols, and expanded
  candidates now share one `278`-point portrait height; compact landscape
  remains `216` and inline preferences remain `368`. Repeated refreshes leave
  an unchanged height constraint untouched.
- Replaced the controller's ad hoc self-text callback counters with a focused
  `SelfTextChangeTracker`. Delayed callbacks are suppressed only when they
  match the latest non-empty post-operation context and a safely available
  public document UUID inside the bounded callback window. Host clear/send
  transitions, empty or nil contexts, expired evidence, old contexts, and
  replaced documents fail closed as external changes. The visible cost is
  intentional: deleting to an empty field or switching between empty fields
  resets composition and freezes stale controls until the next presented key,
  which then restores the live surface.
- The first interactive Simulator run exposed a real activation crash rather
  than a source-only concern. During document attachment/reset, the simulator
  host exposed a nil Objective-C `documentIdentifier` even though Swift imports
  it as non-optional `UUID`; reading it trapped in
  `UUID._unconditionallyBridgeFromObjectiveC`. A nullable Objective-C helper
  now reads that same public API without the unconditional Swift bridge. DEBUG
  evidence also confirmed that `ObjectIdentifier(textDocumentProxy)` remained
  unchanged across attachment callbacks, so it is retained only as a cheap
  proxy-liveness signal and is not treated as the document identity.
- Added a DEBUG `模拟发送并收起` host action that clears both diagnostic fields
  and drops focus on the following main-loop turn. This reproduces the
  observable X-style sequence without claiming to reproduce X internals.
- Actual iPhone 17 Pro / iOS 26.5 Simulator verification used the rebuilt
  custom Keyboard Extension. QWERTY `nihao` displayed `ni hao` / `你好` and
  committed once; direct field switching reset the old composition and
  accepted a fresh `nihao`; the simulated Send action cleared the document
  and dismissed the keyboard; refocus restored the custom surface; and
  custom -> system English -> custom switching returned a complete responsive
  keyboard. A 100-ms frame sample of the recorded run showed one monotonic
  dismissal and one monotonic presentation, with no reverse movement or
  second height pull.
- A DEBUG geometry probe measured the rendered surfaces rather than only the
  requested constraint. QWERTY, nine-key, symbols, and expanded candidates
  each reported `view=278`, `root=258`, and `clipped=false`; minimum visible
  button heights were `44`, `44`, `44`, and `49` points respectively. The
  probe now fails immediately if any surface clips or any visible button drops
  below the 44-point minimum, rather than relying on a reviewer to notice a
  changed log value.
- A rebuilt custom nine-key surface was then exercised through the container
  App rather than inferred from source: `64426` displayed `ni hao` and committed
  exactly one `你好`; a live field switch replaced stale composition on the
  first delivered key; delete-to-empty followed by `6` resumed candidates
  without deleting host text; and the simulated send/dismiss could reopen the
  same custom keyboard and commit another `你好`.
- `scripts/check_ios_keyboard_sources.sh`, the standalone
  `SelfTextChangeTracker` regression, and the Xcode 26.6 iOS 26.5 Simulator
  App/Keyboard Extension build passed. The exact X App Publish/Send animation
  and physical display timing are not available in Simulator and remain the
  final device check.

## iOS 0.1.30 (26) TestFlight Upload (2026-07-29)

- Advanced both the container App and Keyboard Extension from `0.1.29 (25)` to
  `0.1.30 (26)`. The in-App About page now records the final X Publish/Send
  lifecycle guard, bounded rapid-input frame coalescing, pending-composition
  Backspace protection, and larger outer hit regions for punctuation keys.
- Passed `scripts/run_ios_smoke_readiness.sh` with Xcode 26.6 (`17F109`) and
  the iPhoneSimulator 26.5 SDK. The source contract, Rust simulator core,
  container App, and Keyboard Extension all passed; bundle IDs, App Group
  entitlement, and `RequestsOpenAccess=false` remained intact.
- Rebuilt the device Rust FFI for `aarch64-apple-ios` with iOS 18 minimum and
  `ios-ai`, then created the signed arm64 archive at
  `dist/ios/PrivatePinyin-0.1.30-build26-xcode26.xcarchive`. Archive metadata
  for both the App and extension reports `0.1.30 (26)`.
- Uploaded through `xcodebuild -exportArchive` with
  `manageAppVersionAndBuildNumber=false`. Xcode reported `Upload succeeded`
  and delivery UUID `08a2fbb8-ff3c-4b06-94ae-0814dcbf492c`; App Store Connect
  accepted the package into processing without upload errors.
- Apple processing, TestFlight group assignment, external Beta App Review, and
  physical-device acceptance remain separate pending steps. The device matrix
  still covers X Publish/Send dismissal timing, warm field switching, rapid
  full-key and nine-key input, punctuation hit regions, and the intentional
  absence of haptics while Full Access remains disabled.

## iOS Nine-Key and X Dismissal Follow-up (2026-07-29)

- A physical-device retest still reproduced visible host pulling in X after
  Publish/Send. The previous 50 ms document-change thaw remained a timing
  heuristic: X can stay in the visible presentation phase beyond that window,
  allowing a deferred candidate, key-state, height, and root-layout refresh
  before its later disappearance callback.
- Removed timer-based document thaw entirely. External `textWillChange` keeps
  surface geometry frozen through `textDidChange`; only a real
  `viewWillAppear`/`viewDidAppear` transition or the next key delivered while
  the extension is presented can recover the warm surface. Logical reset work
  still completes off-main. During a same-App field switch, the prior
  candidate frame is deliberately retained but immediately dimmed and made
  noninteractive; the first key restores the surface from cleared logical
  state instead of presenting a false actionable candidate.
- The shared Rust release benchmark remains well below the 60 ms budget:
  correction-on medians measured `0.334 ms/key` for 21 digits,
  `0.331 ms/key` at the 24-digit correction ceiling, and `0.420 ms/key` for
  64 digits; correction-off measured `0.315`, `0.298`, and `0.423 ms/key`
  respectively. This rules out the incremental lattice as the source of the
  newly reported touch lag.
- The iOS host now coalesces superseded nine-key digit and Backspace output
  frames while preserving serial core execution and the final candidate
  result. A coalesced completion is discarded only when `shouldCommit` is not
  true; fallback insertion and `afterApply` state-release paths are never
  eligible. Full-key and nine-key operations that can create composition are
  tracked by operation identity until their main-thread completion, so
  Backspace cannot mistake an asynchronous composition for an empty field and
  delete surrounding host text.
- Added `ApplyCoreOutput`, `UpdateCandidateBar`, `CoreOutputCoalesced`, and
  `NineKeyRenderSmoke` signposts plus a DEBUG counter probe. On the same iOS
  26.5 iPhone 17 Pro Simulator Debug build, an instant synthetic `64426`
  baseline completed 5 core outputs and performed 5 `apply` plus 5 candidate
  bar updates. With coalescing enabled, all 5 core outputs still completed,
  4 superseded frames were discarded, and only 1 `apply` plus 1 candidate bar
  update ran: an 80% reduction in main-thread output/render passes. These
  counts establish the host-side work reduction; physical X animation timing
  still requires a TestFlight trace.
- A separate DEBUG simulator probe inserted a host-document sentinel, queued
  rapid tracked/coalescible `644`, and invoked Backspace before those outputs
  completed. The probe reported
  `PRIVATE_PINYIN_PENDING_BACKSPACE_SMOKE host_text_preserved=true`, proving
  that the in-flight operation guard kept Backspace inside the core instead
  of deleting surrounding host text.
- Because the shipping extension keeps `RequestsOpenAccess=false`, UIKit
  feedback is unavailable. Selection/impact calls and preparation are now
  skipped in that state. This closes the misleading haptic path rather than
  claiming a material latency gain; ordinary input remains independent of
  tactile feedback.
- Validation passed with `cargo test --workspace`,
  `cargo clippy --workspace --all-targets -- -D warnings`,
  `cargo fmt --all -- --check`, the iOS source contract, and the full
  simulator smoke-readiness script. On an iOS 26.5 iPhone 17 Pro simulator,
  rapid `64426`, Backspace/retype, exactly-once `你好` commit, and direct
  two-field warm reuse all passed. X Publish/Send remains a required physical
  device check because the host app and its dismissal timing are unavailable
  in Simulator.

## macOS 0.1.29 Public Package (2026-07-29)

- Advanced the macOS App and installer receipt to `0.1.29 (29)`. The
  preferences release notes now cover bounded full-key typo correction,
  opt-in tolerant pinyin, a stable Space-key default, gentle-learning
  hysteresis, and prediction-safe blind-typing digits while retaining the
  reviewed White Frost, Writer V1, AI Lite, and tiered-preferences features
  from `0.1.28`.
- Passed the macOS host source contract, TYPO-01 and ABC-01 through ABC-04
  source gates, `cargo test --workspace`, `cargo fmt --all -- --check`,
  `git diff --check`, and a complete macOS host build.
- Signed the App and nested Writer runtime with Developer ID Application and
  the installer with Developer ID Installer. Apple notarization submission
  `4177a643-7161-4994-b3a0-9973865d766f` completed with `Accepted`, and the
  ticket was stapled successfully.
- Final release validation passed: the installer certificate is trusted,
  expanded-payload signatures satisfy their designated requirements,
  Gatekeeper reports `Notarized Developer ID`, and `stapler validate`
  succeeds.
- Artifact: `dist/macos_imk/PrivatePinyin-0.1.29.pkg` (`14,470,598` bytes);
  SHA-256
  `a2e036f668dec4e15058db51f3caeacd3722a2131462752a7cbc5d15bef60832`.

## iOS Inset-Row Hit Target Follow-up (2026-07-29)

- Traced an untappable full-key symbol-page period to the same visual inset
  boundary that previously affected `A`. Only the letter keys `A` and `L` had
  hard-coded edge expansion, so taps in the symbol row's empty left margin
  never reached `.`.
- Replaced the letter-specific workaround with one row-level rule. Whenever a
  QWERTY row has a visual horizontal inset, its first and last key extend only
  into the corresponding unused outer margin. This covers `A`, `L`, `.`, and
  `/` without overlapping adjacent keys.
- The existing iOS 17.5+ view-attached UIKit feedback calls remain fail-soft,
  but the shipping extension deliberately keeps `RequestsOpenAccess=false`.
  Physical haptic output is therefore not a release promise in the current
  privacy configuration, and testers should not troubleshoot its absence
  through system haptic settings. Requesting Full Access solely for tactile
  feedback is deferred to a separate Owner-approved privacy decision.
- Strengthened `scripts/check_ios_keyboard_sources.sh` by reusing the
  string/comment-aware brace parser from ABC-04. The source contract now
  verifies that row layout margins and both outer hit-test expansions consume
  the same `horizontalInset`, and scopes the legacy `A`/`L` prohibition to
  `makeKeyButton`.
- Re-ran `scripts/check_ios_keyboard_sources.sh`, the Xcode 26.5 iOS Simulator
  build, and `git diff --check`; all passed after the review closure.

## iOS 0.1.29 (25) TestFlight Upload (2026-07-29)

- Advanced both the container App and Keyboard Extension from `0.1.28 (24)` to
  `0.1.29 (25)`. The in-App About page now summarizes candidate stability,
  opt-in tolerant pinyin, gentle learning hysteresis, blind-typing digit
  behavior, and the latest host-transition fixes.
- Passed `scripts/run_ios_smoke_readiness.sh` with Xcode 26.6 (`17F109`) and
  the iPhoneSimulator 26.5 SDK. The Rust simulator core, container App, and
  Keyboard Extension built successfully; bundle IDs, App Group entitlement,
  and `RequestsOpenAccess=false` remained intact.
- Rebuilt the device Rust FFI for `aarch64-apple-ios` with iOS 18 minimum and
  `ios-ai`, then created the signed arm64 archive at
  `dist/ios/PrivatePinyin-0.1.29-build25-xcode26.xcarchive`.
- Uploaded through `xcodebuild -exportArchive` with
  `manageAppVersionAndBuildNumber=false`. Xcode reported `Upload succeeded`
  and delivery UUID `441154bb-bb6f-401b-911c-fad50df37261`; no upload error was
  returned.
- App Store Connect processing, TestFlight group assignment, and external Beta
  App Review remain separate pending steps. Physical-device acceptance still
  covers X Publish/Send dismissal timing, field switching, haptic feedback,
  tolerant-input settings, learning hysteresis, and prediction-only number-page
  entry.

## ABC-04 Blind-Typing Interaction and Acceptance (2026-07-28)

- Added a shared numbered-candidate mapping policy. Physical keys `1` through
  `9` can select only a slot that exists on the current visible page; an
  unavailable slot preserves the active composition, page, and candidate
  identities.
- Replaced implicit candidate-zero literals in the Space path with the named
  blind-default index, and reused that same identity for punctuation commit.
  Space commits candidate one for an active composition, commits raw input when
  no candidate exists, and remains a literal space when only idle prediction
  candidates are visible.
- Separated desktop composition state from prediction-only state. Physical
  digits select current-page candidates only while pinyin is being composed;
  after a commit, macOS and Windows pass the digit to the host even if next-word
  predictions remain visible. The shared core also leaves those predictions
  untouched if a stale or direct C ABI caller submits an idle digit.
- Applied the same boundary to the iOS on-screen number page. A digit may select
  a numbered candidate only while `currentPreedit` contains a real composition;
  prediction-only state inserts the literal digit instead of consuming it or
  committing an advisory prediction.
- Added a dedicated integration suite covering Space exactly once, every
  visible numbered slot, out-of-range fail-closed behavior, page-relative
  selection, Enter raw commit, Escape cancellation, Backspace/retype identity,
  punctuation default alignment, nine-key Space, prediction-state digit
  passthrough, and explicit prediction selection through the candidate API.
- Repeated Space, number, Enter, and Escape traces through the C ABI used by
  macOS, Windows, and iOS so host bindings cannot appear correct while the
  exported behavior differs.
- Documented the deliberate lower-candidate boundary: candidate one is stable
  for a fixed snapshot, while candidates two through nine are guaranteed not
  to move after display but may change before display or after context,
  settings, or learning changes.
- Added one release-smoke row per platform and a standalone acceptance record
  covering desktop native/Chromium hosts plus iOS QWERTY, nine-key, compact,
  expanded, warm-reuse, and process-recreation paths. Evidence remains
  content-free.
- Validation passed with `cargo test --workspace`, desktop-AI and iOS-AI C ABI
  feature suites, workspace and feature-specific Clippy under `-D warnings`,
  ABC-01 through ABC-04 source gates, and the existing macOS, Windows, and iOS
  host source contracts. The macOS host app built successfully, and the iOS
  simulator app plus keyboard extension built successfully with Xcode 26.6 and
  the iPhoneSimulator 26.5 SDK. The ABC-04 gate now parses scoped function
  bodies while ignoring braces inside strings and comments, and explicitly
  checks the iOS digit mapping, fallback boundary, and candidate-tap guard.

## ABC-03 Gentle Learning (2026-07-28)

- Added one shared effective-learning-weight policy to the Rust ranker. Raw
  SQLite frequency and 30-day-half-life weight remain the source of truth, but
  the first two decayed observations contribute zero ranking weight. The third
  confirmation begins with the same effective weight that one observation
  contributed before ABC-03.
- Added a persisted maturity bit to direct phrase, bigram, trigram, and
  short-phrase learning rows. New or inactive identities activate at weight
  3.0, remain active while decaying through the 2.0-3.0 hysteresis band, and
  deactivate only below 2.0. A deactivated identity must reach 3.0 again, so a
  moderate habit cannot repeatedly flip the Space-key default near one hard
  boundary.
- Applied the policy to exact and prefix user candidates, bigram predictions,
  short-phrase predictions, trigram predictions, and continuous sentence
  transitions. A single accidental choice can therefore be remembered without
  taking over the Space-key default or the next-word default.
- Kept one learning store and the existing three-platform `用户学习` control.
  The idempotent schema migration marks only old rows with current decayed
  weight at least 3.0 as mature. Lower-weight long-tail rows remain stored but
  can stop affecting ordering immediately after upgrade; stronger recent
  habits stay active. Strict privacy and disabled learning still prevent all
  writes, while export and capacity eviction continue to use raw local
  history.
- Prevented optional AI Lite from bypassing the warm-up period. User and
  learned-prediction candidates expose only effective learning weight to the
  feature adapter; warm-up rows do not receive the user-frequency, bigram, or
  trigram feature boosts.
- Added integration coverage proving `shi -> 时` leaves `是` and the complete
  base order unchanged after confirmations one and two, then promotes `时`
  after confirmation three. Bigram, trigram, short-phrase, and ambiguous
  continuous-transition tests exercise the same `1/2 unchanged, 3 active`
  boundary.
- Added a migration regression starting from a pre-ABC-03 database. It proves
  a two-use long-tail identity remains present but inactive while a stronger
  current identity is migrated as mature. A separate hysteresis regression
  proves an active weight of 2.5 remains stable, a weight below 2.0
  deactivates, one later confirmation is insufficient, and reaching 3.0 again
  reactivates without deleting lifetime history.
- Added a narrow 0.001 threshold tolerance and regression for the decay accrued
  while three immediate confirmations cross separate SQLite writes. This keeps
  normal interaction and slower CI scheduling from requiring a fourth
  confirmation, while two confirmations remain structurally unable to mature.
- Validation passed with `cargo test --workspace`, the desktop-AI and iOS-AI
  FFI feature suites, workspace and feature-specific Clippy with warnings
  denied, the ABC-03/macOS/iOS/Windows source gates, a complete macOS app
  build, and an unsigned iOS simulator app/keyboard build using Xcode 26.6.

## ABC-02 Tolerant Input (2026-07-27)

- Activated the existing `fuzzy_pinyin` schema as a default-off production
  feature for the bidirectional `zh/z`, `ch/c`, `sh/s`, `n/l`, `an/ang`,
  `en/eng`, and `in/ing` pairs. Each generated path changes one complete legal
  syllable only; combinations of multiple fuzzy edits are deliberately
  excluded.
- Kept the ordinary parser, continuous lattice, candidate ordering, and
  ABC-01 Space-key default authoritative. The postpass examines at most 16
  alternate spellings, appends at most two exact base/user-lexicon matches, and
  shares the existing one-correction compact-page/two-correction wide-page
  visibility policy with TYPO-01.
- Added an exact-only packed-index lookup for base candidates and an exact
  SQLite `pinyin` query for learned candidates. This avoids rerunning the
  continuous decoder for every fuzzy variant and keeps user-selected local
  phrases eligible without introducing a second store.
- Added one master `宽容拼音` control to macOS, Windows, and the iOS container
  App. The control defaults off. Existing hand-edited individual fuzzy-pair
  values are preserved until the user explicitly changes the master control,
  at which point all seven reviewed pairs are changed together.
- Added deterministic generation, bidirectional-pair, single-edit, bounds,
  redacted-debug, ordinary-order preservation, stable-default, exact commit,
  disabled-mode, and Apple latency regressions. The raw preedit remains exactly
  what the user typed. Functional and three-platform smoke coverage uses the
  two-letter `la` -> `那` `n/l` case while TYPO-01 remains enabled, so the
  older `zongguo` common-confusion rule cannot satisfy ABC-02 validation.
- Documented the shared visibility priority: TYPO-01 candidates consume
  correction slots first, and ABC-02 fills only remaining allowance.
- On the development Apple host, a 24-key input
  (`sansansansansansansansan`) that exercises the full 16-variant allowance
  was measured with a real temporary SQLite user lexicon enabled for both
  sides. The unoptimized Rust test-profile median was `2.519441 ms/key`
  enabled versus `1.296113 ms/key` disabled. The optimized release-profile
  median was `0.616428 ms/key` enabled versus `0.402756 ms/key` disabled. These
  local references are not device claims; the existing Apple-only `60 ms/key`
  ceiling remains unchanged.
- Passed `cargo test --workspace`, the desktop-AI and iOS-AI FFI feature
  suites, workspace plus feature-specific Clippy with warnings denied,
  formatting, installer/macOS/iOS source gates, the ABC-02 source contract,
  and `git diff --check`. The unsigned macOS IMK App and Xcode 26.6 iOS 26.5
  simulator App/Keyboard Extension also built successfully with the new shared
  core and platform controls.

## ABC-01 Candidate Stability (2026-07-27)

- Added one shared candidate-page stability policy rather than duplicating
  host-specific rules. The policy validates an exact permutation, pins original
  index zero as the Space-key default, and permits optional ranking changes only
  among lower candidates.
- Applied the policy after AI response identity/text validation and also inside
  the public Rust session reorder API. AI Lite canonicalizes its proposal before
  updating both the session and host output, while any future direct caller that
  tries to move index zero is rejected without mutation. A delayed or reversed
  AI Lite result therefore cannot change what Space commits, while AI Lite can
  still improve candidates two through nine before first display.
- Kept ordinary base ranking semantics intact. New input, changed context, or a
  changed learning snapshot still receives a complete fresh ranking; ABC-01
  promises repeatability only when those inputs are the same.
- Added fail-closed unit coverage for incomplete, duplicate, out-of-range, and
  default-moving permutations; a reversed-AI regression that commits the
  original default; full candidate-`id` equality after Backspace/retype and a
  separately initialized engine replay; and paging coverage proving the full
  list is unchanged while the displayed selection commits exactly once.
- Passed all 44 production candidate tests, `cargo test --workspace`, desktop
  AI and iOS AI FFI feature suites, workspace plus feature-specific Clippy with
  warnings denied, formatting, the new ABC-01 source gate, the existing AI-07
  and AI-08 integration gates, and `git diff --check`. The unsigned macOS IMK
  App and Xcode 26.6 iOS 26.5 simulator App/Keyboard Extension also built
  successfully against the updated shared core.

## iOS Physical Host-Submission Follow-up (2026-07-27)

- The physical-device X retest of TestFlight `0.1.28 (24)` still showed about
  one second of host-view pulling after Publish. The supplied capture shows
  that the custom keyboard has disappeared while X remains in its
  `正在发送帖子...` transition.
- The remaining race precedes `viewWillDisappear`: X can issue an external
  document change first, allowing a queued reset completion to touch keyboard
  height and root-stack layout before the previous freeze boundary activates.
- The extension now freezes its visible surface at the start of external
  `textWillChange`, records explicit detached/appearing/visible/disappearing
  presentation phases, and permits delivered-key recovery only while the
  keyboard is actually presented. Queued core work may update logical state
  while frozen but cannot change the host's dismissal geometry.
- Closed the same-App field-switch side effect found in review. After
  `textDidChange`, the extension waits for a bounded 50 ms presentation-state
  settling window, then thaws and clears the old candidate surface only if its
  presentation phase is still `visible`; a phase that has advanced to
  `disappearing` or `detached` remains frozen. The revision guard also prevents
  a delayed thaw from applying after newer input work.
- The 50 ms window is a reviewed host-lifecycle heuristic, not proof of X's
  callback timing. If the physical-device pull remains, record timestamps for
  `textDidChange`, `viewWillDisappear`, and the queued core-reset completion;
  a disappearance arriving after this window is the first residual race to
  investigate.
- Replaced unassociated feedback-generator construction with the iOS 17.5+
  view-attached UIKit APIs and re-prepares them after presentation. Physical
  feedback remains subject to the device's system haptic settings and needs a
  real-device check. The project already has an iOS 18 minimum deployment
  target, so this API does not raise the supported system version.
- Removed the compact candidate strip's previous/next arrows. The downward
  entry remains the single route to the expanded 3-by-3 candidate grid, whose
  own page controls continue to expose later groups. Its VoiceOver hint now
  explicitly identifies those previous/next controls.
- A clean Xcode 26.6 arm64 iOS 26.5 simulator build passed. Simulator smoke
  confirmed compact `hai` candidates expose only the downward entry, the
  expanded grid retains later-page navigation, and a warm keyboard can dismiss,
  return, and produce a fresh `ni` composition and candidates.

## iOS 0.1.28 (24) TestFlight Upload (2026-07-27)

- Advanced both the container App and Keyboard Extension to `0.1.28 (24)`.
  The in-App About page now records full-key pinyin correction, bounded
  nine-key correction, and smoother keyboard submission/transitions as this
  release's update summary.
- Xcode 26.6 (`17F109`) built the Release Rust device library with `ios-ai`,
  passed the full iOS smoke-readiness gate, and archived the arm64 container
  App and keyboard extension with an iOS 18 minimum.
- Archive, App, and extension metadata all report `0.1.28 (24)`. The signed
  archive is
  `dist/ios/PrivatePinyin-0.1.28-build24-xcode26.xcarchive`.
- Xcode re-signed the upload with the managed Apple Distribution identity and
  uploaded it successfully to App Store Connect. Delivery
  `a0389de8-7ca4-4818-92fb-c8994e07245c` entered TestFlight processing without
  upload errors.

## Windows White Frost Import Diagnostics (2026-07-27)

- Reproduced the fixed official White Frost 1.0.4 asset as 44,008,360 bytes with SHA-256 `4f4998ae83f63d757c0a4ace192f69d48265bddfabe231642b73e3739ed0f2f5`.
- Re-ran the production importer successfully: 653,308 accepted rows, 653,136 unique phrase/pinyin identities, and an 18,083,664-byte canonical `rime_frost.tsv`.
- Replaced `Start-Process -ArgumentList` with native array invocation so Windows profile and temporary paths containing spaces remain single arguments, and quoted the remaining Notepad configuration-file path.
- Added conditional TLS 1.2 compatibility to both White Frost and Writer downloads. Modern `SystemDefault` negotiation remains untouched; only legacy explicit protocol sets missing TLS 1.2 are extended.
- Added bounded stage-specific failures and a Windows CI self-test that exercises both successful space-containing arguments and a deliberate nonzero settings-tool exit.

## iOS Host Submission Transition Smoothing (2026-07-27)

- Traced the reported X compose-screen pull after tapping Publish to visible
  keyboard work continuing during the host's dismissal transition. External
  `textWillChange` callbacks cleared the candidate hierarchy immediately, while
  asynchronous core reset results could refresh key state during the same
  system animation.
- Split logical document invalidation from visible surface refresh. The
  extension now waits for `textDidChange`, defers that refresh by one main-loop
  turn, and rejects stale document revisions before touching the surface.
- Freeze candidate visibility, key state, minimum-height changes, keyboard
  rebuilds, and gradient-frame redraw while the input view is disappearing.
  Deferred work is coalesced into one animation-free refresh when the keyboard
  next appears, preserving the final dismissal frame without retaining stale
  composition in the next field.
- Closed the warm-reuse thaw gap identified in review. Both appearance
  callbacks now resume the surface idempotently, while a delivered key event
  provides a final recovery path if a host reuses the controller without the
  normal callback pair. Resuming explicitly requests a layout pass so a bounds
  change made while frozen cannot leave the tray gradient stale.
- Restored the symmetric `super.textWillChange` lifecycle call and extended
  the source gate to require freeze, thaw, active-key recovery, and layout
  recovery contracts.
- Added iOS source gates for the dismissal lifecycle contract and a dedicated
  host-submit smoke row covering X-style compose screens.
- Xcode 26.6 (`17F109`) rebuilt the App and extension successfully. On an
  iPhone 17 Pro / iOS 26.5 simulator, the real custom nine-key surface entered
  `64426`, ranked and committed exactly one `你好`, then dismissed while the
  host navigated away from the focused field. The destination page completed
  the transition without a second visible pull, Auto Layout warning, or crash.
  Returning from that page reused the same warm keyboard surface; a second
  `64426` immediately restored the live `ni hao` / `你好` strip and committed
  once, leaving the diagnostic field at `你好你好`.
  Physical-device X Publish confirmation remains required because simulator
  host Apps cannot reproduce X's exact publishing transition.

## NINEKEY-TYPO-01 Bounded Nine-Key Correction (2026-07-27)

- Added a shared Rust correction postpass for one missing digit, one extra
  digit, an adjacent keypad substitution, or an adjacent digit transposition.
  Only `2` through `9` are accepted; work stops after 24 digits, 64 exact-index
  viability attempts, and two accepted correction candidates.
- Kept corrections outside the incremental nine-key lattice. Ordinary exact,
  continuous, and prefix candidates are decoded and capped first, then
  corrections are appended and optionally promoted into one compact-page slot
  or two wide-page slots without changing the relative order or reachability of
  any ordinary candidate.
- Added a conservative ambiguity rule: when the typed signature already has an
  exact reading, correction must produce a multi-character, multi-syllable
  entry. This lets `6426` expose `你好` through missing-digit `64426` without
  turning valid ambiguous signatures such as `636` into an automatic
  single-character `猫` correction.
- Reused the existing default-on `拼音智能纠错` setting on macOS, Windows, and
  iOS. Turning it off restores the exact pre-stage output. Strict privacy keeps
  the stateless local path available; digit signatures and candidate content
  are neither logged nor persisted.
- Added full ordinary-candidate equivalence checks, all four edit-family
  fixtures, disabled-setting coverage, exact single-commit behavior, redacted
  debug output, the exact 64-attempt ceiling, and cached/stateless equality
  across append, Backspace, and retype.
- Reserved twelve viability attempts for every edit family before allowing
  earlier generators to consume unused capacity. Missing-digit insertion,
  extra-digit removal, transposition, and substitution therefore remain
  reachable at the 24-digit limit while the global 64-attempt ceiling stays
  unchanged. Completed the keypad adjacency map with bidirectional `2`/`6`.
- On the development Apple host in the unoptimized Rust test profile, median
  incremental cost with correction enabled was `0.851750 ms/key` for the
  21-key sentence, `0.819333 ms/key` at the 24-key correction ceiling, and
  `0.842667 ms/key` at the 64-key maximum, versus `0.724916`, `0.659917`,
  and `0.785791 ms/key` with correction disabled.
- On the same host in the optimized release profile, medians were
  `0.243625`, `0.236208`, and `0.278958 ms/key` with correction enabled,
  versus `0.228125`, `0.211083`, and `0.272542 ms/key` disabled. These are
  local Rust references, not real-device claims; the Apple-only regression
  retains the unchanged `60 ms` per-key budget.
- Passed `cargo test --workspace`, workspace Clippy with warnings denied,
  formatting, desktop-AI and iOS-AI FFI feature tests, TYPO-01 and
  NINEKEY-TYPO-01 source gates, and the iOS keyboard source contract. Xcode
  26.6 also built the iOS simulator container App and keyboard extension
  successfully against the shared Rust release library.

## TYPO-01 Bounded Full-Keyboard Correction (2026-07-26)

- Reused the reviewed first-party AI-04 correction table in the production Rust
  core, then added bounded duplicate-key removal, adjacent QWERTY-key
  substitution, and neighboring-letter transposition for otherwise invalid
  full-keyboard input.
- Required corrected spellings to produce a complete parser result and an exact
  production-lexicon pinyin identity. Generic edits are disabled for already
  valid full pinyin, apostrophe input, non-ASCII input, and input longer than 24
  characters.
- Preserved the raw composition and complete original candidate sequence.
  TYPO-01 adds no more than two correction candidates. Five-item pages reserve
  only one visible correction slot while wider pages may expose two; remaining
  corrections stay reachable after the original paths instead of being
  truncated.
- Bounded actual complete-pinyin parser attempts to 64 per lookup, independently
  of how many suggestions are accepted. Candidate spellings are deduplicated
  before parser work, so repeated rules and generic edits cannot spend the
  budget more than once on the same spelling.
- Added independent default-on typo-correction controls to macOS, Windows, and
  the iOS container App. Strict privacy continues to permit this stateless,
  local-only path while disabling learning, statistics, and Writer content
  actions.
- Added exact/probable/weak correction metadata and wired it into the existing
  AI Lite `typo_correction` feature. AI Lite remains optional; unavailable,
  disabled, stale, or rejected AI work cannot remove the deterministic
  correction or ordinary candidates.
- Confirmed `zongguo` retains its original candidates while exposing `中国`,
  and `nihap` retains the raw `nihap` preedit while exposing and committing
  `你好`. Normal `nihao`, `wojintian`, `zhongguo`, and `gailv` results are
  unchanged when correction is enabled.
- Kept nine-key lookup and its incremental lattice untouched. Candidate
  equality tests compare enabled and disabled settings for representative
  digit sequences; ambiguous digit-signature correction is deferred to
  `NINEKEY-TYPO-01`.
- On the development Apple host, the dedicated warm full-keyboard TYPO-01
  lookup regression measured a `2.398125 ms` median for `nihap` in the Rust test
  profile, below the unchanged `60 ms` interactive budget. This is a local
  reference rather than a hosted-CI or real-device release measurement.
- On the same host and test profile, a 24-key incremental worst-case sequence
  measured `1.77028 ms` per key with correction enabled and `0.914943 ms` with
  correction disabled. The Apple-only regression keeps the enabled path below
  the unchanged `60 ms` per-key budget; cross-platform CI still runs the
  attempt-bound, candidate-preservation, and settings source contracts.
- Repeating the same Apple-host regressions with the optimized Rust release
  profile measured a `0.649302 ms` median for `nihap` and `0.452382 ms` per key
  for the 24-key sequence with correction enabled versus `0.288388 ms` with it
  disabled. These are local reference measurements rather than real-device
  latency claims.

## iOS 0.1.27 (23) TestFlight Upload (2026-07-26)

- Released from merged `main` commit `e12f6f7`, which includes the approved
  NINEKEY-PERF-01 exact-key lookup, complete stateless/incremental candidate
  equivalence regressions, and the bounded session-local nine-key lattice cache.
- Updated the container App and Keyboard Extension to `0.1.27 (23)`.
  `0.1.26 (23)` was accepted by upload transport, but it cannot be submitted
  to the external group while `0.1.26 (22)` is already in Beta App Review.
  Advancing the marketing version keeps build `23` available as a separate
  review candidate. `ExportOptions.plist` explicitly sets
  `manageAppVersionAndBuildNumber=false` so the corrected upload preserves the
  reviewed repository build number.
- The superseded `0.1.26 (23)` upload remains in App Store Connect but will not
  be assigned to a testing group. Its delivery UUID is
  `840e9dc7-8e12-4286-a9da-c147abe2ebab`.
- Xcode 26.6 (`17F109`) archived the corrected arm64 app with the iPhoneOS 26.5
  SDK and iOS 18.0 minimum deployment target at
  `dist/ios/PrivatePinyin-0.1.27-build23-xcode26.xcarchive`. The archive,
  container App, and Keyboard Extension metadata all report `0.1.27 (23)`.
- `cargo test --workspace`, `cargo fmt --all -- --check`, the iOS source gate,
  plist validation, and `git diff --check` passed. The Helper lifecycle tests
  now remove host home-directory model discovery so release verification cannot
  accidentally observe a developer-installed Writer model.
- App Store Connect accepted the corrected `0.1.27 (23)` upload under delivery
  UUID `f1fd7ee0-9b84-4963-9f8d-d8f166fe780a`. The 6,608,723-byte IPA reached
  `COMPLETE` with no errors or warnings and entered build processing.

## NINEKEY-PERF-01 Incremental Nine-Key Decoding (2026-07-26)

- Replaced the direct nine-key exact-match check inside the prefix scan with
  one packed-index lookup that returns both exact and prefix bounds, then scan
  only the remaining prefix range. This preserves direct-candidate order while
  avoiding the duplicated lower-bound binary search and every exact-key string
  comparison inside the prefix scan.
- Added a dedicated nine-key decode cache alongside the existing continuous
  full-pinyin cache. Appended digits reuse prior bounded lattice positions;
  Backspace truncates the cached suffix; changing the previous committed context
  invalidates the cache. Full-pinyin and nine-key state remain separate.
- Added direct range-coverage and cache invalidation unit tests, plus an
  integration test that compares the complete candidate list (not only the
  visible page) after every incremental append, Backspace, and retyped suffix
  with the stateless candidate order.
- Added an Apple-only per-key regression that records each incremental
  nine-key `InputSession::feed_key` call for both the 21-key sentence and a
  64-key maximum-length composition, while retaining the existing median
  `60 ms` budget. This is intentionally a local Apple-target measurement,
  because the hosted Linux and Windows CI jobs do not execute it; CI continues
  to protect ordering and platform integration, not the machine-dependent
  latency figure.
- On the development arm64 Mac in the Rust test profile, three warmed runs of
  the same 5-session, 21-key sequence produced a median per-key result of
  `7.284542 ms` on `main` and `0.722500 ms` with this branch's cache: a
  `90.1%` median reduction (about `10.1x` faster). These are local reference
  measurements from the unoptimized test profile (`opt-level = 0`) and must not
  be read as release-build or directly user-visible latency.
- Repeating the comparison with `cargo test --release` on the same Mac produced
  median-of-three per-key results of `3.445083 ms` versus `0.391167 ms` for the
  21-key sequence (`88.6%`, about `8.8x` faster), and `13.654250 ms` versus
  `0.495208 ms` for a 64-key composition (`96.4%`, about `27.6x` faster).
  These release figures cover the maximum supported raw-input length, remain
  local reference measurements, and do not replace the unchanged `60 ms`
  regression budget.
- The cache exists only for an active composition. Input sessions cap raw
  nine-key input at 64 digits, so the cache holds at most 65 lattice positions
  and each position is beam-capped at 32 paths; commit, cancel, reset, and mode
  changes drop the complete cache. A direct regression proves both bounds and
  release-on-clear behavior.
- Validation passed locally: `cargo fmt --all -- --check`, `cargo test
  --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, and
  the desktop/iOS FFI test and clippy suites with their respective
  `desktop-ai` and `ios-ai` features. `git diff --check` also passed.

## FROST-01 Reviewed White Frost Desktop Import (2026-07-25)

- Audited the official `gaboolic/rime-frost` 1.0.4 stable Release and pinned its
  44,008,360-byte `rime-frost-schemas.zip` asset with SHA-256
  `4f4998ae83f63d757c0a4ace192f69d48265bddfabe231642b73e3739ed0f2f5`.
  The GPL-3.0 archive is never committed or bundled.
- Added a shared Rust importer that validates every ZIP member without extracting
  it, rejects traversal, duplicate names, symlinks, special files, excessive
  members, expanded size, member size, or compression ratio, and reads only six
  reviewed dictionaries.
- A real import of the approved archive accepted 653,308 rows, retained 653,136
  unique phrase/pinyin identities, and produced an 18,083,664-byte
  `rime_frost.tsv` including its header. The import completed in approximately
  11.4 seconds on the development Mac.
- White Frost is stored independently from the bundled lexicon,
  `imported_lexicon.tsv`, `rime_ice.tsv`, and local learning. A failed download,
  identity check, archive validation, parse, or limit check leaves the previous
  White Frost layer byte-for-byte unchanged.
- macOS and Windows require a visible GPL-3.0 confirmation before downloading
  from the fixed official GitHub Release. Both show the installed version and
  support import/update, enable/disable, clear, license access, and a latest-tag
  check that reports unreviewed releases as `新版待审核`.
- Desktop generic Rime imports now allow 64 MiB per selected source, 128 MiB per
  canonical layer, and 750,000 retained entries. The reviewed White Frost archive
  applies a tighter 32-MiB per-member cap. iOS remains unchanged at 16 MiB,
  32 MiB, and 200,000 entries and exposes no White Frost network action.
- Dedicated Rust tests cover valid import, artifact mismatch, traversal,
  excessive entries, symlink members, compression bombs, old-layer preservation,
  independent layer loading, and enable/disable behavior. The FROST-01 source
  gate pins platform scope, artifact identity, GPL consent, update-review state,
  and the unchanged iOS limits.
- `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D
  warnings`, `cargo fmt --all -- --check`, and the desktop/iOS AI FFI feature
  suites passed. The official 1.0.4 archive was also imported through the
  production parser rather than a synthetic fixture.
- `PRIVATE_PINYIN_SKIP_CODESIGN=1 bash scripts/build_macos_imk.sh` passed after
  staging the pinned Writer runtime, including the new AppKit download manager,
  consent UI, FFI bridge, and preference controls.
- Beta Xcode `bash scripts/build_ios_keyboard.sh`: `BUILD SUCCEEDED` with the
  Rust `aarch64-apple-ios-sim` target. This is a non-regression build only:
  FROST-01 remains desktop-only and the iOS import limits and network policy are
  unchanged.
- PR remediation moved the 11.4-second reviewed-archive import completely off
  the macOS IMK main queue and changed it to a no-engine static FFI import, so
  the import path does not construct a second full lexicon snapshot. It also
  refreshed Windows settings before saving the White Frost enable state, made
  missing `rg` fail the source gate, and feature-gated `zip`/`sha2` so the iOS
  FFI dependency graph contains no reviewed-import ZIP stack.
- The macOS shared-engine fingerprint now tracks the manual, Rime Ice, and
  White Frost canonical files independently. Importing, replacing, or clearing
  either reviewed layer rebuilds one shared snapshot even when `settings.json`
  remains byte-for-byte unchanged; no process restart is required.
- The hardened importer now hashes and parses through the same open file
  descriptor, requires each member to expose safe type metadata, and compares
  the EOCD-declared entry count with the ZIP reader's actual directory. A fresh
  post-hardening production CLI import of the exact pinned 1.0.4 asset again
  accepted 653,308 rows, retained 653,136 unique identities, and produced an
  18,083,664-byte TSV. All 161 official members reported regular-file Unix
  types (159 mode `100644`, two mode `100755`), so the stricter member-type
  policy does not reject the only approved archive.
- Closed the remaining review follow-ups without weakening artifact identity.
  macOS version checks now report a bounded `operationInProgress` or
  `versionCheckFailed` result instead of silently omitting their completion.
  White Frost downloads still start at the fixed official GitHub Release URL
  and require HTTPS on every redirect, while exact size and SHA-256 are the
  authoritative content identity; changeable GitHub asset-CDN hostnames are no
  longer pinned. Windows HTTP responses are disposed in `finally`, and the
  existing PowerShell AST parser remains required by the `windows-2022` CI job.
- Added `private-pinyin-settings measure-engine-load --settings PATH` so the
  same cold engine-construction measurement can be repeated on macOS and native
  Windows without loading user content. On the development arm64 Mac running
  macOS 26.5.2 (build 25F84), five Release-process samples measured the bundled
  base at a 70.350-ms median and 27,066,368-byte median maximum RSS (25.81 MiB).
  With the approved 653,136-entry White Frost layer enabled, the median was
  1,011.915 ms and 271,679,488 bytes (259.09 MiB). These are development CLI
  reference values rather than signed IMK lifecycle evidence. Native Windows
  x64 TSF RSS, post-reload RSS, and five-minute idle retention remain mandatory
  release smoke items because the TSF DLL is hosted by multiple applications.

## Desktop Imported-Lexicon Capacity Expansion (2026-07-24)

- Split imported Rime dictionary limits into explicit platform policies. macOS and Windows now accept source files up to 64 MiB, canonical imported layers up to 128 MiB, and 750,000 merged entries.
- iOS remains unchanged at 16 MiB per source, 32 MiB for the canonical imported layer, and 200,000 merged entries. Other unclassified targets use the same conservative policy rather than inheriting desktop capacity.
- The shared 4-KiB line limit, 32-character phrase limit, explicit-pinyin requirement, atomic replacement, and separate imported-layer storage remain unchanged.
- Added direct policy tests plus injected small-limit boundary tests. Oversized sources are rejected before reading, entry-limit failures preserve the previous imported file byte-for-byte, and repeated imports still merge and deduplicate.
- `cargo test --workspace` passed with an isolated HOME so the existing "approved Writer model is absent" fixture could not see the developer machine's installed model. `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --all -- --check`, `scripts/check_local_lexicon_import_sources.sh`, and the imported-lexicon integration suite passed.
- Beta Xcode `scripts/build_ios_keyboard.sh`: `BUILD SUCCEEDED`, including the Rust `aarch64-apple-ios-sim` target, confirming that the unchanged conservative iOS policy still compiles through the container App and Keyboard Extension.

## iOS Keyboard Input-Latency Remediation (2026-07-24)

- Audited the complete Keyboard Extension event path after reports of wooden QWERTY response, delayed candidates, one-second transition ghosting, and raw nine-key lookup digits. Although lexicon construction was already off-main, feed, reset, candidate commit, paging, and secure-input FFI calls still ran synchronously on UIKit's main thread.
- Replaced the split loading/direct-call model with one user-interactive serial core queue. Every Rust session operation now executes off-main in input order; only the resulting immutable output is delivered to UIKit on main.
- Added a controller interaction revision alongside the engine generation. Results produced for a previous text field, keyboard layout, or engine generation are discarded before touching preedit, candidates, or the host document.
- Cold-start keys remain bounded to 64 operations and are replayed on the same worker rather than in one main-thread burst. Inline preferences are now constructed only when first opened, reducing first-frame work during keyboard presentation.
- Empty-composition Backspace stays on the immediate document-proxy path, and punctuation does not enqueue an unnecessary Enter. These common operations therefore avoid worker round trips when no core state exists.
- Candidate selection now has one main-thread in-flight latch. Compact and expanded candidate controls are disabled until the queued commit finishes; queue rejection, engine invalidation, host-field changes, and layout changes all release the latch, preventing rapid repeated taps from committing twice without risking a permanently disabled candidate bar.
- Nine-key display converts an unresolved internal digit signature into readable key groups such as `WXYZ MNO MNO GHI` until candidate pinyin becomes available. Internal `2-9` lookup digits are never shown as user-facing preedit.
- Added light impact feedback for typing keys and retained selection feedback for candidate and mode commands. Feedback remains best-effort under iOS and must not affect input when system haptics are unavailable.
- Apple documents that secure fields and phone-pad fields use the system keyboard, and that a host App may reject every custom keyboard through its extension-point policy. A single App such as Marriott refusing 猫栈拼音 is therefore a host policy boundary rather than something the extension can override.
- `scripts/check_ios_keyboard_sources.sh` now rejects synchronous `feed`, `reset`, or candidate-commit calls outside the serial worker, requires stale-result revision checks, and pins the lazy preferences, haptic, and readable nine-key fallback contracts.
- Beta Xcode `scripts/run_ios_smoke_readiness.sh`: passed with Xcode 26.6 and the iOS 26.5 Simulator SDK. The built app installed and ran on an iOS 27.0 iPhone 17 Pro simulator.
- Simulator interaction passed: rapid nine-key `64426` displayed `ni hao` with `你好` first and committed exactly one `你好`; rapid QWERTY `nihao` displayed the same first candidate and committed it. Six consecutive system/custom keyboard transitions returned to a complete keyboard surface, retained host text, and produced no new simulator crash report.
- Physical-device verification remains required for perceived frame timing, best-effort haptic strength, extension recreation under memory pressure, password/phone fallback, and host Apps that intentionally reject third-party keyboards.

## macOS Installed-Server Identity Validation (2026-07-24)

- Diagnosed intermittent no-input periods as two same-bundle InputMethodKit servers running at once: the signed app under `/Library/Input Methods` and a development copy under `dist/macos_imk`. LaunchServices also retained registrations for package roots, helper-test bundles, and old build outputs.
- Added an exact launch policy: only `/Library/Input Methods/PrivatePinyin.app` or the current user's `~/Library/Input Methods/PrivatePinyin.app` may create the production IMK server. UI-only launch arguments remain server-free, and similarly named sibling directories are rejected.
- Installed launches verify that both the input method bundle and `.Mode` identifiers exist in the TIS registry and repair missing registration with `TISRegisterInputSource`. Recovery from an uninstalled development or staging copy always re-registers the exact installed bundle path so stale LaunchServices/TIS cache mappings cannot survive; it deliberately never calls `TISEnableInputSource`, so it cannot append duplicate enabled-source records.
- Registration verification uses the complete installed TIS source list, including disabled sources. A successful repair is therefore not misreported as failed, repeated launches do not re-register a healthy disabled source, and enablement remains an explicit user action.
- An uninstalled build now emits only a content-free launch code, restores the exact installed executable when it is not already running, and exits instead of competing for the production InputMethodKit connection.
- Native policy tests cover system and per-user installs, development output, misleading sibling paths, and UI-only launches. The macOS CI job runs the Swift test, while source gates require the policy in every host build.
- Local runtime smoke stopped the installed server, launched the development bundle deliberately, observed `installed_server_restored` followed by `uninstalled_bundle_refused_imk_server`, and confirmed that the sole surviving process was `/Library/Input Methods/PrivatePinyin.app/Contents/MacOS/PrivatePinyin`.
- A second runtime smoke launched the freshly built uninstalled app while the signed installed server was active. The development app emitted `uninstalled_bundle_refused_imk_server`, exited, and left the single installed process alive. TIS registration repair restored and selected `com.privatepinyin.inputmethod.PrivatePinyin.Mode` without starting another server.
- Computer-generated TextEdit key events bypassed both the custom and system IMK paths, so they are not recorded as a typing pass. The remaining manual smoke is to unlock the Mac, select 猫栈拼音, and type `nihao` -> `你好` with a physical keyboard.
- `scripts/test_macos_launch_policy.sh`, `scripts/test_macos_input_source_registration.sh`, `scripts/check_macos_imk_sources.sh`, `PRIVATE_PINYIN_SKIP_CODESIGN=1 scripts/build_macos_imk.sh`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo fmt --all -- --check`: passed.

## Desktop Writer V1 Validation (2026-07-22)

- PR review remediation separated the per-launch AI-09 Helper token from the `llama-server` API key. The server now receives an independently generated 256-bit key through a private file rather than argv (Unix mode `0600`, Windows current-user app-data ACL); the file is removed immediately after authenticated readiness, with drop-time cleanup as a retry path.
- Full model SHA-256 verification now shares the request's absolute deadline and observes cancellation before metadata access, between every 1-MiB read, and after the final block. Direct tests exercise cancellation after the first hash read plus key-file contents, Unix permissions, name independence, and removal.
- macOS and Windows runtime preparation now parse `llama-server --help` and fail packaging unless pinned release `b10069` exposes `--api-key-file`, `--offline`, `--no-webui`, `--log-disable`, `--parallel`, `--ctx-size`, `--batch-size`, and `--ubatch-size`.
- The current hand-written HTTP parser intentionally targets the pinned non-streaming llama.cpp response and fails closed on incompatible transfer framing. Port reserve/rebind is protected by authenticated readiness plus bounded retries, and one-request-at-a-time generation remains bounded by cancellation and the absolute deadline.
- Added Decision 043 and a machine-readable desktop Writer runtime manifest. The Owner approval is limited to explicit on-demand download and local use of the exact Qwen2.5 1.5B Instruct Q4_K_M artifact; model redistribution remains prohibited.
- Pinned llama.cpp `b10069` / revision `178a6c44937154dc4c4eff0d166f4a044c4fceba` for macOS arm64 and Windows x64. Packaging scripts verify the official release archive SHA-256 before staging the runtime.
- The model is absent from the repository and installers. macOS and Windows require a visible user action, fixed official URL, exact `1,117,320,736`-byte size, and SHA-256 `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`; the Helper repeats full verification at use time.
- The Helper owns a random-key `llama-server` child bound only to `127.0.0.1`, with web UI, network model access, and logs disabled. Source and result content use authenticated AI-09 IPC plus private loopback only and never enter argv, diagnostics, telemetry, or temporary prompt files.
- macOS preferences/menu and Windows settings expose explicit rewrite and translation previews. Results are copy-only and never replace text automatically. Strict privacy, consent/model changes during inference, cancellation, timeout, stale state, and runtime/model failure discard the result without affecting ordinary input.
- Automatic short completion remains disabled. The signed/notarized macOS and signed Windows package matrix, native Windows cold/warm RSS, and final runtime fault injection remain tracked by `AI-OI-010` and `AI-OI-012`.
- `cargo test --workspace`, `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, desktop/iOS feature FFI tests, and every AI-01 through AI-12/source privacy gate passed.
- `PRIVATE_PINYIN_SKIP_CODESIGN=1 bash scripts/build_macos_imk.sh` passed after staging the pinned llama.cpp runtime and validating its complete dylib dependency closure with `llama-server --version`.
- A real on-demand model smoke exercised macOS host client -> authenticated AI-09 Helper -> independently keyed loopback `llama-server` -> bounded Writer preview. After the credential-separation remediation it returned two suggestions, with `2,303 ms` model preparation and `228 ms` inference. The preceding equivalent run reported `1,283,571,712` bytes maximum RSS and zero swaps via `/usr/bin/time -l`. These local references contain no source or generated text and are not cross-platform release thresholds.
- Native Windows PowerShell packaging, signed installer identity, cold/warm RSS, and runtime fault smokes require the GitHub `windows-2022` job plus a Windows 11 machine; they cannot be claimed from this development Mac.

## AI-12 Validation (2026-07-22)

- Added maintained first-party synthetic privacy fixtures grouped as password, token, identity card, phone, payment, and false-positive cases. The data-driven guard regression rejects all sensitive groups while preserving ordinary phrases, and the release manifest records that the corpus contains no user data.
- Added exact FFI output-equivalence coverage for both `desktop-ai` and `ios-ai`: an AI-enabled engine blocked by secure-input privacy produces the same preedit, commit, mode, update flags, candidates, scores, and sources through ordinary keys, backspace correction, candidate paging, and two consecutive candidate commits.
- Added exact 64-KiB protocol and Helper process frames, oversized-frame rejection, active-work saturation and `QueueFull` behavior, cancellation, graceful shutdown, and retained idle-exit coverage.
- Added absolute macOS Helper request deadlines and a bounded three-launch-per-30-second restart budget. The native Swift lifecycle suite covers authentication, health, cancellation, forced termination, restart, shutdown, timeout cleanup, and launch-budget recovery.
- Replaced one-shot Windows pipe writes with deadline-aware retry semantics and expanded the native lifecycle probe to validate the maximum frame, eight active requests, the rejected ninth request, cancellation, spawned-helper PID binding, crash/restart, and shutdown.
- Added `ai/eval/ai12_release_gate.json` and `scripts/check_ai12_release_gates.sh`. The JSON is explicitly a declarative expectation contract rather than a generated result report; named CI tests own executable pass/fail evidence without being rerun by the source gate. The machine-readable decision is `AI Lite = Go`, `Writer = No-Go`; the latter still requires warmed-request evidence, native Windows RSS, signed package/installer identity smokes, and exact Owner redistribution approval.
- Local Rust core, protocol, Helper process, desktop FFI, iOS FFI, and macOS Swift Helper tests passed. Windows native execution is delegated to the `windows-2022` CI job and must be green before merge.

## iOS Keyboard Transition Responsiveness Validation (2026-07-22)

- Root-cause review found that `KeyboardViewController.viewDidLoad()` synchronously created the Rust bridge and parsed the 137,699-entry lexicon before UIKit could present the keyboard. On extension recreation this exposed the previous keyboard frame long enough to look like ghosting or a stalled transition.
- Direct iOS actions that bypass the queued character-input path now reacquire a configured core and refresh secure-input state before backspace, candidate commit, paging, composition finalization, or punctuation submission.
- The keyboard now builds an opaque, clipped surface first and starts core initialization on a dedicated worker queue. The completed bridge and every subsequent Rust core operation remain confined to that serial queue; only outputs are published to main.
- Up to 64 key operations received during cold initialization are retained in FIFO order and replayed once on the worker. A real host text change invalidates pending results so early keys cannot leak into another field; engine initialization failure preserves the existing fallback insertion behavior.
- Complete keyboard rebuilds run without UIKit animation, while ordinary character entry continues to update only the preedit/candidate state rather than reconstructing the key hierarchy.
- Historical diagnostics contained one retired `PrivatePinyinKeyboard` Auto Layout crash from the former nine-key construction order. The current grid activates cross-row constraints only after every row belongs to the shared grid hierarchy; repeated simulator switching produced no new extension crash report.
- iOS 27.0 iPhone 17 Pro simulator smoke: switched from 猫栈拼音 to Simplified Chinese, English, and back to 猫栈拼音. The complete keyboard appeared on return, and immediate `mao` input produced readable preedit plus `猫` and other candidates without a lost or duplicated key.
- `scripts/check_ios_keyboard_sources.sh`, `git diff --check`, and Beta Xcode `scripts/build_ios_keyboard.sh`: passed. Frame-level transition smoothness on physical devices remains a required TestFlight check because simulator screenshots cannot establish display-refresh timing.

## iOS Nine-Key Numeric And Settings Navigation Validation (2026-07-22)

- The nine-key `123` key now opens a dedicated numeric grid with `1-9`, `0`, Delete, Space, Return, `拼音`, a quick punctuation key, `#@¥`, and `更多`; it no longer reuses the QWERTY symbol page. Devices that require an input-mode switch show the system globe key in place of the direct `ABC` shortcut.
- The quick punctuation key inserts `，` on tap. A bounded long press opens `！/？/。/，`, vertical sliding selects one item before insertion, and the same alternatives are available as VoiceOver custom actions. `#@¥` opens the primary symbol page while `更多` opens the extended page.
- The iOS container App home page now shows four compact entries: `开始使用`, `隐私与学习`, `词库管理`, and `关于猫栈拼音`. Existing setup, local-learning, imported-lexicon, reviewed-rime-ice, and version behavior lives on separate second-level pages.
- `scripts/check_ios_keyboard_sources.sh`: passed with source contracts for quick punctuation, primary/extended symbol routing, the required globe key, VoiceOver actions, and the two-level settings hierarchy. The contract no longer relies on the former `sed | grep` pipeline that could fail under CI `pipefail` after an early match.
- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- Beta Xcode `scripts/build_ios_keyboard.sh`: `BUILD SUCCEEDED` after the PR review follow-up.
- Beta Xcode `scripts/run_ios_smoke_readiness.sh`: `BUILD SUCCEEDED`; Stage 14 source/signing checks and iOS smoke readiness passed for the Rust-backed container App and Keyboard Extension.
- `scripts/test_ios_chinese_transform.sh`: passed with the Beta Xcode Swift toolchain.
- iOS 27.0 iPhone 17 Pro simulator: installed and launched the rebuilt container App; the first-level page showed the four settings destinations without clipping or an overlong home page.
- Real-device touch ergonomics for the long-press/slide punctuation selector remains a TestFlight smoke item; its UI behavior cannot be fully established by source checks alone.

## AI-11 Validation (2026-07-21)

- Added a versioned Writer helper contract for bounded short completion, explicit rewrite, and explicit translation previews. Requests carry complete session/request/revision/source identity, expire within three seconds, and can return at most three bounded suggestions.
- Strict privacy normalization now force-disables short completion, rewrite, and translation while preserving the separate stateless AI Lite policy. `AI-OI-011` also requires the future default-off short-completion UI to state “停顿时当前输入会交给本地 AI 进程” before the feature may ship.
- In the historical AI-11 profile, the dormant helper validated Writer frames but returned only `ModelUnavailable`; that preserved the No-Go boundary before the separately reviewed Decision 043 Writer V1 activation.
- Evaluated official `Qwen/Qwen2.5-1.5B-Instruct-GGUF` revision `dd26da440ef0330c47919d1ecae0966d24022222`, exact Q4_K_M SHA-256 `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`, with official llama.cpp release `b10069` on the development Mac. Model and runtime binaries remain temporary and outside the repository/product.
- Result: 5/5 first-party synthetic completion, rewrite, and translation cases passed; cold-process first byte was 321-444 ms, total latency 403-528 ms, cancellation completed immediately, and peak RSS was about 1,192 MiB. The content-free report stores no prompt, generated text, path, or user data.
- Release decision remains `NoGo`: warmed-request evidence, native Windows RSS, final package/cold-start review, and separate Owner/license redistribution approval are still required. Quality or privacy gates were not weakened to convert the Mac technical result into product approval.
- `cargo fmt --all -- --check`, `cargo test --workspace`, strict workspace Clippy, and the AI-05/AI-09/AI-10/AI-11 source gates: passed. The exact temporary artifact evaluation also passed on the development Mac; no artifact is tracked or retained by the product.

## iOS 0.1.23 Keyboard Recovery and Candidate Browser Validation (2026-07-21)

- Reproduced the failure to switch to the `0.1.23` Keyboard Extension as a UIKit Auto Layout exception: nine-key constraints were activated before their rows shared a view hierarchy. The hierarchy is now installed before constraint activation. No jetsam termination was observed, so the startup fix is not attributed to memory pressure.
- Added an expandable 3-by-3 candidate browser with nine candidates per group, previous/next paging, and the existing compact strip preserved for ordinary typing in both full-keyboard and nine-key layouts.
- Replaced duplicate per-entry pinyin `String` keys in the base and imported lexicon indexes with packed UTF-8 key storage. Direct index coverage now verifies duplicate `lü` exact matches, the `lü`/`lüe` prefix boundary, the distinct `lv` spelling, and missing lower/upper lexical boundaries.
- Simulator RSS reference measurement used the same iOS 27.0 iPhone 17 Pro simulator, Xcode Beta Debug extension, nine-key idle state, and three stable `ps` samples. Baseline `6b06783` with only the startup-ordering backport and the previous string-key indexes measured `360,048 KiB` three times. The current packed-index branch measured `348,448`, `348,432`, and `348,432 KiB`; median RSS fell by `11,616 KiB` (about `11.34 MiB`, `3.23%`). The current sample also includes the new collapsed candidate-browser UI, making this a conservative net comparison.
- These simulator measurements are local reference evidence, not an iOS release threshold or proof that jetsam is resolved. Real-device first-load RSS, memory-pressure behavior, imported-lexicon reloads, and repeated host switching remain required before closing the iOS portion of `OI-042` or changing AI hardware policy.
- `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, `scripts/check_ios_keyboard_sources.sh`, the focused packed-index test, and `scripts/run_ios_smoke_readiness.sh`: passed. Xcode Beta reported `BUILD SUCCEEDED` for the container App and Keyboard Extension.

## AI-10 Validation (2026-07-21)

- Evaluated official `Qwen/Qwen2.5-0.5B-Instruct-GGUF` revision `9217f5db79a29953eb74d5343926648285ec7e67`, file `qwen2.5-0.5b-instruct-q4_k_m.gguf`, with official llama.cpp release `b10069` revision `178a6c44937154dc4c4eff0d166f4a044c4fceba` on the development Mac.
- Exact model, runtime archive/executable, and synthetic-dataset byte sizes and SHA-256 values are pinned. Weights and runtime binaries remain outside the repository, application bundle, installer, and AI-05 approval registry.
- The offline probe exposes no arbitrary prompt input, runs only three checked-in first-party synthetic cases, uses no network client, bounds prompt/output/process time, measures first-byte/total latency and peak RSS, and kills/waits for the child on cancellation.
- Result: short completion passed; short notice rewriting passed; polite scheduling rewrite failed its required-text rule. Technical quality therefore failed at 2/3 cases and the release decision is `NoGo`.
- Local reference measurements: 276-295 ms first byte, 334-387 ms total, 579 MiB peak RSS, and cancellation within the 500-ms budget. Every case launches a fresh runtime, so first-byte latency includes process startup and cold model loading. These are development-Mac evidence, not portable CI performance thresholds.
- The checked-in report stores only identity, timing, memory, output length, result codes, and decision reasons. It contains no prompt, generated text, file path, or user data.
- `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, the AI-05/AI-09/AI-10 source gates, and the real pinned-artifact validation/run: passed.

## macOS Imported Source Status Validation (2026-07-20)

- The imported-source label is a single-line, vertically resistant AppKit field with a full-text tooltip, preventing compact Station Board scaling from clipping glyphs.
- macOS menu and preferences imports share one source resolver. Known upstream files under `rime-ice`, `雾凇`, or `霧凇` record `雾凇拼音`; custom files keep their cleaned filename, and only dates at or below the matched source directory are retained as metadata-only versions.
- Existing `imported_lexicon.tsv` layers without `imported_lexicon_manifest.json` remain usable but are labelled as legacy. The app does not invent provenance from normalized phrase/pinyin rows or retain the user's original path.
- `scripts/test_macos_imported_lexicon_source.sh`, local-import and macOS source checks, the complete macOS IMK build, `cargo fmt --all -- --check`, `cargo test --workspace`, and strict workspace Clippy: passed.

## macOS Shared Engine Memory Validation (2026-07-20)

- Activity Monitor investigation found 17 input controllers and 18 independently parsed engines in one long-running process; heap growth matched roughly one full lexicon/index allocation per engine rather than the tiny AI Lite coefficient package.
- The macOS C ABI bridge now owns only a per-controller session. A locked process-wide pool owns the engine, serializes engine-level administration, and coalesces settings/imported-lexicon reload fan-out by exact settings data plus imported-file metadata.
- Existing sessions remain valid while a changed shared snapshot is replaced because Rust sessions retain their own `Arc` references; every controller still has isolated raw input, candidate page, context, and secure-input state.
- Replacement is constructed before the previous engine is released, deliberately accepting a short two-snapshot memory peak so a failed rebuild can preserve working input. Each failed configuration fingerprint emits one content-free Unified Logging error code and is not retried until its fingerprint changes.
- `scripts/test_macos_shared_engine.sh` creates 24 bridges, asserts a single engine load, verifies two simultaneous compositions remain independent, reloads every bridge, and asserts unchanged configuration does not reparse the lexicon.
- The native 24-session regression peaked at `53,280,768` bytes RSS (about 50.8 MiB) on the development Mac, compared with the diagnosed long-running process where 18 independent engine snapshots had grown to about 2.07 GB of Rust heap; this is local reference evidence, not a portable CI threshold.
- Real installed-app Activity Monitor validation with 5 and 20 client apps remains required before closing the memory portion of OI-042.

## Imported Lexicon Visibility Validation (2026-07-20)

- macOS and iOS display imported-source metadata from a separate atomic JSON manifest; clearing the imported layer also clears its source record.
- The optional iOS `rime-ice` import is container-App-only, requires an explicit confirmation, uses an ephemeral session, and pins release, final HTTPS host, exact byte count, and SHA-256 for every reviewed file.
- Partial reviewed-source imports are labelled as partial and are replaced by the complete status after a successful retry.
- The official `cn_dicts.zip` release asset and all three fixed raw tag URLs were independently downloaded on 2026-07-20; exact byte counts and SHA-256 values match, and the evidence/tooling is recorded in `docs/local_rime_lexicon_import.md`.
- Decision 037 remains the merged AI-08 policy; the optional verified upstream lexicon import is Decision 038 and explicitly directs GitHub-restricted networks to the local document-picker path instead of an unofficial mirror.
- Local document-picker parsing/import now runs on a user-initiated worker queue while security-scoped access remains active; only progress and completion state return to the main thread.
- `cargo test --workspace`, `cargo test -p private_pinyin_ime_ffi --features ios-ai`, `cargo test -p private_pinyin_ime_ffi --features desktop-ai`, `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, macOS source/build checks, AI-07/AI-08 source checks, iOS source checks, and local-import source checks: passed.
- Xcode 27.0 Beta (`27A5194q`) simulator-target build: `BUILD SUCCEEDED` for the container App and Keyboard Extension.
- Real-device download/import remains a release smoke item because this branch deliberately does not automate a network action on the owner's phone.

## Stage Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| 01 | Rust core engine | completed | 2026-07-06 12:12 | Core engine, CLI, tests, and CI are ready for local review |
| 02 | User lexicon and prediction | completed | 2026-07-06 15:01 | Merged to `main` through PR #3 |
| 03 | C ABI and CLI integration | completed | 2026-07-06 15:53 | Merged to `main` through PR #4 |
| 04 | Windows TSF prototype | completed | 2026-07-06 17:00 | Merged to `main`; Windows smoke test still required |
| 05 | macOS InputMethodKit prototype | completed | 2026-07-06 18:22 | Merged to `main` after local review |
| 06 | Installers and settings | completed | 2026-07-06 19:40 | Merged to `main` after local review |
| 07 | iOS keyboard extension | completed | 2026-07-06 20:44 | iOS container app, Keyboard Extension, C ABI static-library wiring, candidate bar, Globe key, and privacy-default scaffold are ready for local review |
| 08 | Platform validation and CI hardening | completed | 2026-07-06 21:57 | Windows Rust test and TSF compile CI, platform smoke-test records, release-readiness validation checks, and Stage 9-12 planning are ready for local review |
| 09 | Core production hardening | completed | 2026-07-06 23:04 | Merged to `main` through PR #8 |
| 10 | Platform host polish | completed | 2026-07-06 23:14 | Merged to `main` through PR #9 |
| 11 | Settings, privacy, and iOS storage closure | completed | 2026-07-07 07:45 | Shared default template use, stronger settings/export writes, hidden CapsLock platform UI, iOS App Group settings storage, learning opt-in, mode derivation, Globe-key visibility, review fixes, and Stage 11 checks are ready for local review |
| 12 | Release packaging and distribution | completed | 2026-07-07 08:35 | Release distribution plan, Windows signing hooks, macOS Developer ID/notarization hooks, iOS App Store archive/export templates, automatic update strategy, and Stage 12 checks are ready for local review |
| 13 | Lexicon import and production dictionary | completed | 2026-07-08 10:42 | Merged to `main` through PR #10 |
| 14 | iOS signing and App Group configuration | completed | 2026-07-09 11:20 | Merged to local `main`; owner signing env inputs, bundle ID overrides, App Group build-setting injection, export-options checks, and Stage 14 CI source gates are ready |
| 15 | iOS simulator/local development build | completed | 2026-07-10 13:32 | Beta Xcode source/readiness gates and iOS 27 Simulator install, enablement, continuous-pinyin, prediction, local learning, portrait, and landscape smoke checks passed |
| 16 | TestFlight archive and upload | completed | 2026-07-22 20:13 | TestFlight candidate `0.1.25 (21)` was archived with Xcode 26.6, uploaded as delivery `7388b499-48c5-470e-89f4-95569a6b7309`, and validated as App Store eligible |
| 17 | Device keyboard behavior and privacy closure | in_progress | 2026-07-22 20:13 | Build `0.1.25 (21)` is ready for external assignment; final TestFlight keyboard-transition, nine-key numeric/punctuation, password/phone fallback, candidate paging, verified `rime-ice` import, and App Group persistence checks remain |
| 18 | App Store release preparation | planned | | Prepare screenshots, description, privacy labels, age rating, URLs, and release checklist |

## Core Follow-up Status

| Item | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| OI-045 | Incremental lattice caching and mixed full-pinyin/initial decoding | completed | 2026-07-16 11:28 | Session-local append/backspace prefix reuse, context/boundary invalidation, joint full/initial beam edges, `wojt -> 我今天`, raw-English fallback protection, C ABI coverage, and latency regression checks are ready for review |

## iOS Regression Validation (2026-07-18)

- `cargo test --workspace`, `cargo fmt --all -- --check`, and `cargo clippy --workspace --all-targets -- -D warnings`: passed.
- Focused nine-key tests cover `64426 -> 你好`, continuous digit segmentation, Backspace/commit behavior, and the interactive lookup budget: passed.
- `scripts/check_ios_keyboard_sources.sh`: passed with contracts for extension-local preference fallback, delayed self-change callback handling, revised nine-key geometry, and symbol entry.
- Xcode 27.0 (`27A5194q`) simulator build: `BUILD SUCCEEDED`; the app installed and launched on an iOS 27.0 iPhone 17 Pro simulator.
- Wrote `nine_key` and `traditional` to the extension-local preference domain, fully restarted the simulator, and read both back unchanged: passed.
- Production-lexicon regression ranks `zyao` as `主要 (zhu yao)` first: passed.
- Mixed shorthand decoding is capped at 16 characters, avoids sort-comparator allocations, and keeps the 16-character regression below the shared 60-ms input budget: passed.
- Common full-pinyin regressions keep `woshi -> 我是`, `jintian -> 今天`, and `zhongguo -> 中国` first after mixed/continuous candidates enter one score-sorted bucket: passed.
- Delayed self-generated text callbacks now require a matching document identifier and captured text context inside a 250-ms window; unrelated field/app changes continue to reset composition.
- Layout/script reads compare shared-JSON and extension-local timestamps, so the freshest successful write wins while either sandbox remains a usable fallback.
- `scripts/run_ios_smoke_readiness.sh`: passed with `BUILD SUCCEEDED` for both the container app and Keyboard Extension under Xcode 27.
- Final TestFlight/device taps for candidate selection, top-left symbol navigation, revised geometry, and delayed host callbacks remain required before release.

## iOS Nine-Key Candidate and Touch Validation (2026-07-19)

- Added a bounded session-level candidate-page setter to the Rust core and C ABI; iOS requests exactly nine entries even when engine construction falls back to default settings.
- Added executable C ABI coverage proving nine-key `626` returns nine visible candidates, includes `猫` on the first page, and produces a distinct non-empty second page: passed.
- Added a dedicated `候选` key for the next candidate group; the fixed previous/next controls above the horizontally scrolling strip remain available.
- Rebuilt the nine-key surface into the requested five-column geometry, restored the required Globe and Chinese/English controls, removed the placeholder key, and made row heights adapt to compact-height layouts.
- Candidate-page configuration now has one bridge-owned preferred size and degrades to the core default without making the keyboard unavailable; haptics remain best-effort because the extension does not request Full Access.
- Added cancellable candidate-button tracking, preserved scroll position, and expanded non-overlapping `A`/`L` edge hit regions.
- `cargo test --workspace`, `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `scripts/check_ios_keyboard_sources.sh`: passed.
- Xcode Beta simulator build: `BUILD SUCCEEDED`; the app installed and launched on an iOS 27.0 iPhone 17 Pro simulator.
- TestFlight device validation is still required for candidate-strip inertial dragging, `A` accuracy, optional haptic behavior, five-column portrait/landscape geometry, required Globe access, Chinese/English switching, `626 -> 猫`, and repeated `候选` paging before release.

## Local AI Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| AI-01 | Offline evaluation baseline | completed | 2026-07-14 14:34 | 13/13 required regressions pass; 7 correction/mixed-input opportunities are measured; latency remains report-only |
| AI-02 | Runtime contracts and mock provider | completed | 2026-07-16 06:40 | Isolated zero-dependency contracts, bounded budgets/deadlines, full request identity, scoped cancellation, redacted debug output, deterministic mock behavior, non-cryptographic fingerprint limits, worker-queue-only host guidance, and CI source checks are ready for review |
| AI-03 | Privacy guard and source gates | completed | 2026-07-16 10:04 | Merged to `main` through PR #25; guarded construction, secure/sensitive/oversized rejection, eight-token context minimization, code-only errors, and no-network/no-content-log source gates remain isolated from production input |
| AI-04 | Rules-first correction, terms, and cleanup suggestions | completed | 2026-07-17 10:05 | Two-result validated pinyin correction, first-party canonical English terms, strict-privacy-blocked read-only cleanup analysis, redacted debug output, and 13/13 required plus 7/7 observed offline quality are ready for review; hosts remain untouched |
| AI-05 | Model manifest, approval, integrity, and hardware gate | completed | 2026-07-17 15:09 | Merged to `main` through PR #29; strict schema, dual-control Owner approval, bounded integrity/use-time verification, safe paths, local-only privacy, platform/hardware gates, atomic packager, and CI checks form the model supply-chain boundary |
| AI-06 | Shared compact Rust AI Lite ranker | completed | 2026-07-18 00:15 | Fixed-point stable ranking over six bounded engine signals, ranker/feature schema version gates, exact AI-05-approved 426-byte first-party coefficients, overflow boundaries, 8/8 targeted improvements, 4/4 preservation cases, bounded cancellation/scratch state, and no host integration are ready for review |
| AI-07 | macOS and Windows asynchronous integration | completed | 2026-07-19 06:36 | Merged to `main` through PR #33; bounded asynchronous desktop ranking, stale-result rejection, secure-input cancellation, macOS IMK wiring, Windows TSF wiring, and the signed/notarized macOS 0.1.22 validation package are complete |
| AI-08 | iOS AI Lite integration | completed | 2026-07-20 | Merged to `main` through PR #36; isolated `ios-ai` feature, approved 426-byte local ranker, bounded non-blocking worker, stale-result rejection, secure-input fallback, controller-lifetime memory-pressure suspension, and iOS 27 simulator build are complete; real-device latency/RSS and hardware calibration remain release gates |
| AI-09 | Authenticated desktop Helper boundary | completed | 2026-07-20 15:46 | Shared bounded protocol and helper, controlled macOS pipes, current-user-only Windows request/response named-pipe pair, per-launch authentication, health/cancel/crash/restart/shutdown/idle lifecycle, packaging/signing hooks, and CI probes are ready for review; no Writer model or input-path dependency is added |
| AI-10 | Optional Writer feasibility | completed (No-Go) | 2026-07-21 00:31 | Exact Qwen2.5 0.5B Q4_K_M and llama.cpp inputs are pinned; offline Mac probe passed cancellation and 2/3 quality cases, so the model remains unapproved, unbundled, and disconnected from every input path |
| AI-11 | Gated Writer contracts and stronger-candidate evidence | completed (No-Go) | 2026-07-22 | Versioned bounded helper frames, explicit-action policy, complete stale-result identity, and 5/5 development-Mac evidence are complete; no model or Writer UI ships until warmed-request, native Windows RSS, packaging, and Owner redistribution gates pass |
| AI-12 | Cross-platform hardening and release gates | completed | 2026-07-22 | Merged through PR #44; categorized privacy regressions, exact AI-off equivalence, bounded cross-platform Helper fault injection, model notices, and the historical AI Lite Go / Writer No-Go release profile remain preserved |
| Writer V1 | On-demand verified desktop Writer runtime | implemented, pending review | 2026-07-22 | macOS arm64 and Windows x64 package the pinned llama.cpp runtime; explicit verified model download, authenticated local rewrite/translation previews, strict-privacy cancellation, and fail-soft behavior are implemented under Decision 043. Automated gates and a real-model macOS smoke pass; signed final-package and native Windows memory smokes remain open |

## AI-09 Validation

- Shared protocol tests cover deterministic framing, 64-KiB fail-before-allocation limits, redacted diagnostics, constant-time fail-closed authentication, bounded payload decoding, and the ten-minute maximum idle policy.
- Helper process tests cover authentication, health, bounded mock work, completed-worker handle reclamation, cancellation, graceful shutdown, unauthenticated rejection, and idle process exit without logging request payloads.
- macOS builds the helper in release mode and separately signs `Contents/Helpers/PrivatePinyinAIHelper`; the Swift controlled-child test exercises authentication, health, cancellation, forced termination, automatic restart, and clean shutdown over anonymous pipes.
- Windows builds and packages `PrivatePinyinAIHelper.exe`; its lifecycle probe uses a random current-user-only request/response named-pipe pair with `PIPE_REJECT_REMOTE_CLIENTS`, verifies both connected clients match the spawned helper PID, terminates one authenticated helper, relaunches another, then exercises cancellation and shutdown.
- CI now runs the shared source/privacy gate on Ubuntu, the compiled controlled-process test on macOS, and the compiled named-pipe lifecycle probe on `windows-2022`.
- AI-09 was introduced as infrastructure only. Decision 043 now uses it for explicit desktop Writer actions; basic pinyin, user learning, AI Lite ranking, and iOS still do not invoke the helper. `AI-OI-010` and `AI-OI-012` track signed-package identity, hang/runtime fault injection, native Windows RSS, and ten-minute idle smoke before public Writer release.

## AI-08 Validation

- `cargo test -p private_pinyin_ime_ffi --features ios-ai`: passed, including iOS platform enablement, secure-input base fallback, unsupported-memory rejection, invalid-platform rejection, and ordinary input after every rejected AI path.
- `cargo test -p private_pinyin_ime_ffi --features desktop-ai`: passed, confirming the generic local-AI ABI preserves AI-07 desktop behavior.
- `cargo clippy -p private_pinyin_ime_ffi --all-targets --features ios-ai -- -D warnings`, `cargo fmt --all`, `check_ai08_ios_integration_sources.sh`, `check_ai07_desktop_integration_sources.sh`, and `check_ios_keyboard_sources.sh`: passed.
- Xcode Beta iOS 27 simulator build through `scripts/build_ios_keyboard.sh`: `BUILD SUCCEEDED` with Rust `aarch64-apple-ios-sim`, the C support module, container App, and Keyboard Extension.
- The iOS build enables only `ios-ai`, keeps `RequestsOpenAccess=false`, embeds no heavy neural model, and contains no keyboard-extension network API or URL.
- `didReceiveMemoryWarning` now cancels optional AI through the secure-input path and keeps it suspended for the controller lifetime while preserving the current composition and ordinary input path.
- Real-device iOS measurements remain required for first-enable latency, extension resident memory, available-memory rejection/recovery, secure-field system fallback, numeric/phone fail-closed behavior, queue saturation, and unchanged base typing before release approval or hardware-policy changes. The matrix must include at least one 8-GiB device that exercises the enabled path and one sub-8-GiB device that verifies fallback.

## AI-07 Validation

- `cargo fmt --all`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo clippy -p private_pinyin_ime_ffi --all-targets --features desktop-ai -- -D warnings`: passed.
- `cargo test --workspace`: passed, including 53 local-AI core tests and the new exact-permutation candidate-page mutation guard.
- `cargo test -p private_pinyin_ime_ffi --features desktop-ai`: passed with worker-backed desktop C ABI coverage, secure-input fallback, stable partial-order completion, mismatch rejection, and an executable expired-ready-result no-reorder regression.
- `bash scripts/check_ai03_privacy_sources.sh`, `check_ai05_model_gate_sources.sh`, `check_ai06_lite_ranker_sources.sh`, and `check_ai07_desktop_integration_sources.sh`: passed; no network/external AI runtime or content log was introduced.
- `bash scripts/run_c_demo.sh`, `check_macos_imk_sources.sh`, and `check_windows_tsf_sources.sh`: passed.
- `bash scripts/build_macos_imk.sh`: passed with the `desktop-ai` FFI feature and produced `dist/macos_imk/PrivatePinyin.app`.
- GitHub Actions run `29653165683` passed Rust, macOS lifecycle, and Windows `windows-2022` MSVC/TSF jobs after the AI-07 merge.
- Physical MacBook Air M5 validation passed bounded queue pressure, expired/mismatched/invalid-order rejection, secure-input cancellation and base fallback, and exact 4096/8191/8192/16384-MiB hardware-threshold checks.
- Real secure-input probes observed the platform signal in a native `NSSecureTextField`, Chrome password field, and Safari password field; the signal returned to normal after the test fields closed.
- Windows 11 TSF password-field behavior and queue-pressure smoke still require a real Windows host; they cannot be closed by the macOS build or CI compiler alone.
- iOS build scripts do not enable `desktop-ai`; AI-08 uses the isolated `ios-ai` feature and the same bounded local worker without desktop host code.

## AI-06 Validation

- `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- `bash scripts/check_ai05_model_gate_sources.sh`: validates the approved package, exact files, hashes, sizes, external fingerprint, license, privacy, platform, and hardware declarations.
- `bash scripts/check_ai06_lite_ranker_sources.sh`: validates bounded source contracts and requires eight targeted improvements with zero preservation regressions.
- `.gitattributes` pins hashed model JSON and notice files to LF so Windows checkout cannot alter approved artifact bytes.
- Offline quality: baseline Top-1 `4/12`, MRR `0.653`; AI Lite Top-1 `12/12`, MRR `1.000`; 8 improved, 0 regressed, 0 gate failures.
- Local arm64 macOS reference inference: maximum `5 us`, mean `2.1 us` across the 12-case dataset; CI uses the deterministic 30 ms contract test rather than portable latency claims.
- Artifact: model version `1.0.1`, ranker `ai06-v1`, feature schema `1`, SHA-256 `340a2e54f2f5aace39728b38e968a1e4fee8740aab7c41c20af00923e8b85dbd`, 426 bytes; approval fingerprint `8bc7977a88f64a818fd232b7cfafd19af477232259e700d690ea37dfa639d439`.
- Boundary regressions cover maximum approved features, weights, candidate count, `i64` base-score extremes, and a `usize::MAX` rank-normalization input without arithmetic overflow.
- `AI-OI-009` tracks broader owner-approved typo, mixed-English, and long-candidate benchmarks before AI-07 without collecting production typing data.
- Production behavior: unchanged. No FFI, macOS, Windows, iOS, settings, or input-thread path invokes the ranker before AI-07.

## Update Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| UPDATE-01 | macOS version check and reminder | completed | 2026-07-14 22:27 | Merged to `main` through PR #20; fixed HTTPS feed, opt-in checks, strict-privacy gate, manifest validation, and update UI are complete |
| UPDATE-02 | Verified package download and Installer handoff | completed | 2026-07-15 00:08 | Bounded private download, SHA-256/size/signature/notarization verification, two-step consent, and visible system Installer handoff are ready for review |
| UPDATE-03 | Post-install process refresh | completed | 2026-07-15 10:38 | Merged to `main` through PR #22; dedicated UI-only postinstall helper, same-bundle launch-time detection, consent/revalidation, normal exit, success guidance, and logout-only fallback are complete |

## UPDATE-03 Validation

- `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- `bash scripts/run_c_demo.sh` and `bash scripts/build_macos_imk.sh`: passed.
- UPDATE-01, UPDATE-02, UPDATE-03, AI-01, macOS IMK, installer/settings, Stage 11, Stage 12, Stage 15, and Stage 16 source gates: passed.
- AppKit visual smoke: stale-process initial state and successful-refresh state rendered without clipping; both UI-only test instances exited after their final windows closed.
- Temporary unsigned pkg smoke: `pkgbuild` included the UPDATE-03 `postinstall`; the expanded script passed `sh -n` and launched the fixed signed-bundle executable path rather than unsupported LaunchServices `open`. The temporary package was removed after inspection.

## OI-045 Validation

- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- `bash scripts/run_c_demo.sh` and `bash scripts/build_macos_imk.sh`: passed; the public C ABI is unchanged.
- Stage 09 core, Windows TSF, macOS IMK, iOS keyboard, platform-validation, and AI-01 evaluation source gates: passed.
- Production lexicon behavior: `wojt` ranks `我今天` first; backspace plus retyping preserves the same visible ranking; `abc` still has no candidate and commits raw input.
- Cache behavior: append reused two then three normalized prefix characters, backspace reused the retained prefix, and changed apostrophe boundaries or previous context invalidated the affected cached suffix.
- Report-only arm64 macOS release benchmark: engine initialization p50 `36.84 ms` / p95 `61.13 ms`, continuous pinyin p95 `3.33 ms`, and mixed full/initial p95 `0.26 ms`; these are local reference values, not portable CI thresholds, and `OI-042` remains the cross-platform initialization follow-up.
- AI-01 required regressions remain `13/13`; the pre-existing observation case `mixed_full_initials` now meets target `1/1` through deterministic core behavior without any AI provider or model.

## iOS Keyboard UI Follow-up Validation

- Added a persistent inline `简体` / `繁體` output selector. Candidate display, predictions, and commits use the local system Chinese transform while core candidate identity and learning remain shared and normalized.
- Changed nine-key composition display to use the leading candidate's readable pinyin when available, so valid signatures such as `9664` no longer expose internal lookup digits; renamed the generic Return action from `换行` to `回车`.
- Beta Xcode readiness build: passed with `BUILD SUCCEEDED` for both the container app and Keyboard Extension; the resulting Debug app installed and launched on the iPhone 17 Pro / iOS 27 Simulator.
- Local conversion regression: `里面头发发展干嘛面条` produced `裡面頭髮發展乾嘛麵條`; 50,000 short-string conversions completed in approximately 0.03 seconds on the local Mac reference machine.
- iOS 27 runtime phrase probe confirmed that the system transform is phrase-aware for `头发 -> 頭髮`, `面条 -> 麵條`, `皇后在后面 -> 皇后在後面`, and `只有一只猫 -> 只有一隻貓`; a compiled regression now runs in the macOS CI job. The option remains documented as generic Traditional rather than complete Taiwan/Hong Kong localization.
- Simulator settings regression: a fresh local settings repair persisted `ios_chinese_script = simplified`, preserving the existing default until the user explicitly selects `繁體`.
- Expanded the iOS runtime candidate page from five to nine entries; long candidates remain readable in a horizontally scrollable strip, while group navigation stays fixed outside the scroll content.
- Added a dedicated `#+=` iOS symbol page covering the requested bracket, operator, book-title, punctuation, ellipsis, and separator characters without replacing the existing numeric/basic-symbol page.
- `bash scripts/check_ios_keyboard_sources.sh` and `bash scripts/run_ios_smoke_readiness.sh`: passed with Xcode 27 and the iOS 27 Simulator build.
- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed after the shared OI-045 decoder was included.
- iPhone 17 Pro / iOS 27 Simulator visual smoke: Station Cat colors, compact candidate strip, balanced QWERTY, adaptive nine-key controls, Shift/delete symbols, and inline preferences rendered without clipping.
- Full-key behavior: `nh` ranked `你好` first; an `a` candidate page moved forward and backward with fixed visible controls; touch-down typing produced one event per tap.
- Nine-key behavior: the saved layout reopened correctly, `64426` ranked `你好` first, and one candidate tap inserted exactly one `你好` into Messages.
- The system-owned bottom dictation key remains available when iOS provides it; the extension does not show a duplicate non-functional microphone control.

## iOS 0.1.20 (16) TestFlight Upload

- `plutil -lint`, `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- `bash scripts/run_ios_smoke_readiness.sh` with Xcode 26.6 (`17F109`) and iPhoneOS 26.5: passed with `BUILD SUCCEEDED`.
- The device Rust static library was rebuilt with `IPHONEOS_DEPLOYMENT_TARGET=18.0`; `vtool` reports the bundled SQLite object as iOS `minos 18.0` / SDK 26.5.
- Signed archive `dist/ios/PrivatePinyin-0.1.20-build16-xcode26.xcarchive` reports version `0.1.20`, build `16`, and arm64.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `9824d39f-ef1a-4fe2-a024-ad0bfd86b0be`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, and `IS-ON-APP-STORE-CONNECT: true`.
- External TestFlight review: submitted; `BUILD-STATUS` and `BETA-REVIEW-STATE` are both `WAITING_FOR_REVIEW`.

## iOS 0.1.21 (17) TestFlight Upload

- Container app and Keyboard Extension versions were advanced together to `0.1.21 (17)` in release commit `ab1fd88`.
- The device Rust FFI library was rebuilt for `aarch64-apple-ios` with `IPHONEOS_DEPLOYMENT_TARGET=18.0`.
- Signed archive `dist/ios/PrivatePinyin-0.1.21-build17-xcode26.xcarchive` reports version `0.1.21`, build `17`, and arm64.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `cd60fb42-9506-4aee-a7e8-4d71bb9d55cb`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, `BUILD-STATUS: BETA_INTERNAL_TESTING`, and `IS-ON-APP-STORE-CONNECT: true`.
- External TestFlight review: ready for the Owner to finish the test-content form, assign build `17` to the external group, and submit it for Beta App Review.

## iOS 0.1.22 (18) TestFlight Upload

- PR #32 was approved and merged to `main` as `3e33c42`; container app and Keyboard Extension versions were advanced together in release commit `4c1cae9`.
- The device Rust FFI library was rebuilt for `aarch64-apple-ios` with `IPHONEOS_DEPLOYMENT_TARGET=18.0`.
- Signed archive `dist/ios/PrivatePinyin-0.1.22-build18-xcode26.xcarchive` reports version `0.1.22`, build `18`, and arm64.
- `plutil -lint` for both release plists and `bash scripts/check_ios_keyboard_sources.sh`: passed.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `fe40dc42-10f0-4c4c-abd5-5bd9da81e122`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, `BUILD-STATUS: BETA_INTERNAL_TESTING`, and `IS-ON-APP-STORE-CONNECT: true`.
- External TestFlight review: ready for the Owner to add build `18` to the external group, provide test content, and submit it for Beta App Review.

## iOS 0.1.23 (19) TestFlight Upload

- PR #35 was merged as `b44eb7f` and PR #34 was merged as `a915ec6`; container app and Keyboard Extension versions were advanced together in release commit `c56a9a3`.
- `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, both release-plist lints, the iOS source gate, and the local Rime import source gate passed.
- The device Rust FFI library was rebuilt for `aarch64-apple-ios` with `IPHONEOS_DEPLOYMENT_TARGET=18.0`.
- Signed archive `dist/ios/PrivatePinyin-0.1.23-build19-xcode26.xcarchive` reports version `0.1.23`, build `19`, and arm64.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `586c1d52-6389-4564-a097-db40555f32ad`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, `BUILD-STATUS: BETA_INTERNAL_TESTING`, and `IS-ON-APP-STORE-CONNECT: true`.
- External TestFlight review remains a separate Owner action: assign build `19` to the external group, provide test content, and submit it for Beta App Review.

## iOS 0.1.24 (20) TestFlight Upload

- PR #42 was merged to `main` as `b048501`; container app and Keyboard Extension versions were advanced together to `0.1.24 (20)`.
- `plutil -lint` for both release plists, `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, the iOS source gate, AI-08 integration gate, and local Rime import gate passed.
- The device Rust FFI library was rebuilt for `aarch64-apple-ios` with `IPHONEOS_DEPLOYMENT_TARGET=18.0` and the `ios-ai` feature.
- Signed archive `dist/ios/PrivatePinyin-0.1.24-build20-xcode26.xcarchive` reports version `0.1.24`, build `20`, and arm64.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `e25c8f4b-64b2-46a6-b4d3-e83dbf8810d3`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, `BUILD-STATUS: BETA_INTERNAL_TESTING`, and `IS-ON-APP-STORE-CONNECT: true`.
- This candidate includes the Keyboard Extension activation repair, expandable nine-candidate browser, packed lexicon indexes, local document import, and explicit verified `rime-ice` import action.
- External TestFlight review remains a separate Owner action: assign build `20` to the external group, provide test content, and submit it for Beta App Review.

## iOS 0.1.25 (21) TestFlight Upload

- PR #44 was merged to `main` as `fe57d2f`; container app and Keyboard Extension versions were advanced together to `0.1.25 (21)`.
- `plutil -lint` for both release plists, the iOS source gate, Stage 14 signing gate, Stage 16 TestFlight gate, AI-08 integration gate, and `git diff --check` passed before archive.
- The device Rust FFI library was rebuilt for `aarch64-apple-ios` with `IPHONEOS_DEPLOYMENT_TARGET=18.0` and the `ios-ai` feature.
- Signed archive `dist/ios/PrivatePinyin-0.1.25-build21-xcode26.xcarchive` reports version `0.1.25`, build `21`, and arm64.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `7388b499-48c5-470e-89f4-95569a6b7309`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, `BUILD-STATUS: BETA_INTERNAL_TESTING`, and `IS-ON-APP-STORE-CONNECT: true`.
- This candidate includes smoother cold keyboard activation, the dedicated nine-key numeric and punctuation surfaces, the two-level container settings interface, and the merged AI-12 release hardening gates.
- External TestFlight review remains a separate Owner action: assign build `21` to the external group, provide test content, and submit it for Beta App Review.

## Completed Work

- Rebuilt the iOS Keyboard Extension visual surface from the Station Cat handoff with exact warm-dark tokens, 46-point candidate strip, gradient key styles, native pressed feedback, and compact inline preferences.
- Kept QWERTY as the default while preserving the optional nine-key layout; when iOS supplies the bottom Globe key, the nine-key grid uses its left control position for a visible `全键` return action.
- Added fixed previous/next candidate-group controls around the horizontal candidate scroller and a conservative end-of-pages state so paging remains reachable with long candidate text.
- Changed typing keys to touch-down delivery without changing command-key release semantics, and made core creation retryable so a transient settings/App Group failure does not leave the keyboard inert.
- Closed `OI-045` with a session-local continuous-decoder cache that retains bounded lattice states across ordinary key appends and safely truncates them for backspace.
- Added context and apostrophe-boundary compatibility checks plus composition-lifecycle clearing so cached path scores never cross commits, cancellations, resets, mode changes, sessions, or processes.
- Unified exact full-pinyin and initial edges inside the shared beam decoder with an abbreviation penalty and a minimum full-pinyin guard; `wojt` produces `我今天` while ordinary `abc` retains raw fallback behavior.
- Added production, backspace, cache-reuse, latency, and C ABI regressions, so macOS, Windows, and iOS inherit the feature without host-specific logic or ABI changes.
- Made `AiRequestBuilder` plus `PrivacyGuard` the only public local-AI request construction path while keeping the crate isolated from the engine, FFI, and platform hosts.
- Added fail-closed policy checks for disabled features, strict-privacy opt-out, unapproved model licenses, unsupported hardware, expanded budgets, expired deadlines, mismatched candidate identity, secure input, and missing explicit rewrite/translation consent.
- Added bounded content checks and local sensitive-pattern rejection for password/secret assignments, labeled or standalone one-time codes, payment cards, Chinese identity numbers, and phone numbers without exposing rejected content in errors.
- Distinguished full-pinyin and nine-key raw input so digit-only OTP heuristics fail closed for undeclared numeric input without blocking a declared `64426 -> 你好` nine-key request.
- Retained only the last eight non-empty recent tokens, rejected oversized candidate pages instead of changing their lifecycle hash, and kept forbidden clipboard/document/web/email/chat/screen context structurally absent.
- Added eighteen local-AI runtime tests plus AI-03 privacy, no-content-log, and no-network/external-service source gates; no model or user-visible input behavior is connected.
- Added explicit false-positive regressions for ordinary `API key`, `token economy`, `secret garden`, and `password manager` discussion, and tracked a categorized privacy corpus plus future context/confirmation/allowlist policy in `AI-OI-006`.
- Added the isolated `ai/local_ai_core` crate without connecting it to the existing engine, C ABI, or platform hosts.
- Defined local AI features, hardware tiers, latency/output budgets, monotonic deadlines, sanitized error codes, request/response candidate contracts, and opaque session/request/composition/candidate-set identity.
- Added a deterministic zero-dependency mock provider whose cancellation is scoped to the complete request identity and whose responses preserve identity for stale-result rejection.
- Redacted content-bearing request, candidate, and response `Debug` output so routine diagnostics cannot expose raw pinyin, composition text, candidate text, or recent tokens.
- Added eight focused runtime-contract tests and an AI-02 CI source gate; user-visible input behavior remains unchanged.
- Documented that the FNV candidate fingerprint is lifecycle-only and cannot serve as a persistent/cross-process cache identity; recorded AI-07's mandatory bounded worker-queue dispatch for the synchronous provider contract.
- Made the macOS Station Board preferences window resizable with a fixed aspect ratio, a compact 86% default size, and a bounded 72%-100% whole-canvas scale.
- Kept every card, label, button, custom toggle, and pointer hit region synchronized through AppKit scroll-view magnification; local visual smoke covered default and minimum sizes plus a toggle round trip at minimum scale.
- Disabled independent trackpad pinch magnification so only proportional window resizing can change the board scale, preventing hidden-scroller clipping at compact window sizes.
- Added UPDATE-03 post-install lifecycle handling without changing the shared Rust engine or normal IMK typing path.
- Changed pkg follow-up launch to a new UI-only executable process in the console user's Aqua session with a bounded install timestamp, avoiding both old-instance activation and Input Method LaunchServices failures.
- Made onboarding, preferences preview, and post-install modes UI-only so they never create a competing `IMKServer` and exit after their last window closes.
- Added exact-bundle PID/launch-time detection, current-helper exclusion, click-time target revalidation, normal termination only, and a bounded wait with no force-kill path.
- Made the launch cutoff strictly conservative: subsecond timestamps are used when available, while same-boundary and later processes are always preserved; a dedicated macOS CI job now executes the Swift policy tests instead of relying on Ubuntu's skip path.
- Added Station-style success and recovery guidance: successful refresh requires only switching input sources, while a process that remains receives logout/login instructions and no routine restart prompt.
- Added pure Swift policy tests, UPDATE-03 source gates, privacy/update-strategy decisions, and macOS upgrade smoke coverage.
- Added UPDATE-02 package delivery to the macOS host while keeping the shared Rust engine and typing path network-free.
- Added same-host HTTPS `.pkg` downloads through an ephemeral no-cache/no-cookie session, with streaming and final-size enforcement plus a private single-package cache.
- Added streaming CryptoKit SHA-256 verification, pinned Developer ID Installer Team ID validation, and notarization assessment through exact-argument `pkgutil` and `spctl` subprocesses.
- Added cancel/retry states, strict-privacy download cancellation, sanitized errors, a second user confirmation, and mandatory re-verification immediately before opening Apple's visible Installer app.
- Explicitly excluded silent privileged installation, `sudo`, credential collection, and automatic process restart from UPDATE-02; post-install process refresh remains UPDATE-03.
- Added UPDATE-01 version discovery to the macOS host without changing the network-free Rust engine or typing path.
- Kept automatic checks off by default, limited opt-in checks to once per 24 hours, paused them under strict privacy, and exposed manual checks through the menu and preferences.
- Added a fixed-host schema-1 manifest with HTTPS, redirect, response-size, package-extension, SHA-256, package-size, version, and minimum-system validation plus offline Swift tests and a CI source gate.
- Established AI-01 before introducing any model: a 20-case first-party offline corpus separates 13 required engine regressions from 7 observed AI improvement opportunities.
- Added deterministic Top-1, target-rank, found-rate, and MRR reporting plus a release-mode initialization/lookup latency benchmark with no machine-dependent CI threshold.
- Recorded dataset provenance and an explicit no-user-data rule; the parser rejects provenance other than project regressions or first-party synthetic cases.
- Added the approved AI-01 through AI-12 implementation plan, including stable visible candidate numbering and stale asynchronous-result rejection requirements.
- Added an optional iOS nine-key layout without replacing QWERTY or the symbols page; Chinese users can persistently switch with `九宫` / `ABC`, while English mode continues to use QWERTY.
- Added shared Rust nine-key indexing and continuous digit-string decoding, C ABI key code `102`, learned-candidate lookup, old SQLite user-phrase migration, and regression coverage for `64426 -> 你好`.
- Added local trigram learning so the last two selected tokens can produce context-specific next-token predictions across macOS, Windows, and iOS through the shared Rust core.
- Added 30-day-half-life ranking decay, an eight-token in-memory context bound, and decayed-weight capacity eviction for all four local learning tables.
- Added user-learning regression tests for trigram context, inactivity decay, privacy write guards, export/clear behavior, bounded context, and low-weight eviction.
- Changed the macOS candidate panel to InputMethodKit's horizontal 9-column stepping layout, made nine candidates the macOS default, and added a targeted migration from the previous default page size of five.
- Routed native candidate selection keys through the macOS controller first, keeping digit selection on one core-owned path while retaining four-host manual verification as a release gate.
- Bumped the macOS app metadata to `0.1.16 (16)` and added horizontal-layout source gates and smoke coverage.
- Bumped the macOS app and installer to `0.1.17 (17)` and the Windows/core package to `0.1.13`, with bundled Simplified Chinese release notes for bounded local trigram learning.
- Diagnosed intermittent macOS input loss as repeated `EXC_BAD_ACCESS` crashes in InputMethodKit server deactivation while calling `isVisible` on a released candidate panel.
- Retained the server-attached `IMKCandidates` panel for the input-method process lifetime, added host palette cleanup, and bumped the signed macOS release to `0.1.15`.
- Installed `0.1.15` over the existing build and completed 20 TextEdit/Chrome focus switches with active and committed compositions; the process stayed alive and the existing 17 crash reports did not increase.
- Replaced first-pass continuous-pinyin segmentation with a joint raw-character lattice and bounded beam decoder shared by macOS, Windows, and iOS.
- Added logarithmic phrase scoring, starter/base bigram transitions, local user-bigram reranking, apostrophe-boundary enforcement, and internal segment learning for selected sentence candidates.
- Added ambiguity, learned-reranking, common-sentence, apostrophe, and under-60-ms lookup regression tests for the second-generation decoder.
- Bumped the macOS app and installer to `0.1.14`, updated its bundled release notes, and produced a signed, notarized, stapled package for the second-generation decoder.
- Updated the Stage 15 source gate to match the current `Host composition` and `App Group fallback` smoke-record labels so CI can validate the merged iOS record again.
- Redesigned the macOS preferences window as a fixed dark Station Board with a branded header, privacy card, two-column prediction/learning controls, settings-file panel, and release information.
- Added dynamic public-version display without the internal build number, plus bundled Simplified Chinese release notes for future package updates.
- Bumped the macOS app and installer package to public version `0.1.13` for the redesigned preferences release.
- Added an isolated `--show-preferences` visual-preview path and verified the complete window on macOS with no clipped or overlapping content.
- Updated the Stage 11 privacy source gate to match the current localized iOS learning copy.
- Created the initial repository skeleton.
- Added the project development specification under `docs/`.
- Added progress, changelog, decision, and open item tracking files.
- Added platform and tool placeholder directories.
- Added a pull request template with privacy review checks.
- Addressed initialization PR review feedback for ignore rules, privacy logging, sample data provenance, and Stage 1 workflow expectations.
- Implemented the stage-01 Rust workspace and `ime_core` crate.
- Implemented `InputSession`, `KeyEvent`, `ImeOutput`, `Candidate`, basic pinyin parsing, embedded sample lexicon lookup, and simple ranking.
- Added `tools/test_cli` and minimal GitHub Actions for Rust validation.
- Addressed local review feedback for raw input limits, modifier-key passthrough, punctuation commits, no-candidate space fallback, and exact-before-prefix ranking.
- Addressed local review feedback so idle Enter does not commit an empty string.
- Implemented the stage-02 SQLite user lexicon and local bigram prediction.
- Added commit learning for selected candidates, plus `enable_user_learning` and `strict_privacy_mode` write guards.
- Added tests for `jintian -> 今天 -> 天气`, user lexicon persistence, disabled learning, and strict privacy mode.
- Addressed stage-02 review feedback so idle Space commits a normal space while digit keys select prediction candidates.
- Reused one mutex-protected SQLite connection per user lexicon instance instead of reopening the database for each lookup or learning write.
- Recorded follow-up open items for SQLite prefix range queries, exact-match preservation before query limits, user/base ranking fusion, and sanitized DB error logging.
- Deduplicated compact pinyin normalization across base and user lexicon lookup.
- Merged stage 02 to `main` through GitHub PR #3.
- Implemented the stage-03 `ffi/ime_ffi` crate that exposes `libprivate_pinyin_ime`.
- Added `ffi/c_api.h`, output ownership rules, C demo, Swift/C++ integration notes, and C ABI CI coverage.
- Added FFI tests for engine/session creation, `nihao` input, candidate reading, commit output, null-handle behavior, and output freeing.
- Addressed stage-03 review feedback by documenting NULL-return, non-thread-safe handle, and output ownership contracts in the C ABI.
- Added Rust layout assertions and C `_Static_assert` checks to catch header/ABI drift in CI.
- Recorded a follow-up open item for exposing user lexicon path, learning controls, and strict privacy mode through C ABI settings loading.
- Merged stage 03 to `main` through GitHub PR #4.
- Implemented the stage-04 Windows TSF C++ DLL prototype under `platform/windows_tsf`.
- Added COM class factory, `DllRegisterServer`/`DllUnregisterServer`, TSF profile registration hooks, and local `regsvr32` scripts.
- Added `ITfTextInputProcessorEx`, `ITfKeyEventSink`, and `ITfCompositionSink` host wiring for activation, key handling, composition updates, candidate display, and commit output.
- Added a thin C ABI bridge from Windows key events to the Rust core and a simple non-activating candidate popup.
- Added Windows build instructions, manual Notepad smoke-test steps, and a CI source scaffold check for TSF files.
- Addressed stage-04 review feedback so Windows TSF passes through Ctrl/Alt/Win shortcuts, avoids eating idle editing keys, and leaves Shift-modified text keys to the host.
- Recorded follow-up open items for TSF text-extent candidate positioning, window class unload cleanup, display attributes, and Windows CI compile coverage.
- Addressed stage-04 review feedback so Windows TSF hides prediction candidates and clears host active-input state on focus loss.
- Addressed stage-04 review feedback so Windows TSF resets the Rust session when focus loss or external composition termination invalidates host-side composition.
- Merged stage 04 to `main`.
- Implemented the stage-05 macOS InputMethodKit prototype under `platform/macos_imk`.
- Added Swift `IMKServer` startup and a `PrivatePinyinInputController` subclass for key handling, standalone Shift toggle, marked text, candidate selection, commit output, and cleanup.
- Added a Swift C ABI bridge around `ime_engine_new`, `ime_session_feed_key`, `ime_session_commit_candidate`, and `ime_session_reset`.
- Added `IMKCandidates` candidate panel wiring and local install/uninstall scripts for `~/Library/Input Methods`.
- Added `scripts/build_macos_imk.sh` to build an ad-hoc signed local `PrivatePinyin.app` bundle and `scripts/check_macos_imk_sources.sh` for CI scaffold checks.
- Recorded follow-up open items for macOS signing/notarization, packaged installer, candidate UI polish, and menu icon/settings UI.
- Addressed stage-05 review feedback so unhandled keys during active composition preserve current preedit/candidates instead of clearing host state.
- Addressed stage-05 review feedback so macOS Shift+digit passes through consistently with Windows, and recorded a follow-up for IMK candidate panel number-key routing validation.
- Implemented stage-06 JSON settings loading and atomic settings writing for `ImeSettings`.
- Wired `config_json_path` through the C ABI so desktop hosts can pass a settings snapshot path at engine creation.
- Added C ABI and Rust core APIs for clearing and exporting the user lexicon.
- Added `tools/settings_cli` for installer scripts to write defaults, toggle strict privacy mode, clear the user lexicon, and export the user lexicon.
- Added macOS settings menu actions for strict privacy mode, clearing/exporting the user lexicon, and opening the settings file.
- Added Windows settings initialization under `%LOCALAPPDATA%\PrivatePinyin` and a PowerShell settings window for privacy, learning, prediction, clear, and export actions.
- Added prototype packaging scripts for macOS `.pkg`, Windows installer staging zip, and optional WiX MSI generation.
- Added a Windows NSIS setup EXE packaging path for internal testing, including 64-bit TSF registration and a post-install setup guide.
- Fixed the Windows NSIS setup EXE to use the cat-brand installer icon instead of the default NSIS gear icon.
- Hardened the Windows NSIS setup EXE as version `0.1.11` by requesting administrator rights and making TSF profile registration clear stale records before reinstalling.
- Localized the Windows TSF display name and installer surfaces to `猫栈拼音`, bumped the Windows/core build to `0.1.12`, and added first-pass continuous-pinyin, initials shorthand, full-width punctuation, and common `lü` lexicon fixes.
- Added CI scaffold coverage for installer/settings files.
- Addressed stage-06 review feedback by changing the WiX MSI template to per-user install and user-context TSF registration.
- Addressed stage-06 review feedback by enabling SQLite WAL and a busy timeout for multi-process user lexicon writes.
- Addressed stage-06 review feedback so invalid numeric settings clamp to defaults without discarding other settings, and export without a configured user lexicon writes an empty TSV.
- Recorded follow-up open items for default settings drift, stronger Rust atomic file replacement, and CapsLock toggle support.
- Merged stage 06 to `main`.
- Implemented the stage-07 iOS container app and Keyboard Extension prototype under `platform/ios_keyboard`.
- Added a SwiftUI container app with a clear-local-lexicon action for app-container artifacts.
- Added a `UIInputViewController` keyboard extension with QWERTY rows, candidate bar, Globe key, symbols toggle, Chinese/English toggle, Space, Delete, and Return.
- Added an iOS C ABI bridge that creates the Rust engine/session, feeds key events, commits candidates, toggles mode, and frees outputs.
- Added `PrivatePinyinC/module.modulemap` and `scripts/build_ios_keyboard.sh` to link the Rust C ABI as an iOS static library.
- Added `RequestsOpenAccess=false` in the keyboard extension plist and CI scaffold checks for iOS privacy defaults and network API absence.
- Recorded follow-up open items for iOS App Store signing, App Group storage, user-facing permission explanation, simulator/device smoke tests, mode-state derivation, and Globe key visibility.
- Addressed stage-07 review feedback so iOS self-triggered text changes do not reset the Rust session, Chinese-mode Shift+letter inserts uppercase text, and mode-toggle UI state only changes after engine success.
- Merged stage 07 to `main`.
- Added stage-08 platform validation and CI hardening work.
- Added a pinned `windows-2022` GitHub Actions job that runs `cargo test --workspace`, runs `scripts/build_windows_tsf.ps1`, and compiles the Windows TSF DLL with MSVC/CMake.
- Added Rust build caching to CI.
- Added `docs/platform_smoke_test_plan.md` with manual smoke-test record templates for Windows 11 TSF, macOS InputMethodKit, and iOS Keyboard Extension, including focus/app-switch cleanup and multi-process learning regressions.
- Added `scripts/check_platform_validation_sources.sh` and wired it into CI.
- Extended the development specification with release-preparation stages 8 through 12.
- Linked platform READMEs to the shared smoke-test record template.
- Fixed CI feedback by pinning the Windows runner, making Windows COM declarations and DLL exports explicit, and adding a non-`rg` fallback to the iOS source scan.
- Closed `OI-022` for Windows Rust test and TSF compile CI coverage while keeping runtime smoke-test items open.
- Implemented stage-09 core production hardening.
- Changed base lexicon lookup to build a compact-pinyin sorted index and use binary prefix ranges.
- Changed SQLite user lexicon lookup to use compact-pinyin range queries and exact-row preservation before prefix limits.
- Added exact/prefix-aware user/base ranking fusion before deduplication.
- Implemented candidate paging by `candidate_page_size`, with PageUp/PageDown and ArrowUp/ArrowDown page movement.
- Changed composition punctuation to commit the first visible candidate plus punctuation, such as `你好,` for `nihao,`.
- Added sanitized log sink support and wired user lexicon lookup/learning failures to `error code=...` events.
- Added `docs/lexicon_data_policy.md` to keep production lexicon replacement gated on source/license approval.
- Added `scripts/check_stage09_core_sources.sh` and wired it into CI.
- Addressed stage-09 review feedback by constraining numeric selection to the visible candidate page, adding a SQLite `pinyin` index for exact user-lexicon lookup, documenting the compact-prefix upper-bound assumption, and recording host log callback work as `OI-041`.
- Closed `OI-006`, `OI-008`, `OI-009`, `OI-010`, `OI-011`, `OI-012`, and `OI-013`; kept `OI-001` open for licensed production data selection.
- Merged stage 09 to `main` through GitHub PR #8.
- Implemented stage-10 platform host polish.
- Changed Windows TSF candidate popup positioning to use `ITfContextView::GetTextExt` inside the edit session, with a caret fallback when text extents are unavailable.
- Added DPI-aware sizing, Windows app light/dark theme colors, monitor work-area clamping, and one-time window-class registration/unregistration for the Windows candidate popup.
- Added a macOS InputMethodKit Preferences window for strict privacy, prediction, and user learning toggles, with input-engine reload after settings changes.
- Addressed stage-10 review feedback by making the macOS preferences window a shared process-wide controller and broadcasting settings changes to all active input controllers.
- Added `scripts/check_stage10_platform_host_sources.sh` and wired it into CI.
- Closed `OI-017`, `OI-019`, and `OI-020`; kept TSF display attributes, custom macOS menu icon assets, and real platform smoke validation open.
- Merged stage 10 to `main`.
- Implemented stage-11 settings, privacy, and iOS storage closure.
- Added a shared Rust `AtomicFile` helper and moved settings JSON writes plus user lexicon TSV exports away from remove+rename.
- Added a Rust test that keeps `config/default_settings.json` aligned with `ImeSettings::default`.
- Changed Windows, macOS, and iOS default settings initialization to read packaged `default_settings.json` and patch only platform-local user lexicon paths.
- Added iOS App Group entitlements for the container app and keyboard extension, and made the shared settings/user-lexicon path available to both targets.
- Added iOS container-app controls and copy for Full Access, no-network behavior, App Group storage, local learning opt-in, and lexicon clearing.
- Changed the iOS keyboard extension to pass the settings path into `ime_engine_new`, derive mode UI from `ImeOutput.mode`, and hide the Globe key when `needsInputModeSwitchKey` is false.
- Added `scripts/check_stage11_settings_privacy_sources.sh` and wired it into CI.
- Closed `OI-032`, `OI-033`, `OI-034`, `OI-036`, `OI-037`, `OI-039`, and `OI-040`; kept iOS simulator/device smoke validation open as `OI-038`.
- Addressed stage-11 review feedback so the iOS keyboard falls back to the built-in engine if shared settings or App Group storage cannot be opened, and expanded `OI-038` to explicitly verify `RequestsOpenAccess=false` App Group behavior on device/simulator.
- Addressed stage-11 review feedback by pinning the `"user_lexicon_path": null` default-template format in the Stage 11 source check so Windows template patching cannot silently lose learning after JSON reformatting.
- Implemented stage-12 release packaging and distribution preparation.
- Added `docs/release_distribution_plan.md` with public release gates for final license, production lexicon data, signing, notarization, iOS provisioning, platform smoke-test evidence, privacy posture, and version consistency.
- Extended Windows packaging with SignTool support for staged DLL/EXE artifacts and MSI output, plus a `-RequireSigning` gate for release candidates.
- Extended macOS app and pkg scripts with Developer ID app signing, hardened runtime, installer signing, notarytool submission, and stapling hooks while keeping ad-hoc/unsigned local builds available by default.
- Added an iOS App Store archive/export script that requires owner-provided team ID and export options.
- Added iOS App Store metadata and export-options templates under `platform/ios_keyboard/AppStoreMetadata`.
- Recorded the initial automatic update strategy: signed MSI/zip, signed/notarized pkg, and TestFlight/App Store updates first; defer Sparkle, MSIX, and App Installer.
- Added `scripts/check_stage12_release_sources.sh` and wired it into CI.
- Updated platform READMEs, script docs, changelog, decisions, open items, and development spec for Stage 12 release gates.
- Addressed stage-12 review feedback so Windows packaging signs staged PowerShell installer/settings scripts with Authenticode when a signing certificate is configured, and folded that requirement into `OI-015`.
- Added a macOS post-install onboarding window that opens after pkg installation and links users to Keyboard Settings.
- Updated macOS input method metadata for System Settings discovery and added smoke-test coverage for input-source discovery, enabling, and upgrade-onboarding behavior.
- Redesigned the macOS onboarding window with the Station Cat visual system: fixed dark appearance, warm lamp accent, Chinese setup copy, station-style step card, and hover-aware custom AppKit buttons.
- Addressed macOS onboarding review feedback by removing the `paddedBadge` local-variable shadowing risk and pinning the brand row width so the `setup` badge aligns to the right edge.
- Bumped the app and package version from `0.1.0` to `0.1.3` for the regenerated onboarding installer and input source discovery refresh.
- Fixed macOS input source discovery by setting `tsInputModeDefaultStateKey` to false; local System Settings debugging showed default-enabled third-party modes are filtered out of the add-input-source list.
- Implemented Stage 13 lexicon import and starter dictionary work.
- Added active `base_lexicon.tsv` and `bigram.tsv` first-party starter assets so installed local builds are no longer limited to the original eight-word sample lexicon.
- Changed the Rust core to load the active starter assets while retaining the original sample files as source fixtures.
- Added `tools/lexicon_builder`, a local Rust CLI that converts project TSV or local CC-CEDICT-style files into the standard base-lexicon TSV and emits an audit manifest with a release-approval flag.
- Updated lexicon policy, manifest, changelog, README, CI, and open items so `OI-001` remains open for owner-approved production data.
- Added `scripts/check_stage13_lexicon_sources.sh` and wired it into CI.
- Extended `tools/lexicon_builder` with mozillazg pinyin-data and AOSP PinyinIME rawdict import support, including UTF-16 rawdict decoding, marked-pinyin normalization, frequency scaling, and supplemental single-character readings.
- Replaced the first-party starter base lexicon with a 100,657-entry owner-approved AOSP PinyinIME rawdict import supplemented by pinyin-data single-character readings.
- Added `THIRD_PARTY_NOTICES.md`, updated the active lexicon manifest with exact upstream revisions and licenses, and closed `OI-001` for the current bundled base dictionary.
- Added a `ganma -> 干嘛` core candidate regression.
- Addressed macOS formal-pkg review feedback by documenting that `tsInputModeDefaultStateKey` must stay `false`, pinning that value in the macOS scaffold check, and recording the decision in `docs/DECISIONS.md`.
- Added a macOS C ABI fallback so the installed IMK host retries `ime_engine_new(nil)` if a user settings path cannot open.
- Verified the actual `PrivatePinyin-0.1.3.pkg` install path from `/Library/Input Methods`: `PrivatePinyin 拼音` appears under Simplified Chinese, the TIS mode can be enabled/selected, and TextEdit commits `nihao -> 你好`.
- Added the redesigned macOS template menu icon, color app icon, and `InfoPlist.strings` localization fallback resources.
- Wired the new icon resources into the macOS IMK plist, build script, package output, and scaffold checks.
- Bumped the workspace, platform plist, and package default versions to `0.1.7` for the icon/name refresh.
- Renamed the macOS Chinese input source display name to `猫栈拼音`, with localized input method name `猫栈`.
- Closed `OI-028` for macOS settings entry and menu icon assets; real light/dark menu-bar icon appearance still needs macOS smoke evidence.
- Localized the macOS input method menu, preferences window, and settings action alerts into Chinese.
- Updated the macOS onboarding window title, brand label, and setup subtitle to consistently refer to `猫栈拼音`.
- Bumped the workspace, platform plist, and package default versions to `0.1.8` for the macOS menu localization refresh.
- Redesigned the macOS preferences window with the Station Cat dark visual system, custom toggle controls, a settings path card, and hover-aware AppKit buttons.
- Extended macOS scaffold checks to pin the redesigned preferences window's fixed dark appearance, Chinese settings copy, custom toggles, and hover states.
- Bumped the workspace, platform plist build numbers, and package default versions to `0.1.9` for the macOS preferences UI refresh.
- Added a macOS public-release checklist for personal-website distribution, including Developer ID setup, notarization, website download copy, smoke tests, and manual update flow.
- Added `scripts/check_macos_public_release.sh` to gate public `.pkg` publication on Developer ID identities, package signature, Gatekeeper install assessment, stapled notarization, notarytool profile access, and SHA256 output.
- Documented that the local pkg remains blocked for public website distribution until Owner-provided Developer ID certificates and notarization evidence are available.
- Added first-pass local user bigram learning so selecting `A` then `B` teaches the local predictor to suggest `B` after future `A` commits.
- Kept user bigram learning behind the existing `enable_user_learning` and `strict_privacy_mode` write guards.
- Extended user lexicon clear/export behavior to cover learned one-step prediction transitions.
- Added second-pass local short phrase learning so selecting `A`, `B`, then `C` can teach the local predictor to suggest `BC` after future `A` commits.
- Kept short phrase learning bounded to two-token continuations with a 12-character phrase cap, and covered it with clear/export behavior.
- Addressed short-phrase-learning review feedback so prediction candidates without pinyin do not create empty-pinyin `user_bigrams` rows.
- Bumped the workspace, platform plist build numbers, and package default versions to `0.1.10` for the regenerated macOS installer.
- Deleted the old local macOS `0.1.9` package and generated `dist/macos_imk/PrivatePinyin-0.1.10.pkg` as a local unsigned test installer.

## Current Work

- UPDATE-02 is implemented on `codex/update-02-verified-installer` and is awaiting PR review.
- A package is downloaded only after explicit consent, verified away from the typing thread, and handed to Apple's Installer only after a second confirmation and immediate re-verification.
- The current public stable-manifest endpoint still returns HTTP 404, so a successful live-package end-to-end smoke remains blocked on publisher action and is tracked as `UPDATE-OI-001`.
- UPDATE-03 stale-process detection and reload/logout/restart guidance has not started.

## Validation Results

- Command: `cargo test --workspace`
- Result: passed
- Notes: 67 workspace tests passed with workspace crates reporting version `0.1.10`.

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: No clippy warnings in the Rust workspace.

- Command: `cargo fmt --check`
- Result: passed
- Notes: Formatting is clean after the macOS package refresh.

- Command: `bash scripts/check_stage09_core_sources.sh`
- Result: passed
- Notes: Existing core production-hardening scaffold remains green after adding local short phrase prediction learning.

- Command: `bash scripts/check_macos_imk_sources.sh`
- Result: passed
- Notes: macOS IMK scaffold remains green after the version bump.

- Command: `env CARGO_NET_OFFLINE=true bash scripts/package_macos_pkg.sh`
- Result: passed
- Notes: Built local unsigned test package `dist/macos_imk/PrivatePinyin-0.1.10.pkg`; package signature check reports `Status: no signature`.

### Stage 14 - iOS Signing And App Group Configuration

- Added explicit iOS release inputs for Apple team ID, container app bundle ID, keyboard extension bundle ID, App Group ID, and export-options plist.
- Changed the iOS Xcode project, Info.plist files, and entitlements to inject App Group and bundle identifiers through build settings while keeping local defaults.
- Added `Signing.env.example`, ignored local signing/export plist files, export-options consistency checks, and a Stage 14 source-check script wired into CI.
- Kept `OI-035` open for owner-provided provisioning profiles, App Store metadata, archive/export evidence, and TestFlight validation.

- Command: `git diff --check`
- Result: passed
- Notes: No whitespace or patch formatting issues.

- Command: `bash scripts/check_ios_keyboard_sources.sh`
- Result: passed
- Notes: Existing iOS keyboard scaffold check accepts build-setting injected App Group values.

- Command: `bash scripts/check_stage11_settings_privacy_sources.sh`
- Result: passed
- Notes: Stage 11 privacy/storage gates remain green after the App Group source wiring change.

- Command: `bash scripts/check_stage12_release_sources.sh`
- Result: passed
- Notes: Existing release packaging gates remain green.

- Command: `bash scripts/check_stage14_ios_signing_sources.sh`
- Result: passed
- Notes: Stage 14 signing, bundle ID, App Group, and export-options source gates pass.

- Command: `bash scripts/build_ios_keyboard.sh`
- Result: passed
- Notes: Required sandbox escalation for local Xcode/CoreSimulator access; produced a Debug iOS Simulator build and expanded `PrivatePinyinAppGroupIdentifier` to `group.com.privatepinyin.ios` in both the app and keyboard extension Info.plist files.

- Command: `bash -n scripts/package_ios_app_store.sh scripts/build_ios_keyboard.sh scripts/check_stage14_ios_signing_sources.sh scripts/check_ios_keyboard_sources.sh scripts/check_stage11_settings_privacy_sources.sh`
- Result: passed
- Notes: Shell script syntax is valid.

- Command: `cargo fmt --check`
- Result: passed
- Notes: Rust formatting remains clean.

### Stage 15 - iOS Smoke Readiness

- Added `scripts/run_ios_smoke_readiness.sh` to run source gates, build the iOS Simulator app/extension, and verify built bundle identifiers, App Group expansion, `RequestsOpenAccess=false`, `PrimaryLanguage=zh-Hans`, bundled defaults, and no-network Keyboard Extension Swift sources.
- Added `docs/ios_keyboard_smoke_record.md` to separate automated readiness evidence from the remaining manual Simulator/device keyboard checks.
- Added `docs/ios_release_stage_plan.md` to record the Stage 14-18 iOS release-preparation plan.
- Added `scripts/check_stage15_ios_smoke_sources.sh` and wired it into CI.
- Updated `OI-038` to keep manual keyboard enablement, Notes composition, prediction retention, App Group storage, Globe switching, no Full Access, and password/phone fallback checks open.

- Command: `bash scripts/check_stage15_ios_smoke_sources.sh`
- Result: passed
- Notes: Stage 15 source scaffold, smoke record, platform smoke plan link, and shell syntax checks passed.

- Command: `bash scripts/run_ios_smoke_readiness.sh`
- Result: passed
- Notes: Required sandbox escalation for local Xcode/CoreSimulator access; produced the Debug iOS Simulator app and Keyboard Extension, verified bundle IDs, App Group expansion, `RequestsOpenAccess=false`, `PrimaryLanguage=zh-Hans`, bundled defaults, and no-network Keyboard Extension Swift source usage.

### Stage 16 - TestFlight Archive And Upload

- Added upload-aware `scripts/package_ios_app_store.sh` validation for `ExportOptions.plist` destination, App Store Connect API key inputs, and package summary output.
- Added `platform/ios_keyboard/AppStoreMetadata/ExportOptions.upload.plist.template` for App Store-eligible TestFlight uploads without forcing internal-only distribution.
- Extended `Signing.env.example` and iOS platform docs with App Store Connect API key variables.
- Added `docs/ios_testflight_upload_record.md` to track signed archive/export, uploaded build number, processing status, and TestFlight distribution status.
- Added `scripts/check_stage16_ios_testflight_sources.sh` and wired it into CI.
- Updated `OI-035` to keep real provisioning profiles, signed archive/export, upload, and TestFlight evidence open for Owner credentials.

- Command: `bash scripts/check_stage16_ios_testflight_sources.sh`
- Result: passed
- Notes: Stage 16 upload template, App Store Connect API key gating, package summary, upload record, and CI scaffold checks passed.

- Command: `bash -n scripts/package_ios_app_store.sh`
- Result: passed
- Notes: Shell syntax is valid. The scripted API-key path remains available; build 13 used the signed-in Xcode account, automatic provisioning, and direct `xcodebuild -exportArchive` upload instead.

### Stage 17 - Optimized iOS Keyboard Build 13

- Command: `cargo test --workspace && cargo fmt --all -- --check && cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: All 70 Rust tests passed; formatting and clippy were clean.

- Command: `env DEVELOPER_DIR=/Users/shaola/Downloads/软件/Xcode.app/Contents/Developer bash scripts/run_ios_smoke_readiness.sh`
- Result: passed
- Notes: Beta Xcode reported `BUILD SUCCEEDED`; Stage 14-16 source gates, bundle IDs, App Group expansion, `RequestsOpenAccess=false`, bundled settings, and no-network checks passed.

- Command: iOS 27.0 iPhone 17 Pro Simulator manual smoke
- Result: passed
- Notes: Added `猫栈拼音`, kept Full Access off, verified `nihao -> 你好`, `wojintian -> 我今天`, retained prediction, inline learning opt-in, current-container path repair, Globe switching, and non-overlapping portrait/landscape layouts.

- Command: Beta Xcode Release archive and App Store Connect upload
- Result: passed
- Notes: `dist/ios/PrivatePinyin-build13.xcarchive` reports `0.1.12 (13)` arm64; Xcode reported `Upload succeeded` with delivery UUID `0ba67b28-a10c-437c-9968-456d8ee8d95b`.

- Command: `xcrun altool --build-status --delivery-id 0ba67b28-a10c-437c-9968-456d8ee8d95b --wait ...`
- Result: passed
- Notes: Apple returned `import-status=VALID`, `build-audience-type=APP_STORE_ELIGIBLE`, and `is-on-app-store-connect=true`.

### Stage 17 - Local Trigram TestFlight Build 14

- Command: `cargo test --workspace && cargo fmt --all -- --check && cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: All 83 Rust workspace tests passed; formatting and clippy were clean.

- Command: `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/run_ios_smoke_readiness.sh`
- Result: passed
- Notes: Xcode 27 and the iOS 27 Simulator build passed Stage 14-16 source gates, App Group expansion, `RequestsOpenAccess=false`, bundled settings, and no-network checks.

- Command: iOS 27.0 iPhone 17 Pro Simulator trigram smoke
- Result: passed
- Notes: With Full Access off and local learning enabled, selecting `我 -> 喜欢 -> 猫` created the expected local trigram row; a new `我 -> 喜欢` context then predicted `猫`.

- Command: Xcode 27.0 beta archive and App Store Connect upload
- Result: upload rejected before import
- Notes: App Store Connect no longer accepted build `27A5194q`; no TestFlight build was created from this attempt.

- Command: Xcode 26.6 Release archive and App Store Connect upload
- Result: passed
- Notes: `dist/ios/PrivatePinyin-build14-xcode26.xcarchive` reports `0.1.18 (14)`, iPhoneOS 26.5, and arm64; Xcode reported `Upload succeeded` with delivery UUID `2bcd0055-5594-46bd-aa56-d8193b53ba58`.

- Command: `altool --build-status --delivery-id 2bcd0055-5594-46bd-aa56-d8193b53ba58 --wait ...`
- Result: passed
- Notes: Apple returned `import-status=VALID`, `build-audience-type=APP_STORE_ELIGIBLE`, `build-status=BETA_INTERNAL_TESTING`, and `is-on-app-store-connect=true`.

### macOS 0.1.13 Signed Release Package

- Command: signed `bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and `private-pinyin-notary`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.13.pkg`; Apple notarization submission `edc25310-8b8f-4558-84c3-706bcad40dbb` returned `Accepted`, and stapling succeeded.

- Command: `PRIVATE_PINYIN_VERSION=0.1.13 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: Trusted installer signature, Gatekeeper assessment, stapled ticket, notarytool profile, and SHA-256 validation passed. SHA-256: `9c17738382c030a87db4208ba456e1abcf73545af85bb63a451ea8147ca1451e`.

### macOS 0.1.14 Signed Release Package

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.14 bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and `private-pinyin-notary`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.14.pkg`; Apple notarization submission `9a037028-fae7-46d8-b7ef-8a9801f92571` returned `Accepted`, and stapling succeeded.

- Command: `PRIVATE_PINYIN_VERSION=0.1.14 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: Trusted installer signature, Gatekeeper assessment, stapled ticket, notarytool profile, and SHA-256 validation passed. SHA-256: `30c75e24d8ad9b3356acfc6aa7e50e47fb30e9363f23ac2aad06dbd61b40cd79`.

### macOS 0.1.15 Candidate-Panel Lifetime Fix

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.15 bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and `private-pinyin-notary`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.15.pkg`; Apple notarization submission `e413d75d-d53e-49b5-9918-0c40f20ac5ba` returned `Accepted`, and stapling succeeded.

- Command: `PRIVATE_PINYIN_VERSION=0.1.15 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: Trusted installer signature, Gatekeeper assessment, stapled ticket, notarytool profile, and SHA-256 validation passed. SHA-256: `cb48d25bfd31345ba91f9a9d073a9cf49cabb407d376edaa304b04cffdf59211`.

- Command: installed-upgrade TextEdit/Chrome focus-switch smoke
- Result: passed
- Notes: Verified installed version `0.1.15 (15)`, committed `nihao -> 你好` in Chrome, switched between TextEdit and Chrome 20 times with candidates active or committed, confirmed the process remained alive, and observed no new `PrivatePinyin-*.ips` report beyond the 17-report pre-test baseline.

### macOS 0.1.16 Horizontal Candidate Package

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.16 bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and `private-pinyin-notary`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.16.pkg`; Apple notarization submission `37ddc538-0be0-4f11-b24c-8ba9968e4220` returned `Accepted`, and stapling succeeded.

- Command: `PRIVATE_PINYIN_VERSION=0.1.16 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: Trusted installer signature, Gatekeeper assessment, stapled ticket, notarytool profile, and SHA-256 validation passed. SHA-256: `678026ab7a6e9c86b284e5048c78fa52fbb59f587954e2f16e33495a1d41a289`. Four-host horizontal layout and number-selection smoke remains required before public release.

### Local Trigram Learning Validation

- Command: `cargo test --workspace`
- Result: passed
- Notes: All Rust, C ABI, layout, settings, prediction, privacy, lexicon-builder, and 28 user-lexicon tests passed, including legacy-schema migration and concurrent SQLite learning updates.

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: C ABI demo returned `你好` and committed it successfully.

- Command: `bash scripts/build_macos_imk.sh`
- Result: passed

- Command: `bash scripts/build_ios_keyboard.sh`
- Result: passed
- Notes: Xcode 27 Simulator build completed with `BUILD SUCCEEDED` after running with CoreSimulator access.

- Command: stage 09/11, platform-validation, macOS, iOS, and Windows source gates
- Result: passed

- Command: GitHub Actions CI run `29180012276` on PR #15
- Result: passed
- Notes: Ubuntu Rust/source gates and the `windows-2022` Rust/TSF job both passed; the Windows job includes the concurrent trigram learning regression that originally exposed SQLite writer starvation.

### macOS 0.1.17 Bounded Trigram Package

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.17 bash scripts/package_macos_pkg.sh` with Developer ID Application and Developer ID Installer, followed by direct `notarytool submit` using the existing local Apple credential
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.17.pkg`; Apple notarization submission `90edbce9-e28f-40a9-9f98-71830dad8839` returned `Accepted`, and stapling succeeded.

- Command: trusted-system `pkgutil --check-signature`, `spctl --assess --type install`, `xcrun stapler validate`, and `codesign --verify --deep --strict`
- Result: passed
- Notes: Developer ID Installer and Application signatures are valid, Gatekeeper reports `Notarized Developer ID`, and SHA-256 is `43bcec63708a16098dec51a6a0d7533795a0cf7b7d459040eb1e9abf449bdb79`.

### macOS 0.1.22 AI-07 Validation Package

- Command: signed and notarized `bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and the `private-pinyin-notary` profile
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.22.pkg`; Apple notarization submission `5b4d744d-9251-4a2d-954d-c8e3415f6769` returned `Accepted`, stapling succeeded, and the full public-release preflight passed.
- SHA-256: `bbe3ab7ef99bb429e4be97fa0230fbfefc35dbde9fd483d7675c135d48e25b92`
- Install smoke: installed over the existing input method; the installed bundle reports `0.1.22 (22)`, its nested dylib passes strict code-signature verification, and Gatekeeper reports `Notarized Developer ID`.
- Host input smoke: TextEdit, Chrome, and Safari each committed `nihao -> 你好`; a 20-cycle rapid TextEdit run produced exactly 20 `你好` commits without a lost or duplicated key. VS Code was not installed on the validation Mac and remains unexecuted.
- Installed-artifact AI smoke: the packaged dylib enabled AI Lite at 8192/16384 MiB, rejected 4096/8191 MiB, preserved five base candidates, and kept secure-input base fallback functional. A 3250-call pressure run completed with 1.734-ms mean, 8.395-ms P95, 8.536-ms P99, and 10.202-ms maximum feed latency.
- Remaining release gates: clean-user install/uninstall, visible horizontal overflow and `1` through `9` candidate selection, VS Code host coverage, website checksum publication, and a real Windows 11 TSF password/pressure smoke.

### Desktop 0.1.23 Lexicon Release Packages

- Command: signed and notarized `PRIVATE_PINYIN_VERSION=0.1.23 bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and the `private-pinyin-notary` profile
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.23.pkg`; Apple notarization submission `9dd8e96f-f94a-464e-8a7c-2cc293765b59` returned `Accepted`, stapling succeeded, Gatekeeper accepted the package as `Notarized Developer ID`, and the full public-release preflight passed.
- macOS SHA-256: `ee057e94e55ac68f4c193d4e4e57967c20f163c88d9f84fa9739381805104e66`
- Release scope: expanded reviewed permissive base lexicon plus upgrade-safe, separately stored local Rime text-dictionary import. A `0.1.23` installed-upgrade smoke remains pending.

- Command: GitHub Actions `Windows Unsigned Package`, run `29688158295`, version input `0.1.23`
- Result: passed
- Notes: The `windows-2022` job built and uploaded NSIS EXE, WiX MSI, and ZIP packages from commit `9931a12`; the downloaded ZIP reports `0.1.23`, includes x64 and x86 TSF components, and carries the matching Simplified Chinese release notes. These Windows artifacts remain unsigned internal-test packages.
- EXE SHA-256: `8ed9510556d14a7744547355881f3cfcfa8b58e5e36db0150ac298cf26f5fa7c`
- MSI SHA-256: `42d46d0f4f3b4733397a511702c8e034b7a8bd96860a4988f32773b27ba85a7f`
- ZIP SHA-256: `70b8d19b2f130e93bec24343674702049616a0c0f3ee727c2e3d5c5e0ccb0496`

### Windows 0.1.25 Unsigned Feature Package

- Command: GitHub Actions `Windows Unsigned Package`, run `30428421394`,
  version input `0.1.25`
- Result: passed in 5 minutes 19 seconds on `windows-2022`
- Source: `main` commit `9600c5528069d5ccd38221c8c59ee59f24dadbe0`
- Notes: The NSIS EXE, WiX MSI, and ZIP include x64/x86 TSF components,
  stable default-candidate identity, opt-in tolerant pinyin,
  confirmation-based learning hysteresis, prediction-state digit
  pass-through, and the Windows White Frost/settings path and TLS fixes.
  The packaged Simplified Chinese release notes and preferences `本版更新`
  copy describe the same scope.
- Validation: `cargo test --workspace`, strict workspace and desktop-AI
  Clippy, desktop-AI FFI tests, reviewed White Frost archive tests, Windows
  installer/settings source gates, formatting, and `git diff --check` passed.
  The Apple-only stateless nine-key latency test initially measured
  `65.341687 ms` under unrelated host load, then passed its unchanged `60 ms`
  budget on targeted rerun and in the complete workspace rerun.
- EXE: `dist/windows_tsf/PrivatePinyin-0.1.25-setup.exe`
  (`13,461,501` bytes), SHA-256
  `f819de9a17ad319ce3abf5f8551b674278e3e90709167cb457e73932fff41600`
- MSI: `dist/windows_tsf/PrivatePinyin-0.1.25.msi`
  (`24,539,136` bytes), SHA-256
  `36c9c311fd4ee55cb454e02f512e51f2f54f4fa343cc308209aa0ffeb8ba31a3`
- ZIP: `dist/windows_tsf/PrivatePinyin-0.1.25.zip`
  (`25,319,305` bytes), SHA-256
  `de1e6465015b6786083a94b27b82c47854cf8f6498baecc7c37edb58e1de2e4b`
- Distribution note: these Windows artifacts are unsigned and remain
  internal-test packages until a Windows code-signing certificate and native
  Windows 11 install/uninstall smoke are available.

### Windows 0.1.24 Unsigned Feature Package

- Command: GitHub Actions `Windows Unsigned Package`, run `30224705017`,
  version input `0.1.24`
- Result: passed in 4 minutes 11 seconds on `windows-2022`
- Source: `main` commit `9f49898`
- Notes: The NSIS EXE, WiX MSI, and ZIP include x64/x86 TSF components,
  bounded full-keyboard typo correction, reviewed White Frost 1.0.4 import,
  expanded desktop Rime limits, local AI Lite ranking, Writer V1, and the
  matching Simplified Chinese release notes. The Writer model remains an
  explicit on-demand download and is not bundled.
- EXE: `dist/windows_tsf/PrivatePinyin-0.1.24-setup.exe`
  (`13,421,061` bytes), SHA-256
  `1252f8d00888be0cb2b0f25aaa5d4bdc357a441b94ffa183a76112851668be62`
- MSI: `PrivatePinyin-0.1.24.msi` (`24,485,888` bytes), SHA-256
  `594953721dda2c7b2e765cb02073c0cbfe5b738b2318984b24529fffe434b12a`
- ZIP: `PrivatePinyin-0.1.24.zip` (`25,265,446` bytes), SHA-256
  `ea301594bc82438c06b0207d742e79f98dafab1e2678bc18bd4d5d620110a24d`
- Distribution note: these Windows artifacts are unsigned and remain
  internal-test packages until a Windows code-signing certificate and native
  Windows 11 install/uninstall smoke are available.

### Windows 0.1.13 Unsigned Internal-Test Package

- Command: GitHub Actions `Windows Unsigned Package`, run `29180177697`, version input `0.1.13`
- Result: passed
- Notes: The `windows-2022` job built and uploaded the NSIS EXE, WiX MSI, and ZIP from commit `91b37fa02843b4594a5d043b24675ba4a0912787`; the ZIP contains `ReleaseNotes.zh-Hans.txt` and all TSF runtime files.

- Artifact: `dist/windows_tsf/PrivatePinyin-0.1.13-setup.exe`
- SHA-256: `7bcc0125b1e57aa129a85f773aa5feca543c70a852704b80762440d4615c9b88`
- Artifact: `dist/windows_tsf/PrivatePinyin-0.1.13.msi`
- SHA-256: `992141e002b895b9b4c422f835b9261ccb0ae3dba6e22b01111e65efc7aa5bc8`
- Artifact: `dist/windows_tsf/PrivatePinyin-0.1.13.zip`
- SHA-256: `0f167ca8e923f50c89b89723fa1192b407ce5e69bb4a73b8f3a88bf40211f6a1`
- Distribution note: these Windows artifacts are unsigned and remain for internal testing only.

### Local AI AI-01 Validation

- Command: `bash scripts/check_ai01_evaluation_sources.sh`
- Result: passed
- Notes: Dataset provenance and 20-case manifest checks passed; all 13 required pre-AI regressions passed, while 7 correction/mixed-input opportunities remain intentionally observable and non-blocking.

- Command: `cargo fmt --all -- --check`
- Result: passed

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed

- Command: `cargo test --workspace`
- Result: passed
- Notes: Existing core, C ABI, settings, lexicon, learning, nine-key, and the 6 new AI evaluation/benchmark unit tests passed.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged C ABI still returned and committed `你好`.

- Command: `bash scripts/run_ai_eval.sh --benchmark --initialization-iterations 5 --lookup-iterations 100`
- Result: passed
- Notes: On the arm64 macOS reference machine, engine initialization P95 was 56.01 ms, continuous-pinyin lookup P95 was 1.48 ms, and nine-key lookup P95 was 3.67 ms. Measurements are report-only rather than CI thresholds.

### Local AI AI-02 Validation

- Command: `bash scripts/check_ai02_runtime_contracts.sh`
- Result: passed
- Notes: Required contract files, workspace membership, full request identity, cancellation signature, redacted debug surfaces, provider isolation, and deterministic mock tests passed.

- Command: `cargo fmt --all -- --check`
- Result: passed

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed

- Command: `cargo test --workspace`
- Result: passed
- Notes: Eight AI-02 tests cover deterministic candidate-set hashing, mock repeatability, identity-scoped cancellation, stale-revision rejection, deadline expiry, candidate-hash mismatch, debug redaction, and approved latency classes; existing engine and tool tests also remain green.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged C ABI still returned and committed `你好`; AI-02 is not connected to production input paths.

### Local AI AI-03 Validation

- Command: `bash scripts/check_ai03_privacy_sources.sh`
- Result: passed
- Notes: Required guard/builder/tests exist; runtime source scans found no network client, external AI service, forbidden context field, or content-logging macro.

- Command: `cargo fmt --all -- --check`
- Result: passed

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed

- Command: `cargo test --workspace`
- Result: passed
- Notes: Eighteen local-AI tests cover the eight AI-02 lifecycle cases plus normal/minimized context, secure input, password/OTP, payment/identity/phone data, API-key discussion versus assignment, full-pinyin versus nine-key numeric input, oversized input, policy/hardware/budget rejection, strict privacy, explicit actions, and builder debug redaction.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged C ABI still returns and commits `你好`; AI-03 is not connected to production input paths.

### Local AI AI-04 Validation

- Command: `bash scripts/check_ai04_rules_sources.sh`
- Result: passed
- Notes: Required rule sources and first-party assets exist; source scans found no content logging, network client, or external AI service. The quality gate reports 13/13 required regressions and 7/7 observed opportunities within target.

- Command: `cargo test -p private_pinyin_local_ai_core`
- Result: passed
- Notes: 30 tests cover existing runtime/privacy contracts plus common-confusion, repeated-key, missing-medial, normal-input, two-result limit, validator, canonical-term, multi-term, decodable boundaries, overlong/non-ASCII rejection, debug-redaction, duplicate/stale/invalid cleanup, no-mutation, and strict-privacy behavior.

- Command: `cargo test -p private_pinyin_ai_eval_runner`
- Result: passed
- Notes: The rules-first evaluation test uses the complete 20-case first-party corpus and requires all required and observed targets to pass.

- Command: `bash scripts/run_ai_eval.sh --rules --require-observed-successes 7`
- Result: passed
- Notes: Overall Top-1 is 19/20, all expected candidates are found, and MRR is 0.975. The unchanged production engine remains the fallback and no platform host invokes AI-04 rules.

### Local AI AI-05 Validation

- Command: `bash scripts/check_ai05_model_gate_sources.sh`
- Result: passed
- Notes: The strict schema/template/empty-registry source contract passed, no external AI service or runtime network source was detected, the CLI packaged local synthetic bytes, and no model weight was added to the repository.

- Command: `cargo test -p private_pinyin_local_ai_core -p private_pinyin_model_packager`
- Result: passed
- Notes: Forty-one core tests include valid dual-control loading, manifest-self-approval rejection, bounded corruption checks, use-time replacement, platform, memory tier, unsafe path, local-only privacy, preapproval, empty registry, and symbolic-link cases; two packager tests cover atomic hashing and refusal to manufacture Owner approval.

- Command: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`
- Result: passed
- Notes: The complete workspace remains formatted, warning-free, and green with the committed Cargo lockfile.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged production C ABI still returns and commits `你好`; AI-05 adds no provider, model, FFI change, host integration, setting, or visible input behavior.

### UPDATE-01 macOS Version Check Validation

- Command: `bash scripts/check_update01_sources.sh`
- Result: passed
- Notes: Fixed-host, opt-in, strict-privacy, ephemeral-session, 128-KiB streaming cap, manifest-validation, UI wiring, and offline Swift tests passed.

- Command: `bash scripts/check_macos_imk_sources.sh && bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: The complete Swift InputMethodKit host compiled without warnings and produced `dist/macos_imk/PrivatePinyin.app`.

- Command: local `--show-preferences` and `--show-onboarding` visual smoke
- Result: passed
- Notes: Update status, manual check, automatic opt-in, privacy copy, and existing controls fit without clipping or overlap; the fresh automatic-check state is off.

- Command: `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, and `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged shared engine and C ABI still return and commit `你好`; update code remains isolated to the macOS host.

- Command: `curl -I https://wwwstationcat.org/updates/private-pinyin/macos/stable.json`
- Result: pending publisher action (`HTTP 404` on 2026-07-14)
- Notes: The client and manifest contract are ready, but `UPDATE-OI-001` remains open until the owner publishes and smoke-tests the live stable manifest after an immutable signed/notarized pkg is available.

### UPDATE-02 Verified Package Handoff Validation

- Command: `bash scripts/test_macos_update_package.sh`
- Result: passed
- Notes: Offline Swift tests cover successful verification plus exact-size, SHA-256, Team ID, installer-signature, and notarization failures without requiring a live network endpoint.

- Command: `bash scripts/check_update02_sources.sh`
- Result: passed
- Notes: The source gate pins ephemeral download policy, same-host HTTPS redirects, bounded package size, private cache permissions, exact subprocess arguments, pinned Team ID, notarization, two-step consent, re-verification, and the ban on silent privileged installation.

- Command: `bash scripts/check_update01_sources.sh && bash scripts/check_macos_imk_sources.sh && bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: UPDATE-01 compatibility and the complete Swift InputMethodKit host build passed without warnings.

- Command: `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, and `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged shared engine and C ABI remain clean and still return and commit `你好`; UPDATE-02 remains isolated to the macOS host.

- Command: local `--show-preferences` update-state visual smoke
- Result: passed
- Notes: The update status and action controls fit the Station Board preferences window without clipping or overlap. A successful live signed-package handoff remains pending `UPDATE-OI-001`.

### Permissive Base + Local Rime Import Validation

- Review hardening preserves a non-empty custom macOS `user_lexicon_path`, reports the accepted row count when a later selected file fails, rejects unavailable iOS security-scoped documents with a precise message, and documents the current sequential batch and damaged-layer recovery contract.
- Executable regressions now prove repeated imports merge cumulatively and a merge beyond 200,000 entries returns `ImportedLexiconLimit` without changing the existing canonical file.
- Command: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`
- Result: passed
- Notes: The complete workspace is formatted and warning-free. Import tests cover source and canonical size limits, cumulative merge, byte-preserving limit failure, explicit-pinyin parsing, deduplication, malformed-layer fail-soft loading, independent storage, and new-engine visibility; the production input regressions remain green against the 137,699-entry base.

- Command: `cargo clippy -p private_pinyin_ime_ffi --all-targets --features desktop-ai -- -D warnings` and `cargo test -p private_pinyin_ime_ffi --features desktop-ai`
- Result: passed
- Notes: The optional AI-07 desktop FFI remains compatible with the expanded engine settings and import ABI; secure-mode, stale-result, and candidate-permutation tests remain green.

- Command: `bash scripts/check_local_lexicon_import_sources.sh`, `bash scripts/check_stage13_lexicon_sources.sh`, and `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The bounded CLI import/clear smoke produced one canonical row, the approved manifest reports exactly 137,699 base entries, and the unchanged C demo still commits `你好`.

- Command: `bash scripts/check_macos_imk_sources.sh`, `bash scripts/check_windows_tsf_sources.sh`, `bash scripts/check_installers_settings_sources.sh`, and `bash scripts/check_ios_keyboard_sources.sh`
- Result: passed
- Notes: All three hosts expose the isolated import layer while preserving platform privacy contracts. iOS source gates pin the document picker, container-side Rust import into the App Group, and a read-only keyboard extension so Full Access remains unnecessary.

- Command: `bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: The complete InputMethodKit app compiles successfully with the expanded bundled base and hardened local import controls.

- Command: Beta Xcode `scripts/build_ios_keyboard.sh` plus `scripts/test_ios_chinese_transform.sh`
- Result: passed (`BUILD SUCCEEDED`)
- Notes: The iOS container App and Keyboard Extension compile with the isolated C import bridge, partial-import status, and security-scoped document handling; the standalone Chinese conversion regression also remains green.

### Desktop 0.1.24 macOS Public Package Validation

- Command: `PRIVATE_PINYIN_VERSION=0.1.24 bash scripts/package_macos_pkg.sh`
- Result: passed
- Notes: The app and dormant AI-09 Helper were signed with `Developer ID Application`; the pkg was signed with `Developer ID Installer`, submitted to Apple, accepted under submission `54645912-7b0d-4d83-b670-453067f3897f`, and stapled successfully.

- Command: `PRIVATE_PINYIN_VERSION=0.1.24 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: The trusted installer signature, Gatekeeper `Notarized Developer ID` assessment, stapled ticket, notary profile, and package checksum all passed. Artifact: `dist/macos_imk/PrivatePinyin-0.1.24.pkg` (`3,800,887` bytes); SHA256 `ff0d2d73e0ee63daf06ac052b5a06cf7a17df309ae7d1713c0867d09d832fc7d`.

- Release scope: macOS clients now share one immutable engine snapshot while retaining independent session state. Installed multi-client resident-memory and upgrade smokes remain manual release gates; the AI-09 Helper remains dormant and does not alter normal input behavior.

### macOS Tiered Preferences Navigation Validation

- Summary: The Station Board preferences now opens on a compact first-level overview with privacy, prediction, and learning controls plus navigation cards for lexicon management, local Writer, and about/updates. Each feature opens on a dedicated second-level page with one consistent return-to-overview action; existing settings, import, Writer, update, reload, and proportional-resize behavior remains on its original code path.

- Command: `bash scripts/check_macos_imk_sources.sh`
- Result: passed
- Notes: The source gate now pins the tiered page enum, navigation cards, overview return action, and the three user-visible feature destinations.

- Command: `bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: The complete Swift InputMethodKit host compiled successfully and produced `dist/macos_imk/PrivatePinyin.app` with the new preferences navigation.

- Command: local `--show-preferences` overview and second-level visual smoke
- Result: passed
- Notes: The compact overview, lexicon, Writer, and about/update pages all render without clipping or overlap. Every navigation card opens its intended page, the shared `总览` action returns correctly, and the window preserves proportional sizing while adapting its height to the active page.

### Desktop 0.1.26 macOS Public Package Validation

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.26 bash scripts/package_macos_pkg.sh`
- Result: passed
- Notes: The app, AI-09 Helper, FFI framework, llama-server, and Writer Runtime libraries were signed with `Developer ID Application`; the pkg was signed with `Developer ID Installer`, submitted to Apple, accepted under submission `d12188ae-f39c-4044-babb-05578efd2b7d`, and stapled successfully.

- Command: `PRIVATE_PINYIN_VERSION=0.1.26 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: The trusted installer signature, expanded-payload nested-code signatures, Gatekeeper `Notarized Developer ID` assessment, stapled ticket, notary profile, and checksum all passed. Artifact: `dist/macos_imk/PrivatePinyin-0.1.26.pkg` (`14,066,233` bytes); SHA256 `5c83e1770f7eb8d18096c08bf4e4e2e2fa05fdcb82e402060b73f3e8160e4200`.

- Command: `bash scripts/test_macos_launch_policy.sh`, `bash scripts/test_macos_input_source_registration.sh`, `bash scripts/check_stage12_release_sources.sh`, `bash scripts/check_desktop_writer_runtime_sources.sh`, and `bash scripts/check_macos_imk_sources.sh`
- Result: passed
- Notes: The release preserves exact installed-bundle server ownership, includes registered-but-disabled TIS sources in registration health checks without enabling them, and keeps the Writer runtime license outside the nested-code signature boundary.

- Release scope: `0.1.26` includes Writer V1 plus the fix for intermittent input loss caused by stale development or staging copies competing with the installed InputMethodKit server. An installed-upgrade typing smoke and clean-user install/uninstall smoke remain manual release gates.

### Desktop 0.1.27 macOS Public Package Validation

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.27 bash scripts/package_macos_pkg.sh`
- Result: passed
- Notes: The app, AI-09 Helper, FFI framework, llama-server, and Writer Runtime libraries were signed with `Developer ID Application`; the pkg was signed with `Developer ID Installer`, submitted to Apple, accepted under submission `1539ece0-a619-49c7-a77c-82d51543a1ac`, and stapled successfully.

- Command: `PRIVATE_PINYIN_VERSION=0.1.27 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: The trusted installer signature, expanded-payload nested-code signatures, Gatekeeper `Notarized Developer ID` assessment, stapled ticket, notary profile, and checksum all passed. Artifact: `dist/macos_imk/PrivatePinyin-0.1.27.pkg` (`14,072,621` bytes); SHA256 `00eca727600f37476e1676207c0307bf685d4883b3b8f6be63cb6e56216d16bf`.

- Command: `bash scripts/check_macos_imk_sources.sh`, `bash scripts/test_macos_launch_policy.sh`, `bash scripts/test_macos_input_source_registration.sh`, and `bash scripts/check_desktop_writer_runtime_sources.sh`
- Result: passed
- Notes: The release preserves the exact installed-bundle server and registered-but-disabled source repairs while adding the compact overview plus dedicated lexicon, Writer, and version/update preference pages.

- Release scope: `0.1.27` adds the reviewed tiered Station Board preferences navigation and retains the signed Writer V1 and input-server reliability fixes from `0.1.26`. An installed-upgrade typing smoke and clean-user install/uninstall smoke remain manual release gates.

### FROST-01 Review Closure Validation

- Summary: Reviewed White Frost ZIP parsing and hashing are now compiled only through the desktop `reviewed-rime-frost` feature. The iOS `ios-ai` graph does not enable that feature and no longer links `zip`, `flate2`, or `zopfli` through `ime_core`.

- Follow-up: The macOS settings layer now records caller-supplied reviewed source metadata instead of depending on the download manager's catalog type. This keeps the standalone shared-engine and source-label Swift tests independent from networking code while preserving the exact approved White Frost manifest values at the import call site.

- Command: `cargo test -p ime_core --features reviewed-rime-frost --test reviewed_rime_frost_tests`
- Result: passed (13 tests)
- Notes: The approved archive path, SHA-256 rejection, traversal and symlink rejection, compression-ratio and entry-count limits, duplicate members, missing approved members, oversized members, false declared sizes, and atomic old-layer preservation all remain green. Direct central-directory mutations additionally prove that missing Unix mode and forged EOCD entry counts fail closed, while a valid non-empty ZIP comment remains accepted.

- Command: `cargo run -q -p private_pinyin_settings -- import-rime-frost --settings <temporary-settings> --input rime-frost-schemas.zip`
- Result: passed against the fixed official 1.0.4 Release after the TOCTOU, EOCD, and Unix-mode hardening
- Notes: The downloaded asset was independently rechecked as 44,008,360 bytes with SHA-256 `4f4998ae83f63d757c0a4ace192f69d48265bddfabe231642b73e3739ed0f2f5`. The production CLI accepted 653,308 source rows, retained 653,136 unique phrase/pinyin identities, and wrote an 18,083,664-byte canonical TSV (653,137 lines including the header) in approximately 10.69 seconds. ZIP inventory inspection reported 161 central-directory entries: 159 regular files with Unix mode `100644` and two regular files with mode `100755`.

- Command: `cargo clippy --workspace --all-targets -- -D warnings`, plus FFI Clippy with `desktop-ai` and `ios-ai`
- Result: passed
- Notes: Both host feature graphs compile without warnings. `scripts/check_frost01_sources.sh` now fails immediately if `rg` is unavailable and inspects the resolved iOS Cargo graph for the desktop Frost feature and archive dependencies.

- Command: `bash scripts/check_frost01_sources.sh`, `bash scripts/check_windows_tsf_sources.sh`, `bash scripts/check_installers_settings_sources.sh`, and `bash scripts/check_ios_keyboard_sources.sh`
- Result: passed
- Notes: The Windows settings save path rereads the latest persisted settings before applying form fields, so a newly changed White Frost enable state is not overwritten by the launch-time snapshot. A negative control temporarily enabled `reviewed-rime-frost` in the `ios-ai` feature graph; the FROST-01 gate failed with the expected iOS dependency-leak error, and passed again after restoring the graph. The PowerShell AST parser is wired into the `windows-2022` job because this development Mac does not provide `pwsh`.

- Command: `PRIVATE_PINYIN_SKIP_CODESIGN=1 bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: Reviewed archive verification and parsing now run on a dedicated serial background queue through the static no-engine FFI import. Only final status and one shared-engine reload return to the main queue, so a large import neither blocks the InputMethodKit UI nor creates a second full lexicon engine.

- Command: `PRIVATE_PINYIN_REQUIRE_SWIFTC=1 bash scripts/test_macos_shared_engine.sh` and `PRIVATE_PINYIN_REQUIRE_SWIFTC=1 bash scripts/test_macos_imported_lexicon_source.sh`
- Result: passed
- Notes: The standalone Swift targets compile without the White Frost network manager, continue to prove process-wide engine sharing for ordinary clients, and retain imported-source status behavior. The shared-engine test also creates temporary reviewed-layer settings and proves that adding White Frost, adding Rime Ice, and removing White Frost each invalidate exactly one shared snapshot while an unchanged configuration remains coalesced. Layer-only candidates become visible immediately after each reload and disappear after the corresponding layer is cleared.

- Command: `bash scripts/build_ios_keyboard.sh`
- Result: passed (`BUILD SUCCEEDED`)
- Notes: The iOS container and keyboard extension build with `ios-ai` while excluding the desktop White Frost archive parser and ZIP dependency chain.

- Command: `cargo test -p ime_core --test candidate_tests continuous_sentence_latency_budget`, `nine_key_latency_budget`, and `nine_key_continuous_sentence_latency_budget`
- Result: passed
- Notes: The default no-import fast path and deterministic compact index keep all three candidate paths under their unchanged 60 ms assertions; FROST-01 does not widen an unrelated latency budget.

- Manual release gate: capture macOS and Windows RSS before White Frost import, at peak verification/import, immediately after the one shared-engine reload, and after five idle minutes, together with the shared-engine reload duration. The implementation prevents a second full engine during import, but release evidence must still prove the real signed desktop processes return to the normal single-engine retained-memory range.

## Open Items

- Select the final project license before external reuse or release.
- Keep production runtime data outside source directories.
- Refine Shift toggle semantics in platform hosts.
- Provide Windows code-signing certificate and signed binary/MSI/PowerShell-script evidence.
- Validate signed Windows MSI install/uninstall on Windows 11.
- Validate TSF DLL loading and Notepad smoke test on Windows 11.
- Add TSF display attributes for preedit text.
- Validate signed/notarized macOS pkg install/uninstall and release uninstall guidance.
- Polish macOS candidate positioning and appearance.
- Verify IMK candidate panel number-key routing on macOS.
- Validate Windows installer and settings UI on Windows 11.
- Submit build `0.1.21 (17)` to the external TestFlight group, monitor Beta App Review, and publish tester access after approval.
- Run real-device smoke tests in Notes, Safari, password, and phone fields, including Full Access-off App Group behavior and local learning persistence under distribution provisioning.
- Expose sanitized core logging through host ABI callbacks.
- Measure production lexicon engine initialization latency on macOS, Windows TSF, and iOS inline-settings reload before deciding whether precompiled data, lazy loading, or a runtime settings API is needed.
- Replace the 20-entry starter bigram predictor with a licensed production prediction data source.
- Capture Windows, Intel macOS, and real-device iOS latency and resident-memory baselines before calibrating AI Lite budgets.
- Detect and calibrate trustworthy memory/GPU profiles on macOS, Windows, and iOS before host model integration.
- Publish and smoke-test the fixed macOS stable manifest after the versioned pkg and release page are live.

## Files Changed In Latest Stage

- `ai/helper_protocol/src/lib.rs`
- `ai/helper/private_pinyin_ai_helper/src/writer_runtime.rs`
- `ai/writer_runtime/desktop_writer_runtime_manifest.json`
- `platform/macos_imk/Sources/PrivatePinyinWriterModelManager.swift`
- `platform/macos_imk/Sources/PrivatePinyinWriterWindowController.swift`
- `platform/windows_tsf/installer/open-writer.ps1`
- `scripts/prepare_macos_writer_runtime.sh`
- `scripts/prepare_windows_writer_runtime.ps1`
- `scripts/check_desktop_writer_runtime_sources.sh`

## Next Step

- Review Desktop Writer V1, then run the signed/notarized macOS pkg and native Windows 11 package,
  identity, cold/warm RSS, timeout, crash, queue-saturation, and offline-reuse matrix tracked by
  `AI-OI-010` and `AI-OI-012` before enabling Writer in a public release.
