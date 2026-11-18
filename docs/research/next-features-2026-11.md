# Next features: Watch, iPhone, integrations and metrics (18 Nov 2026)

The owner (iPhone 17 on iOS 27, Apple Watch Series 12 on watchOS 27.2.1, Oura Ring 5, Cronometer for food) asked what Tensile should add next on the Watch and the iPhone, which other health services are worth connecting, and which health measures it should start tracking. The rules: follow published evidence, prefer the strongest evidence and the biggest health effect, leave out what has none, and label unvalidated options instead of hiding them. No app code was written.

**How this was researched.** These were read first so nothing here repeats them: `README.md`, `roadmap.md`, `evidence-audit-2026-11.md`, `healthy-living-2026-11.md`, `competitor-features-2026-11.md`, `watch-features.md`, `oura-ring-2026-11.md`, `longevity-insights.md`, `behaviour-change.md`, and the Watch redesign spec (`watch-app-redesign-2026-11.md`, treated as planned). The file names in `Packages/AppCore/Sources/AppCore/`, `App/Features/**` and `App/Services/` were listed, and the code was searched for every HealthKit identifier and feature named below ("In Tensile?" columns). Apple facts come from the JSON behind developer.apple.com documentation pages. Papers were checked through NCBI E-utilities (PubMed records and abstracts). Vendor API facts come from the vendors' own pages where they could be fetched.

**Labels.** **[P]** PubMed abstract read this round. **[A]** Apple developer documentation read this round. **[W]** vendor or press page fetched and read this round. **[S]** seen only in a search-result summary this round. **[D]** carried from an earlier Tensile research file, with that file's check. **[M]** from memory, not checked this round. Effort: **S** a day or two, **M** about a week, **L** several weeks. "Unvalidated" means no published study tests the number or feature itself.

---

## Summary

