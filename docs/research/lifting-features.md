# Lifting and fitness features Tensile could add: what the competitors do, what the evidence says

Research round, 6 November 2026. Question from the user: "research competitors for what can be added to the weightlifting and fitness section to make the app better; research till you have 8 great options."

**How this was researched.** The existing docs (`competitors.md` §1d/§2, `workout-science.md`, `watch-features.md`, `roadmap.md`, `README.md`) and the code (`App/Features/Fitness`, `Workout`, `Trainer`; `Packages/AppCore`: `WorkoutPlanner`, `TrainingBlock`, `WeeklyPlan`, `TrainingDayPlanner`, `WarmUp*`, `LoadEstimator`, `Supersets`, `TrainingTools`, `MuscleRecovery`, `TrainingStatus`) were read first so nothing below re-proposes what exists. Product facts were checked by web search against official feature pages, help centres and App Store listings on 6 Nov 2026 (vendor blogs are marked as such). Evidence was checked through PMC, publisher pages or university repositories; PubMed itself is blocked from the sandbox. Where a figure comes from a secondary write-up rather than the paper it is marked **(secondary)**.

**Evidence labels**: *strong* = meta-analyses/RCTs or guideline consensus; *moderate* = a meta-analysis of few small trials, or consistent RCTs; *weak* = small or indirect studies; *none* = usability or engagement only. **Build size**: S = a day or two, M = about a week, L = multi-week.

**What already exists** (not re-proposed): auto-planned sessions by focus, time and recovery with loads rounded to the user's gym and progressed by its smallest jump; double progression with a "big jump, get N reps first" note; RPE/RIR per set and per session (Zourdos table); ramp sets and dynamic warm-up tiers; supersets; 4–6 week training blocks with RIR 3→1, a set ramp and a planned deload held back when HRV is low (`TrainingBlock`, `DeloadAdvisor`); weekly plan with if-then plans and consistency; muscle map, per-muscle recovery and weekly hard sets against 10–20; e1RM, PR badge on the live set, plateau detection, lift charts; exercise swap in the builder; plate-per-side hint; exercise guides with form-video link; Watch app with per-set logging and rest timer; HR zones; lifting counted in strain and recovery; `TrainingStatus` (untrained → advanced) from years trained.

---

## 1. Competitor snapshot (lifting features only)

| App | Distinctive lifting features (verified source) | Tensile today |
|---|---|---|
| **Hevy** | Set types: regular, warm-up, drop, failure; rest timer skipped before a drop set; percentage warm-up calculator with plate/dumbbell rounding; plate calculator toggle; supersets and giant sets; previous-session values shown beside each set [P1][P2] | set types missing; warm-up and plates built in |
| **Strong** | Warm-up and plate calculators, 1RM and volume charts, full Apple Watch app that logs without the phone [P3] | has |
| **RP Hypertrophy** | Mesocycles from MEV toward MRV; per-session pump, soreness, performance and joint feedback each scored 0–2 and summed to "below/at/above MEV"; RIR progression 3→0; deload at ~50% volume [P4][P5] | blocks exist; no per-muscle volume adjustment, no pump/soreness input |
| **JuggernautAI** | Readiness inputs (sleep, soreness) plus per-set RPE/RIR; adds sets, holds or backs off week by week; warm-up planner and meet-day adviser (third-party descriptions only) [P6][P7] | recovery already scales the day |
| **Alpha Progression** | Set-level targets (weight *and* reps) recomputed from the last session; blocks where sets, rep targets and RIR change; integrated deload; 795 exercise videos; no watch app [P8][P9] | partial (per-exercise load, not per-set) |
| **Fitbod** | Muscle recovery 0–100% per group drives exercise selection; Replace Exercise keeps the muscle group; "Recommend less / Never again" [P10][P11] | has recovery map and swap; no "never again" |
| **Boostcamp** | 100+ free programs (nSuns, GZCLP, 5/3/1, PPL, PHUL); 5RM onboarding computes T1 loads; auto-progression (Pro); builder with multi-week periodisation and custom progressions [P12][P13] | no library (deliberately, `roadmap.md`) |
| **KeyLifts** | 5/3/1 and nSuns calculator-style log; automatic training-max progression; plate calculator; Watch app [P14] | n/a |
| **Caliber** | Strength Score (composite of five muscle-group sub-scores, five bands) and Strength Balance across groups; 60+ coach plans [P15][P16] | strength-for-health card planned (`roadmap.md` Phase 4) |
| **Gravitus** | Plate calculator, real-time in-workout analytics, per-workout progressive-overload breakdown, leaderboards/streaks [P17] | skip social |
| **Setgraph** | Minimal-tap logging; timer in Dynamic Island; supersets/circuits; volume vs last session; consistency calendar; Watch app [P18] | has most |
| **Liftin'** | Rule-based auto progression ("Auto progression 2.0" with set progression and in-workout progression info); everything on Watch [P19] | partial |
| **Apple Fitness+ Gym Strength** (beta, 3 Nov 2026) | Four-week progressive plans from goals, experience, schedule and equipment; next week adjusts to logged reps and weight; 150–350 exercise demos; Watch logs reps/weight; "Training Note" written by Apple Intelligence; needs iOS/watchOS 27.3 [P20][P21] | Tensile's planner does this today on iOS 26; Apple adds video demos and voice |
| **Apple Workout Buddy** (watchOS 26) | Spoken AI encouragement for Functional/Traditional Strength; one outlet claims it counts reps, no second source confirms it [P22][P23] | — |
| **Peloton Strength+** | Coach-led programs, workout generator by muscle/time/equipment, video clips; reviewers note a narrow library and no import [P24] | — |
| **Garmin** | Wrist rep counting (needs 4+ reps, counts when the arm returns to start; leg exercises may not count); post-workout muscle map; recovery-by-muscle only surveyed, not shipped [P25][P26] | — |
| **Whoop Strength Trainer** | Accelerometer/gyroscope "muscular load" from logged exercises; validation unpublished [P27] | lifting already counted via sRPE |

