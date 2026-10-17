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
