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

Use the Flutter-documented native-view image proxy technique for composition that cannot safely mix with live UIKit. Keep controls mounted and interactive as UIKit when stationary and outside a content blur region. Cache a bounded image of each native control outside motion; paint it on Flutter's canvas while its page moves or its content lies under a feather. Do not capture on each animation/scroll frame, dispose/recreate controls, change durations, replace native glass with a drawn imitation, inspect UIKit internals, or change menu contents. Above-edge header/dock controls remain live while stationary. Preserve active-control pointer completion.

Restore `EasyScrollEdge` for native iOS after installing the composition boundary; remove the nine-band approximation. Route primary AND secondary motion must participate, including successful/cancelled back gestures and early pop. A missing snapshot must have an explicit safe fallback and remain reported as unverified; never paint an empty substitute or invent a performance pass.

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