---

## 2. Candidate features evaluated

Fit = fit with Tensile's research-first, gym-aware, single-user, on-device rules.

| # | Candidate | Who has it | Evidence | Size | Verdict |
|---|---|---|---|---|---|
| a | Live set targets with last-time values and immediate feedback ("beat last time") | Hevy, Strong, Alpha Progression, Setgraph | **Moderate–strong**: augmented feedback raises acute performance (g 0.63, ~8% velocity), visual beats verbal (g 1.11 vs 0.47), per-rep feedback best, and feedback across a cycle gives larger strength gains; it also raises motivation and perceived effort (Weakley 2023, 20 studies) [E1] | M | **Pick 1** |
| b | Set-by-set RIR autoregulation of the next load | RP, JuggernautAI, Alpha Progression | **Moderate**: RIR-based load autoregulation equals percentage-based for 1RM (Hickmott 2022, 15 studies) [E2]; lifters under-predict RIR by ~1 rep, more accurately near the end of a set and on sets ≤12 reps (Halperin 2022, 414 participants) [E3] | M | **Pick 2** |
| c | Drop sets, rest-pause, myo-reps as logged set types and as a short-session option | Hevy (drop/failure), RP, Liftosaur | **Moderate** for "same growth in less time": drop sets ≈ traditional for hypertrophy (ES ~0.08) in half to a third of the time (Coleman 2022; Sødal 2023) [E4][E5]; rest-pause ≈ traditional, maybe a small hypertrophy edge (Carvalho 2022; Tsartsapakis 2026) [E6][E7]; myo-reps themselves untested | M | **Pick 3** |
| d | Per-muscle weekly volume progression ("volume landmarks" done honestly) | RP (MEV/MAV/MRV), Hevy (sets per muscle), Alpha Progression | **Moderate** for volume dose-response: diminishing returns with no detectable superiority past ~31 fractional sets/week, minimum effective dose ~4 (Pelland 2024 preprint, 67 studies, **secondary** figures) [E8]; **weak** for pump/soreness as the signal: swelling correlates with growth in some data and is "minimal and inconsistent" in others; soreness tracks damage, not growth [E9][E10] | M | **Pick 4** (performance-driven, not pump-driven) |
| e | Pain/niggle log that avoids or regresses lifts | None of the trackers; physio apps only | **Moderate**: strength training itself cuts sports injuries by about two thirds, dose-dependent (Lauersen 2018, RR 0.34) [E11]; exercising into tolerable pain is not harmful and gives a small short-term pain benefit in chronic MSK pain (Smith 2017, 7 RCTs, SMD −0.27) [E12] | M | **Pick 5** |
| f | Long-term lift goal with a projected date from the e1RM trend | None do projections; Caliber has a score | **Moderate** for goal setting on activity (McEwan 2016, d 0.55) but specific goals were no better than vague ones, and Swann's group shows specific performance goals backfire when beyond reach; only ~36% hit activity goals in low-bias trials (**secondary**) [E13][E14][E15] | M | **Pick 6** (approach goal, range not date) |
| g | Easy cardio sessions scheduled around lifting | Garmin/Whoop (cardio only), Fitbod (cardio modules) | **Strong** that concurrent training does not blunt hypertrophy or max strength; explosive strength may suffer when both are in one session; running (not cycling) linked to smaller type I fibres (Schumann 2022, 43 studies; Lundberg 2022) [E16][E17] | M | **Pick 7** |
| h | Watch rep counting and bar speed (velocity loss) | Garmin, Whoop, Apple (Workout Buddy, unconfirmed), StrengthControl | **Moderate validity, weak outcome**: wrist Apple Watch mean velocity r 0.95–0.97 vs motion capture in squats (Achermann 2023) [E18]; rep counts accurate for squat and deadlift, poor for bench, 1RM prediction failed (Huber 2021, n=30) [E19]; VBT ≈ percentage for strength (Liao 2021; Zhang 2022 SMD 0.26 favouring VBT) [E20][E21] | L | **Pick 8** (experimental, opt-in) |
| i | Bodyweight/calisthenics progressions for no-equipment days | Fitbod, Peloton | **Weak–moderate**: 4-week push-up progression matched bench press for 1RM gain (Kotarsky 2018, n=23); loaded push-ups interchangeable with 50–80% bench [E22] | M | Worth doing after the eight; fits "If I'm travelling, bodyweight at the hotel" |
| j | Rep-range scheme selector per exercise (double/triple, linear, wave) | Boostcamp, Liftosaur, Liftin' | **Moderate** that load and rep progression both work (Plotkin 2022) [E23]; linear vs undulating no different for hypertrophy (Grgic 2017, in `competitors.md`) | S–M | Fold into Pick 2 as a per-exercise "progress by reps / by load / by sets" switch; no separate feature |
| k | 1RM-percentage programs (5/3/1, GZCLP) and a program library | Boostcamp, KeyLifts | **None** that any named program beats a sensible progressive one; RPE ≈ % loading (Helms 2018) | L | Skip (as `roadmap.md`); revisit on request |
| l | Tempo prescriptions | RP, Liftosaur | **Moderate against prescribing**: hypertrophy similar from 0.5 to 8 s per rep, >10 s inferior (Schoenfeld 2015) [E24] | S | Skip as prescription; allow a free-text tempo note |
| m | Unilateral left/right logging | Few trackers | **Moderate** that unilateral and bilateral give similar hypertrophy, strength follows specificity (Kassiano 2025) [E25]; no evidence that tracking asymmetry changes outcomes | S | Low priority; add "per side" reps field only |
| n | Exercise substitution by muscle equivalence | Fitbod, Hevy | Usability; swap exists | S | Add Fitbod-style "never again" and "needs equipment X" filters to the swap (small, part of Pick 5) |
| o | Training-age graduation (novice → intermediate) | Alpha Progression (experience setting) | **Weak**: large powerlifting datasets show a smooth decline in gain rate, no biological boundary (**secondary**) [E26] | S | Auto-suggest `TrainingStatus` promotion after 6 and 24 months or when e1RM gain rate falls, labelled an app choice |
| p | Offline exercise video library | Hevy, Alpha Progression, Apple Gym Strength | None (usability); free-exercise-db is images only; video licensing is the blocker | L | Skip; keep the form-video link |
| q | Gym crowd/equipment availability, social sharing, leaderboards, streaks | Gravitus, Hevy | None; single user | – | Skip |
| r | Mid-session "effort check" prompts, deload auto-trigger, plate calculator | RP, JuggernautAI; Strong, Hevy | — | – | Already exist (per-set RPE; `DeloadAdvisor`; plate-per-side) |

