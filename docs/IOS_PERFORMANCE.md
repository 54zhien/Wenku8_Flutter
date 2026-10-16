# iOS motion investigation

Priority from user: preserve animations, bookshelf/article style and functionality; fix low frame rate before calling the candidate accepted. Reference images IMG_9809/9810/9811 were inspected: appearance selection trigger, discovery sort menu and appearance menu. These map to native popup selection buttons and UIMenu; UIKit owns selection shape and menu corners.

## Reproduced work and changes

- A widget regression rebuilt an unchanged control 20 times: 21 native state messages before, one after deduplication. A real option change still sends exactly one update; delayed creation/state-race regressions remain passing. This proves bridge chatter, not its share of physical-device frame time.
- Surface state updates previously constructed a fresh UIGlassEffect each time. Effects now persist across geometry/label updates, change only when the opaque mode changes, and are never created for an opaque surface. Explicit benchmark-only native counters record state, platform-view, effect and button-configuration work without content.
- The paper Hero still uses the same route duration, mesh density, peel/contact formulas, texture, occlusion and timing. Row-invariant trigonometry is computed once per mesh row; scalar projection removes per-vertex Offset intermediates. More than 100000 point comparisons against the old formula and existing cover-flight geometry tests pass.
- Windows x64 Dart 3.11.3 AOT CPU microbenchmark (7 alternating samples, 12000 iterations of 833 vertices each): baseline median 248103 us, revised 72126 us, 3.44x for the depth kernel. Raw samples are in validation/paper-depth-aot-windows.json outside the repository. This excludes Flutter/UI/raster/UIImage work and is not an app FPS claim. Regenerate with `dart compile exe native_tests/benchmark_paper_depth.dart -o <output>` then run the executable.
- No synchronous network/disk reads or explicit synchronous image decode were found in the inspected open-book path. The existing conditional, single cover `toImageSync` fallback remains a separate cold-image candidate; it is not a repeated disk read. Do not attribute all reported jank to any candidate without timing data.

## Same-scene CI evidence

The performance job runs the identical integration harness against the original candidate 11f307775495a3824c98a920d84caf881717b4ce and the new commit, on the same iPhone simulator. Fixture data, encoded covers, image warmup, five open/return cycles, five search cycles and animation durations are held constant. Engine FrameTiming records, build/raster p95, refresh-derived budgets, over-budget ratio, device dimensions and mode are preserved separately from native work counts. Missing timing samples fail collection; no timing values are invented and no animation is disabled. The fixture isolates rendering from variable network latency; it does not test live API speed or cold image loading.

Flutter 3.41.5 `packages/flutter_tools/lib/src/ios/simulators.dart` supports only BuildMode.debug for an iOS simulator. The CI comparison is explicitly debug/simulator evidence. The separate AOT benchmark measures an actual production CPU kernel in release compilation, not full iOS frame delivery. FrameTiming does not capture the complete Core Animation/platform-view presentation pipeline; a low raster p95 alone cannot certify smooth UIKit composition.

Physical iPhone release/profile acceptance remains necessary: repeat open/return, search, menus and reader panels on 60 Hz and ProMotion devices; use Flutter DevTools CPU/raster traces plus Instruments Animation Hitches/Core Animation and allocation/signpost traces to distinguish build work, raster, native composition and decode. Check both warm and cold covers. CI success or a kernel speedup does not prove this device acceptance passed.

No screen capture or input on the user's computer is used. Simulator screenshots are CI-generated test artifacts. Preserve the original 11f3077 previews and all failed/cancelled runs.
