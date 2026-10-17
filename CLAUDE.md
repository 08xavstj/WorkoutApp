# WorkoutApp - notes for Claude

iPhone app (iOS 26+, Swift 6.2, SwiftUI, SwiftData, HealthKit, Foundation Models) in the style of Bevel: strain/recovery/sleep scores, an AI coach, and a gym tracker. See README.md for features and setup.

## Build

- The Xcode project is generated: `xcodegen generate` (spec: `project.yml`). Never commit `*.xcodeproj`.
- Signing (team + bundle ID) comes from `Config/Base.xcconfig`, which includes the git-ignored `Config/Signing.local.xcconfig` written by `scripts/set-signing.sh`. Don't put a team ID in `project.yml`.
- Score math lives in `Packages/AppCore` (pure Swift, no UI/HealthKit). Test it with `swift test --package-path Packages/AppCore`. Put new scoring logic there, with tests.
- CI (`.github/workflows/ios.yml`) runs the tests and a simulator build on macOS. Linux sandboxes can't build Swift for iOS, so check CI after pushing.

## Conventions

- Build settings: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency. Types that are Codable or shared across actors are declared `nonisolated` (see `CoachSnapshot`, `Exercise`). HealthKit work goes through `HealthKitClient`, whose methods are `@concurrent` and return AppCore value types.
- Weights are stored in kilograms; convert only in the UI via `WeightUnit`.
- Colors and card styling come from `App/Design/Theme.swift`. Dark UI, one accent color per score.
- Use the installed skills: `swiftui-pro`, `swiftdata-pro`, `swift-concurrency-pro`, `swift-testing-pro`, `foundation-models-on-device` (its `ToolOutput` example is outdated; return `String` from `Tool.call`).
- The Anthropic API key lives only in Supabase secrets. The app never calls api.anthropic.com directly.
- Don't copy code from GPL or unlicensed reference repos (see docs/REFERENCES.md).
- Don't use Bevel's or Whoop's names, logos or assets.