---

## 3. The eight, ranked

### 1. Live set targets with last-time values and feedback ("beat last time")
- **What the user sees:** On the live set card, the previous session's weight × reps × RPE for that set in grey "ghost" text under the target, the target reps as a ring that fills as reps are entered, and a one-line verdict when the set is logged: "+1 rep on last time", "matched", or "2 short — the planner will hold the load". The existing PR badge stays; add a haptic and a short banner for e1RM, rep or volume PRs at the end of the exercise, not mid-set. Same layout on the Watch (ghost line under the target).
- **Data source:** `ExerciseHistory` (already loaded for the planner) joined to the current `PlannedExercise` set index; `LiftProgress.points` for PR detection.
- **Evidence:** Moderate–strong for feedback on performance and strength over a cycle, visual over verbal, per-rep best (Weakley 2023) [E1]. PR celebration itself is engagement only; keep it quiet and factual (no confetti, no streaks: `behaviour-change.md`).
- **Size:** M. **Dependencies:** none. **Risks:** encourages grinding past the target RIR on block weeks; show the RIR target beside the ghost line and word the verdict around the plan ("matched the plan"), not "beat".

### 2. Set-by-set RIR autoregulation (and a per-exercise progression switch)
- **What the user sees:** After each working set the logged RPE is compared with the block's RIR target. Two or more reps fresher than target → next set's load goes up one gym jump; two or more reps harder → down one jump or reps trimmed; within one → unchanged. The change appears as "Next set 62.5 kg (you had 3 in reserve)" with the plate hint. A per-exercise setting chooses the long-term rule: progress by load (default for barbell), by reps (dumbbells and machines with big jumps), or by sets (isolation work).
- **Data source:** per-set RPE already captured; `GymProfile` jumps; `TrainingBlock.WeekState.targetRIR`.
- **Evidence:** Moderate: RIR-based autoregulation equals percentage loading for strength (Hickmott 2022) [E2], so this is a non-inferior convenience, not a gains claim; the ~1-rep under-prediction (Halperin 2022) [E3] means a one-rep tolerance band and no adjustment on sets over 12 reps. Load vs rep progression both work (Plotkin 2022) [E23].
- **Size:** M (AppCore rule with tests + live view + Watch). **Dependencies:** Pick 1's UI. **Risks:** load whipsawing on noisy RPE: adjust at most once per exercise per session and never on the first set.

