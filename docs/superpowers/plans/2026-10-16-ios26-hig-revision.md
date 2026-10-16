# iOS 26 control and layout revision

User authorized continued implementation, branch pushes and macOS CI after reviewing the first candidate. Latest direction supersedes the earlier control-position freeze: follow Apple placement/safe areas for controls while preserving the Flutter article and 3D bookshelf. Do not use computer input or screen capture; inspect CI-generated images only.

## Official basis (checked 2026-10-16)

- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout): use system safe areas/margins, adapt to size classes, keep controls distinct from content.
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): navigation only, labeled stable tabs, bottom on iPhone; actions belong in a toolbar. iPad has a different system placement and requires separate verification.
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): group related actions and use system spacing.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass): prefer standard system components/spacing, avoid stacked glass and custom control backdrops.
- [Flutter iOS composition limitations](https://docs.flutter.dev/platform-integration/ios/platform-views): ShaderMask/ColorFiltered are unsupported around platform views; backdrop filters have limitations.

The HIG does not prescribe a universal pixel offset for the floating tab bar. Use UIKit's layout/metrics and window safe areas instead of calling custom capsule dimensions an Apple specification.

## Execution

1. Regression-check the iOS composition path. Keep shader/backdrop effects away from UIKit controls; use native glass surfaces for overlay containers and preserve Flutter content.
2. Replace the custom navigation capsule with UITabBar; use UIToolbar for reader actions, native text actions/switches/segmented controls, and system menus. Keep existing callbacks, enabled states and options.
3. Respect safe-area and keyboard geometry; retain the article's layout and restoration model. Keep Android rendering unchanged.
4. Add meaningful widget/native interaction checks and CI previews covering light/dark, small/large screens, menus/panels and keyboard states. Preserve old previews and all RED/timeout results.
5. Review, run exact-SHA macOS CI, inspect actual generated images, package unsigned IPA. Signing, account operations and physical-device acceptance remain outside CI claims.
