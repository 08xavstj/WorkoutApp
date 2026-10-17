# References and licenses

## Used in the app

| Project | License | How it's used |
|---|---|---|
| [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) | Unlicense (public domain) | `App/Resources/exercises.json` (stretches removed). Images load from its GitHub repo at runtime. |
| [@anthropic-ai/sdk](https://www.npmjs.com/package/@anthropic-ai/sdk) | MIT | Claude calls in `supabase/functions/coach` |

Apple frameworks: SwiftUI, SwiftData, HealthKit, Foundation Models.

## Reference only (read for ideas, no code copied)

Run `scripts/fetch-references.sh` to clone these into `references/` (git-ignored).

| Project | License | Why it's useful |
|---|---|---|
| [xtool-org/xtool](https://github.com/xtool-org/xtool) | MIT | Build/install iOS apps without Xcode (Linux/Windows). Optional now that you have a Mac. |
| [StanfordSpezi/SpeziHealthKit](https://github.com/StanfordSpezi/SpeziHealthKit) | MIT | Robust HealthKit querying patterns. Not a dependency: it requires the whole Spezi framework, and plain HealthKit covers this app. |
| [rudrankriyam/Foundation-Models-Framework-Example](https://github.com/rudrankriyam/Foundation-Models-Framework-Example) | MIT | Current Foundation Models API usage (tools, sessions, errors), including a Health tool |
| [jamesrochabrun/SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) | MIT | Swift Claude client. Not used: the app talks to its own server so the API key stays off the phone. |
| [madebysan/aura-health](https://github.com/madebysan/aura-health) | MIT | HealthKit + AI insights app, chart ideas |
| [karimknaebel/Iron](https://github.com/karimknaebel/Iron) | **GPL-3.0** | Polished SwiftUI lifting tracker. Don't copy code, since GPL would apply to the whole app. |
| [RyanCwynar/gym](https://github.com/RyanCwynar/gym) | **No license** | SwiftUI + SwiftData gym logger. All rights reserved; ideas only. |
| [BlakeB88/Training_app](https://github.com/BlakeB88/Training_app) | **No license** | HealthKit strain/recovery app. All rights reserved; ideas only. |
| [wger-project/wger](https://github.com/wger-project/wger) | AGPL-3.0 | Open workout manager with an exercise API (alternative data source) |
| [twostraws/swift-agent-skills](https://github.com/twostraws/swift-agent-skills) | MIT | Directory of more Swift skills (App Intents, widgets, accessibility…) |

## Claude Code skills (installed in `.claude/skills/`)

| Skill | Source | Use it for |
|---|---|---|
| `swiftui-pro` | [twostraws/swiftui-agent-skill](https://github.com/twostraws/swiftui-agent-skill) | Writing and reviewing SwiftUI |
| `swiftdata-pro` | [twostraws/SwiftData-Agent-Skill](https://github.com/twostraws/SwiftData-Agent-Skill) | SwiftData models, queries, migrations |
| `swift-concurrency-pro` | [twostraws/Swift-Concurrency-Agent-Skill](https://github.com/twostraws/Swift-Concurrency-Agent-Skill) | Swift 6 concurrency errors |
| `swift-testing-pro` | [twostraws/Swift-Testing-Agent-Skill](https://github.com/twostraws/Swift-Testing-Agent-Skill) | Swift Testing tests |
| `foundation-models-on-device` | [affaan-m/ecc](https://github.com/affaan-m/ecc) | Apple's on-device model. Its tool example uses the old `ToolOutput` beta API; current code returns a `String`. |
| `ios-simulator-skill` | [conorluddy/ios-simulator-skill](https://github.com/conorluddy/ios-simulator-skill) | Driving the iOS Simulator from Claude Code (Mac only) |
| `using-xtool` | [2389-research/xtool](https://github.com/2389-research/xtool) | Xcode-free builds with xtool |

## Not used: REA (morluto/rea)

REA ("Reverse Engineer Anything") decompiles apps. Using it on Bevel would likely break Bevel's terms of service, and copying their design or code exposes you legally (Whoop is already suing Bevel). This app matches the *style* (dark cards, score rings, coach) with original code and branding.

## Design skills (installed in `.claude/skills/`)

| Skill(s) | Source | License |
|---|---|---|
| `apple-design`, `apple-design-foundations`, `-materials`, `-motion`, `-os`, `-interaction`, `-tactics`, `-web`, `-backend` | [s1gmamale1/apple-design-skills](https://github.com/s1gmamale1/apple-design-skills) | MIT |
| `apple-design-hig` (renamed from `apple-design` to avoid a clash) | [SudewaJay/apple-design-skill](https://github.com/SudewaJay/apple-design-skill) | MIT |
| `liquid-glass` | [heyparsadev/liquid-glass-skill](https://github.com/heyparsadev/liquid-glass-skill) | MIT |
| `ui-ux-pro-max` | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | MIT |
| `swiftui-design-principles` | [arjitj2/swiftui-design-principles](https://github.com/arjitj2/swiftui-design-principles) | MIT |
| `writing-for-interfaces` | [andrewgleave/skills](https://github.com/andrewgleave/skills) | MIT |
| `swiftui-ui-patterns`, `swiftui-liquid-glass`, `swiftui-view-refactor`, `swiftui-performance-audit` | [Dimillian/Skills](https://github.com/Dimillian/Skills) | MIT |
| `swiftui-expert-skill` | [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) | MIT |
| `swift-accessibility-skill` | [PasqualeVittoriosi/swift-accessibility-skill](https://github.com/PasqualeVittoriosi/swift-accessibility-skill) | MIT |
| `widgets` | [n0an/Widgets-Agent-Skill](https://github.com/n0an/Widgets-Agent-Skill) | MIT |

Not installed: [dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills) has no license and a registry security advisory; read it for reference only.

Planned UI libraries (added to the app when the redesign uses them): Swift Charts (built in), [EmergeTools/Pow](https://github.com/EmergeTools/Pow) (MIT), [twostraws/Vortex](https://github.com/twostraws/Vortex) (MIT), [twostraws/Inferno](https://github.com/twostraws/Inferno) (MIT), [airbnb/lottie-ios](https://github.com/airbnb/lottie-ios) (Apache-2.0), [rive-app/rive-ios](https://github.com/rive-app/rive-ios) (MIT), [SFSafeSymbols](https://github.com/SFSafeSymbols/SFSafeSymbols) (MIT), [markiv/SwiftUI-Shimmer](https://github.com/markiv/SwiftUI-Shimmer) (MIT).