### 3. Time-saving set styles: drop sets, rest-pause, myo-reps
- **What the user sees:** Set types on any set (warm-up exists; add drop, rest-pause, myo-rep, failure) with the rest timer skipped between drop stages. On a planned day where the time budget is short (the existing "15-minute version"), the planner offers "Same work, less time: last set of each isolation exercise as a drop set" with the drop loads rounded to the gym (dumbbell rack, stack pin, or plates to strip).
- **Data source:** `PlannedExercise` sets gain a `style`; `GymProfile.plateBreakdown` and dumbbell set for the drop loads; `WorkSet` gains a style for history and volume maths (count a drop set as one hard set plus a half, as indirect sets already are, and say so).
- **Evidence:** Moderate: drop sets equal traditional sets for hypertrophy and strength in a half to a third of the time (Coleman 2022; Sødal 2023) [E4][E5]; rest-pause equal or slightly better (Carvalho 2022; Tsartsapakis 2026) [E6][E7]. Label myo-reps as "untested, a rest-pause variant". Goal tailoring: offer only to muscle/health goals; strength goals keep straight sets on main lifts.
- **Size:** M. **Dependencies:** Iversen 2021 time-budget logic already in the planner. **Risks:** sRPE load and muscle-recovery maths must treat a drop set as one effortful set, not three; fatigue carry-over, so never on the first exercise.

### 4. Per-muscle weekly volume progression inside blocks
- **What the user sees:** The muscle map's weekly hard-set count becomes a target band per muscle for this block week (for example chest 10 → 12 → 14 → 16 sets, deload 8). Each week the planner adds one set to a muscle only if last week's sets were all completed at or under the RIR target and the muscle is recovered in `MuscleRecovery`; holds if reps fell; the block-level deload stays. A one-line note explains the change ("Back held at 14 sets: reps dropped on rows last week").
- **Data source:** `WeeklySets` by muscle, `MuscleRecovery`, per-set RPE and reps; `TrainingBlock.WeekState.setMultiplier` becomes per-muscle.
- **Evidence:** Moderate for the volume dose-response (Pelland 2024, diminishing returns past ~31 fractional sets, minimum dose ~4) [E8] and the 10–20 band already in the app. Deliberately **not** pump- or soreness-driven: swelling and soreness are inconsistent signals [E9][E10], so the UI must say the rule uses performance and recovery, and that MEV/MRV are coaching heuristics, not measured quantities.
- **Size:** M. **Dependencies:** training blocks. **Risks:** small muscles in supersets get double-counted; cap the ramp at 20 direct sets and at the user's session-time budget.

