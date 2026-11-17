# Apple's Readiness, Sleep score and Health Age: can an app get them?

Checked 17 November 2026, for an owner on iOS 27 with an Apple Watch Series 12 (watchOS 27). This follows `watch-features.md` §6, which found no HealthKit type for any of the three. The question here is wider: every route by which an app could get the numbers, not only HealthKit.

## Verdict

| Number | Where Apple shows it | Can Tensile read it? | How it gets into Tensile |
|---|---|---|---|
| **Readiness** (0–10) | Readiness app on the Watch; Fitness app and the Health app's Insights tab on iPhone [S1][S5][S9] | **No.** No route found. | Screenshot read on the phone, typed, or passed in from Shortcuts |
| **Sleep score** (0–100) | Sleep app on the Watch; Health app on iPhone [S6] | **No.** Apple's engineer said so in September 2025 and nothing has changed since [S10]. | Same |
| **Health Age** (years) | Health app › Longevity, iOS 27.3 [S2][S3] | **No.** No route found. | Same |

No real API was found, so nothing in the app is gated on iOS 27 for this. If Apple adds a type later, read it in `HealthKitClient`, save it through `AppleScoresStore` with a new source, and keep the manual ways as the fallback.

One thing worth knowing about timing: the redesigned Health app with Health Age was in the iOS 27.2 beta, was pulled from the 27.2 release, and is in the iOS 27.3 developer beta since 3 November 2026; Apple says it reaches users "later this year" [S3][S4][S11]. An owner on a released iOS 27 may not have Health Age yet.

## Route by route

| # | Route | What was checked | Result |
|---|---|---|---|
| 1 | **HealthKit quantity types** | The full `HKQuantityTypeIdentifier` list [S12] | No readiness, sleep score or Health Age identifier. The only identifiers with "score" in the name are the two workout effort scores. The only new one for the Series 12 is `heartRateVariabilityRMSSD`. |
| 2 | **HealthKit category types** | The full `HKCategoryTypeIdentifier` list [S13] | Nothing. Sleep is still only `sleepAnalysis` (the stages the score is built from). |
| 3 | **Other HealthKit object types** | The Data types page: characteristic, correlation, activity summary, audiogram, ECG, series, clinical, workout, vision prescription [S14]; the HealthKit landing page [S15] | Nothing that holds a score, a readiness value or an age. |
| 4 | **HealthKit updates page** | "HealthKit updates" [S16] | The newest entry is still June 2026: workout zones and the menopause API. No later entry for the Series 12, iOS 27.2 or 27.3. |
| 5 | **iOS 27.2 and 27.3 release notes** | Both pages in full [S4][S17] | 27.2 has a "Health" section with two known issues about the redesigned app (Insights summaries; the app removed from the beta). 27.3 beta 2 has no Health or HealthKit section at all. No new API in either. |
| 6 | **Apple's developer forum** | "Sleep Score API access" [S10] | An Apple DTS engineer, September 2025: "As of today, there is no API that allows the access to sleep scores", with a suggestion to file feedback (a developer filed FB20278031). No later reply. A September 2026 thread about a wrong sleep score in the 27.2 beta doesn't mention an API [S18]. |
| 7 | **Clinical records (FHIR)** | `HKClinicalTypeIdentifier` [S19] | Allergy, clinical note, condition, immunization, lab result, medication, procedure, vital sign, coverage. These are records from a health provider. Apple's own scores aren't among them, and an app can't create clinical records. |
| 8 | **Health export** (Health › profile › Export All Health Data) | Not verified on a phone. Third-party reports only [S20] | An app can't run the export anyway: it's started by hand and produces a zip the owner would have to share. Reports say the Sleep score isn't in `export.xml`, which fits it not being a HealthKit sample. Not a usable route even if a future export includes it. |
| 9 | **Shortcuts actions from Health** | Not verified on a phone. The public descriptions of "Find Health Samples" and "Get Details of Health Sample" [S21] | These actions read HealthKit sample types. None of the three numbers is a sample type (rows 1–3), so they shouldn't be offered. To check on the owner's phone: Shortcuts › new shortcut › Find Health Samples › tap the type and search "Sleep Score", "Readiness", "Health Age". If one appears, a shortcut can pass it straight to Tensile's "Log Apple scores" action, with no screenshot. |
| 10 | **App Intents / Spotlight from Health** | The 27.3 release notes list one new App Intents schema domain (Video) [S17]. No documentation was found of the Health app exposing entities or intents to other apps. | No route. An app can't query another app's App Intents in any case; only the owner can, through Shortcuts or Siri. |
| 11 | **Widgets, complications, Smart Stack** | Reports that Readiness appears in Smart Stack widgets and complications [S9] | A widget is a picture drawn by its own app. iOS and watchOS give no app the content of another app's widget. No route. |
| 12 | **Health Sharing** (Sharing tab; share with a provider) | Apple's support pages [S22] | Shares chosen categories with people in Contacts or with a health provider's system. Not available to apps. Which categories include the scores wasn't checked. |
| 13 | **Reading the screen** | — | An app can't see another app's screen. The owner can take a screenshot and hand it over: that is the screenshot route below. |
| 14 | **Announced for later** | Apple's September and November 2026 announcements [S1][S2][S3] | Neither mentions developer access to Readiness, Health Age, Insights or Longevity. Third-party write-ups that looked reached the same conclusion [S23][S24]. |

