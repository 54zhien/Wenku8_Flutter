# Execution ledger — plan: docs/superpowers/plans/2026-10-16-ios26-port.md

## Setup

- Baseline: fe222b0; implementation branch codex/ios26-port in isolated sibling worktree.
- User approved design and explicitly instructed execution: "继续，开工"; preserve inline execution and continue through tasks without repeated permission requests.
- Ruling: Treat the user's explicit start instruction as authorization to write and execute the concrete plan — avoid another planning-only turn — cost if wrong: implementation needs scope correction.
- Native app worktree tool returned "Not a git repository" because the chat root contains the source clone rather than being the clone; used git worktree fallback.
- Flutter 3.41.5 being provisioned locally outside app checkout. Swift 6.2.3 found; runtime DLL path must be set for Windows commands.
- macOS/Xcode is unavailable locally. Swift Foundation execution and Flutter tests do not imply an iOS build passed.

## Progress

- Task 1: Foundation protocol implementation complete locally. Red evidence: missing protocol symbols before implementation; final executable harness passes 32 checks. Python tooling suite: 15 passed.
- Task 2: iOS network/Keychain bridge and real mobile app boot wired. Numeric/HTML response regression tests failed before the reader fix and pass afterward. A follow-up regression ensures literal `<error>` text inside prose remains readable. UIKit-dependent transport and Keychain require macOS compile/runtime acceptance.
- Task 3: Native documents/share/legacy import and screen-awake implementations wired. iOS screen ownership regression failed before enabling iOS and passed afterward. Native picker/iPad presentation remains unverified.
- Task 4: Native glass prototype available only with WENKU8_NATIVE_GLASS=true. Dock, mapped icon/primary buttons and reader sliders are wired. Menus, text actions and full panels are not yet replaced: do not propagate the prototype until iOS backdrop composition is accepted.
- Task 5: iOS 26 deployment settings, source membership, background audio, native XCTest and macOS workflow added. All plists parse and source membership checks pass. CI has not been pushed or run; no iOS build/IPA claim.
- Task 6: Independent read-only review completed. All three confirmed findings fixed: delayed native view creation loses state; vertical dock pan changes tabs; missing SF Symbol mappings. Each has a failing regression before its correction. Unknown symbols deliberately retain the existing control rather than displaying an unrelated icon.

## Baseline and rulings

- Baseline Flutter suite (before implementation): 511 passed, 1 failed, 1 opt-in live test skipped. Failure: listening_cache_test.dart / LRU is bounded and does not delete the protected playing file, line 317.
- Ruling: Fix this reproduced baseline defect while establishing the port's test environment — Windows directory enumeration and File construction use differing separators, so raw path-string protection missed the same file — use normalized absolute file URIs; existing assertions retained. Targeted cache/offline/native-contract tests then passed.
- Ruling: Keep native glass default off pending iOS composition acceptance, as required by the design. This is a prototype gate, not a claim that the existing Flutter material is native glass. Remaining menu/panel work is deferred until that gate passes.
- Swift parser checks cover all native source files and XCTest syntax; parsing cannot resolve UIKit or prove an iOS SDK build.
- Source-policy validation runs on the exported public candidate. The working Flutter checkout necessarily contains ignored Generated.xcconfig/flutter_export_environment.sh/android local.properties after pub get; these are not committed or exported.
- No remote push, fork, PR, signing, account mutation or publication was performed.

## Validation evidence

All logs are local under the workspace's sibling validation directory and excluded from app source commits.

- flutter-baseline.txt: original RED preserved.
- ios-reading-red.txt, ios-glass-red.txt, ios-glass-race-red.txt, ios-symbol-red.txt, swift-protocol-red.txt, swift-dock-red.txt, prose-error-tag-red.txt: regression RED evidence.
- flutter-reviewed-tests.txt: 523 passed, 1 existing opt-in live test skipped.
- edge-live-test.txt: explicitly enabled real online voice catalogue and synthesis test passed.
- Final full-suite run: `flutter test --no-pub --dart-define=LIVE_EDGE_TTS=true --reporter expanded` → 525 passed, zero failures and zero skipped, including real online speech synthesis. Evidence: flutter-final-all-tests.txt.
- Final `flutter analyze --no-pub` → No issues found. Foundation executable → 32 checks passed. Python tooling → 15 tests passed. Public source export policy and `git diff --check` → passed.
- flutter-final-analyze.txt: final analyzer result; native harness execution and exported source-policy checks are independently reported.

## Outstanding acceptance

1. Compile iOS candidate and run five native XCTest methods on macOS/Xcode 26+.
2. Validate native backdrop composition, layout, keyboard, gestures and accessibility before enabling glass by default or replacing remaining menus/panels.
3. Exercise login and cookie persistence on a device without putting credentials in chat/logs; validate account reads and explicitly authorized writes.
4. Validate file workflows, offline paragraph/selection restore, background audio and physical iPhone/iPad behavior separately.
5. Establish user-owned remote and release identity before remote CI, signing or distribution. Original upstream grants this account pull access only.

## Authorized remote verification

- User explicitly authorized creating a fork, pushing the candidate and running macOS CI.
- Fork created: https://github.com/54zhien/Wenku8_Flutter; only codex/ios26-port is pushed, original upstream remains unchanged.
- First exact-candidate CI: https://github.com/54zhien/Wenku8_Flutter/actions/runs/38848462850 on 03548fa9a4fcbf30ad13e417f225e9867ce8bb85. Preserve its actual outcome; no same-SHA rerun to hide a failure.
- First CI outcome: FAILED. Flutter checks/tests, Foundation checks and simulator compilation passed. Native XCTest executed all five cases: four passed, GBK review byte-equality failed (nil instead of expected encoded text).
- Root cause from downloaded xcresult: iOS runtime logs "Unknown encoding 2147485233" for the GBK_95 NSString codec. The enum exists and compiled, but the converter is unavailable at runtime.
- Fix: replace that runtime codec with an explicit strict GBK mapping generated using Java's Charset encoder with REPORT for malformed/unmappable input. No GB18030 substitution and no changed XCTest expectation. Resource is 23940 records / 95760 bytes; pure Swift suite now passes 36 checks, including the original failing review bytes and emoji rejection.
- Ruling: Extend the next candidate's CI with simulator previews and an unsigned device IPA after native tests pass — provide a concrete iOS artifact for review — signing and physical-device acceptance remain separate.