### 5. Pain and niggle log with exercise avoidance
- **What the user sees:** "Something hurts?" on the pre-session screen and in the morning check-in: body area, 0–10 pain, "worse after training?" The planner then avoids the lifts that load that area, offers a regression (box squat for knee pain, floor press for shoulder) and a load cap, and keeps the rest of the session. Rule shown in the UI: tolerable pain (≤5/10) that settles by the next morning is acceptable to train through; pain that rises during the set or the next day is a stop signal and a "see a clinician if it lasts 2+ weeks" line. Fitbod-style "never again" lives here too.
- **Data source:** new check-in fields; HealthKit symptom types (`lowerBackPain`, `generalizedBodyAche`, read and written, see `watch-features.md` §4.5); exercise → joint/area mapping in the catalogue.
- **Evidence:** Moderate: strength training is the best-evidenced injury prevention (Lauersen 2018) [E11], so the goal is to keep the user lifting rather than resting; pain-tolerant loading is safe and slightly better short-term (Smith 2017) [E12]. The 5/10 threshold is the pain-monitoring model used in tendinopathy rehab, a clinical convention: label it as such.
- **Size:** M. **Dependencies:** exercise catalogue metadata. **Risks:** the app is not a diagnostic tool; copy must avoid diagnosing and always offer the clinician line.

### 6. Long-term lift goal with a projected range
- **What the user sees:** In Goals, "Bench 100 kg" (or a bodyweight multiple). The Strength card shows the e1RM trend with a shaded projection band ("At your last 12 weeks' rate, 95–105 kg between March and June") and the next block's contribution. Framed as an approach goal: the weekly review reports progress toward it and offers the open alternative ("see how far you get by spring").
- **Data source:** `StrengthProgress` e1RM series (sets ≤10 reps, ±3 kg per `watch-features.md` 3.6), linear fit over the last 12 weeks with the residual SD as the band; `Goals` gains lift targets.
- **Evidence:** Moderate that goal setting raises activity (McEwan 2016, d 0.55) [E13]; specific hard goals help the already-active and can hurt when out of reach (Swann 2020/2026) [E14][E15], so the projection must widen as the goal gets further away and flag "not on the current trend" without a deficit tone. The projection itself is arithmetic, not science: say "if the last 12 weeks continue".
- **Size:** M. **Dependencies:** weekly review (`roadmap.md` Phase 2). **Risks:** novices' linear gains flatten (training-age curve [E26]); cap projections at 6 months and widen the band for intermediate+ lifters.

### 7. Easy cardio scheduled around lifting
- **What the user sees:** The weekly plan gains cardio slots: 1–2 easy sessions (bike, row or incline walk preferred over running on hypertrophy goals) and, when the VO2max trend is flat, one long-interval session (`roadmap.md` Phase 3). Placement rules the user sees: not in the same session as a heavy lower day when strength is the goal; cycling over running for leg-focused hypertrophy; the Watch cardio mode (`watch-features.md` 2.1/2.2) runs it. Cardio minutes count toward the 150/300 weekly band and the strain target.
- **Data source:** `WeeklyPlan`, `TrainingDayPlanner` strain targets, HR zones, `MuscleRecovery.Cardio` (already models leg fatigue from cardio).
- **Evidence:** Strong that concurrent training does not compromise hypertrophy or maximal strength; explosive strength may be attenuated when both are in one session; running but not cycling linked to smaller type I fibres (Schumann 2022; Lundberg 2022) [E16][E17]. The 150/300 minute band is WHO 2020 (already cited in `roadmap.md`).
- **Size:** M. **Dependencies:** Watch cardio mode for the wrist; none for the plan. **Risks:** over-scheduling on low-recovery days: cardio slots obey the same recovery band and the "15-minute version" rule.