1. **Most of the high-value work is already built or planned.** The things with the biggest health effects for a man who lifts 4–5 times a week are covered: aerobic minutes counted correctly, the weekly hard interval session, strength days, sleep length and regularity, blood pressure, the lipid/Lp(a)/HbA1c schedule, alcohol, hearing, mood screens and the illness watch. What follows is mostly about **making the aerobic work happen more easily**, **getting lab results in without typing**, and a few **cheap functional tests**.
2. **The best Watch addition is sending structured cardio to Apple's own Workout app** with WorkoutKit (iOS 17 / watchOS 10 [A]). The weekly 4 × 4 then runs with Apple's step alerts, and with Workout Buddy's spoken coaching if he wants it, which third-party apps cannot use any other way: Workout Buddy has no developer API [W1][S1]. Cardiorespiratory fitness is the largest lever he has (high vs low fitness, mortality HR 0.47; Lang 2024 [D]), and long intervals raise VO₂ max most (Wen 2019 [P]).
3. **The second is a brisk-walk mode paced by cadence, not heart rate.** At 100 steps a minute or more, walking reaches moderate intensity (3 METs; PPV 91%, Tudor-Locke 2019 [P]), but a fit person's heart rate can stay below a heart-rate-reserve "moderate" band at that pace. Walking is his cheapest source of aerobic minutes.
4. **The best iPhone addition is importing lab results from Apple Health Records** (FHIR, read-only, needs Apple's clinical-records entitlement [A]). Quest and Labcorp send results to Health Records [S], and institutions in the US, Canada and the UK can join [S]. It turns the existing "know your numbers" schedule from typing into automatic. It depends on whether his clinic or lab is connected (question for the owner).
5. **One correction comes first:** the vitamin D retest line in `LabMarkers` ("Once, in winter, if you train indoors") goes against the Endocrine Society 2024 guideline, which suggests against routine 25(OH)D testing in healthy adults (Demay 2024 [P]), and USPSTF 2021, which found the evidence insufficient (I statement; JAMA 2021 [P]).
6. **Integrations: almost none are worth it for this owner.** He has no Garmin, Polar, Whoop, Eight Sleep or CGM. Cronometer has no public API [S], so HealthKit stays the route. A Withings cuff or scale is best read through Apple Health, not its API, which needs a server for the code exchange [W]. Strava requires a client secret, documents no PKCE [W], shows a user's data only to that user [W], and its policy bars AI use of API data [S], which would cover the on-device coach.
7. **Leave out:** hydration prompts, a smart alarm, live heart-rate alerts outside workouts, fall detection, breathing and meditation sessions (still), CGM for a non-diabetic, fasting insulin, the omega-3 index, ultra-processed-food scoring, protein-per-meal targets, screen time, and cycle-phase training. Reasons in §5.

---

## 0. What exists, so it isn't proposed again

From the code and README (18 Nov 2026):

- **Scores and baselines:** strain, recovery and sleep; Oura HRV and sleeping heart rate as one-device baselines; the "Oura's own numbers" panel (display only, owner's choice 18 Nov).
- **Training:** zones; the weekly plan with if-then and coping lines, a busy-week mode and calendar export (`PlanCalendarSync`); the hard interval session (`HardCardio`, `IntervalSession`); the quarterly walking fitness check (`FitnessCheck`: Rockport one-mile walk and the Ebbeling treadmill walk); grip strength; PainGuard; illness watch (z-scored wrist temperature, breathing disturbances, symptoms, two-day rule).
- **Watch:** lifting and a cardio mode with 27 activities, GPS routes, zone haptics, complications, double tap, Siri start. Planned in the redesign: pagers, laps, auto-pause, Water Lock, Always On, interval runner (C7), Controls and `fitnessCenter` relevance (C8).
- **Health:** longevity factors, insights, mood check-ins with PHQ-9 and GAD-7 when mornings run low, blood tests with a due schedule (`BloodTestSchedule`: lipids with ApoB, Lp(a) once, HbA1c/glucose), home BP protocol and Apple's hypertension notification, STOP-Bang and sleep-apnoea events, hearing budget, daylight, alcohol and a drink limit, sleep window (insomnia path), saturated fat, micronutrients, supplements, medications with the iOS 26 Medications API and "Taken/Snooze" notification actions, progress photos, waist, body measurements.
- **Sharing:** share cards, weekly card, exports, route privacy, calendar, best efforts, year in review.

HealthKit types **not read anywhere** in the code (searched 18 Nov): `walkingSpeed`, `appleWalkingSteadiness`, `sixMinuteWalkTestDistance`, `atrialFibrillationBurden`, `appleStandHour`/`appleStandTime`, `highHeartRateEvent`, `lowHeartRateEvent`, `irregularHeartRhythmEvent`, `lowCardioFitnessEvent`, `estimatedWorkoutEffortScore`, `physicalEffort`, `waistCircumference`, `hipCircumference`, `bloodGlucose`, `mindfulSession`, clinical records (`HKClinicalTypeIdentifier`). Nothing uses WorkoutKit or `AVSpeechSynthesizer`.

---

## 1. Watch app: new features beyond the redesign spec

| # | Feature | watchOS capability (checked) | Evidence | Health effect | Effort | Verdict |
|---|---|---|---|---|---|---|
| **W1** | **Send this week's cardio to Apple's Workout app.** The hard session (for example 4 × 4 min, as `IntervalSession` plans it) and the easy sessions as `CustomWorkout`s with warm-up, `IntervalBlock`s and cool-down. Each work step carries a `HeartRateRangeAlert` set to Tensile's own bpm band, so the wrist's alerts match Tensile's zones. Schedule them on the planned day with `WorkoutScheduler`. Tensile already reads the finished `HKWorkout` and its events from Health. | WorkoutKit: `CustomWorkout`, `IntervalBlock`, `HeartRateRangeAlert`, `WorkoutScheduler.schedule(_:at:)`, iOS 17 / watchOS 10 [A2][A3]. Later additions: pool-swim workouts, named steps, power and pace alerts, `workoutPreview` [A4]. | HIIT raises VO₂ max. Long intervals (≥ 2 min), higher volume and 4–12+ weeks give the largest gains over continuous training (SMD 0.65–1.07; Wen 2019 [P]; Milanović 2015 [P record]). Fitness is the strongest mortality predictor he can change (Lang 2024 [D]). | **Large, indirect.** It makes the evidence-backed hard session run in the app he may already use. It also gets Apple's Workout Buddy voice for running, walking, outdoor cycling, HIIT and strength, which needs Bluetooth headphones and an Apple Intelligence iPhone [W1]. | S–M | **Build.** It overlaps spec C7 (Tensile's own interval runner). Do W1 first: it is smaller and adds Apple's metrics, pool swim and Buddy. Keep C7 for activities and targets WorkoutKit can't express. |
| **W2** | **Spoken cues in Tensile's own Watch workouts** (to AirPods): step changes ("Hard 2 of 4, 4 minutes, effort 8"), split, rest over, "ease off" after 20 s above the band. Lines are templates from the phone's data; the on-device model is not on watchOS [D]. | `AVSpeechSynthesizer` is available on watchOS 2+ [A5]. Workout Buddy itself is Apple-only, with no API [W1][S1]. | No trial tests spoken workout cues on health. Music during exercise improves affect (g = 0.48), performance (g = 0.31) and perceived exertion (g = 0.22; Terry 2020 [P]): a related effect, not the same thing. | Small (usability; may help intervals get done as planned) | S | **Build after W1**, off by default except on interval sessions (app's choice). Label it usability only. |
| **W3** | **Brisk-walk mode paced by cadence.** A walking workout with a tap when cadence drops below 100 steps/min for 30 s (app's choice), and "brisk minutes" (≥ 100 spm) in the summary. It counts toward the aerobic floor even when heart rate stays low. | `CMPedometerData.currentCadence` on watchOS 2+ [A6]; Tensile already uses 100 steps per raised-HR minute (`app-audit.md`). | 100 spm ≈ 3 METs in 21–40-year-olds (PPV 91.4%); 130 spm ≈ vigorous (PPV 70.7%; Tudor-Locke 2019 [P]). About 150 min/week of activity ≈ RR 0.69 for mortality (Garcia 2023 [D]). | Moderate: the easiest aerobic minutes for a lifter | S–M | **Build.** Pair it with spec §4.5 (walk is already one of the 27 activities). |
| **W4** | **More Smart Stack relevance** beyond the spec's `fitnessCenter` card: the bed-by window in the hour before it, the hard-cardio card on its planned day, and the next dose at its time (the medications Live Activity already covers doses). | RelevanceKit / Smart Stack relevance API in watchOS 26 [W1]; the spec's §4.9 notes what to verify. | None for health. It lets glances replace clock reminders, which the evidence says to keep off for an established habit (Buyalskaya 2023 [D]). | Small | S | **Build with C8.** |
| **W5** | **Apple's heart events, one line.** Read `highHeartRateEvent`, `lowHeartRateEvent` and `irregularHeartRhythmEvent` and show "Apple flagged N this month; see Health" in the heart section, with no alert of our own. | Category types since iOS 12.2 / watchOS 5.2 [A7]. | In a 2026 living meta-analysis, Apple Watch AF detection had specificity 0.91 and sensitivity 0.79 (Lambe 2026 [P]). The base rate is low at his age (`watch-features.md` 1.9 [D]). | Small | S | **Optional.** Proposed in `watch-features.md`, still unbuilt; cheap. |
| W6 | Live heart-rate alerts outside workouts | Not possible in the background beyond workouts; Apple's own high, low and irregular-rhythm notifications already run system-wide [A7] | No evidence that a second alert helps | None; risks duplicates | – | **Leave out** (§5) |
| W7 | Fall detection | `CMFallDetectionManager` needs a special Apple entitlement; Apple's own fall detection already calls emergency services [A8] | – | None for a 30-year-old lifter | – | **Leave out** |
| W8 | Medication reminders on the wrist | Already built: dose notifications carry "Taken" and "Snooze 10 min" actions (`Reminders.swift`), which show on the Watch, plus the meds Live Activity | Text reminders roughly double the odds of adherence (OR 2.11; Thakkar 2016 [P]) | Already delivered | – | **Nothing new.** Check on the wrist that the actions appear. |
| W9 | Sleep: smart alarm, wind-down session | – | No outcome trials; the only paper found is an engineering conference abstract [P: PMID 33018943] | None shown | – | **Leave out** (the sleep window and bed-by already exist) |
| W10 | Hydration prompts | – | Drink to thirst; over-drinking causes exercise hyponatraemia (Hew-Butler 2015 consensus [P]). The water status was removed on 17 Nov because logged water mostly measures logging (`evidence-audit-2026-11.md` [D]). | None, possible harm | – | **Leave out** |
| W11 | Breathing / mindfulness session (re-checked) | `mindAndBody` workouts; mindful sessions in HealthKit | Breathwork lowers self-reported stress a little (g = −0.35, 12 RCTs, most at moderate risk of bias; Fincham 2023 [P]). But breathing apps kept a median **0%** of users at day 30 (Baumel 2019 [P]), and relaxation may be counterproductive inside insomnia therapy (Furukawa 2024 [P]). The owner removed it earlier. | Small, and unlikely to be used | – | **Stays out.** If he uses Apple's Mindfulness app, read `mindfulSession` as a "What affects you" factor (S). See W12 for the one breathing intervention with a blood-pressure effect. |
| W12 | **Inspiratory muscle strength training (IMST), conditional.** 30 breaths a day against a handheld trainer (a device he would need to buy), with a Watch counter and a log. Offered only if his 7-day home systolic average is 120 or more. | Timer and counter; no special API | A meta-analysis of 12 RCTs (n = 386) found SBP −7.9 mmHg and DBP −3.8 mmHg (Li 2023 [P]). In the key trial (ages 50–79, SBP ≥ 120), SBP fell from 135 to 126 mmHg over 6 weeks (Craighead 2021 [P]). Trials were small, and mostly midlife and older adults. | Moderate **if** BP is above normal; none otherwise | S | **Consider later**, behind the BP condition. Evidence moderate, small trials. |

---

## 2. iPhone app: new features

| # | Feature | Evidence | Health effect | Effort | Verdict |
|---|---|---|---|---|---|
| **I1** | **Lab results from Apple Health Records.** Read `HKClinicalRecord` lab results (FHIR `Observation`) and map LOINC codes to `LabMarkers` ids (LDL, ApoB, Lp(a), HbA1c, ferritin, eGFR…). They feed Labs and `BloodTestSchedule` with the test date, so "due" rows update themselves. Optionally read conditions and medication records to cross-check the Medications list. Read-only, on the device, its own permission sheet; needs the Clinical Health Records capability, a usage string and a privacy-policy URL [A9]. | The schedule rests on strong guidance: test Lp(a) at least once in adults (Kronenberg 2022 [P]); lipids every 4–6 years from 20 (ACC/AHA 2019 [D]); HbA1c from 35 (ADA 2026 [D], USPSTF 2021 [P]). Data entry is a top reason people stop using health apps (Krebs & Duncan 2015 [D]). | Moderate to large, indirect: results that arrive are results that get acted on | M | **Build, if his clinic or lab is connected.** Institutions in the US, Canada and the UK can register [S2]; Quest and Labcorp send results to Health Records [S3]. Ask the owner first. |
| **I2** | **Vitamin D retest fix** (a correction, not a feature). Change `LabMarkers` vitamin D "retest" from "Once, in winter, if you train indoors" to "Only when a doctor has a reason (bone health, a condition or a medicine that affects it)". Keep the result's interpretation. | Endocrine Society 2024: "the panel suggests against routine 25(OH)D testing in all populations considered" (Demay 2024 [P]); USPSTF 2021: insufficient evidence to screen (I; JAMA 2021 [P]). | Avoids a test with no proven benefit | S | **Fix now.** |
| **I3** | **Travel and time zones.** Store the time zone with each night (the open item in `qa-2026-11-17.md`), move bed-by, caffeine cut-off and dose times onto local time over a few days, and after flights across 5+ zones show one card: melatonin 0.5–5 mg near the local bedtime works (9 of 10 trials; NNT 2; more benefit flying east; taken early in the day it delays adaptation) (Herxheimer, Cochrane 2002 [P]), and when to seek and avoid light (Roach 2019 review [P record]). Safety lines: warfarin, epilepsy [P]. | Melatonin: moderate (Cochrane, small trials). Light timing: weak to moderate, mostly lab and model studies [P record]. | Small to moderate, only on trips | M | **Build if he flies across zones** (open question 11 in `healthy-living-2026-11.md`). |
| **I4** | **Functional test pack**, added to the yearly fitness check: **push-ups to failure** (men: > 40 vs < 10 went with 96% fewer CVD events over 10 years, IRR 0.04; 1,104 firefighters, only 37 events; Yang 2019 [P]); from 45, the **sitting-rising test** (0–10; lowest vs highest group HR 3.84 for natural death and 6.05 for CV death, ages 46–75; Araújo 2026 [P]; Brito 2014 [P record]) and the **10-second one-leg stand** (unable: HR 1.84, ages 51–75; Araújo 2022 [P]). | Cohorts only, mostly middle-aged and older; push-up evidence is one small occupational cohort | Small directly (a test doesn't change health); useful as a trend and for spotting decline | S | **Build the push-up test now**; show the other two from 45. Label each "linked with, one cohort". |
| **I5** | **Accountability without a server.** (a) A weekly prompt inside the review to send the existing weekly card to one chosen person (share sheet; nothing uploaded). (b) "Plan a session together": share an `.ics` invite for a planned session from the weekly plan. EventKit can't add attendees to an event, so it goes through the share sheet [M]. | Monitoring helps more when progress is reported to someone (Harkin 2016 [D]). Group-based PA interventions showed only a small, non-significant edge over individual ones for activity (g = 0.09) and health (g = 0.13), but helped functional outcomes (g = 0.16; 71 studies; Kritz 2026 [P]). Stronger social relationships went with 50% higher odds of survival (OR 1.50; Holt-Lunstad 2010 [P]). | Small | S | **Build if he names a person** (open question 10 in `healthy-living-2026-11.md`). |
| I6 | **Social connection check** (3-item UCLA loneliness scale; Hughes 2004 [P record]) every 3 months in the weekly review, optional, with "plan time with someone" as the only follow-up | The link is strong: isolation HR 1.32 and loneliness HR 1.14 for all-cause mortality (90 cohorts, 2.2 million people; Wang 2023 [P]). The intervention evidence is weak: randomised trials showed smaller effects, and the best addressed maladaptive social thinking (Masi 2011 [P]), which an app can't deliver. | Uncertain | S | **Consider later**, off by default. Fold the useful part into I5. |
| I7 | Coaching and habits | Already built: if-then and coping plans, consistency score, minimum sessions, autonomy-supportive wording (`behaviour-change.md` [D]). New: habits took a median 59–66 days to form, ranging 4–335 (20 studies, mostly high risk of bias; Singh 2024 [P]). So don't fade structure before about 2 months. | – | – | **Nothing new to build.** Check that nothing fades sooner than 2 months. |
| I8 | Nutrition beyond what Cronometer sends | Energy, macros, fibre, saturated fat, sodium, potassium and 12 micronutrients are already read and judged (`Micronutrients`, `SaturatedFat`). Ultra-processed food can't be measured: HealthKit carries nutrients, not food names, and most of the UPF associations are low or very low GRADE (Lane 2024 [P]). Protein per meal has no ceiling (Trommelen 2023 [P]); the daily total is what matters (Morton 2018 [P record]). | – | – | **Nothing new.** |
| I9 | **DEXA fields** (visceral fat mass, appendicular lean mass index), entered after a scan and shown beside waist-to-height | VAT per SD: OR 1.45 for prevalent ASCVD; top vs bottom quartile HR 6.28 for CV death in adults 20–59 (NHANES, 44 CV deaths; Cesaro 2026 [P]). Muscle mass index predicted survival in older adults (Srikanthan 2014 [P record]). | Small to moderate; scans are optional and at most yearly | S | **Consider later**, if he gets scans. |
| I10 | Write waist/hip to Health and read others' (`waistCircumference`, `hipCircumference` [A10]) | Plumbing; waist-to-height is already graded (Ashwell 2012 [D]) | None directly | S | **When convenient.** |
| I11 | Illness detection, injury | Built (`IllnessWatch` z-score, symptoms; `PainGuard`) | – | – | **Nothing new.** |
| I12 | Women's health / cycle-aware training (**optional; owner is male**) | Phase-based programming is premature (umbrella review, `watch-features.md` [D]); cycle notes already exist (`CycleEnergy`, `CycleRecovery`); menopause types exist in iOS 27 [A1] | – | – | **Leave out** for this owner. |

---

## 3. Health integrations beyond Apple Health and the Oura API

App rules that apply: no cloud AI; secrets in the Keychain. The Oura link set the pattern: the owner creates his own developer app, and its client ID, secret and tokens stay in this iPhone's Keychain. That is acceptable for a personal app, but a secret shipped in a distributed app is not secret.

| Service | API? | Server or business account? | What it gives | Data validated? | For this owner |
|---|---|---|---|---|---|
| **Apple Health Records** (FHIR) | Yes, in HealthKit: `HKClinicalRecord`, `HKClinicalTypeIdentifier` (lab results, conditions, medications, immunizations…), read-only [A9][A11] | No server. Needs the Clinical Health Records capability, a usage string and a privacy policy; App Review checks the use [A9]. The provider must be registered with Apple: US, Canada, UK [S2]. | Lab results with LOINC codes, units and reference ranges; conditions; medication records | Clinical lab values (the lab's own) | **Worth it** (I1), if his clinic or lab is connected. |
| **Apple Medications API** (iOS 26) | Yes: `HKUserAnnotatedMedication`, `HKMedicationDoseEvent`, per-object authorization [A1] | No | Medications in the Health app and logged doses | – | **Already built** (`HealthKitClient+iOS26`). |
| **Dexcom** (G7, Stelo) | Yes, Dexcom API v3, OAuth [S4] | Sandbox for anyone; production needs an upgrade. "Individual" Limited Access allows up to 5 users; commercial use needs a partnership [S4]. The token exchange is server-side by design [M]. | Glucose readings, events | Dexcom's G7 is a cleared device [M]. Apple Health gets G7 data after a **3-hour delay** [S5]. | **Not worth it.** He doesn't have diabetes, and CGM outcome data in people without diabetes are scarce; a 2026 meta-analysis found short-term diet change but no independent weight effect (reviews [S6]). If he ever wears one, read `bloodGlucose` from Health (no API). |
| **FreeStyle Libre** | No consumer API (LibreView is for clinics) [S7] | – | – | – | **Not worth it.** Users report no Apple Health sync for Libre 3 Plus in Canada [S7]. |
| **Withings** (scales, BPM cuffs) | Yes, Public API, OAuth 2, no contract [W2] | The code exchange needs the client secret server-side; codes expire in 30 s; access tokens last 3 h and refresh tokens a year; webhooks need a public callback URL [W2] | Weight, fat and muscle mass, BP and pulse, ECG/AF flags, temperature, sleep [W2] | Cuffs: some models are on validated-device lists (check the model on validatebp.org [M]). Body fat from scales: about 5–8 points off DEXA (README, `EnergyCalculator` [D]). | **Use Health, not the API.** Health Mate writes weight, body composition and BP to Apple Health [S8], which Tensile already reads. Any validated cuff that writes to Health works the same. |
| **Cronometer** | No public API; partner-only or enterprise [S9] | Partner agreement | – | – | **HealthKit only** (already done). |
| **Garmin** | Yes. New: a **Personal** tier for individuals, pull only, with a personal API key; Business tiers by application (Starter push-only; Enterprise push or ping/pull) [W3] | Personal: no business account. Business: application and approval [W3]. | Activity and FIT files, health summaries (incl. HRV status, sleep), women's health [W3] | Garmin's own metrics are proprietary | **Not now** (he wears an Apple Watch). The README's roadmap item 1 ("needs approved business access") is out of date: re-check if he goes back to Garmin. |
| **Strava** | Yes, OAuth; mobile OAuth through the Strava app [W4] | New apps get 1 athlete ("Single Player Mode") [S10]; the token exchange requires `client_secret` and no PKCE is documented [W4]; from June 2026 Standard developers need a Strava subscription [S11] | Activities, streams, routes | Device data as uploaded | **Leave out.** Personal use fits Single Player Mode, but Strava data "can only be displayed … to that user" [W5], caching is limited [S11], and the API policy bars AI use including prompts and RAG [S11], which would cover the on-device coach. Strava already reads Apple Health workouts [M], and Tensile exports GPX. |
| **Polar AccessLink** | Yes, v3, OAuth 2; users must be registered via the API before data flows [W6] | Polling works without a server; webhooks need HTTPS [W6] | Exercises (FIT/TCX/GPX), daily activity, 5-min continuous HR, cardio load, sleep, Nightly Recharge [W6] | Polar H10 chest strap is a common ECG-grade reference [M] | **Not relevant** (no Polar device). Exercises appear only if uploaded in the last 30 days and after registration [W6]. |
| **Whoop** | Yes, v2, OAuth 2: recovery (incl. HRV RMSSD, RHR, SpO₂, skin temperature), sleep, cycles, workouts [S12] | Developer access requires a Whoop device and membership; integrations are reviewed before release [S12] | As above | Whoop's scores are unvalidated composites [D] | **Not relevant** (no device). If ever used: read the raw HRV/RHR only, never the scores, and never show Whoop's name or branding in the UI (CLAUDE.md). |
| **Eight Sleep** | No official public API; community tools use undocumented endpoints [S13] | – | Writes some sleep data to Apple Health; HRV reportedly not [S14] | – | **Not relevant**; never use undocumented endpoints. |
| **Smart scales in general** | Through Apple Health | – | Weight (good), body fat and muscle (poor) | Bioimpedance body fat is too noisy for decisions (README [D]) | **Use weight only**, as now. |
| **Lab services** (Quest, Labcorp, others) | No self-serve consumer API; developer routes are EHR or partner products [S3] | Business | – | – | **Use Health Records (I1)**, where both send results [S3]. |
| **Google Health Connect** | Android only | – | – | – | **Not relevant on iOS.** |

---

## 4. New health metrics, ranked by evidence for health or longevity

"In Tensile?" was checked by searching the code for the HealthKit identifier or the feature name (18 Nov 2026).

### 4a. From the Series 12, iPhone or Oura

| Rank | Metric | Evidence (effect size) | Strength | How / how often | In Tensile? | Verdict |
|---|---|---|---|---|---|---|
| 1 | Hypertension notification | Sensitivity 41%, specificity 92% vs 30-day home BP; a missed notification doesn't rule it out (Apple validation paper [W7]; FDA K250507 summary [S15]) | Moderate (for the notification); strong for BP itself | Watch, passive | **Yes** (`hypertensionEvent`, home BP protocol) | Keep |
| 2 | Sleep apnoea notification + nightly breathing disturbances | Catches about two thirds of cases (`StopBangView` [D]) | Moderate | Watch, nightly | **Yes** | Keep |
| 3 | Wrist temperature trend | One of the better early-infection signals with a personal baseline (TemPredict 82% sensitivity [D]) | Moderate | Watch/Oura, nightly | **Yes** (illness watch, z 1.5) | Keep |
| 4 | Heart-rate recovery | Built with the clinical cut-off removed (`evidence-audit-2026-11.md` M3 [D]) | Moderate | After cardio | **Yes** | Keep |
| 5 | Daylight | Each extra hour outdoors went with lower odds of depression (UK Biobank, cross-sectional [D]) | Weak–moderate | Watch | **Yes** | Keep |
| 6 | Noise / headphone dose | WHO/ITU 80 dB(A) for 40 h/week [D] | Moderate (guideline) | Watch, AirPods | **Yes** | Keep |
| 7 | **Walking speed** (`walkingSpeed`, iPhone) | 0.1 m/s faster: HR 0.94 for death; fastest vs slowest HR 0.57 (13 cohorts, 530,841 people; Liu 2024 [P]). Self-reported slow vs brisk pace: HR about 2 in men (UK Biobank; Yates 2017 [P]). Strongest in older adults (Studenski 2011 [P record]). | Strong (observational), mostly older adults | iPhone in a pocket, passive, weekly trend | **No** | **Optional stat now** (tracked, not graded); grade it from 60. Ceiling effect at his age. |
| 8 | SpO₂ trend | Apple Watch: mean bias −0.04% but limits of agreement ±4% (Lambe 2026 [P]) | Low for healthy people | Watch | **Yes** (stat) | Keep as is; no target |
| 9 | Stand hours / sedentary time | With about 60–75 min/day of moderate activity, the sitting-mortality link disappears; TV ≥ 3 h/day is attenuated, not removed (Ekelund 2016, 1 million people [P]). Accelerometer data: most vs least sedentary HR 2.63, mean age 63 (Ekelund 2019 [P]). | Strong for inactive people | Watch | **No** | **Leave out** while he trains 4–5×/week; revisit if training stops for weeks. |
| 10 | Walking steadiness | Designed to flag fall risk from a mobility limitation over the next 12 months; Apple's own validation [W8] | Moderate, older adults | iPhone | **No** | Leave out until his 60s |
| 11 | AFib burden | Only for people already diagnosed with AF [A12] | – | Watch | **No** | Leave out (not applicable) |
| 12 | Six-minute walk estimate | A clinical test for limited mobility [A12] | – | iPhone | **No** | Leave out |
| 13 | Apple's heart events (high, low, irregular) | AF detection specificity 0.91, sensitivity 0.79 (Lambe 2026 [P]) | Moderate; low base rate | Watch | **No** | Optional one line (W5) |
| 14 | New iOS 26/27 types | Workout zones (deliberately not adopted, `watch-features.md` 6.9), RMSSD (**built**), PHQ-9/GAD-7 (**built**), medications (**built**), menopause (n/a), `estimatedWorkoutEffortScore` (Apple's, unvalidated) [A1] | – | – | Mostly yes | Nothing new to adopt |
| – | Oura's composite numbers | Unvalidated [D] | – | Oura API | **Yes, display only** (owner's override 18 Nov) | Unchanged; still labelled unvalidated |

### 4b. Lab markers

| Marker | Evidence | Strength | Schedule | In Tensile? | Verdict |
|---|---|---|---|---|---|
| ApoB (with lipids) | Counts atherogenic particles; used for residual risk (2026 ACC/AHA [D]) | Strong | Every ~5 years if normal, yearly if raised | **Yes** (`apoB`, schedule) | Keep |
| Lp(a) | "Test at least once in adults" (Kronenberg 2022 [P]) | Strong (consensus) | Once in life | **Yes** | Keep |
| HbA1c / fasting glucose | ADA 2026 from 35, every 3 years [D]; USPSTF 2021: 35–70 with overweight [P] | Strong | Every 3 years; yearly in prediabetes | **Yes** | Keep |
| hs-CRP | Top vs bottom fifth: HR 1.70 for major CV events over 30 years, independent of LDL and Lp(a) (27,939 women; Ridker 2024 [P]); a "risk enhancer" in ACC/AHA 2019 [M] | Moderate | Only to refine borderline risk; repeat if > 3 mg/L when well | **Yes** (marker, retest text) | Keep |
| eGFR | Kidney function; routine in panels | Strong (clinical) | With other bloods | **Yes** | Keep |
| Ferritin | Low for training under 30 µg/L (`roadmap.md` [D]) | Moderate | When tired or after heavy endurance blocks | **Yes** | Keep |
| Vitamin D | Endocrine Society 2024 suggests **against** routine testing (Demay 2024 [P]); USPSTF I (2021 [P]) | Strong (against routine testing) | Only with a clinical reason | **Yes, wrong retest advice** | **Fix (I2)** |
| Fasting insulin / HOMA-IR | Not among the screening tests in ADA 2026 (A1c, fasting glucose, OGTT) [D] | No screening evidence | – | No | **Leave out** |
| Omega-3 index | Predicts mortality in one cohort (Framingham, 2,240 people; McBurney 2021 [P]), but no trial shows that raising it improves outcomes; omega-3 supplements carry a dose-related AF risk (Gencer 2021 [D]) | Weak | – | No | **Leave out** |

### 4c. Functional tests

| Test | Evidence | Strength | How / how often | In Tensile? | Verdict |
|---|---|---|---|---|---|
| VO₂ max field test | Fitness predicts mortality strongly (Lang 2024 [D]; Kodama 2009 [P record]); the watch estimate is ±16% (Caserman 2024 [D]) | Strong | Quarterly walking test | **Yes** (`FitnessCheck`: Rockport walk, Ebbeling treadmill) | Keep. Optional for fit runners later: Cooper 12-min run, reliable (φ = 0.96) and not different from lab VO₂ max in young adults (Penry 2011 [P]) |
| Grip strength | Per 5 kg lower, HR 1.16 for death (PURE; Leong 2015 [D]) | Moderate | Every 3–6 months, dynamometer | **Yes** | Keep |
| **Push-ups** | > 40 vs < 10: IRR 0.04 for CVD events (Yang 2019 [P]) | Weak (one small cohort) | Yearly, manual | No | **Add (I4)** |
| **Sitting-rising test** | HR 3.84 natural death, 6.05 CV death, lowest vs highest score, ages 46–75 (Araújo 2026 [P]) | Moderate (one large cohort, replicated by the same group) | Yearly from 45, manual | No | **Add from 45 (I4)** |
| **One-leg stand 10 s** | Unable: HR 1.84, ages 51–75 (Araújo 2022 [P]) | Moderate (one cohort) | Yearly from 50, manual | No | **Add from 50 (I4)** |
| 30-s sit-to-stand | Older-adult test | – | – | No | Leave out (ceiling for a lifter) |

### 4d. Body composition

| Measure | Evidence | Strength | How / how often | In Tensile? | Verdict |
|---|---|---|---|---|---|
| Waist-to-height | Beats BMI for cardiometabolic risk (Ashwell 2012 [D]) | Strong (screening) | Tape, monthly | **Yes** | Keep; write to Health (I10) |
| DEXA visceral fat | Cesaro 2026 [P] (above) | Moderate | Yearly at most, if scanned | Partly (DEXA body fat used for the energy equation) | Consider (I9) |
| Muscle mass (ALMI) | Srikanthan 2014, older adults [P record] | Moderate | DEXA | Lean mass read from Health | Consider (I9); never from a scale |

### 4e. Lifestyle

| Measure | Evidence | Strength | How | In Tensile? | Verdict |
|---|---|---|---|---|---|
| Social connection / loneliness | Isolation HR 1.32, loneliness HR 1.14 (Wang 2023 [P]); OR 1.50 for survival (Holt-Lunstad 2010 [P]); interventions weak (Masi 2011 [P]) | Strong association; weak for interventions | 3-item scale (Hughes 2004 [P record]) | No | Consider (I6); act through I5 |
| Purpose in life | Higher purpose: RR 0.83 for death and CV events (10 cohorts; Cohen 2016 [P]); lowest vs highest HR 2.43 over 50 (Alimujiang 2019 [P]) | Moderate association; no intervention evidence | Questionnaire | No | **Leave out** (nothing the app can do with it) |
| Screen time | Evidence is for TV viewing: RR 1.13 per 2 h/day for death (Grøntved 2011 [P]); phone time isn't TV. Screen Time numbers aren't readable by the app; only a sandboxed report extension can show them [M]. | Weak for phones | – | No | **Leave out** |
| Sedentary time | See 4a row 9 (Ekelund 2016, 2019 [P]) | Strong for inactive people | Watch | No | Leave out for now |
| Ultra-processed food share | Associated with CV death RR 1.50 and all-cause death RR 1.21, but GRADE mostly low or very low (Lane 2024 [P]); not measurable from HealthKit | Weak–moderate; can't measure | – | No | **Leave out** |
| Protein distribution | No ceiling per meal (Trommelen 2023 [P]); the daily total matters (Morton 2018 [P record]) | – | – | Daily total yes | **Leave out** |

---

## 5. Ranked shortlist and leave-out list

**Fix first (not an addition):** the vitamin D retest advice (I2; S).

### Top 15 additions

Ranked by expected health effect × strength of evidence, with clutter counted against.

| # | Addition | Area | Effort | Expected health effect | Evidence |
|---|---|---|---|---|---|
| 1 | Structured cardio sent to Apple's Workout app (WorkoutKit), with Tensile's bpm bands as alerts (W1) | Watch | S–M | **Large, indirect** (makes the hard session happen; CRF is the biggest lever) | Strong for HIIT → VO₂ max and CRF → mortality |
| 2 | Brisk-walk mode paced by cadence (≥ 100 spm), minutes counted toward the aerobic floor (W3) | Watch | S–M | Moderate | Strong threshold data; strong for activity → mortality |
| 3 | Lab results from Apple Health Records into Labs and the due schedule (I1) | iPhone / integration | M | Moderate–large, indirect (conditional on his clinic) | Strong for the tests; plumbing for the import |
| 4 | Push-up test in the yearly fitness check; sitting-rising from 45, one-leg stand from 50 (I4) | iPhone | S | Small–moderate (tracking, early decline) | Cohort, weak–moderate |
| 5 | Spoken cues in Tensile's Watch workouts, on by default only for intervals (W2) | Watch | S | Small | Indirect (music meta-analysis); usability |
| 6 | Smart Stack relevance for bed-by and hard-cardio cards (W4) | Watch | S | Small (lets reminders stay off) | Usability |
| 7 | Travel: time zone per night, local times for bed-by, caffeine and doses; melatonin/light card after ≥ 5 zones (I3) | iPhone | M | Small–moderate, only on trips | Moderate (Cochrane) |
| 8 | Accountability: send the weekly card to one person; share a session invite (I5) | iPhone | S | Small | Moderate for reporting; weak for groups |
| 9 | IMST, offered only if home systolic averages ≥ 120 (W12) | Watch / iPhone | S | Moderate if BP is raised; none otherwise | Moderate (12 small RCTs) |
| 10 | Walking speed as a tracked, ungraded stat (graded from 60) | iPhone | S | Small now, larger later | Strong (observational) |
| 11 | Apple's heart events as one line in the heart section (W5) | Watch / iPhone | S | Small | Moderate; low base rate |
| 12 | DEXA fields (VAT, ALMI) beside waist-to-height (I9) | iPhone | S | Small–moderate, if scanned | Moderate (cohort) |
| 13 | Social connection 3-item check every 3 months, optional (I6) | iPhone | S | Uncertain | Strong association, weak intervention |
| 14 | Mindful minutes from Apple's Mindfulness app as a "What affects you" factor (W11; no session of our own) | iPhone | S | Small | Weak–moderate |
| 15 | Waist and hip written to and read from Health (I10) | iPhone | S | None directly (one source of truth) | Plumbing |

### Leave out

| Feature | Reason |
|---|---|
| Hydration prompts, water targets | Drink to thirst; over-drinking is the harm (Hew-Butler 2015 [P]); the water status was already removed [D] |
| Smart alarm, sleep sounds | No outcome trials [P: PMID 33018943] |
| Live heart-rate alerts outside workouts | Apple's own notifications already cover it; a second alert has no evidence and duplicates [A7] |
| Fall detection | Needs an Apple entitlement; Apple's own feature already calls for help [A8] |
| Breathing or meditation sessions | Small effect (g = −0.35 [P]), 0% day-30 retention for breathing apps [P], possibly counterproductive in insomnia [P]; the owner removed it |
| CGM (Dexcom API, Libre) for a non-diabetic | Outcome data scarce [S6]; 3-hour Health delay [S5]; already on the skip list (`roadmap.md`) |
| Strava, Polar, Whoop, Eight Sleep, Garmin APIs | No such device, or terms that block the coach (Strava AI clause [S11]); Eight Sleep has no official API [S13] |
| Lab-company APIs | None for consumers; Health Records is the route [S3] |
| Fasting insulin, omega-3 index | Not in screening guidance [D]; prediction without trial benefit, and omega-3 has an AF risk [P][D] |
| Routine vitamin D testing | Endocrine Society 2024 and USPSTF 2021 [P] (and fix I2) |
| Walking steadiness, 6-minute walk, AFib burden, 30-s sit-to-stand | Built for older or diagnosed people [A12][W8] |
| Stand hours / sedentary nudges | His activity level removes the sitting risk (Ekelund 2016 [P]); anti-sedentary prompts showed no effect (Klasnja 2019 [D]) |
| Ultra-processed food score, protein per meal | Can't be measured from HealthKit; low-GRADE evidence (Lane 2024 [P]); no per-meal ceiling (Trommelen 2023 [P]) |
| Screen time | Phone time isn't TV time [P]; the numbers aren't readable by the app [M] |
| Purpose-in-life score | Association only; nothing the app can act on [P] |
| Cycle-phase training | Premature (umbrella review [D]); owner is male |
| Garmin-style composites, Apple's or Whoop's scores | Unvalidated composites (`evidence-audit-2026-11.md` [D]); the Oura panel stays the one labelled, display-only exception |

---

## 6. Questions only the owner can answer

1. Is his clinic or lab connected to Apple Health Records (Health app › profile › Health Records › Add Account shows it)? I1 depends on it.
2. Does he want Apple's Workout app (with Workout Buddy) to run the weekly intervals, or Tensile's own Watch app (spec C7)? W1 assumes "Apple's app, Tensile plans".
3. Does he fly across 3+ time zones more than twice a year? (I3)
4. Is there one person he would send a weekly card to, or train with? (I5)
5. Is his 7-day home systolic average 120 or more? (W12)

---

## References

### Apple developer documentation [A] (JSON behind developer.apple.com, read 18 Nov 2026)

- [A1] HealthKit updates (workout zones, menopause types, Medications API, PHQ-9/GAD-7, effort scores). https://developer.apple.com/documentation/updates/healthkit
- [A2] WorkoutKit: CustomWorkout, IntervalBlock, WorkoutAlert, HeartRateRangeAlert (iOS 17, watchOS 10). https://developer.apple.com/documentation/workoutkit ; https://developer.apple.com/documentation/workoutkit/customworkout ; https://developer.apple.com/documentation/workoutkit/heartraterangealert
- [A3] WorkoutScheduler and schedule(_:at:) (iOS 17, watchOS 10). https://developer.apple.com/documentation/workoutkit/workoutscheduler
- [A4] WorkoutKit updates (pool swim, named steps, power and speed alerts, workoutPreview). https://developer.apple.com/documentation/updates/workoutkit
- [A5] AVSpeechSynthesizer (watchOS 2.0+). https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
- [A6] CMPedometerData.currentCadence (watchOS 2.0+). https://developer.apple.com/documentation/coremotion/cmpedometerdata/currentcadence
- [A7] highHeartRateEvent, irregularHeartRhythmEvent (iOS 12.2, watchOS 5.2). https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/highheartrateevent ; https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/irregularheartrhythmevent
- [A8] CMFallDetectionManager ("requires an entitlement from Apple"). https://developer.apple.com/documentation/coremotion/cmfalldetectionmanager
- [A9] Accessing health records (FHIR, read-only, Clinical Health Records capability, usage string, privacy policy). https://developer.apple.com/documentation/healthkit/accessing-health-records
- [A10] waistCircumference. https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/waistcircumference
- [A11] HKClinicalTypeIdentifier; labResultRecord. https://developer.apple.com/documentation/healthkit/hkclinicaltypeidentifier ; https://developer.apple.com/documentation/healthkit/hkclinicaltypeidentifier/labresultrecord
- [A12] walkingSpeed, appleWalkingSteadiness, sixMinuteWalkTestDistance, atrialFibrillationBurden ("while wearing Apple Watch", for people with AF), appleStandHour, lowCardioFitnessEvent. https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/walkingspeed ; https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applewalkingsteadiness ; https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/sixminutewalktestdistance ; https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/atrialfibrillationburden ; https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/applestandhour

### Vendor and press pages [W] (fetched) and search summaries [S]

- [W1] Apple Newsroom, "watchOS 26 delivers more personalized ways to stay active and connected" (Workout Buddy requirements; Smart Stack relevance API; Control Widget API), 9 Jun 2025. https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/
- [W2] Withings API reference (no contract; OAuth; server-side secret; webhooks; data types). https://developer.withings.com/llms.md
- [W3] Garmin Connect Developer Program overview (Personal tier, pull only; Business Starter/Enterprise). https://developer.garmin.com/gc-developer-program/overview
- [W4] Strava API authentication (client_secret required; mobile OAuth). https://developers.strava.com/docs/authentication/
- [W5] Strava API Agreement, effective 1 Jun 2026 (data shown only to the contributing user). https://www.strava.com/legal/api
- [W6] Polar AccessLink API v3 documentation. https://www.polar.com/accesslink-api/
- [W7] Apple, Hypertension Notifications Validation Paper, Sept 2025. https://www.apple.com/nz/health/pdf/Hypertension_Notifications_Validation_Paper_September_2025.pdf
- [W8] Apple, Measuring Walking Quality Through iPhone Mobility Metrics (May 2022). https://www.apple.com/healthcare/docs/site/Measuring_Walking_Quality_Through_iPhone_Mobility_Metrics.pdf
- [S1] Reviews of watchOS 26 Workout Buddy (no third-party API found). https://www.dcrainmaker.com/2025/07/apple-watchos-26-workout-beta-real-world.html ; https://www.macrumors.com/2025/06/09/apple-announces-watchos-26/
- [S2] Apple, Health Records registration and technical requirements (Canada, UK, US; FHIR R4/DSTU2). https://support.apple.com/guide/healthregister/apd12d144779/web
- [S3] Quest results via Apple Health; Labcorp Patient to Apple Health Records; no self-serve consumer API. https://www.questdiagnostics.com/patients/test-results ; https://jp.labcorp.com/creating-meaningful-interoperability-patient-healthcare-records
- [S4] Dexcom developer docs: scopes and access (sandbox; individual Limited Access up to 5 users; commercial partnership). https://developer.dexcom.com/docs/dexcom/scopes-access
- [S5] Dexcom FAQ: G7 data reaches Apple Health after a 3-hour delay. https://www.dexcom.com/en-ca/faqs/g7/how-do-i-share-my-glucose-data-with-the-apple-health-app
- [S6] CGM in people without diabetes: systematic reviews (outcome data scarce). https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11722592/ ; https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12612783/ ; https://pubmed.ncbi.nlm.nih.gov/41588451/
- [S7] Libre 3 Plus and Apple Health in Canada (user reports; Abbott Canada apps page). https://discussions.apple.com/thread/256202406 ; https://www.freestyle.abbott/en-ca/products/apps-and-data-sharing.html
- [S8] Withings Health Mate on the App Store (Apple Health sync). https://apps.apple.com/ca/app/id542701020
- [S9] Cronometer forum: no public API; partner and enterprise access. https://forums.cronometer.com/discussion/3365/any-chance-a-public-api-for-cronometer-will-be-available
- [S10] Strava rate limits (athlete capacity 1, Single Player Mode). https://developers.strava.com/docs/rate-limits/
- [S11] Terra, "Strava API changes 2026" (subscription from June 2026; AI/ML restriction; 7-day caching) (secondary). https://tryterra.co/blog/strava-api-changes-2026
- [S12] Whoop developer API and terms (secondary summaries). https://developer.whoop.com/api/ ; https://developer.whoop.com/api-terms-of-use/ ; https://tryterra.co/blog/whoop-api-data-access-permissions-limitations-2026
- [S13] Eight Sleep: no official public API (third-party). https://providers.apievangelist.com/providers/eight-sleep/
- [S14] Eight Sleep HRV not written to Apple Health (user feedback board). https://feedback.bevel.health/bug-reports/p/hrv-not-picked-up-by-bevel-pro-from-eight-sleep
- [S15] FDA 510(k) K250507 summary (sensitivity 41.2%, specificity 92.3%). https://fda.innolitics.com/device/K250507

### Papers [P] (PubMed abstract read this round unless marked "record")

- Araújo CGS et al. Sitting-rising test scores predict natural and cardiovascular causes of deaths. Eur J Prev Cardiol 2026;33(12):2170-8. doi:10.1093/eurjpc/zwaf325
- Araujo CG et al. Successful 10-second one-legged stance performance predicts survival. Br J Sports Med 2022;56:975-80. doi:10.1136/bjsports-2021-105360
- Brito LB et al. Ability to sit and rise from the floor as a predictor of all-cause mortality. Eur J Prev Cardiol 2014. doi:10.1177/2047487312471759 (record)
- Yang J et al. Push-up exercise capacity and future cardiovascular events among active adult men. JAMA Netw Open 2019;2:e188341. doi:10.1001/jamanetworkopen.2018.8341
- Liu Y et al. Dose-response association between walking speed and all-cause mortality. J Sports Sci 2024. doi:10.1080/02640414.2024.2390302
- Yates T et al. Walking pace and handgrip strength with mortality: UK Biobank. Eur Heart J 2017. doi:10.1093/eurheartj/ehx449
- Studenski S et al. Gait speed and survival in older adults. JAMA 2011. doi:10.1001/jama.2010.1923 (record)
- Lambe R et al. The accuracy of Apple Watch measurements: a living systematic review and meta-analysis. NPJ Digit Med 2026. doi:10.1038/s41746-025-02238-1
- Tudor-Locke C et al. Walking cadence and intensity in 21-40 year olds: CADENCE-adults. Int J Behav Nutr Phys Act 2019;16:8. doi:10.1186/s12966-019-0769-6
- Wen D et al. Effects of different protocols of HIIT for VO2max improvements. J Sci Med Sport 2019. doi:10.1016/j.jsams.2019.01.013
- Milanović Z et al. HIT and continuous endurance training for VO2max improvements. Sports Med 2015. doi:10.1007/s40279-015-0365-0 (record)
- Kodama S et al. Cardiorespiratory fitness as a quantitative predictor of all-cause mortality. JAMA 2009. doi:10.1001/jama.2009.681 (record)
- Penry JT et al. Validity and reliability of Cooper's 12-minute run and the multistage shuttle run. J Strength Cond Res 2011. doi:10.1519/JSC.0b013e3181cc2423
- Terry PC et al. Effects of music in exercise and sport: a meta-analytic review. Psychol Bull 2020. doi:10.1037/bul0000216
- Fincham GW et al. Effect of breathwork on stress and mental health: meta-analysis of RCTs. Sci Rep 2023;13:432. doi:10.1038/s41598-022-27247-y
- Baumel A et al. Objective user engagement with mental health apps. J Med Internet Res 2019;21:e14567. doi:10.2196/14567
- Furukawa Y et al. Components and delivery formats of CBT for chronic insomnia: component network meta-analysis. JAMA Psychiatry 2024. doi:10.1001/jamapsychiatry.2023.5060 (record)
- Li W et al. A hypotensive protocol of inspiratory muscle strength training: meta-analysis with trial sequential analysis. J Clin Hypertens 2023. doi:10.1111/jch.14655
- Craighead DH et al. Time-efficient IMST lowers blood pressure… in midlife/older adults with above-normal BP. J Am Heart Assoc 2021;10:e020980. doi:10.1161/JAHA.121.020980
- Thakkar J et al. Mobile telephone text messaging for medication adherence: meta-analysis. JAMA Intern Med 2016. doi:10.1001/jamainternmed.2015.7667
- Hew-Butler T et al. Statement of the 3rd International Exercise-Associated Hyponatremia Consensus Development Conference. Br J Sports Med 2015. doi:10.1136/bjsports-2015-095004 (record)
- Slyusarenko K et al. Smart alarm based on sleep stages prediction. IEEE EMBC 2020. doi:10.1109/EMBC44109.2020.9176320 (record)
- Herxheimer A, Petrie KJ. Melatonin for the prevention and treatment of jet lag. Cochrane Database Syst Rev 2002;(2):CD001520. doi:10.1002/14651858.CD001520
- Roach GD, Sargent C. Interventions to minimize jet lag after westward and eastward flight. Front Physiol 2019;10:927. doi:10.3389/fphys.2019.00927 (record)
- Demay MB et al. Vitamin D for the prevention of disease: an Endocrine Society clinical practice guideline. J Clin Endocrinol Metab 2024. doi:10.1210/clinem/dgae290
- US Preventive Services Task Force. Screening for vitamin D deficiency in adults. JAMA 2021. doi:10.1001/jama.2021.3069 (record)
- US Preventive Services Task Force. Screening for prediabetes and type 2 diabetes. JAMA 2021;326:736. doi:10.1001/jama.2021.12531 (record)
- Kronenberg F et al. Lipoprotein(a) in ASCVD and aortic stenosis: EAS consensus statement. Eur Heart J 2022. doi:10.1093/eurheartj/ehac361 (record)
- Ridker PM et al. Inflammation, cholesterol, lipoprotein(a), and 30-year cardiovascular outcomes in women. N Engl J Med 2024. doi:10.1056/NEJMoa2405182
- McBurney MI et al. Erythrocyte fatty acid fingerprint and all-cause mortality: Framingham Offspring. Am J Clin Nutr 2021. doi:10.1093/ajcn/nqab195
- Cesaro A et al. DXA visceral adipose tissue, prevalent CVD and mortality in US adults (NHANES 2011-2018). Nutr Metab Cardiovasc Dis 2026. doi:10.1016/j.numecd.2026.105043
- Srikanthan P, Karlamangla AS. Muscle mass index as a predictor of longevity in older adults. Am J Med 2014. doi:10.1016/j.amjmed.2014.02.007 (record)
- Wang F et al. Meta-analysis of 90 cohort studies of social isolation, loneliness and mortality. Nat Hum Behav 2023;7:1307-19. doi:10.1038/s41562-023-01617-6
- Holt-Lunstad J et al. Social relationships and mortality risk: a meta-analytic review. PLoS Med 2010;7:e1000316. doi:10.1371/journal.pmed.1000316
- Masi CM et al. A meta-analysis of interventions to reduce loneliness. Pers Soc Psychol Rev 2011. doi:10.1177/1088868310377394
- Hughes ME et al. A short scale for measuring loneliness in large surveys. Res Aging 2004. doi:10.1177/0164027504268574 (record)
- Kritz M et al. Individual versus group-based interventions: physical activity, functional, psychosocial and health outcomes. Nat Hum Behav 2026. doi:10.1038/s41562-026-02429-0
- Cohen R et al. Purpose in life and all-cause mortality and cardiovascular events: a meta-analysis. Psychosom Med 2016. doi:10.1097/PSY.0000000000000274
- Alimujiang A et al. Life purpose and mortality among US adults older than 50. JAMA Netw Open 2019. doi:10.1001/jamanetworkopen.2019.4270
- Ekelund U et al. Does physical activity attenuate, or even eliminate, the association of sitting time with mortality? Lancet 2016;388:1302-10. doi:10.1016/S0140-6736(16)30370-1
- Ekelund U et al. Dose-response associations between accelerometry measured physical activity and sedentary time and all cause mortality. BMJ 2019;366:l4570. doi:10.1136/bmj.l4570
- Grøntved A, Hu FB. Television viewing and risk of type 2 diabetes, cardiovascular disease, and all-cause mortality. JAMA 2011. doi:10.1001/jama.2011.812
- Lane MM et al. Ultra-processed food exposure and adverse health outcomes: umbrella review. BMJ 2024;384:e077310. doi:10.1136/bmj-2023-077310
- Trommelen J et al. The anabolic response to protein ingestion has no upper limit in magnitude and duration. Cell Rep Med 2023. doi:10.1016/j.xcrm.2023.101324 (record)
- Morton RW et al. Protein supplementation and resistance training: meta-analysis. Br J Sports Med 2018. doi:10.1136/bjsports-2017-097608 (record)
- Singh B et al. Time to form a habit: systematic review and meta-analysis. Healthcare (Basel) 2024;12:2488. doi:10.3390/healthcare12232488

### Carried from earlier Tensile research [D]

Lang 2024 (CRF and mortality), Garcia 2023 (activity dose-response), Ahmadi 2022, Momma 2022, Caserman 2024, Buyalskaya 2023, Kronenberg 2022, Leong 2015 (`evidence-audit-2026-11.md` references); Harkin 2016, Krebs & Duncan 2015, Klasnja 2019 (`behaviour-change.md`, `healthy-living-2026-11.md`); Gencer 2021 (omega-3 and AF), ACC/AHA 2019 and 2026, ADA 2026 (`evidence-audit-2026-11.md`, `BloodTestSchedule.swift`); Ashwell 2012 (`longevity-insights.md`); TemPredict, cycle-phase umbrella review, heart-rate events (`watch-features.md`); Oura validation and the owner's 18 Nov decision (`oura-ring-2026-11.md`).

### From memory [M], not checked this round

EventKit cannot add attendees to an event; Screen Time data is shown only through a sandboxed DeviceActivity report extension; Strava reads Apple Health workouts; Dexcom's token exchange is server-side; the G7 is a cleared device; validatebp.org lists validated home cuffs; Polar H10 as a reference strap; hs-CRP as an ACC/AHA 2019 risk enhancer. Check each before building on it.

## Owner's answers and choices, 18 Nov 2026

- **Health Records:** his clinic or lab is not connected yet. The import (I1) is built anyway and stays empty until one connects.
- **Who runs the weekly intervals:** Tensile's own Watch app. WorkoutKit (W1) is an optional extra ("Also add to Apple's Workout app"), not the default.
- **Chosen to build:** W1, I1, I4, W4, I3, W12, and the metrics bundle (walking speed, Apple's heart events line, DEXA fields, the social connection check, mindful minutes as a factor, waist and hip synced with Health).
- **Not chosen:** the brisk-walk mode (W3), spoken cues (W2) and sending the weekly card to one person (I5).