**Not verified, and why it matters little:** rows 8, 9 and 12 weren't checked on a real iPhone (there is none here). Row 9 is the only one that could turn out to be a route, and the app is already ready for it: the Shortcuts action takes the numbers whatever their source.

## What Apple says about each number

Used for ranges, level words and the "About Apple's numbers" text. Apple hasn't published a formula for any of them, so the app stores and compares them and never mixes them into its own scores.

- **Readiness.** 0 to 10 with a recommendation: Recover (0–1), Pace Yourself (2–4), Ready (5–7), Go For It (8–10). From activity (today's and recent active calories, workout effort ratings, training load), vitals (daytime and overnight; a metric that is off lowers it, higher-than-usual overnight HRV can raise it) and sleep (last night's sleep score and recent history). Needs 7 nights of overnight vitals first. Series 12 and Ultra 4 only. It changes through the day [S1][S5][S9]. The bands are whole-number ranges, so the app takes whole numbers; whether the Watch ever shows a decimal is **not confirmed**.
- **Sleep score.** 0 to 100: sleep duration 50 points, bedtime consistency (the last 13 nights) 30, interruptions 20. Levels: Very Low 0–40, Low 41–60, OK 61–80, High 81–95, Very High 96+ [S6]. The bands were changed once, in iOS/watchOS 26.2 [S7]; early coverage used "Excellent" for the top level [S8], so the screenshot reader accepts that word too.
- **Health Age.** In the Longevity tab; from VO₂ max, resting heart rate, sleep and HRV, shown against chronological age; lab values such as A1c and LDL cholesterol can be added [S3]. The formula, weights and reference population aren't published [S24].

## What was built instead

Three ways in, all ending in the same store (`AppleScoresStore`, a JSON file in Application Support):

1. **Screenshot.** The owner screenshots the Readiness, Sleep or Health screen and picks it in the photo picker. Vision's `RecognizeTextRequest` reads the text on the phone [S25]; the picture is used once and not kept. `AppleScoreScreenReader` (AppCore, tested) finds numbers that sit beside a "Readiness", "Sleep Score" or "Health Age" label and returns candidates with the label each was next to. The owner sees what was read and confirms or corrects it before saving.
2. **Typed.** Readiness from a 0–10 picker, Sleep score 0–100, Health Age 10–120.
3. **Shortcuts.** The "Log Apple scores" action with optional Readiness, Sleep score, Health Age and Day.

**Assumed about Apple's screens.** Nobody outside Apple has a specification of the wording. The reader assumes English labels containing "Readiness", "Sleep Score" and "Health Age", whole numbers (optionally "7/10", "7 of 10", "82/100", "34 years"), and Apple's level words. It rejects anything with a unit, a percent sign, a time, a date, a decimal or a second number, and stops at any wording it doesn't know. None of this has been tried on a real screenshot. Other languages aren't handled.

**Comparing.** Tensile's own recovery, sleep score and body age are saved beside Apple's for the same day. The history view counts how often the two moved the same way from one day to the next, and shows a Spearman rank correlation once 20 days have both, with an approximate 95% interval [S26]. The 20 is the app's choice; correlations only settle at around 250 pairs [S27], and days in a row aren't independent. Everything is labelled as a description of those days. Nothing says which score is right: they're worked out differently, and Apple's method isn't public.

## Sources

Apple's developer pages were fetched as Markdown (the `.md` form of each URL) on 17 November 2026.