### 8. Watch rep counting and bar speed (experimental, opt-in)
- **What the user sees:** On the Watch, during a barbell set, a rep counter that pre-fills the reps field (editable) and, for squats and deadlifts, a "speed" dot per rep; when mean velocity falls about 20–25% from the first rep the Watch taps once: "slowing — about 1–2 reps left". Off by default; labelled "experimental, squat and deadlift only".
- **Data source:** CoreMotion accelerometer/gyroscope on the Watch during the live set (the `HKLiveWorkoutBuilder` session already runs); per-exercise motion templates; nothing leaves the device.
- **Evidence:** Moderate validity: wrist Apple Watch mean velocity r 0.95–0.97 against motion capture in squats, barbell-mounted better (Achermann 2023) [E18]; rep counting accurate for squat and deadlift, poor for bench, with a third-party app (Huber 2021) [E19]; Garmin's manual admits leg exercises may not count [P25]. Velocity-loss autoregulation at ≤25% gave greater strength than larger losses in Hickmott 2022 [E2]; VBT vs percentage overall is a wash to slightly positive (Liao 2021; Zhang 2022) [E20][E21]. The outcome evidence is for barbell-mounted sensors in athletes, so present the RIR hint as a cross-check for the user's own RPE, never a replacement.
- **Size:** L (signal processing, per-exercise templates, battery). **Dependencies:** Watch app, Pick 2 for the RIR comparison. **Risks:** bench and dumbbell work will miscount; false taps are worse than none, so ship squat/deadlift only and require 3+ reps before counting.

**Also worth doing when convenient:** bodyweight progressions for travel days (i, M); `TrainingStatus` auto-promotion suggestion (o, S); per-side reps field (m, S); "never again" and equipment filters on swap (n, S). **Skip:** program library, tempo prescriptions, offline video library, gym crowd, social and streaks.

---

## 4. References

### Product sources
- [P1] Hevy Help, "Set Types in Hevy Explained: Drop Sets, Warm Up Sets and More". https://help.hevyapp.com/hc/en-us/articles/34896293707927-Set-Types-in-Hevy-Explained-Drop-Sets-Warm-Up-Sets-and-More
- [P2] Hevy, "Warm Up Set Calculator" and "Track Workouts" feature pages. https://www.hevyapp.com/features/warm-up-set-calculator/ ; https://www.hevyapp.com/features/track-workouts/
- [P3] Strong, App Store listing (warm-up and plate calculators, Watch app). https://apps.apple.com/gb/app/id464254577
- [P4] RP Strength, "Training Volume Landmarks for Muscle Growth" (vendor). https://rpstrength.com/training-volume-landmarks-muscle-growth/
- [P5] RP Hypertrophy app listing and help centre (pump/soreness/workload feedback). https://help.rpstrength.com/hc/en-us/articles/34825395726743-Muscle-Emphasis-Breakdown
- [P6] JTS Strength, JuggernautAI product page (vendor). https://jtsstrength.com/product/powerlifting-a-i
- [P7] sensai.fit, "Juggernaut AI vs RP Hypertrophy vs Alpha Progression (2026)" (third party). https://www.sensai.fit/blog/juggernaut-ai-vs-rp-hypertrophy-vs-alpha-progression-2026
- [P8] Alpha Progression blog (vendor; set-level targets, blocks, deload). https://alphaprogression.com/en/blog/best-progressive-overload-apps
- [P9] HotelGyms, "Alpha Progression App Review 2024". https://www.hotelgyms.com/blog/alpha-progression-the-gym-logger-app-from-germany
- [P10] Fitbod Help, "How Fitbod Creates Your Workout". https://help.fitbod.me/hc/en-us/articles/360004429814-How-Fitbod-Creates-Your-Workout
- [P11] Fitbod blog, "The Fitbod algorithm" (vendor). https://fitbod.me/blog/fitbod-algorithm
- [P12] Boostcamp, App Store listing (program library, builder, auto progression). https://apps.apple.com/us/app/boostcamp-gym-workout-fitness/id1529354455
- [P13] Boostcamp, "GZCL Program (GZCLP)" page (5RM onboarding, progression rules). https://www.boostcamp.app/coaches/cody-lefever/gzcl-program-gzclp
- [P14] KeyLifts – 531 Workout Log, App Store listing. https://apps.apple.com/us/app/keylifts-531-workout-log/id1437949461
- [P15] Caliber, App Store listing (Strength Score, Strength Balance). https://apps.apple.com/app/id1482405410
- [P16] Tom's Guide on Caliber (five bands, coach texting). https://tomsguide.com/news/forget-chatgpt-this-workout-app-lets-you-text-your-personal-trainer-247
- [P17] Gravitus, App Store listing and site. https://apps.apple.com/us/app/gravitus-gym-workout-tracker/id965383840 ; https://gravitus.com/app
- [P18] Setgraph, App Store listing. https://apps.apple.com/us/app/id1209781676
- [P19] Liftin', App Store listing (Auto progression 2.0). https://apps.apple.com/app/id1445041669
- [P20] 9to5Mac, "Apple announces Fitness+ Gym Strength program with personalized workout plans", 3 Nov 2026. https://9to5mac.com/2026/11/03/apple-announces-fitness-gym-strength-program-with-personalized-workout-plans/
- [P21] FITT Insider, "Apple Fitness+ adds progressive strength coaching", 3 Nov 2026. https://insider.fitt.co/apple-fitness-adds-progressive-strength-coaching/
- [P22] Engadget, "How to use Workout Buddy with Apple Watch and iOS 26". https://www.engadget.com/wearables/how-to-use-workout-buddy-with-apple-watch-and-ios-26-130000922.html
- [P23] Analytics Insight on Workout Buddy (claims rep counting; unconfirmed elsewhere). https://www.analyticsinsight.net/news/workout-buddy-on-apple-watch-the-future-of-personalized-fitness
- [P24] Peloton, "Peloton Strength+ app" (vendor); Engadget launch coverage. https://www.onepeloton.com/blog/peloton-strength-plus-app ; https://engadget.com/apps/peloton-is-introducing-a-new-audio-focused-strength-training-app-222145376.html
- [P25] Garmin manual, "Recording a Strength Training Activity" (rep counting rules). https://www8.garmin.com/manuals/webhelp/GUID-8C2C402F-55AC-431F-9CF2-1442B89CE149/EN-US/GUID-49D892BF-429E-454D-B0C6-D4AE07E9D4A0.html
- [P26] the5krunner, "Garmin Advanced Strength Feature – Detailed Evidence Emerges", Apr 2026 (survey of planned features). https://the5krunner.com/2026/04/02/garmin-strength-training-features-survey/
- [P27] WHOOP, "How WHOOP measures Muscular Load" and "The research and development behind Strength Trainer" (vendor). https://www.whoop.com/je/en/thelocker/how-whoop-measures-muscular-load ; https://www.whoop.com/thelocker/the-research-and-development-behind-strength-trainer

