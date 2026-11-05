# WorkoutApp - notes for Claude

iPhone app (iOS 26+, Swift 6.2, SwiftUI, SwiftData, HealthKit, Foundation Models) in the style of Bevel: strain/recovery/sleep scores, an AI coach, and a gym tracker. See README.md for features and setup.

## Build

- The Xcode project is generated: `xcodegen generate` (spec: `project.yml`). Never commit `*.xcodeproj`.
- Signing (team + bundle ID) comes from `Config/Base.xcconfig`, which includes the git-ignored `Config/Signing.local.xcconfig` written by `scripts/set-signing.sh`. Don't put a team ID in `project.yml`.
- Score math lives in `Packages/AppCore` (pure Swift, no UI/HealthKit). Test it with `swift test --package-path Packages/AppCore`. Put new scoring logic there, with tests.
- CI (`.github/workflows/ios.yml`) runs the tests and a simulator build on macOS. Linux sandboxes can't build Swift for iOS, so check CI after pushing.

## Conventions

- Research comes first. Every score, target, threshold and recommendation must follow published evidence (prefer meta-analyses, systematic reviews and position stands), with the citation in a comment next to the constant, and must be tailored to the user's goals (`Goals`) where the evidence differs by goal. If the evidence is weak or mixed, say so in the code and in the UI; don't present app-made numbers as science. Research write-ups live in `docs/research/`.

- Build settings: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency. Types that are Codable or shared across actors are declared `nonisolated` (see `CoachSnapshot`, `Exercise`). HealthKit work goes through `HealthKitClient`, whose methods are `@concurrent` and return AppCore value types.
- Weights are stored in kilograms; convert only in the UI via `WeightUnit`.
- Colors and card styling come from `App/Design/Theme.swift` (light by default, adaptive dark). Reusable pieces (rings, gauges, chips, sparklines) are in `App/Design/ScoreRing.swift`. The mockups in `docs/mockups/` are the visual reference. Each tab has a pastel `TopGlow` wash and each score a two-color gradient (`Theme.strainColors` etc.).
- SwiftUI resolves colors and draws shapes on a background render thread. Color providers and `Shape` types must be `nonisolated` (see `Theme.adaptive`, `GaugeArc`); a main-actor closure there crashes at launch. Avoid `Canvas` for the same reason.
- Scroll content gets `.lockedToScreenWidth()` so pages never pan sideways.
- The trainer (`WorkoutPlanner`, `GymProfile` in AppCore) must only plan exercises the user's gym supports and loads they can make with their plates/dumbbells/stacks.
- Use the installed skills: `swiftui-pro`, `swiftdata-pro`, `swift-concurrency-pro`, `swift-testing-pro`, `foundation-models-on-device` (its `ToolOutput` example is outdated; return `String` from `Tool.call`).
- The app has no cloud AI. The coach runs only on Apple's on-device model (FoundationModels); nothing the user types or photographs leaves the iPhone.
- Don't copy code from GPL or unlicensed reference repos (see docs/REFERENCES.md).
- Don't use Bevel's or Whoop's names, logos or assets.
