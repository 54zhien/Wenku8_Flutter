# iOS composition boundary repair

> Execute inline with systematic-debugging, TDD, and verification-before-completion. Review the complete change after verification. No IPA, archive, signing, or delivery in this task.

**Goal:** Retain real UIKit Liquid Glass controls, restore the upstream continuous scroll edge and unchanged push/pop/cover choreography, and remove unnecessary cross-compositor work during movement.

**Base:** `7bfd1edab5fbb7720173c88b06d30bf064ac54e7`. Upstream motion/edge reference: `fe222b071e8bc88918d4cb47c94bb973d148d85f` in sibling `upstream-review`.

## Evidence and limits

- The user reports every repeated book push/pop stutters, plus other page transitions and top blur defects. All motion/low-performance switches were already confirmed off.
- Current edge emits up to nine independent BackdropFilters instead of the upstream single feathered Gaussian. Existing continuity acceptance is expected to reject the band approximation; it was not a passing native-quality result.
- Pinned engine `052f31d115eceda8cbff1b3481fcde4330c4ae12` propagates backdrop filter rect/sigma into visited UIKit views. `ChildClippingView.applyBlurBackdropFilters` creates or updates native effect views. It does not propagate the Flutter child's dstIn feather. Ancestry isolation alone cannot solve this.
- Admission only delays newly entering native controls. Source-page controls, return routes, and native bars remain live in moving page composition. Unit mocks cannot establish native frame cost or visible return correctness.
- Physical root-cause attribution (CPU/raster/Core Animation) is still unmeasured. Do not turn structural evidence into a claim that physical stutter is solved.

## Chosen boundary

Use the Flutter-documented native-view image proxy technique ONLY during route motion. Keep controls mounted, painted, and interactive as UIKit while stationary, including when they lie under a content feather. Omitting a PlatformViewLayer removes the native UIView from UIKit, so a hitTest-only patch cannot preserve its real touches. The original static-edge proxy experiment is rejected.

Cache a bounded image of each native control outside route/scroll motion; paint it on Flutter's canvas while its page moves. Refresh once after scrolling settles and state/size changes; refuse outdated snapshots and avoid consecutive failed full-window retries. Do not capture on each animation/scroll frame, dispose/recreate controls, change durations, replace native glass with a drawn imitation, inspect UIKit internals, or change menu contents. Preserve active-control pointer completion.

Restore `EasyScrollEdge` for native iOS after installing the composition boundary; remove the nine-band approximation. Route primary AND secondary motion must participate, including successful/cancelled back gestures and early pop. A missing snapshot must have an explicit safe fallback and remain reported as unverified; never paint an empty substitute or invent a performance pass.

Stationary UIKit/Flutter feather parity remains unresolved. The user requires the original pure Gaussian effect and rejected UIKit system-material substitution. The pinned engine already strips saturation/tint from its platform-view Gaussian; investigate forwarding the original feather to that engine path. Keep the candidate unshipped.

## Work

- [ ] RED: use real Flutter raster continuity/contrast checks to expose the banded edge; preserve the existing integration gate.
- [ ] RED: exercise platform-view layer output during primary/secondary/reverse motion and under a feather, including above-edge controls, cold snapshots, and active pointers.
- [ ] Implement the shared paint boundary and native capture bridge with bounded memory/work, generation checking, lifecycle disposal, and no frame-loop method calls.
- [ ] Restore the exact upstream edge implementation and retain original route/Hero/cover geometry and timings.
- [ ] Verify stationary native interaction, scrolling through an edge, push/pop/cancel, stale/asynchronous snapshots, and teardown. Add hosted native capture checks; distinguish unexecuted native checks from local results.
- [ ] Run focused checks, full native-define and default suites, analyzer, and appropriate native validation without producing an IPA. Review complete diff. Record exact limitations and stop before packaging.

## References

- https://docs.flutter.dev/platform-integration/ios/platform-views#performance
- https://github.com/flutter/flutter/blob/052f31d115eceda8cbff1b3481fcde4330c4ae12/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm
- https://github.com/flutter/flutter/blob/052f31d115eceda8cbff1b3481fcde4330c4ae12/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViews.mm

## Execution ledger