### Evidence
- [E1] Weakley J, et al. The effect of feedback on resistance training performance and adaptations: a systematic review and meta-analysis. Sports Med 2023. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10432365/
- [E2] Hickmott LM, Chilibeck PD, Shaw KA, Butcher SJ. The effect of load and volume autoregulation on muscular strength and hypertrophy: a systematic review and meta-analysis. Sports Med Open 2022;8:9. https://pmc.ncbi.nlm.nih.gov/articles/PMC8762534
- [E3] Halperin I, Malleron T, Har-Nir I, et al. Accuracy in predicting repetitions to task failure in resistance exercise: a scoping review and exploratory meta-analysis. Sports Med 2022;52:377–390. https://sportrxiv.org/index.php/server/preprint/view/67
- [E4] Coleman M, et al. Muscular adaptations in drop set vs. traditional training: a meta-analysis. Int J Strength Cond 2022. https://vuir.vu.edu.au/46296/
- [E5] Sødal LK, et al. Effects of drop sets on skeletal muscle hypertrophy: a systematic review and meta-analysis. Sports Med Open 2023. https://www.pubmed.gov/37523092/
- [E6] Carvalho L, et al. Muscle hypertrophy and strength gains after resistance training with different volume-matched loads: a systematic review and meta-analysis (rest-pause and drop sets vs traditional). Appl Physiol Nutr Metab 2022. Cited via https://lyfta.app/articles/rest-pause-hypertrophy
- [E7] Tsartsapakis I, et al. Advanced resistance training systems in recreationally trained adults: systematic review and meta-analysis. J Funct Morphol Kinesiol 2026;11(1):80. https://www.mdpi.com/2411-5142/11/1/80/xml
- [E8] Pelland JC, Remmert JF, Robinson Z, Hinson S, Zourdos MC. The resistance training dose-response: meta-regressions exploring the effects of weekly volume and frequency on muscle hypertrophy and strength gain. SportRxiv 2024 (preprint). https://sportrxiv.org/index.php/server/preprint/view/460
- [E9] Schoenfeld BJ (Human Kinetics excerpt), "Is the pump a signal for hypertrophy?" (swelling correlates in some data; more research needed). https://us.humankinetics.com/blogs/excerpt/is-the-pump-a-signal-for-hypertrophy
- [E10] Canadian Kinesiology Alliance, "Is post-exercise muscle soreness a valid indicator of muscular adaptations?" (Schoenfeld & Contreras 2013 summary). https://cka.ca/en/kas-current-issues/is-post-exercise-muscle-soreness-a-valid-indicator-of-muscular-adaptations
- [E11] Lauersen JB, Andersen TE, Andersen LB. Strength training as superior, dose-dependent and safe prevention of acute and overuse sports injuries: a systematic review, qualitative analysis and meta-analysis. Br J Sports Med 2018;52:1557–1563. https://bjsm.bmj.com/content/52/24/1557.info
- [E12] Smith BE, Hendrick P, Smith TO, et al. Should exercises be painful in the management of chronic musculoskeletal pain? A systematic review and meta-analysis. Br J Sports Med 2017;51:1679–1687. https://eprints.nottingham.ac.uk/41764/
- [E13] McEwan D, et al. The effectiveness of multi-component goal setting interventions for changing physical activity behaviour: a systematic review and meta-analysis. Health Psychol Rev 2016;10:67–88. https://pmc.ncbi.nlm.nih.gov/articles/PMC7928044
- [E14] Swann C, et al. Updating goal-setting theory in physical activity promotion: a critical conceptual review. Health Psychol Rev 2021;15:34–50. https://informahealthcare.com/doi/full/10.1080/17437199.2019.1706616
- [E15] Swann C, et al. Goal achievement in physical activity trials: systematic review and meta-analysis. Health Psychol Rev 2026 (secondary summary). https://eprints.soton.ac.uk/506038
- [E16] Schumann M, Feuerbacher JF, Sünkeler M, et al. Compatibility of concurrent aerobic and strength training for skeletal muscle size and function: an updated systematic review and meta-analysis. Sports Med 2022;52:601–612. https://pmc.ncbi.nlm.nih.gov/articles/PMC9474354/
- [E17] Lundberg TR, Feuerbacher JF, Sünkeler M, Schumann M. The effects of concurrent aerobic and strength training on muscle fiber hypertrophy: a systematic review and meta-analysis. Sports Med 2022. https://sportrxiv.org/index.php/server/preprint/view/37
- [E18] Achermann B, et al. Velocity-based strength training: the validity and personal monitoring of barbell velocity with the Apple Watch. Sports 2023;11(7):125. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10383699/
- [E19] Huber C, Lüthy S, Lorenzetti S. Validation of a smartwatch-based workout analysis application in exercise recognition, repetition count and prediction of 1RM in the strength training-specific setting. Sports 2021;9(9):118. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8471343/
- [E20] Liao K-F, et al. Effects of velocity based training vs. traditional 1RM percentage-based training on strength, jump, sprint and change of direction: a systematic review with meta-analysis. PLoS ONE 2021;16:e0259790. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8601436/
- [E21] Zhang M, et al. Comparison of velocity and percentage-based training on maximal strength: meta-analysis. Int J Sports Med 2022. https://lida.sport-iat.de/ta/Record/4078288?lng=en
- [E22] Kotarsky CJ, et al. Effect of progressive calisthenic push-up training on muscle strength and thickness. J Strength Cond Res 2018;32:651–659. https://katalog.lib.cas.cz/KNAV/EdsRecord/cmedm,29466268 ; summary https://www.naseinc.com/blog/comparison-pushup-vs-bench-press/
- [E23] Plotkin D, et al. Progressive overload without progressing load? The effects of load or repetition progression on muscular adaptations. PeerJ 2022;10:e14142. https://peerj.com/articles/14142
- [E24] Schoenfeld BJ, Ogborn DI, Krieger JW. Effect of repetition duration during resistance training on muscle hypertrophy: a systematic review and meta-analysis. Sports Med 2015;45:577–585. https://pubmed.ncbi.nlm.nih.gov/25601394/
- [E25] Kassiano W, et al. Comparison of muscle growth and dynamic strength adaptations induced by unilateral and bilateral resistance training: a systematic review and meta-analysis. Sports Med 2025. https://pubmed.ncbi.nlm.nih.gov/39794667/
- [E26] 17-year powerlifting dataset on strength gain rate by training age (secondary summaries only; not re-verified). https://sci-sport.com/en/?p=87664

Already cited in `competitors.md` and reused here: Helms 2018 (RPE vs % loading), Williams 2017 and Grgic 2017 (periodisation), Iversen 2021 (time-efficient training), Schoenfeld 2017 (10–20 sets), Coleman 2024 (deload RCT), Bell 2023 (deload practice), Mazeas 2022 (gamification fades).