- [S1] Apple Newsroom, "Introducing Apple Watch Series 12, with the all-new Health Sensing System", 9 Sep 2026. https://www.apple.com/newsroom/2026/09/introducing-apple-watch-series-12-with-the-all-new-health-sensing-system/ (read for `watch-features.md` §6; not re-fetched this round)
- [S2] Apple Newsroom, "Apple advances health and fitness capabilities using Apple Intelligence", 9 Sep 2026. https://www.apple.com/newsroom/2026/09/apple-advances-health-and-fitness-capabilities-using-apple-intelligence/ (as [S1])
- [S3] Apple Newsroom, "Redesigned Health app expands language support", 3 Nov 2026. https://www.apple.com/newsroom/2026/11/redesigned-health-app-expands-language-support/
- [S4] iOS & iPadOS 27.2 Release Notes. https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_2-release-notes
- [S5] Apple Support 128112, "Understand your readiness score on Apple Watch". https://support.apple.com/en-au/128112
- [S6] Apple Watch User Guide, "Track your sleep with Apple Watch" (sleep score points and levels). https://support.apple.com/guide/watch/apded441a669
- [S7] MacRumors, "iOS 26.2 and watchOS 26.2 Update Sleep Score Ranges", 4 Nov 2025 (seen as a search result; not opened). https://www.macrumors.com/2025/11/04/watchos-26-2-updates-sleep-score-ranges/
- [S8] MacRumors, "You Don't Need the Apple Watch Series 11 to Get Your Sleep Score", 10 Sep 2025 (as [S7]). https://www.macrumors.com/2025/09/10/watchos-26-sleep-score/
- [S9] Apple World Today, "How to use the new Readiness app on the Apple Watch", 23 Sep 2026 (secondary). https://appleworld.today/2026/09/how-to-use-the-new-readiness-app-on-the-apple-watch/
- [S10] Apple Developer Forums, "Sleep Score API access" (DTS reply, Sep 2025). https://developer.apple.com/forums/thread/800403
- [S11] MacRumors, "Hands-On With the Redesigned Health App in the iOS 27.2 Beta", 16 Sep 2026 (secondary). https://www.macrumors.com/2026/09/16/ios-27-2-health-app-beta/
- [S12] HKQuantityTypeIdentifier. https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier
- [S13] HKCategoryTypeIdentifier. https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier
- [S14] HealthKit, Data types. https://developer.apple.com/documentation/healthkit/data-types
- [S15] HealthKit. https://developer.apple.com/documentation/healthkit
- [S16] HealthKit updates. https://developer.apple.com/documentation/updates/healthkit
- [S17] iOS & iPadOS 27.3 Beta 2 Release Notes. https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_3-release-notes
- [S18] Apple Developer Forums, "Health sleep score incorrect in 27.2", Sep 2026. https://developer.apple.com/forums/thread/847460
- [S19] HKClinicalTypeIdentifier. https://developer.apple.com/documentation/healthkit/hkclinicaltypeidentifier
- [S20] Terra, "Apple sleep score not exposed by HealthKit" (secondary; seen as a search result, not opened). https://docs.tryterra.co/faq/help-topics/data-api-sdk/provider-coverage-and-per-provider-data-availability/apple-sleep-score-not-exposed-by-healthkit
- [S21] Matthew Cassinelli, "Find Health Samples" action reference (secondary; seen as a search result, not opened). https://matthewcassinelli.com/actions/find-health-samples/
- [S22] Apple Support, "Health app data Share with Provider FAQ" (seen as a search result, not opened). https://support.apple.com/guide/healthregister/apd531bc6215/web
- [S23] Sahha, "Apple Watch Series 12 Health Features" (secondary; from `watch-features.md` [C9]). https://sahha.ai/blog/apple-event-2026-health-readiness-labs/
- [S24] Terra, "Apple Health features 2026", 11 Sep 2026 (secondary; says Apple hasn't published Health Age's formula; silent on developer access). https://tryterra.co/blog/apple-health-features-2026
- [S25] Vision: RecognizeTextRequest, RecognizedTextObservation, NormalizedRect (iOS 18+). https://developer.apple.com/documentation/vision/recognizetextrequest
- [S26] Bonett DG, Wright TA, "Sample size requirements for estimating Pearson, Kendall and Spearman correlations", Psychometrika 2000;65(1):23–28. Citation and the variance form checked through search results; the paper itself is paywalled and **was not read**.
- [S27] Schönbrodt FD, Perugini M, "At what sample size do correlations stabilize?", J Res Pers 2013;47:609–612. Checked through the authors' summary and a 2020 replication found by search; **the paper itself was not opened**.
