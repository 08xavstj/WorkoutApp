# Competitive landscape: what the best health, fitness, lifting and nutrition apps do in 2026, and what Tensile is missing

November 2026. Part of the Tensile research round (see the shared brief).

**How this was researched.** Web search (extended mode) over official feature pages, press releases, developer sessions and 2026 reviews, with the date of each source in the reference list. The sandbox blocked direct fetches of whoop.com, ouraring.com, support.apple.com and pubmed.ncbi.nlm.nih.gov, and the shared web-search budget ran out before the last few lookups (Zoe, Noom's GLP-1 companion, Everlywell, WaterMinder, Garmin Hill/Endurance scores, and several evidence papers). Where a product fact or a citation could not be re-checked online in this session it is marked **(not re-verified)**; those are well-known product features or widely cited papers that I am confident exist, but check them before quoting. Nothing below is invented.

**Reading the "Tensile today" column.** Checked against the code in `App/` and `Packages/AppCore` on 3 Nov 2026: **has** / **partial** / **missing**.

---

## 1. Feature matrix

### 1a. Recovery, readiness and training load

| Feature | Whoop | Oura | Garmin | Apple (watchOS 26 / iOS 26) | Fitbit / Google Health | Watch-only apps (Bevel, Athlytic, Gentler Streak, Training Today) | Tensile today |
|---|---|---|---|---|---|---|---|
| Daily recovery / readiness score from HRV + RHR + sleep | Recovery % | Readiness 0-100 with contributors | Training Readiness (recovery time, sleep, HRV status, stress, acute load) | No single score (Vitals flags out-of-range) | Daily Readiness 1-100 | All four | **has** (0-100, 14-night baseline, contributors sheet) |
| Daily strain / load score | Strain 0-21 | Activity score | Acute load, Training Status | Training Load (28-day, effort 1-10) | Cardio Load, weekly target | Athlytic Exertion, Bevel Strain | **has** (0-100 TRIMP + sRPE) |
| Target strain band from recovery | Yes | Activity goal adapts | Daily Suggested Workout | No | "If readiness low, reduce load" | Athlytic, Bevel | **has** |
| 7- vs 28-day load trend, "spike" warning | No explicit | No | Training Status (productive/strained/…) | Training Load bands | Cardio Load vs target | Bevel | **has** (uncoupled 7 vs 21 days) |
| Foster monotony / weekly strain | No | No | No | No | No | No | **missing** (flagged "Open" in strain-science.md) |
| HRV 7-day trend vs personal normal band | Yes | Yes | HRV Status (balanced/low/unbalanced) | Vitals range | Yes | Training Today OFI | **has** |
| Morning camera / chest-strap HRV reading | No (sensor) | No | No | No | No | HRV4Training, Elite HRV, Welltory | **has** (camera PPG) |
| Daytime stress from HRV | Stress Monitor | Daytime Stress, Cumulative Stress (31-day), Resilience | Stress, Body Battery | No | Stress Management score | Bevel Stress | **missing** (Garmin does not sync daytime HRV; the app deliberately renamed its HR-only estimate) |
| Breathing / relaxation exercise in-app | Yes (Stress Monitor) | Yes | Breathwork activity | Mindfulness app | Yes | Headspace watch app (HR-triggered) | **missing** |
| Muscle-level fatigue / recovery map | No | No | No | No | No | Fitbod (muscle recovery %), Bevel training balance | **has** |
| Illness / vitals-out-of-range alert | Health Monitor (RHR, HRV, resp, SpO2, skin temp vs 30-day) | Symptom Radar → Health Radar (May 2026) | Health status | Vitals app (2+ metrics outlier) | No | Bevel, Athlytic | **has** (2+ signals, No/Minor/Major, rest mode) |
| Sick / "not 100%" mode that pauses targets | Partial | Rest mode | No | No | No | Gentler Streak rest days; Runna "Not feeling 100%" | **has** |
| Heat and acclimation | No | No | Heat/altitude acclimation | No | No | Runna "Adapt for Heat" (Jul 2026) | **has** |
| VO2 max estimate + age bands | VO2 max (2025) | Cardio Capacity | VO2 max, Fitness Age | Cardio Fitness + low-fitness notifications | Yes | Bevel | **has** (FRIEND bands) |
| Lactate threshold, Hill/Endurance score, race predictor | No | No | Yes (running) | No | No | No | **missing** (running-specific; low value for a lifter) |
| Women's cycle / hormonal insights | Menstrual Cycle Insights, perimenopause, cycle-specific lab ranges (Mar 2026) | Cycle Insights, Perimenopause, Menopause Insights, hormonal birth control (2026) | Women's health | Cycle Tracking, retrospective ovulation | Yes | Bevel | **partial** (cycle logged in check-in; no phase-aware advice, by design: McNulty 2020) |

### 1b. Sleep

| Feature | Whoop | Oura | Garmin | Apple | Rise / Sleep Cycle / Samsung | Tensile today |
|---|---|---|---|---|---|---|
| Sleep score with components | Yes | Yes | Sleep Score | Sleep Score (watchOS 26: duration, consistency, interruptions) | Yes | **has** |
| Sleep need and sleep debt | Sleep need from strain + debt + naps | No debt | Sleep Coach (need from load, history, recovery) | No | Rise: 14-night debt, Energy Potential | **has** (14-night debt, need fixed at ~8 h after review) |
| Recommended bedtime tonight | Sleep Planner | Bedtime guidance (chronotype) | Sleep Coach | Wind Down | Rise "melatonin window"; Samsung Bedtime Guidance | **partial** (caffeine cut-off and morning-light nudge, but no "be in bed by" window from debt + tomorrow's plan) |
| Sleep regularity index | Consistency | Yes | Yes | Consistency in score | Yes | **has** (true SRI) |
| Nap detection / advice | Yes | Yes | Yes | No | Rise | **has** (naps separated from night) |
| Stages shown as rough | No | No | No | No | No | **has** (weighted lightly, labelled) |
| Sleep apnea / breathing disturbances | No | No | No | Breathing Disturbances + apnea notification (watchOS 11+) | Samsung (FDA De Novo 2024) | **missing** (does not read `sleepApneaEvent`) |
| Snore / sound detection | No | No | No | No | Sleep Cycle | **missing** (skip) |
| Smart alarm | No | No | No | No | Sleep Cycle | **missing** (skip) |
| Caffeine cut-off, alcohol effect | Journal → monthly impact | Tags → insights | No | No | No | **has** (personal t-test with FDR) |
| CBT-I style programme | No | No | No | No | Calm Sleep, Headspace, Sleepio (not surveyed) | **missing** |

### 1c. Health monitoring, longevity and labs

| Feature | Whoop | Oura | Garmin | Apple | Withings / Function / InsideTracker / Superpower | Tensile today |
|---|---|---|---|---|---|---|
| Biological / body age | WHOOP Age (6-month) + Pace of Aging (30-day) | Cardiovascular Age | Fitness Age | No | InnerAge, Function Biological Age, Superpower Score | **has** (Gompertz effective age, with confidence label) |
| Blood pressure: cuff logging + protocol | Blood Pressure Insights (MG, estimate, "not for diagnosis") | Hypertension signs (Labs, US) | No | Hypertension notifications (FDA-cleared), BP logging + PDF (iOS 26) | Withings BPM | **has** (7-day home protocol, AHA/ACC bands); **partial**: no repeat-protocol schedule or PDF export |
| Labs upload + reference ranges | Advanced Labs (clinician-reviewed, tied to Healthspan pillars Jan 2026) | Health Panels + lab import (Jun 2026) | No | Health Records | All four | **has** (PDF or manual; coach sees them) |
| Labs linked to behaviours ("your sleep pillar ↔ these markers") | Yes (Jan 2026) | Oura Advisor | No | No | InsideTracker action plan | **partial** (interpretation only) |
| Medications with physiological effects | No | Tags | No | Medications (iOS 16+), HealthKit Medications API (iOS 26) | No | **has** (own list + known effects on HR/HRV/sleep); **missing**: reads Apple's Medications |
| ECG / AFib | MG | Ultrahuman add-on | ECG on some | ECG, AFib History | Withings | **missing** (hardware; skip) |
| Continuous glucose | Study | Meals + Dexcom Stelo | No | No | Zoe, Ultrahuman | **missing** (skip for non-diabetics, see review-2026-10) |
| Antioxidant index, vascular load | No | No | No | No | Samsung | **missing** (skip, unvalidated) |
| Time in daylight | No | No | No | Yes (watchOS 10+) | No | **missing** (nudge exists, but no HealthKit read) |
| Mental state / mood log | Journal | Tags | No | State of Mind (iOS 17+), PHQ-9/GAD-7 | No | **partial** (mood in check-in; not written to HealthKit) |
| Walking steadiness, hearing exposure | No | No | No | Yes | No | **missing** (low value at this user's age; skip) |
| Body composition from scale, segmental | No | No | Index scale | Reads | Withings Body Scan | **has** weight, body fat, lean mass via HealthKit; **missing** waist/limb measurements |
| Grip / strength-for-health marker | No | No | No | No | No | **partial** (strength days per week); no strength-to-bodyweight standards |

### 1d. Lifting

Best-in-class references: Hevy, Strong, Fitbod, JEFIT, Boostcamp, Juggernaut AI, RP Hypertrophy, Alpha Progression, Liftosaur, Stronger by Science program bundle.

| Feature | Who does it best | Tensile today |
|---|---|---|
| Equipment-aware exercise selection | Fitbod (equipment profile), Tensile | **has** (My Gym: bars, plates, dumbbells, stacks) |
| Loads rounded to what the plates can make, plate-per-side hint | Strong/Hevy plate calculator (Strong: Pro) | **has** (built into planning, not just a calculator) |
| Warm-up set calculator (ramp from bar to working weight) | Strong (Pro), RP, Alpha Progression | **missing** (warm-up sets can be marked, not generated) |
| RPE/RIR per set, e1RM from reps + RIR | Hevy, Strong, RP, Juggernaut | **has** (Zourdos RPE table) |
| Progression rule (smallest jump when all reps hit) | Strong, Hevy Trainer, Alpha Progression (set-level targets), Liftosaur (scriptable) | **has** (smallest gym jump) |
| Mesocycle / block planning: volume ramp, RIR 3→1, planned deload, re-start | RP Hypertrophy (MEV→MRV with pump/soreness/performance feedback), Juggernaut AI, JEFIT 4-week mesocycles, Alpha Progression | **partial** (deload suggestion from load; no block structure) |
| Pre-session readiness survey that scales the session | Juggernaut AI, RP (soreness/pump) | **has** (recovery score + soreness-and-where sets effort and sets) |
| Weekly hard sets per muscle vs 10-20 target | Hevy (sets per muscle), RP volume landmarks | **has** (indirect sets as half) |
| Supersets / paired sets, circuits | Hevy, Strong, Boostcamp | **missing** |
| Drop sets, myo-reps, AMRAP, tempo | RP, Liftosaur | **missing** (AMRAP/tempo absent) |
| Rest timer by goal, per-exercise override | Strong, Hevy | **has** |
| Exercise demo images / video + cues | Hevy (video), Fitbod (video), JEFIT | **partial** (free-exercise-db text + images loaded from GitHub at runtime; no offline, no cue on the live set) |
| Program library (5/3/1, GZCLP, nSuns, SBS) | Boostcamp (free), Stronger by Science bundle (21-week, autoregulated) | **missing** (has own planner + custom templates) |
| Program builder with progression rules | Boostcamp, Liftosaur, SBS builder | **partial** (templates without rules) |
| Lift charts, PRs, e1RM history | Strong, Hevy | **has** |
| Body measurements (waist, chest, arms) | Hevy, Strong, MacroFactor | **missing** |
| Apple Watch companion for set logging | Strong (best), Hevy | **missing** (user wears Garmin; skip) |
| Social feed, routines sharing | Hevy | **missing** (skip, single user) |
| Lifting session counted in daily strain and recovery | Whoop Strength Trainer (not re-verified), Tensile | **has** (max of HR TRIMP and sRPE) |
| Workouts written to Apple Health | Hevy, Strong, Fitbod | **has** (HKWorkoutBuilder); **missing**: workout effort score written to HealthKit |

### 1e. Nutrition (distinctive features only; another researcher covers depth)

| Feature | Who | Tensile today |
|---|---|---|
| Adaptive expenditure from intake + weight trend, weekly target adjustment | MacroFactor (consensus leader), Carbon (check-in based) | **has** (measured maintenance, weekly speed guard) |
| Lab-grade micronutrients, EAR-based "low" flags | Cronometer | **has** (reads Cronometer via HealthKit; EAR bands) |
| Protein per meal | MacroFactor | **has** when meal times arrive |
| AI photo / voice logging | MFP, Lose It Snap It, Cronometer (2025), MacroFactor | **missing** (skip: Cronometer does it) |
| Psychology lessons, GLP-1 companion | Noom | **missing** (skip) |
| Gut/microbiome and meal scores | Zoe | **missing** (skip, not re-verified) |
| Hydration goal with weather/activity adjustment | WaterMinder (not re-verified), Garmin | **partial** (reads water; no goal) |
| Meal timing vs sleep/readiness | Oura Meals | **partial** (last-meal time in check-in feeds patterns) |

### 1f. Coaching, reports and engagement

| Feature | Who | Tensile today |
|---|---|---|
| Chat coach with full data context | Whoop AI (My Memory, Proactive Check-ins, May 2026), Oura Advisor, Fitbit/Google Health Coach (Gemini), Garmin Active Intelligence | **has** (on-device or Claude; returns workout cards) |
| Proactive check-ins from the coach (it messages you) | Whoop (May 2026), Garmin Active Intelligence (wake / post-workout / evening) | **partial** (reminders are fixed; the coach never initiates) |
| Weekly / monthly review report | Whoop Weekly & Monthly Performance Assessment (not re-verified), Garmin Connect+ (reports, year recap), Fitbit, Zepp Aura (weekly sleep) | **missing** |
| Morning report / evening report | Garmin Morning Report, Evening Report (2025), Whoop | **partial** (Home shows today; no evening "tomorrow" card) |
| Journal of behaviours → "what moved your recovery" | Whoop Journal (monthly impact), Oura Tags | **has** (check-ins + personal patterns, statistically tested) |
| Voice workout companion | Apple Workout Buddy (watchOS 26) | **missing** (skip) |
| Gamification: streaks, badges, challenges, leaderboards | Garmin badges, Breathwrk streaks, Strava | **missing** (skip, see evidence) |
| Widgets, Live Activity, Siri | Most | **has** widget + Live Activity; **missing** App Intents/Siri |
| Data export (CSV/PDF) | Most | **missing** |

### 1g. HealthKit data types Tensile does not read or write yet

From the SDK (iOS 17-18 additions, plus iOS 26's Medications API per WWDC25 session 321). Tensile's `HealthKitClient` reads 48 types; these are absent:

| Type | Since | Source on this user's setup | Use |
|---|---|---|---|
| `timeInDaylight` (quantity) | iOS 17 / watchOS 10 | Apple Watch only; Garmin does not write it | Would make the morning-light nudge measurable. Without an Apple Watch: skip, or ask in the morning check-in. |
| `stateOfMind` (sample) | iOS 17/18 | Written by Health app, Mindfulness app; Tensile could write it | Write the check-in mood so Health's mental-wellbeing view and other apps see it (small). |
| `workoutEffortScore`, `estimatedWorkoutEffortScore` | iOS 18 | Apple Watch estimates; apps can write effort for their own workouts | Write Tensile's session RPE as `workoutEffortScore` on the HKWorkout it saves, so Apple's Training Load counts lifting (small). |
| `sleepApneaEvent` (category) | iOS 18 | Apple Watch Series 9+/Ultra 2 only | Read and surface as a one-line warning if present (small). |
| `physicalEffort` (quantity, METs) | iOS 17 | Apple Watch | Could replace the step-based NEAT estimate when present. Not on Garmin. |
| `appleWalkingSteadiness`, `environmentalAudioExposure`, `headphoneAudioExposure` | iOS 15 / 13 | iPhone, AirPods | Hearing exposure is readable from AirPods Pro 3; low priority. |
| `HKUserAnnotatedMedication` + `HKMedicationDoseEvent` (Medications API) | iOS 26 | Health app's Medications | Read Apple's list and dose logs instead of (or merged with) Tensile's own, so reminders are not duplicated (medium). Third-party write access was still unconfirmed in the sources found. |
| `atrialFibrillationBurden`, `runningPower`, `cyclingFTP`, `bloodGlucose` | iOS 16-17 | Not produced by this user's devices | Skip. |

No public HealthKit type was found for Apple's hypertension notifications or the Sleep Score; both stay inside the Health app.

---

## 2. What Tensile should add

Evidence strength: **strong** (meta-analyses/RCTs, consistent), **moderate** (some RCTs or large cohorts), **weak** (small studies, cross-sectional, or indirect), **none** (engagement feature, no health evidence). Effort: small (a day or two), medium (about a week), large (multi-week).

### 2a. Worth adding, in priority order

**1. Weekly review (Monday report).**
- *What:* One screen plus a coach message every Monday: last week's strain vs target band, sleep debt and regularity, RHR/HRV 7-day vs normal, hard sets per muscle vs 10-20, protein and calorie average vs target, weight trend vs the goal's allowed pace, PRs, and three concrete changes for the coming week. Keep a history so months can be compared.
- *Who does it best:* Whoop's Weekly/Monthly Performance Assessment (not re-verified) and Garmin Connect+ reports; Fitbit's Gemini coach "adjusts plans after a poor night" (Oct 2025).
- *Evidence:* **moderate**. Self-monitoring with feedback and goal review are the behaviour-change techniques with the largest effects on activity and diet (Michie et al., Health Psychol 2009, meta-regression; Harkin et al., Psychol Bull 2016, 138 studies: monitoring progress raises goal attainment, more so when progress is recorded and reported). Activity trackers with feedback add ~1,800 steps/day and ~1 kg (Ferguson et al., Lancet Digit Health 2022, umbrella review of 39 reviews, n≈164k).
- *Goal tailoring:* fat loss → weight-trend pace and protein lead; muscle → sets per muscle and e1RM lead; endurance/health → zone minutes, VO2 max trend, strength days ≥ 2.
- *Effort:* medium. All inputs already exist in `CoachSnapshot`, `TrainingLoad`, `SleepDebt`, `EnergyBalance`.

**2. Training blocks (mesocycles) with RIR targets and a planned deload.**
- *What:* A 4-6 week block: sets per muscle ramp from the low end of the 10-20 range to the high end, target RIR falls 3→1, loads progress by the gym's smallest jump, then one easier week, then restart at slightly higher volume. The existing HRV/recovery autoregulation still scales each day inside the block. Show "week 3 of 5" on the Trainer tab.
- *Who does it best:* RP Hypertrophy (volume landmarks, pump/soreness/performance feedback), Juggernaut AI (readiness-based), Alpha Progression (set-level targets, periodised), JEFIT (4-week mesocycles).
- *Evidence:* **moderate for strength, weak for hypertrophy**. Periodised beats non-periodised for 1RM (Williams et al., Sports Med 2017, meta-analysis, ES 0.43); for hypertrophy linear vs undulating makes no difference (Grgic et al., PeerJ 2017) and periodised vs not is unclear. Autoregulated and fixed load prescription give similar strength (Hickmott et al., Sports Med Open 2022, meta-analysis); RPE-based loading may add a little 1RM (Helms et al., JSCR 2018, n=21). A one-week deload gave no advantage over continuous training in one RCT (Coleman et al., PeerJ 2024, not re-verified), so keep the deload as "suggested when load spikes", not mandatory. Volume 10-20 sets/muscle/week: Schoenfeld et al., J Sports Sci 2017 (already cited in the app).
- *Goal tailoring:* strength → heavier blocks (3-6 reps, RIR 2→0 on top sets); muscle → 6-15 reps, volume ramp; endurance/health → keep the current 2-3 full-body days with no ramp.
- *Effort:* medium-large (`WorkoutPlanner` + a `TrainingBlock` model + UI).

**3. Supersets / paired sets and a session time budget.**
- *What:* Pair non-competing exercises (push/pull, upper/lower) in the planner and live view; rest timer runs across the pair. Add "I have 35 minutes" to the planner, which chooses pairing, fewer exercises and shorter rests.
- *Who does it best:* Hevy and Strong (supersets), Fitbod (duration input).
- *Evidence:* **moderate**. Agonist-antagonist paired sets and shorter rests keep hypertrophy and most strength gains while cutting session time by roughly a third to a half (Iversen et al., Sports Med 2021, "No Time to Lift?", narrative review of RCTs). Time is the most cited barrier to adherence.
- *Goal tailoring:* strength → pair only accessories, keep main lifts straight sets; muscle → pair freely.
- *Effort:* small-medium.

**4. Warm-up ramp calculator.**
- *What:* For each first exercise and any heavy lift, generate 2-4 ramp sets (e.g. bar × 10, 50% × 5, 70% × 3, 85% × 1) rounded to the plates, shown in the live view as "W" sets.
- *Who does it best:* Strong (Pro), RP, Alpha Progression.
- *Evidence:* **moderate**. Warm-up improves performance in ~79% of criteria measured (Fradkin, Zazryn & Smoliga, JSCR 2010, meta-analysis of 32 studies). Injury-prevention evidence for warm-ups specifically is weaker.
- *Goal tailoring:* strength → more ramp singles; muscle → fewer.
- *Effort:* small (`TrainingTools` + plate rounding already exist; `SetLog.isWarmup` exists).

**5. "Bed by" window tonight.**
- *What:* Each evening, compute a target bedtime from sleep need, current debt, usual wake time and the sleep regularity index, and show it as one line on Home and in the evening check-in (and as a notification 45 min before). Add "tomorrow is a hard day, aim for +30 min".
- *Who does it best:* Garmin Sleep Coach (need from load + history + recovery), Rise (melatonin window), Samsung Bedtime Guidance (3-night calibration), Whoop Sleep Planner.
- *Evidence:* **moderate**. Sleep extension improves sprint, reaction time and mood in athletes (Mah et al., Sleep 2011; Bonnar et al., Sports Med 2018, systematic review); sleep regularity predicts mortality more strongly than duration (Windred et al., Sleep 2024, already in the app). The "need goes up after hard days" rule has no trial support (review-2026-10), so the hard-day bonus should be labelled an app choice.
- *Goal tailoring:* same for all goals; fat loss gets the extra note that short sleep shifts loss toward lean mass (Nedeltcheva et al., Ann Intern Med 2010, n=10, weak).
- *Effort:* small (sleep debt, SRI and caffeine cut-off already exist).

**6. Paced-breathing session (5-10 min at ~6 breaths/min) with before/after HR.**
- *What:* A guided breathing screen with haptics; measure HR (AirPods Pro 3 or camera) before and after; offer it when recovery is low, stress check-in is high, or before bed. Log as a mindful session in HealthKit.
- *Who does it best:* Headspace's Apple Watch app triggers breathing breaks from heart rate (May 2026); Whoop Stress Monitor; Elite HRV biofeedback pacer; Breathwrk; Apple Mindfulness.
- *Evidence:* **moderate for acute HRV and anxiety, weak for long-term health**. Voluntary slow breathing raises HRV acutely and after training (Laborde et al., Neurosci Biobehav Rev 2022, meta-analysis); slow breathing improves relaxation and anxiety markers (Zaccaro et al., Front Hum Neurosci 2018, systematic review). Device-guided breathing for blood pressure is mixed (Cochrane 2012 review found small or uncertain effects; not re-verified). Mindfulness apps overall have small effects on stress and depression (Gál, Ștefan & Cristea, J Affect Disord 2021, 34 RCTs; Linardon et al., World Psychiatry 2024, 176 RCTs, g≈0.3).
- *Goal tailoring:* none needed; surface it more when the user's own patterns show stress lowers HRV.
- *Effort:* small-medium.

**7. Read and write the HealthKit types in section 1g.**
- *What:* Write `workoutEffortScore` (session RPE) on saved workouts; write `stateOfMind` from the check-in mood; read `sleepApneaEvent` and show a one-line notice; read the iOS 26 Medications API and merge with Tensile's medication list (keep Tensile's effects knowledge); read `timeInDaylight` when present.
- *Who does it best:* Apple (Vitals, Training Load, Medications), Bevel reads most of these.
- *Evidence:* **strong** for the underlying conditions (untreated sleep apnea and non-adherence are well-established risks; reminder-based adherence support roughly doubles the odds of adherence in a meta-analysis of text-message trials, Thakkar et al., JAMA Intern Med 2016, not re-verified). The types themselves are plumbing.
- *Goal tailoring:* none.
- *Effort:* small each; medium for the Medications API (new object-level authorization flow).

**8. Body measurements and waist-to-height ratio.**
- *What:* Log waist (navel), hips, chest, arm, thigh with a 4-week trend; show waist-to-height ratio with the 0.5 cut-off; relate waist trend to the weight trend and progress photos so "weight flat, waist down, lifts up" reads as recomposition.
- *Who does it best:* Hevy, Strong, MacroFactor; Withings Body Scan (segmental).
- *Evidence:* **moderate-strong**. Waist-to-height ratio predicts cardiometabolic risk better than BMI (Ashwell, Gunn & Gibson, Obes Rev 2012, meta-analysis of 31 studies; NICE 2022 guidance recommends keeping it under 0.5). Self-monitoring of weight is linked to more weight loss (Zheng et al., Obesity 2015, systematic review; Patel et al., JMIR mHealth 2019, RCT).
- *Goal tailoring:* fat loss → waist leads; muscle → arm/chest/thigh lead and waist is a guard.
- *Effort:* small (HealthKit has `waistCircumference`; the rest stays in SwiftData).

**9. Movement breaks and the post-meal walk.**
- *What:* Using the hourly step timeline, nudge a 2-5 minute walk after a long sedentary stretch and, when Cronometer logs a large meal, a 10-15 minute walk within an hour. Count the minutes toward the step goal.
- *Who does it best:* Apple Stand reminders, Garmin Move bar, Fitbit hourly activity; Oura Meals ties meals to readiness.
- *Evidence:* **moderate**. Breaking up sitting with standing or light walking lowers postprandial glucose and insulin (Buffey et al., Sports Med 2022, meta-analysis); step count-mortality dose-response flattens at ~7-10k (Ding et al., Lancet Public Health 2025; already in the app).
- *Goal tailoring:* fat loss/health → on by default; strength/muscle → optional (NEAT competes with recovery only marginally).
- *Effort:* small.

**10. Strength-for-health marker (relative strength vs norms).**
- *What:* Show best e1RM/body-weight for squat, deadlift, bench, row and a bodyweight test (push-ups or grip if the user owns a dynamometer) against age-and-sex bands, framed as a longevity marker next to VO2 max, not a leaderboard.
- *Who does it best:* No wearable does this; Hevy/Strong show e1RM only; the app's existing "cardio fitness card" is the pattern.
- *Evidence:* **strong for the association, app choice for the bands**. Muscular strength predicts all-cause mortality (García-Hermoso et al., Arch Phys Med Rehabil 2018, meta-analysis, ~2 million people; Leong et al., Lancet 2015, PURE: grip strength beat systolic BP as a mortality predictor). Published lift standards are crowd-sourced, so label the bands as an app choice.
- *Goal tailoring:* health/endurance users see it as "keep 2+ strength days and reach the 'good' band"; strength users see the next band.
- *Effort:* small.

**11. Training monotony (Foster) on the Fitness tab.**
- *What:* Weekly mean/SD of daily load and weekly load × monotony, with a note when monotony > 2 and strain is high. Already flagged "Open" in `docs/research/strain-science.md`.
- *Evidence:* **moderate but old** (Foster, MSSE 1998: illness clustered above individual thresholds; small samples).
- *Effort:* small (`TrainingLoad` has the daily series).

**12. Proactive coach check-ins (the coach starts the conversation).**
- *What:* Twice a week at most, the coach sends one short, data-triggered message: "HRV has been under your range three mornings; want an easy week?", "You hit every rep on bench twice; next time add 2.5 kg", "Four short nights; here's tonight's bed-by time". Delivered as a notification that opens the chat.
- *Who does it best:* Whoop Proactive Check-ins and My Memory (May 2026), Garmin Active Intelligence (Aug 2026 hands-on), Fitbit/Google Health Coach.
- *Evidence:* **weak to moderate, indirect**. Tailored prompts increase the effect of app-based activity interventions (Laranjo et al., Br J Sports Med 2021, meta-regression: text messaging and personalisation raised effect sizes). No randomised trial of LLM-generated coaching on health outcomes was found in this session; treat the LLM part as unproven and keep the triggers rule-based with the model only wording the message.
- *Goal tailoring:* triggers chosen by goal (fat loss → weight-pace and protein; muscle → progression and volume).
- *Effort:* medium (needs a server-side or background trigger; on-device model can word it without the Claude key).

**13. Export and share: CSV of workouts and daily metrics, PDF of the home-BP protocol and labs.**
- *Who:* Apple's iOS 26 BP PDF for clinicians; Strong/Hevy CSV.
- *Evidence:* **none for health directly**; it lets the user bring data to a doctor and protects against lock-in.
- *Effort:* small.

### 2b. Skip, and why

| Feature | Who has it | Why skip |
|---|---|---|
| Pace of Aging / WHOOP Age-style 30-day "aging speed" | Whoop (May 2025) | Tensile's body age already covers the estimate with a confidence label. A 30-day "pace" from wearable metrics has no outcome validation; it is a motivational dial. Engagement feature, no health evidence. |
| Daytime stress, Resilience, Cumulative Stress | Oura, Whoop, Garmin | Needs continuous daytime HRV. Garmin keeps it; AirPods Pro 3 give HR only in bursts. Validation of wearable "stress" against cortisol or questionnaires is weak. Revisit if the user changes watch. |
| Body Battery-style energy bar | Garmin, Samsung Energy Score, Rise Energy Potential | No peer-reviewed validation found (review-2026-10). |
| Blood pressure estimated by the wearable | Whoop MG, Oura Labs | AHA/ACC 2025 advises against cuffless estimates; Whoop itself says "not for diagnosis". Keep the cuff protocol. |
| Continuous glucose, antioxidant index, vascular load | Oura + Stelo, Ultrahuman, Samsung | No outcome evidence in non-diabetics; hardware the user does not have. |
| Running coach, lactate threshold, Hill/Endurance scores, race predictor | Garmin, Runna, Samsung Running Coach | Running-specific; the user lifts. If he takes up running later, Runna's "Adapt for Heat" and "Not feeling 100%" are already matched by Tensile's heat and rest modes. |
| Apple Watch companion, Workout Buddy voice | Strong, Hevy, Apple | The user wears a Garmin Instinct 2. |
| Social feed, leaderboards, badges, streaks | Hevy, Strava, Garmin, Breathwrk | Gamified interventions raise physical activity modestly in the short term (Mazeas et al., J Med Internet Res 2022, meta-analysis of RCTs) but the effect fades and needs other people. Single-user app. Streaks also push training through illness; Gentler Streak's reviewers praise it precisely for not doing this. |
| Program library (5/3/1, nSuns, GZCLP) | Boostcamp | Tensile's planner already builds equipment-aware sessions; importing named programs adds maintenance without evidence that any named program beats a sensible progressive one. Reconsider only if the user asks for a specific program. |
| AI photo/voice food logging | MFP, Lose It, Cronometer, MacroFactor | Cronometer already does it and writes to Health. |
| Mobility test and daily stretching routines | Pliability (camera test), GOWOD (10-test score) | Resistance training through a full range of motion improves flexibility as much as stretching (Afonso et al., Healthcare 2021, meta-analysis), and the planner already uses full-ROM lifts. Stretching's injury-prevention evidence is weak (Behm et al., Appl Physiol Nutr Metab 2016). Add only a short "joint-specific warm-up" to item 4. |
| Snore/sound detection, smart alarm | Sleep Cycle | Garmin tracks sleep; smart alarms have no outcome evidence. |
| Menstrual-phase training plans, perimenopause insights | Whoop, Oura | Trivial effects of cycle phase on performance (McNulty et al., Sports Med 2020); the user is male. Keep the check-in field for other users. |
| Injury-risk from acute:chronic ratio | Some coaching apps | Dismissed in the literature (Impellizzeri 2020/2021; see strain-science.md). |
| Hearing/noise exposure, walking steadiness | Apple | Real health value but outside this app's scope and better served by the Health app. |
| Clinician access, lab ordering | Whoop Advanced Labs, Oura Health Panels, Function, Superpower | Business, not software. Tensile's PDF upload already covers the data side. |

---

## 3. Tensile's edge: keep these

Things found in no competitor surveyed, or done better here:

1. **Gym-aware planning with plate maths.** Fitbod knows equipment; nobody else rounds every load to the plates, dumbbells and stack increments the user actually owns and progresses by the gym's smallest jump.
2. **Personal patterns that are statistically tested.** Whoop's Journal and Oura's Tags report averages; Tensile runs a Welch t-test with false-discovery correction and needs 7+ days each side before it claims caffeine, alcohol, sauna or a late meal changed HRV, RHR or sleep.
3. **Lifting counted properly in strain and recovery** (max of HR TRIMP and session-RPE load; muscle-level fatigue map; weekly hard sets with indirect sets as half). Wearables still undercount lifting.
4. **Energy balance with a measured maintenance** from Cronometer intake plus weight trend, with half-logged-day and creatine-water handling, and micronutrients judged against the EAR. MacroFactor does the expenditure part; none of the wearables do.
5. **Medications with known effects on HR, HRV, sleep and training**, so a beta-blocker or a new antihistamine does not read as "poor recovery".
6. **Evidence labels and honesty**: scores say when they are app choices, sleep stages are weighted lightly, body age shows confidence, the illness watch needs two signals, and the app refuses to estimate BP or glucose from a wearable.
7. **Caffeine cut-off from bedtime, alcohol effect, heat acclimation days, sick/rest mode** are each present in one or two competitors; Tensile is the only one with all of them, free of subscription.
8. **Privacy**: progress photos never leave the device except for the explicit weekly analysis; the API key stays server-side; rate limits are enforced server-side.
9. **Device-agnostic through HealthKit**: Garmin watch + Cronometer + AirPods heart rate + iPhone camera HRV in one place; Athlytic and Training Today are Apple Watch only, Whoop/Oura need their hardware.
10. **The coach returns a startable workout card**, not a paragraph. Whoop's and Oura's assistants explain; they do not hand you a session that fits your gym.

---

## 4. References

Product sources (date of page or article; seen in this session unless marked):

- WHOOP press centre, "WHOOP Expands Health Platform with On-Demand Clinician Access and New AI Features" (My Memory, Proactive Check-ins), 8 May 2026. https://www.whoop.com/us/en/press-center/whoop-expands-health-platform-with-on-demand-clinician-access-and-new-ai-features/
- WHOOP, "2026 What's New at WHOOP" (Healthspan ↔ Advanced Labs, Jan 2026; cycle-specific lab ranges, Mar 2026; Advanced Labs without a wearable, Aug 2026). https://www.whoop.com/us/en/thelocker/2026-whats-new/
- Business Wire / Fitt Insider, "WHOOP Unveils WHOOP 5.0 and WHOOP MG" (Healthspan: WHOOP Age over 6 months, Pace of Aging over 30 days, nine biometrics; Health Monitor, Stress Monitor, VO2 max, Blood Pressure Insights, ECG), 8 May 2025. https://www.businesswire.com/news/home/20250508546933/en/
- WHOOP Support, "WHOOP Basics" (tier availability of Healthspan, Health Monitor, Stress Monitor). https://support.whoop.com/s/article/WHOOP-Basics
- TechRepublic, WHOOP blood-sugar and blood-pressure coaching study with Abu Dhabi DoH, Oct 2026. https://www.techrepublic.com/article/news-whoop-blood-sugar-blood-pressure-study/
- Oura, "New Oura Features to Help You Stay Ahead of Your Health" (Oura Ring 5, Health Radar rolling out through Jul 2026, GLP-1 Insights Jun 2026, live activity tracking 4 Jun 2026, lab import 30 Jun 2026), May 2026. https://ouraring.com/blog/new-software-features/
- Oura, "Made for Members March 2026" (Menopause Insights, Hormonal Birth Control). https://ouraring.com/blog/made-for-members-march-2026/
- TechCrunch, "Oura launches redesigned app and Cumulative Stress feature", 20 Oct 2025. https://www.techcrunch.com/2025/10/20/oura-launches-redesigned-app-and-cumulative-stress-feature
- Oura blog, Readiness score, Daytime Stress, Resilience, Meals, Oura Advisor (undated pages, 2023-2025). https://ouraring.com/blog/readiness-score/ ; https://ouraring.com/blog/inside-the-ring-daytime-stress/ ; https://ouraring.com/blog/inside-the-ring-resilience-feature/
- Garmin newsroom, "Elevate your health and fitness goals with Garmin Connect+", 27 Mar 2025. https://www.garmin.com/en-US/newsroom/press-release/wearables-health/elevate-your-health-and-fitness-goals-with-garmin-connect/
- the5krunner, "Garmin Connect+ Reviewed", 20 Apr 2026. https://the5krunner.com/2026/04/20/garmin-connect-plus-review/
- SamsungMagazine.eu, "Garmin Active Intelligence Test", 11 Aug 2026. https://samsungmagazine.eu/en/2026/08/11/garmin-active-intelligence-connect/
- Gadgets & Wearables, "What to expect from Garmin's new Evening Report", 18 May 2025. https://gadgetsandwearables.com/2025/05/18/garmin-evening-report/
- the5krunner, "FORMA: Garmin Recovery Data to Structured Strength Workouts", 13 Apr 2026 (Garmin's recovery data does not translate to strength sessions). https://the5krunner.com/2026/04/13/forma-garmin-recovery-strength-workouts/
- Garmin manuals, Training Status / HRV Status / Training Readiness pages (undated). https://www8.garmin.com/manuals/webhelp/GUID-B613EA0B-EFB7-451C-BA10-DB9EE5A990BF/EN-US/GUID-44C7BB4B-EFF7-4A42-AC03-8A6AABB94807.html
- Apple Support, "About watchOS 26 Updates" (Sleep Score, Workout Buddy, hypertension notifications). https://support.apple.com/en-us/123002
- Apple Newsroom, "Apple debuts Apple Watch Series 11" (hypertension notifications, Sleep Score), 9 Sep 2025. https://www.apple.com/newsroom/2025/09/apple-debuts-apple-watch-series-11-featuring-groundbreaking-health-insights/
- Apple Support, "About iOS 26 Updates" (blood-pressure logging with reminders and PDF report; Workout tab). https://support.apple.com/en-us/123075
- Apple Newsroom, "watchOS 11 brings powerful health and fitness insights" (Vitals app, Training Load, effort rating), 10 Jun 2024. https://www.apple.com/uk/newsroom/2024/06/watchos-11-brings-powerful-health-and-fitness-insights/
- Apple Developer, WWDC25 session 321 "Meet the HealthKit Medications API" (HKUserAnnotatedMedication, dose events, object-level authorization), Jun 2025. https://developer.apple.com/videos/play/wwdc2025/321/
- 9to5Mac, "iOS 26.4 improved Apple's Health app, and bigger upgrades are coming soon", 30 Apr 2026 (food tracking / AI agent not shipped in 26.4; expected in iOS 27). https://9to5mac.com/2026/04/30/ios-26-4-improved-apples-health-app-and-bigger-upgrades-are-coming-soon/
- Google blog, "Fitbit's personal health coach is now available in public preview", Oct 2025. https://blog.google/products-and-platforms/devices/fitbit/personal-health-coach-public-preview/
- Google Store, "Fitbit's New Weekly Cardio Load Target". https://store.google.com/magazine/fitbit-weekly-cardio-load?hl=en-US
- Samsung Newsroom, "New Features on One UI 8 Watch Help Users Build Healthier Habits" (Bedtime Guidance, Vascular Load, Running Coach, Antioxidant Index), Jun 2025. https://news.samsung.com/global/new-features-on-one-ui-8-watch-help-users-build-healthier-habits
- the5krunner, "Ultrahuman Ring Pro", 6 May 2026; Trusted Reviews on the Ultrahuman app update (UltraSphere). https://the5krunner.com/2026/05/06/ultrahuman-ring-pro/
- healthappinsider, "Athlytic vs Bevel vs Gentler Streak vs PeakWatch (2026)"; askvora, "Best Apple Watch Recovery Apps in 2026". https://www.healthappinsider.com/en/comparisons/athlytic-vs-bevel-vs-gentler-streak ; https://askvora.com/blog/best-apple-watch-recovery-apps-2026
- Australian Apple News, "Review: Bevel", 7 Jan 2026; kiledjian.com, "Bevel turns Apple Watch data into useful health guidance", 7 Jul 2026. https://australianapplenews.com/2026/01/07/review-bevel-a-health-app-that-ticks-almost-all-the-boxes/
- App Store, "Training Today" (RTT score, Overall Fitness Index). https://apps.apple.com/us/app/id1507992127
- App Store, HRV4Training and Elite HRV listings. https://apps.apple.com/us/app/hrv4training/id686923970 ; https://apps.apple.com/us/app/elite-hrv-wellness-fitness/id868829970
- Garage Gym Reviews, "Best Weightlifting Apps (2026)"; lifthero, "11 Best Workout Apps for Strength Training in 2026"; sensai.fit, "Hevy vs Strong vs Fitbod (2026)". https://www.garagegymreviews.com/best-weightlifting-app ; https://lifthero.app/best-workout-apps ; https://www.sensai.fit/blog/hevy-vs-strong-vs-fitbod
- Alpha Progression blog, "Alpha Progression vs RP Hypertrophy (2026)" and "Best RP Hypertrophy alternatives" (vendor-written; RP's volume-progression logic, Juggernaut AI readiness, Liftosaur scripting). https://alphaprogression.com/en/blog/alpha-progression-vs-rp-hypertrophy
- Stronger by Science, program bundle page (21-week autoregulated programs, builder). https://www.strongerbyscience.com/?p=50394
- nutrola, "MyFitnessPal vs Cronometer vs MacroFactor 2026" and "Cronometer vs MacroFactor vs Carbon 2026"; best-nutrition-apps.com, "Nutrition App Updates: April 2026" (Cronometer Professional Portal). https://nutrola.app/en/blog/myfitnesspal-vs-cronometer-vs-macrofactor-2026 ; https://best-nutrition-apps.com/nutrition-apps-updates-april-2026/
- Superpower, "Function Health vs InsideTracker (2026)" (vendor); Mallet, "Best Bloodwork Tracker Apps in 2026". https://superpower.com/biomarker-testing-companies/function-health-vs-insidetracker ; https://www.mallet.so/blog/best-bloodwork-tracker-apps-2026
- Rise Science, "What's the Best Sleep Debt Tracking App?" (14-night debt, Energy Potential). https://www.risescience.com/blog/best-sleep-debt-tracking-app
- Sunrise Digest, "Sleep Cycle Review 2026". https://thesunrisedigest.com/rest/sleep-cycle-review-2026/
- Withings, Body Scan / BodyScan 2 pages; Notebookcheck on Cardio Check-Up. https://www.withings.com/us/en/body-scan
- Zepp, "Zepp Aura" pages. https://us.amazfit.com/pages/zepp-aura
- Runna press, "Adapt for Heat" (29 Jul 2026) and 2026 beginner plans. https://www.runna.com/press/runna-announces-new-updates
- endurance.biz, "Strava revamps Athlete Intelligence", 2025; advnture on Athlete Intelligence launch, Oct 2024. https://endurance.biz/2025/industry-news/strava-revamps-athlete-intelligence-leaderboards-flyovers-and-progress-analytics
- Pulse, "Headspace Debuts New Apple Watch App" (heart-rate-triggered breathing breaks), May 2026; TechCrunch on the Calm Sleep app. https://www.pulse.bot/wellness/news/qa-headspace-debuts-new-apple-watch-app-for-mental-health-support-9c5ac671-94e9-434b-a157-ccab4d348b6f/
- Breathwrk site; GOWOD FAQ (10-test mobility score); fitnessdrum, "Pliability App Review 2026". https://www.breathwrk.com/ ; https://www.gowod.app/faq ; https://fitnessdrum.com/pliability-app-review/
- Not re-verified this session (product knowledge, pre-2026): Whoop Journal and Weekly/Monthly Performance Assessment, Whoop Strength Trainer, Oura Chronotype and Cardio Capacity, Garmin Jet Lag Adviser, Hevy/Strong supersets and body-measurement features, MacroFactor expenditure algorithm details, Noom GLP-1 companion, Zoe scores, WaterMinder, Everlywell.

Evidence sources (journal, year; those marked * could not be re-checked online in this session because PubMed was blocked, but are well-known papers):

- Ferguson T, Olds T, Curtis R, et al. Effectiveness of wearable activity trackers to increase physical activity and improve health: a systematic review of systematic reviews and meta-analyses. Lancet Digit Health 2022;4:e615-e626.
- Hickmott LM, Chilibeck PD, Shaw KA, Butcher SJ. The effect of load and volume autoregulation on muscular strength and hypertrophy: a systematic review and meta-analysis. Sports Med Open 2022;8:9.
- Helms ER, Byrnes RK, Cooke DM, et al. RPE vs. percentage 1RM loading in periodized programs matched for sets and repetitions. Front Physiol 2018;9:247.
- * Williams TD, Tolusso DV, Fedewa MV, Esco MR. Comparison of periodized and non-periodized resistance training on maximal strength: a meta-analysis. Sports Med 2017;47:2083-2100.
- * Grgic J, Mikulic P, Podnar H, Pedisic Z. Effects of linear and daily undulating periodized resistance training programs on measures of muscle hypertrophy: a systematic review and meta-analysis. PeerJ 2017;5:e3695.
- * Coleman M, et al. Gaining more from doing less? The effects of a one-week deload period during supervised resistance training on muscular adaptations. PeerJ 2024;12:e16777.
- * Schoenfeld BJ, Ogborn D, Krieger JW. Dose-response relationship between weekly resistance training volume and increases in muscle mass. J Sports Sci 2017;35:1073-1082.
- * Iversen VM, Norum M, Schoenfeld BJ, Fimland MS. No time to lift? Designing time-efficient training programs for strength and hypertrophy: a narrative review. Sports Med 2021;51:2079-2095.
- * Fradkin AJ, Zazryn TR, Smoliga JM. Effects of warming-up on physical performance: a systematic review with meta-analysis. J Strength Cond Res 2010;24:140-148.
- * Michie S, Abraham C, Whittington C, McAteer J, Gupta S. Effective techniques in healthy eating and physical activity interventions: a meta-regression. Health Psychol 2009;28:690-701.
- * Harkin B, Webb TL, Chang BPI, et al. Does monitoring goal progress promote goal attainment? A meta-analysis of the experimental evidence. Psychol Bull 2016;142:198-229.
- * Laranjo L, Ding D, Heleno B, et al. Do smartphone applications and activity trackers increase physical activity in adults? Systematic review, meta-analysis and metaregression. Br J Sports Med 2021;55:422-432.
- * Mazeas A, Duclos M, Pereira B, Chalabaev A. Evaluating the effectiveness of gamification on physical activity: systematic review and meta-analysis of randomized controlled trials. J Med Internet Res 2022;24:e26779.
- * Mah CD, Mah KE, Kezirian EJ, Dement WC. The effects of sleep extension on the athletic performance of collegiate basketball players. Sleep 2011;34:943-950.
- * Bonnar D, Bartel K, Kakoschke N, Lang C. Sleep interventions designed to improve athletic performance and recovery: a systematic review of current approaches. Sports Med 2018;48:683-703.
- * Nedeltcheva AV, Kilkus JM, Imperial J, Schoeller DA, Penev PD. Insufficient sleep undermines dietary efforts to reduce adiposity. Ann Intern Med 2010;153:435-441.
- Windred DP, et al. Sleep regularity is a stronger predictor of mortality risk than sleep duration. Sleep 2024;47:zsad253 (already cited in the app).
- * Laborde S, Allen MS, Borges U, et al. Effects of voluntary slow breathing on heart rate and heart rate variability: a systematic review and a meta-analysis. Neurosci Biobehav Rev 2022;138:104711.
- * Zaccaro A, Piarulli A, Laurino M, et al. How breath-control can change your life: a systematic review on psycho-physiological correlates of slow breathing. Front Hum Neurosci 2018;12:353.
- * Gál É, Ștefan S, Cristea IA. The efficacy of mindfulness meditation apps in enhancing users' well-being and mental health related outcomes: a meta-analysis of randomized controlled trials. J Affect Disord 2021;279:131-142.
- * Linardon J, Torous J, Firth J, Cuijpers P, Messer M, Fuller-Tyszkiewicz M. Current evidence on the efficacy of mental health smartphone apps for symptoms of depression and anxiety: a meta-analysis of 176 randomized controlled trials. World Psychiatry 2024;23:139-149.
- * Thakkar J, Kurup R, Laba TL, et al. Mobile telephone text messaging for medication adherence in chronic disease: a meta-analysis. JAMA Intern Med 2016;176:340-349.
- * Ashwell M, Gunn P, Gibson S. Waist-to-height ratio is a better screening tool than waist circumference and BMI for adult cardiometabolic risk factors: systematic review and meta-analysis. Obes Rev 2012;13:275-286.
- * Zheng Y, Klem ML, Sereika SM, Danford CA, Ewing LJ, Burke LE. Self-weighing in weight management: a systematic literature review. Obesity 2015;23:256-265.
- * Patel ML, Hopkins CM, Brooks TL, Bennett GG. Comparing self-monitoring strategies for weight loss in a smartphone app: randomized controlled trial. JMIR Mhealth Uhealth 2019;7:e12209.
- * Buffey AJ, Herring MP, Langley CK, Donnelly AE, Carson BP. The acute effects of interrupting prolonged sitting time in adults with standing and light-intensity walking on biomarkers of cardiometabolic health: a systematic review and meta-analysis. Sports Med 2022;52:1765-1787.
- * García-Hermoso A, Cavero-Redondo I, Ramírez-Vélez R, et al. Muscular strength as a predictor of all-cause mortality in an apparently healthy population: a systematic review and meta-analysis of data from approximately 2 million men and women. Arch Phys Med Rehabil 2018;99:2100-2113.
- * Leong DP, Teo KK, Rangarajan S, et al. Prognostic value of grip strength: findings from the Prospective Urban Rural Epidemiology (PURE) study. Lancet 2015;386:266-273.
- * Afonso J, Ramirez-Campillo R, Moscão J, et al. Strength training versus stretching for improving range of motion: a systematic review and meta-analysis. Healthcare (Basel) 2021;9:427.
- * Behm DG, Blazevich AJ, Kay AD, McHugh M. Acute effects of muscle stretching on physical performance, range of motion, and injury incidence in healthy active individuals: a systematic review. Appl Physiol Nutr Metab 2016;41:1-11.
- * Foster C. Monitoring training in athletes with reference to overtraining syndrome. Med Sci Sports Exerc 1998;30:1164-1168.
- * Burns AC, Saxena R, Vetter C, Phillips AJK, Lane JM, Cain SW. Time spent in outdoor light is associated with mood, sleep, and circadian rhythm-related outcomes: a cross-sectional and longitudinal study in over 400,000 UK Biobank participants. J Affect Disord 2021;295:347-352.
- McNulty KL, et al. Sports Med 2020; Impellizzeri FM, et al. IJSPP 2020 and Sports Med 2021; Ding D, et al. Lancet Public Health 2025; 2025 AHA/ACC hypertension guideline: already cited in `docs/review-2026-10.md` and `docs/research/strain-science.md`.