- Plan recorded before implementation. Existing worktree is clean at base; no unrelated changes. Existing test/CI failures are preserved in sibling `validation`.
- RED `ios-composition-boundary-red.log`: a feather-overlapped native control remains a PlatformViewLayer; both moving routes also emit live native layers. The new real-layer-output tests fail against the delivered source.
- RED `ios-composition-feather-red.log`: 38,016 channel samples differ from the upstream continuous feather. The restored renderer matches the reference within one channel level for top and bottom on the local Flutter raster backend.
- Implemented a mounted-child paint proxy using cached external native textures. Primary and secondary route movement, body edge overlap, header/dock exemption, pointer ownership, stale asynchronous completion, missing-cache retries and texture/native restoration have focused coverage. This demonstrates the compositor boundary, not physical FPS.
- Ruling: retain cold overlay native material during opening instead of adding entrance admission to PopupRoutes. A full local run caught a native menu source/radius-morph regression from that admission experiment; the pre-existing visual-revision test stays unchanged and passes after retaining its original native entrance. PopupRoutes now get the shared composition scope for return. A missing snapshot always keeps a visible native control rather than painting nothing.
- Ruling: capture the hosting UIWindow, then crop native-control textures. Apple UIVisualEffectView documentation requires the whole window for effects to be included. A one-shot main-loop observer releases the shared window image after the request batch; no permanent display-link/timer. Per-control BGRA buffers are bounded and registered once; state/layout changes refresh them outside route motion. Image quality and capture cost require native verification.
- Ruling: an additional test-only macOS 15 / Xcode 26.3 / iOS 26.2 hosted check will compile and run capture tests without an archive/IPA. Existing required 26.4 interface/performance gates are unchanged and their historical failures remain failures. Additional native unit coverage is not a substitute for those gates or the user's iOS 27.2 physical run.
- Focused edge/composition/original-motion suite: 17 passed before the additional overlay cases. Expanded composition and original iOS control contracts: 24 passed after preserving overlay morph. Local analyzer is clean. Fresh full-suite result is pending after the overlay adjustment.
- Fresh native-define full suite at this diagnostic candidate: 565 passed. This does not execute UIKit or demonstrate physical performance.
- Independent review identified release-blocking questions: an omitted platform layer cannot receive the initial UIKit touch under a stationary feather; stale backdrops after scrolling; pending state/size changes reusing old textures; synchronous whole-window capture cost and real Flutter/Metal effect support. Do not treat this commit as a completed repair or package it. The hosted real-glass test is an experiment to establish whether the texture boundary is viable before further product changes.
- Native capture now checks pixel-buffer lock/base-address success, uses trait display scale, and coalesces failed whole-window attempts within a run-loop batch as well as successful ones. A hosted test captures a real UIGlassEffect in the existing Flutter window, in addition to the plain UIView orientation/lifetime test. These native tests remain unexecuted locally.
- Hosted diagnostic dd7004bedda46caab719e4667454e157aec233b5: CI 38910209201 succeeded on Xcode 26.3 / iOS 26.2. RunnerTests executed 7 tests with zero failures, including real UIGlassEffect capture in the Flutter/Metal window and BGRA orientation/last-frame preservation. No archive/IPA was generated. This is native-capture viability, not motion/UI/performance acceptance. Evidence retained outside the public source checkout.
- Review follow-up RED: `ios-composition-review-red.log` exposed repeated failed readbacks and reuse of a pending stale texture; `ios-composition-touch-red.log` exposed missing stationary native layers. The final motion boundary keeps all stationary native hit planes, limits capture to one attempt per visual invalidation/attachment, refuses stale state, and refreshes once after scrolling ends. `ios-composition-route-only-focused.log`: 42 passed, including cancelled interactive return and original route/cover/control contracts. Local analyzer clean.
- Default full suite before the latest three regression cases: 549 passed, one pre-existing live-service skip. The first native-define full suite passed 565. A new exact candidate full run and same-simulator delivered/candidate timing comparison remain pending. Existing formal iOS 26.4 boot/UI failures are unchanged and are not relabeled as passing.
- Motion snapshots are limited to self-contained UIKit controls. Passive materials beneath Flutter foreground labels stay native: a full-window crop would bake those labels into the material and replay them a second time. Cold overlay entrance/source/radius behavior stays unchanged. This intentionally leaves mixed composition for passive popup material; do not claim all overlays are optimized.
- Additional safety: clear uncropped pixel-buffer areas, retain a captured window only until the one-shot run-loop release (avoiding reused ObjectIdentifier keys), and record whole-window snapshot duration only during an explicitly enabled native probe.
- Native-define full suite after the route-only boundary: 568 passed. The latest passive-material regression adds one further test; final exact-state verification follows before the new diagnostic push.
- Same-simulator diagnostic compares three variants with the identical existing benchmark: delivered 7bfd1ed (banded edge), candidate with route snapshots disabled (`WENKU8_ROUTE_TEXTURE=false`, original single feather), and candidate with route snapshots. This separates edge-pass cost from motion texture cost rather than attributing combined results to one cause. This optional diagnostic switch does not alter glass controls, route choreography, or menus.
- Diagnostic ebf51cf829e3f78028d9f6fc91b4ff62f35a20ae / CI 38911971940 FAILED before any motion scene: hosted native tests passed, but Xcode used its own test-device clone and the selected integration UDID remained shut down. Flutter could not discover it. Preserve this failure; no frame comparison exists. The new diagnostic explicitly boots that exact additional target, waits for bootstatus, and checks Flutter's device inventory. Existing formal readiness/timeouts/assertions are unchanged.
- Review follow-up RED `ios-composition-route-race-red.log`: a capture already in flight at route start could be admitted during movement; a reparented keyed control could accept its prior scope's crop. Both now invalidate the generation and preserve the visible native fallback until a fresh settled capture. The two new behavioral regressions pass.
- The first hosted effect test sampled UIKit stripes inside a Flutter window; it did not prove changing Metal-rendered Flutter pixels were captured. Add `integration_test/ios_native_capture_test.dart`: actual Flutter red/blue/green fields under a real native glass platform view, read through the actual window-crop/CVPixelBuffer bridge. A DEBUG-only fixed centre-pixel probe is absent in release builds. The test must verify all three colour changes; it is not yet executed. No screenshot retry loop or wall-clock sleep is used.
- Explicit native probes now separately record whole-control capture duration, including crop/allocation/copy, as well as the narrower whole-window renderer duration. Rectangular window crops can still bake overlapping content or an already applied edge; native route visual acceptance is outstanding.

- Diagnostic fe7f670 / CI 38913729076 FAILED before Flutter capture or timing: native compilation and 7 hosted tests passed, but XCTest asynchronously left the integration target in Shutting Down. New readiness helper waits for this observed transient state, then performs one boot and monitors bootstatus within the existing five-minute step budget. Five helper tests cover transitions, budget exhaustion, unknown states, and no retries after boot failure. Earlier failed runs remain failures.
