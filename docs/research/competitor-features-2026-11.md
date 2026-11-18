# Tracking, visualizing and sharing activities: what leading apps offer, what the evidence says, what Tensile should add (18 Nov 2026)

**Question.** Which features do the leading cardio, multi-sport and lifting apps offer for tracking, visualizing and sharing activities; which of them Tensile already has; and which to add, change or leave out, judged by the published evidence (CLAUDE.md rule) and by how useful they are for seeing and sharing the metrics Tensile already computes. The owner wants users to be able to see and share all the important metrics.

**Related files.** `competitors.md` (3 Nov, broad matrix), `competitors-2026-11.md` (9 Nov, lifting, Watch and user complaints; it already recommended an image share card, CSV export and a block report), `behaviour-change.md` (self-monitoring, social support, gamification), `workout-zones-2026-11.md` (zones), `evidence-audit-2026-11.md`. This file adds the cardio and multi-sport side, the visualization and sharing side, and a concrete share and export spec.

**How it was researched.** Web search on 18 Nov 2026, plus reading `App/`, `Watch/`, `Widget/`, `Shared/` and `Packages/AppCore`. Most product facts come from vendor manuals and help pages (Garmin, Polar, Strava, Hevy, TrainingPeaks), launch press and specialist reviewers (DC Rainmaker, the5krunner, Wareable). Many product pages could not be fetched from the sandbox, so some facts come from search-result summaries of those pages; product claims that rest only on secondary or competitor blogs are marked **(secondary)**. Paper findings are from abstracts or PubMed/PMC records unless stated. Nothing here is copied from any app; app names are UX references only.

**Evidence grades used below.** *Strong*: consistent meta-analyses or position stands on a health or fitness outcome. *Moderate*: a meta-analysis with heterogeneity or a few good trials, or strong evidence for an underlying technique (for example, self-monitoring) that the feature delivers. *Weak*: single trials, lab-only or surrogate outcomes, mixed reviews. *None*: no outcome evidence (the feature may still be a useful way to see or move data). *Misleading*: evidence that the number misleads or is unvalidated.

---

## Summary

- **Tensile already covers the core of what the best apps measure**: route maps coloured by speed, heart rate or elevation, splits, heart-rate zones with one-minute recovery, a Watch cardio and sports mode (30 activities), interval sessions, Banister-TRIMP strain plus session-RPE lifting load, a 7-vs-28-day cardio and muscular load description that deliberately avoids ACWR injury claims, recovery and sleep scores, VO₂ max trend and a walking fitness check, e1RM charts, personal records by year, muscle maps, weekly sets per muscle, a block report, a weekly review, Live Activities and complications.
- **The big gap is visualization across activities and sharing.** Sharing today is two plain-text `ShareLink`s (workout summary, block report). There is no share image, no GPX or CSV export, no route privacy, no calendar of all activities, no cardio best efforts, no weekly zone-minute trend, and no export or backup at all.
- **Evidence for sharing itself is modest but real.** Self-monitoring with feedback and goal review works (Michie 2009; Harkin 2016, d = 0.40, larger when progress is reported to others). Online social features raise activity only slightly and inconsistently (Tong & Laranjo 2018; Maher 2014); comparison helps more than support (Zhang 2016). So build sharing as private-by-default, user-tapped exports of real metrics, not a social network.
- **Route privacy is a must, and simple endpoint hiding is not enough.** Attacks recovered the hidden home location for 84% (Hassan 2018) and up to 85% (Dhondt 2022) of users of start/end privacy zones, mostly from exact distances. Tensile's share cards and GPX should trim routes near saved places, vary the trimmed length and round the distance shown.
- **Leave out**: ACWR injury risk, a Garmin-style "readiness/Body Battery/recovery time" number on top of the current recovery score, calories burned as a headline on share cards, TSB "form" and peaking predictions, training-status labels from noisy VO₂ max estimates, running-dynamics coaching, public leaderboards/segments/badges/streaks, global heatmaps and live location sharing that needs a server.

---

## 1. What the leading apps offer (2025–2026)

### 1a. Cardio and multi-sport platforms

| App | Tracking and analysis | Visualization | Sharing and export | Planning |
|---|---|---|---|---|
| **Garmin Connect + watches** | Firstbeat-based metrics: Training Effect (aerobic/anaerobic), acute load (EPOC-based, last ~7 days), **Load Focus** (low aerobic / high aerobic / anaerobic over 4 weeks against targets), **Training Status** (Productive, Maintaining, Peaking, Overreaching, Unproductive, Recovery; from VO₂ max, acute load and HRV status trends) [G1][G2]; **HRV Status** (7-day average against your range) [G1]; **Training Readiness** 0–100 (sleep, HRV, recovery time, load) [G3]; **recovery time** (hours to the next hard session); **performance condition** (−20 to +20 after 6–20 min, from pace, HR and HRV) [G4]; **lactate threshold** (estimated, chest strap on some models) [G4]; **race predictor** (VO₂ max + training history) [G4][G5]; running dynamics (cadence, GCT, vertical oscillation; pod or HRM-Pro); ClimbPro (climb profile on a loaded course); Body Battery (energy 0–100). Rep counting for strength | Calendar, reports (weekly/monthly totals per sport), performance stats charts, maps with HR/pace overlays, laps | Share activity image and link; GPX/TCX/FIT export per activity on the web; full data export via Garmin account; LiveTrack (live location link, server-based) | Garmin Coach plans, daily suggested workouts, structured workouts sent to the watch |
| **Apple Fitness + Workout app** (watchOS 26/27, iOS 26/27) | Custom workouts (warm-up / work / recovery / cool-down; built on the iPhone in iOS 26) [A1][A2]; **Race Route** against your last or best time on a route repeated twice; **Pacer** [A1]; heart-rate zones and zone alerts, splits, running form (stride length, ground contact time, vertical oscillation), running power, **Multisport** with automatic transitions (triathlon) [A3][A4]; **Training Load** from a 1–10 **effort rating** (auto for cardio, typed for strength) against a 28-day baseline [A5][A6]; Workout Buddy (spoken, on-device) | Activity rings, Trends, workout summary with maps, zones and splits, Training Load chart | Activity sharing with friends and competitions; Health export (XML); no GPX export in Health [A7] | Custom workouts; Apple Fitness+ video plans |
| **Strava** | **Relative Effort** (HR or perceived exertion) [S1]; **Fitness & Freshness** (Fitness, Fatigue, Form from Relative Effort or power; subscription) [S2]; **Best Efforts** for runs 400 m–50 km, lifetime and annual, top three all-time; rides added 2024 [S3][S4]; segments and live segments; **Athlete Intelligence** (AI summary of pace, HR, elevation, Relative Effort after upload) [S5]; May 2026 strength overhaul: sets/reps/weight log, **auto-filled muscle maps**, five strength share formats, 14 partner integrations (Hevy, Fitbod, Garmin, Whoop...) [S6][S7]; guided strength workouts from Oct 2026 [S8] | Maps, personal heatmaps, monthly stats, **Year in Sport** recap [S9] | Feed, kudos, flybys, clubs; **Sticker Stats** (transparent overlay for Instagram stories, spring 2025) [S10]; share images; GPX export of routes/activities; **privacy zones** (hide up to 1 mile at the start/end near an address or anywhere) and whole-map hiding [S11] | Routes (AI route generation, point-to-point routing from the heatmap, 2025) [S12]; Runna plans (acquired April 2025, separate app) [S13] |
| **TrainingPeaks** | TSS per workout; **Performance Management Chart**: CTL (fitness, ~42-day weighted average), ATL (fatigue, ~7-day), TSB (form = yesterday's CTL − ATL) [T1][T2] | PMC, calendar, dashboards | Exports, coach sharing | Structured workouts, coach plans |
| **Polar Flow** | **Training Load Pro**: Cardio Load (TRIMP), short-term Strain vs long-term Tolerance, Muscle Load (needs a power meter), Perceived Load (RPE × duration) [P1][P2]; Nightly Recharge; Running Index | Calendar, diary, progress reports | Share image; GPX/TCX/CSV export | Training targets, FitSpark |
| **COROS (EvoLab)** | **Base Fitness** (6 weeks) vs **Load Impact** (7 days), fatigue 0–100 in five zones, race predictor, running fitness [C1] | Training Hub calendar, charts | Export to FIT/GPX/TCX | Training plans, structured workouts |
| **Suunto** | Q4 2025 app: multisport with auto transitions (triathlon, SwimRun), interval structure on screen, per-sport lap data and graphs, AI coach, Recovery tab [U1][U2] | Charts per leg | Share, export | Suunto Coach plans |
| **Runna** (Strava) | Plans 5 km–ultra, pace guidance, "not feeling 100%", heat-adjusted paces, Watch/Garmin/COROS sync [R1] | Plan calendar | Auto-upload to Strava | Adaptive plans |
| **Nike Run Club** | ~300 audio-guided runs, plans [N1] | Run history | Trophies and badges; live location sharing with friends; in-run "cheers" [N1] | Plans |
| **Gentler Streak** | **Activity Path** (personal "rest to active" zone from recent load; daily, 10- and 30-day views), RPE synced with Apple Fitness, "set status" for sick/injured, monthly recaps [GS1] | Path chart, monthly recap | Recap images | Kind, non-punishing suggestions |
| **Athlytic** | Recovery (HRV, RHR), Exertion 24/7 with a target range from recovery, workout suggestions with projected exertion [AT1] | Recovery vs exertion trend, widgets, complications | — | Suggestions |

### 1b. Lifting apps

| App | Set logging UX | PRs, 1RM, volume | Visualization | Sharing | Other |
|---|---|---|---|---|---|
| **Hevy** | Previous-set values shown inline; supersets; plate and warm-up calculators [H1] | PRs, e1RM, volume charts [H2] | Muscle distribution chart (30 days free; longer ranges Pro), body diagram of last 7 days [H3] | **Shareable images** of PRs, volume and muscle distribution with light/dark/transparent background; any chart can be shared as an image [H4]; social feed; routine sharing; Strava integration | **Live Activity**: next set, weight and reps, rest timer with ±15 s and skip, mark sets complete from the lock screen [H5]; Watch app |
| **Strong** | Fast, minimal; Watch logging with or without phone **(secondary)** | e1RM and volume charts, PR list | Charts | **CSV export** [ST1] | Plate and warm-up calculators [ST1] |
| **Fitbod** | Generated sessions | e1RM | **Muscle recovery heat map** with 0–100% per muscle [F1] | Muscle heat map appears on the Strava activity [F2] | Equipment profiles |
| **JEFIT** | Logger, big library | PRs, charts | **BodyMap** (muscle focus and recovery status, Nov 2025) [J1] | Community feed | AI adaptive plans |
| **Liftosaur** | Scriptable progression, phone-free Watch app **(secondary)** | Graphs | — | Import/export, API | See `competitors-2026-11.md` |
| **Strava strength** (2026) | Sets, reps, weight | — | Auto muscle maps shaded by sets (Sept 2026) [S7][S8] | Five strength share formats [S6] | Partner imports |

### 1c. What stands out

1. **Share images are standard** for both cardio (map + stats) and lifting (volume, PRs, muscle map). Hevy lets any chart become an image; Strava's transparent stickers let people overlay stats on their own photos.
2. **Muscle maps now cross into cardio apps** (Strava 2026), and every lifting app has one.
3. **Load models** are everywhere (Garmin acute load and Load Focus, Polar strain vs tolerance, COROS base fitness vs load impact, TrainingPeaks CTL/ATL/TSB, Apple Training Load, Strava Fitness & Freshness). They are all versions of the Banister impulse-response idea; none publishes a validation against injury or performance outcomes.
4. **Readiness scores** are everywhere and opaque (Section 4).
5. **Personal bests by distance** (Strava Best Efforts, Garmin PRs) and **year-in-review recaps** are the main progress views for cardio.
6. **Route privacy** is a standard control in Strava (start/end hiding, map hiding).

---

## 2. Features by category, and where Tensile stands

Legend: ✅ has it, ◐ partly, ✗ missing.

### 2a. Cardio metrics and analysis

| Feature | Best reference | Tensile | Notes |
|---|---|---|---|
| Route map coloured by speed/HR/elevation | Garmin, Strava, Apple | ✅ `CardioWorkoutDetailView`, `CardioRoute` | Already as good as most |
| Splits per km/mile with HR | Apple, Garmin | ✅ | — |
| Heart-rate chart, zones, one-minute HR recovery | Apple, Garmin, Polar | ✅ `CardioHeartSummary`, `ZonesDetailView` | Zones: reserve, Apple's or custom (`HeartRateZoneScheme`) |
| Elevation profile chart | Garmin, Strava | ◐ map colour only | Add a small elevation-over-distance chart |
| Pace/speed chart over the workout | Strava, Garmin | ◐ map colour and splits | Add with HR overlay |
| Interval/lap breakdown (work vs recovery) | Garmin, Suunto, Apple | ◐ `IntervalSession` runs on the Watch; the detail screen shows no per-interval table | Add per-interval HR and pace |
| Best efforts (fastest 1 km, 5 km...) | Strava | ✗ | See rec. B7 |
| Race predictor | Garmin, COROS | ✗ | Weak evidence, Section 4 |
| Running dynamics, running power | Garmin, Apple, Stryd | ✗ | Weak/none for health, Section 4 |
| VO₂ max per workout and trend | Apple, Garmin | ✅ `CardioDetailView`, `VO2MaxEstimate`, `FitnessCheck` | Keep the error caveats |
| Lactate threshold, performance condition | Garmin | ✗ | Unvalidated, leave out |

### 2b. Lifting metrics and analysis

| Feature | Best reference | Tensile | Notes |
|---|---|---|---|
| Fast set logging, previous values, RIR | Strong, Hevy | ✅ live workout, Watch effort step | See `competitors-2026-11.md` rec. 1 |
| PR detection and history | Hevy, Strong | ✅ `PRHistory`, `PRYearView` | — |
| e1RM estimate and chart | Strong, Hevy | ✅ `OneRepMax` (Epley with RIR), `LiftProgressView` | Show it as a range, Section 4 |
| Volume charts (session, per lift) | Hevy, Strong | ◐ per lift and session; no weekly tonnage or sets trend chart across weeks | Weekly hard sets per muscle exist this week only |
| Muscle heat map | Fitbod, JEFIT, Hevy, Strava | ✅ `MuscleMap`, `MusclesDetailView` | Rest status or this week's sets |
| Plate calculator | Hevy, Strong | ✅ built into targets | — |
| Supersets | Hevy | ✅ `Supersets` | — |
| Live Activity / Dynamic Island | Hevy | ✅ `WorkoutLiveActivityWidget` | Check it supports ±15 s and complete-set actions |
| Block / long-term report | RP, Whoop | ✅ `BlockReport` | Text share only |

### 2c. Multi-sport and other activities

| Feature | Best reference | Tensile | Notes |
|---|---|---|---|
| Record many sports with their own HealthKit type | Apple, Garmin | ✅ Watch cardio mode: 30 activities (cardio, court and field sports, climbing, snow) | — |
| Import workouts from other devices | all | ✅ reads Apple Health (Garmin, Apple Workout...) | — |
| Multisport (triathlon) with transitions | Apple, Suunto, Garmin | ✗ | Niche for this user base; leave to Apple's Workout app (it writes to Health and Tensile reads it) |
| One history across lifting, cardio and sports | Garmin calendar, Strava feed | ◐ separate `WorkoutHistoryView` (gym) and `CardioHistoryView` (90 days) | See rec. B6 |

### 2d. Training load and recovery

| Feature | Best reference | Tensile | Notes |
|---|---|---|---|
| Per-workout load (TRIMP / sRPE / effort) | Polar, Apple, Strava | ✅ strain = max(HR TRIMP, sRPE) | Writes effort to the HKWorkout |
| Acute vs chronic load description | Garmin, Polar, COROS | ✅ `TrainingLoadCalculator`, cardio and muscular | Correctly framed as description, not injury risk |
| Load focus / intensity mix | Garmin | ◐ zone minutes per day; no weekly mix chart | See rec. B8 |
| Fitness/Fatigue/Form (CTL/ATL/TSB) | TrainingPeaks, Strava | ✗ | Leave the "form" number out, Section 4 |
| HRV status vs personal range | Garmin, Athlytic | ✅ recovery uses a 7-day HRV band | — |
| Readiness / Body Battery / recovery hours | Garmin, Whoop, Oura, Apple (iOS 27.3) | ✅ one recovery score, labelled as the app's own | Don't add more, Section 4 |

### 2e. Visualization

| Feature | Best reference | Tensile | Notes |
|---|---|---|---|
| Week strip of daily strain | Whoop, Bevel | ✅ `WeekStrip` | — |
| Month/year calendar of all activities | Garmin, TrainingPeaks | ✗ | Rec. B6 |
| Weekly totals by type (time, distance, sets, zone minutes) | Garmin reports, Strava | ◐ weekly review numbers; no trend over weeks | Rec. B8 |
| Year-in-review recap | Strava, Gentler Streak | ◐ `PRYearView` lists records by year | Rec. B12 |
| Personal route heatmap | Strava | ✗ | Consider later, private only |

### 2f. Sharing and export

| Feature | Best reference | Tensile | Notes |
|---|---|---|---|
| Workout share image (map, stats, zones) | Strava, Garmin | ✗ (text only) | Rec. B1 |
| Lifting share image (volume, PRs, muscles) | Hevy, Strava | ✗ (text only) | Rec. B3 |
| Transparent stats overlay | Strava Sticker Stats | ✗ | Part of B1/B3 |
| Chart-as-image | Hevy | ✗ | Rec. B9 |
| Weekly summary card | Garmin, Strava monthly stats | ✗ | Rec. B4 |
| GPX/TCX export | Garmin, Strava, third-party HealthKit exporters [A7] | ✗ | Rec. B5 |
| CSV export / backup | Strong | ✗ | Rec. B5 |
| Route privacy zones | Strava | ✗ | Rec. B2 |
| Social feed, kudos, leaderboards | Strava, Hevy | ✗ | Leave out |

### 2g. Planning

Tensile is ahead of most here (weekly plan, adaptive week, blocks, easy cardio, one offered interval session, calendar sync). Gaps worth noting: no route library, no race goal or race plan. Runna and Garmin Coach own race plans; see Consider later.

---

## 3. What Tensile already does (inventory, 18 Nov 2026)

**Cardio and sports.** Watch cardio mode with 30 activities saved under their own HealthKit types, a target band with wrist taps and live zone clock (`CardioZoneTracker`, `Watch/WatchCardio*`), GPS route recording with `HKWorkoutRouteBuilder` (`Watch/WatchRouteRecorder.swift`), start-from-iPhone (`CardioStartSheet`). Detail screen with route map coloured by speed, heart rate or elevation, totals, HR chart, zones, one-minute recovery, Apple's VO₂ max from that workout, and splits with HR (`CardioWorkoutDetailView`, `CardioRoute`). 90-day cardio history (`CardioHistoryView`). Interval session (4×4) sent to the Watch (`IntervalSession`, `HardCardio`) and easy cardio planning (`CardioPlanner`).

**Lifting.** Plate-exact planner, RIR autoregulation, set kinds, supersets, warm-ups, live workout with rest pill and PR badges, Watch logging, Live Activity, summary with volume, ▲/▼ vs last time, records and muscles (`WorkoutSummary`), per-lift e1RM chart (`LiftProgressView`), records by year (`PRYearView`), muscle map and weekly hard sets per muscle (`MusclesDetailView`, `WeeklySetsCard`), block report (`BlockReport`).

**Load and recovery.** Strain (Banister TRIMP plus Foster sRPE), recovery (HRV/RHR/sleep z-scores), sleep score, 7-vs-28-day cardio and muscular load as description only (`TrainingLoadCalculator`), muscle recovery, illness flag, learned max HR (`ObservedMaxHeartRate`).

**Visualization.** Rings, gauges, sparklines, week strip, zone bars, HRV 90-day chart, VO₂ max trend, weekly review, widgets and Watch complications.

**Sharing.** Text `ShareLink` in `WorkoutSummaryView` (`SummaryFormat.shareText`) and `BlockReportView`. No image, file export, GPX, CSV, or backup. `ProgressPhotosModel` uses `UIGraphicsImageRenderer` only for photos.

---

## 4. Evidence for each candidate feature

### 4a. The techniques behind tracking, visualizing and sharing

| Technique | Evidence | Grade | What it means for Tensile |
|---|---|---|---|
| **Self-monitoring with feedback and goal review** | Interventions that combine self-monitoring with another self-regulation technique had effect 0.42 vs 0.26 (Michie et al., Health Psychol 2009, 122 evaluations) [E1]. Prompting progress monitoring raised goal attainment d = 0.40, more when progress was **recorded physically or reported to others** (Harkin et al., Psychol Bull 2016, 138 studies) [E2] | Moderate–strong | Every new view should close a loop (goal → number → review). Sharing a summary is a form of "reporting to others" |
| **Wearable activity trackers** | Umbrella review of 39 reviews, 163,992 people: SMD 0.3–0.6, about 1,800 more steps and 40 more minutes of walking a day, ~1 kg weight loss (Ferguson et al., Lancet Digit Health 2022) [E3]. App interventions: SMD 0.35 (Laranjo et al., Br J Sports Med 2021) [E4] | Strong (for tracking overall) | Tensile's data pipeline is this. New features add little unless they increase use or feedback |
| **Feedback on lifting performance** | Feedback improved acute output and, over a training cycle, strength, speed and technique (Weakley et al., Sports Med 2023, 20 studies) [E5] | Moderate | Supports PRs, ▲/▼ vs last time, e1RM trend |
| **Online social features / social support** | Social features in mHealth apps: non-significant pooled effect on activity (Tong & Laranjo, npj Digit Med 2018; 4 RCTs pooled) [E6]. Online social networks: "very modest evidence" (Maher et al., J Med Internet Res 2014) [E7]. Facebook-based interventions: significant gain in total activity across 11 pooled studies (2022 meta-analysis) [E8] | Weak–moderate, mixed | Sharing is worth offering, not worth building a network |
| **Social comparison vs support** | 790 students, 11 weeks: comparison networks raised class attendance ~90% over control; support-only networks did no better than control (Zhang et al., Prev Med Rep 2016) [E9] | Weak (one RCT) | If people share, comparison with their own past (PRs, last week) is the safer use; no leaderboards (privacy, bloat, Section 4c) |
| **Gamification, badges, streaks** | g = 0.42 overall, g = 0.15 at ~14-week follow-up (Mazeas et al., J Med Internet Res 2022, 16 RCTs) [E10]. Displaying a broken streak lowers later engagement regardless of actual behaviour (Silverman & Barasch, J Consum Res 2023;49(6):1095) [E11] | Weak, fades; streaks can backfire | Leave out badges and streaks (already the app's policy, `behaviour-change.md` §20) |

### 4b. Metrics

| Metric / feature | Evidence | Grade | Verdict |
|---|---|---|---|
| **Heart-rate zone minutes and weekly moderate/vigorous minutes** | WHO 2020: 150–300 moderate or 75–150 vigorous minutes a week (Bull et al., Br J Sports Med 2020) [E12]. 15–20 vigorous minutes a week linked with 16–40% lower mortality (Ahmadi et al., Eur Heart J 2022) [E13]. Fixed-percentage zones match individual thresholds poorly (Iannetta et al., MSSE 2020) [E14] | Strong (minutes); zones are labels | Show weekly minutes and zone mix; keep the "zones are labels" caveat |
| **Polarized intensity mix (Load Focus)** | Polarized beat threshold training for endurance performance in 3 small trials of trained athletes (Rosenblat et al., JSCR 2019) [E15]; polarized better for VO₂peak, not other surrogates (Oliveira et al., Sports Med 2024) [E16] | Weak–moderate, trained endurance athletes only | Show the mix as a picture, no target ratio for lifters |
| **Intervals for VO₂ max** | Intervals raise VO₂ max ~5.5 mL/kg/min vs no exercise and more than continuous training (Milanović et al., Sports Med 2015) [E17]. Higher cardiorespiratory fitness goes with lower all-cause mortality (Mandsager et al., JAMA Netw Open 2018 [E18]; Lang et al., Br J Sports Med 2024 [E19]) | Strong | Interval breakdown and VO₂ max trend are worth showing and sharing |
| **VO₂ max estimates from wearables** | Exercise-based estimates: bias −0.09, limits of agreement about ±10 mL/kg/min; resting-based ones overestimate (Molina-Garcia et al., Sports Med 2022, 14 studies) [E20]. Apple Watch Series 7: MAPE 15.8% vs lab, reads fit people low (Caserman et al., JMIR Biomed Eng 2024) [E21] | Moderate at group level, poor for one person | Show trend with an error band; never a "fitness age" or training-status label from it |
| **Session RPE / effort rating (Apple Training Load)** | sRPE (RPE × minutes) tracks HR-based load across sports (Foster et al., JSCR 2001) [E22]; validity and influencing factors reviewed (Haddad et al., Front Neurosci 2017) [E23] | Moderate | Already in strain. Keep writing effort to Health |
| **RPE/RIR autoregulation** | All autoregulated protocols raised 1RM (Larsen et al., PeerJ 2021, 14 studies) [E24]; velocity-loss autoregulation meta-analysis (Hickmott et al., Sports Med Open 2022) [E25]; RIR predictions off by about one rep (Halperin et al., Sports Med 2022) [E26]; RIR-based RPE scale (Zourdos et al., JSCR 2016 [E27]; Helms et al., Strength Cond J 2016 [E28]) | Moderate | Already built; keep |
| **e1RM from reps (Epley, Brzycki)** | Reps at a given %1RM vary by exercise (leg press vs bench differ) though little by sex, age or training status (Nuzzo et al., Sports Med 2024, 952 tests, 269 studies) [E29]. Equations are most accurate from ≤ 10 reps and differ by lift (LeSuer et al., JSCR 1997) [E30] | Moderate as a trend, weak as an exact number | Show e1RM as "≈", hide it above ~10–12 reps, and say it's an estimate on share cards |
| **Weekly hard sets per muscle (muscle maps)** | Dose-response between weekly sets and hypertrophy (Schoenfeld et al., J Sports Sci 2017) [E31]; diminishing returns, stronger for strength (Pelland et al., Sports Med 2026;56(2):481) [E32] | Moderate (for the number behind the map); none for the map itself | Keep maps tied to sets, not invented "% recovered" |
| **Banister fitness-fatigue model / CTL-ATL-TSB** | Parameters depend on starting values and fitting method, general constants not recommended (Vermeire et al., IJSPP 2022) [E33]; no model family preferred for prediction (Imbach et al., Sci Rep 2022) [E34]; fatigue terms poorly identifiable and add no prediction (Marchal et al., Sci Rep 2025) [E35]. TrainingPeaks itself says TSB is "not a predictor of performance" [T2] | Weak as a predictor | A long-term load line is fine as description; no "form" or "peak day" claims |
| **ACWR / injury-risk ratio** | Conceptual and statistical flaws, no causal evidence (Impellizzeri et al., IJSPP 2020) [E36]; "time to dismiss the ACWR" (Impellizzeri et al., Sports Med 2021) [E37]; coupled ratios are biased (Lolli et al., Br J Sports Med 2019) [E38] | Misleading | Already avoided in `TrainingLoadCalculator`; keep it that way |
| **HRV-guided training** | HRV-guided training gave a small extra VO₂ max gain over pre-planned training (ES 0.187 between groups) in endurance athletes (Granero-Gallegos et al., IJERPH 2020) [E39]; HRV trend monitoring rationale (Plews et al., Sports Med 2013) [E40] | Moderate (small effect) | Already used (7-day band rule) |
| **Proprietary readiness / Body Battery / recovery time** | Review of 14 composite scores from 10 makers: no formulas disclosed, little validation, inputs double-counted (Doherty et al., Transl Exerc Biomed 2025) [E41] | Misleading / none | Don't add another composite; Tensile's recovery already says it's the app's own |
| **Calories burned** | No wrist device had energy-expenditure error under 20%; up to 93% (Shcherbina et al., J Pers Med 2017) [E42]; accuracy varies by activity, large heterogeneity (O'Driscoll et al., Br J Sports Med 2020) [E43] | Misleading as a precise number | Keep off share cards by default; if shown, as a range |
| **Running dynamics (GCT, vertical oscillation)** | Biomechanical injury risk factors: sparse, inconsistent prospective evidence (Ceyssens et al., Sports Med 2019) [E44] | None for health | Leave out coaching on them |
| **Running power** | Stryd: valid contact time, underestimates absolute power (Imbach et al., Sports 2020) [E45]; stable for intensity near threshold (Sensors 2023) [E46] | Weak; device-specific | Consider later, display only if Health has it |
| **GPS distance** | 8 watches, MAPE 3.2–6.1%, underestimation up to 9% in obstructed areas (Gilgen-Ammann et al., JMIR mHealth 2020) [E47] | — (measurement) | Round shared distances; show pace splits as approximate under trees and buildings |
| **Racing a previous self (Race Route, virtual partner)** | 14 recreational cyclists rode a 2 km trial faster against an avatar of their own best (Corbett et al., MSSE 2012) [E48] | Weak (acute, lab) | Consider later |
| **Race time predictor** | Garmin bases it on VO₂ max estimates and history [G4]; given the ±10 mL/kg/min error [E20], predictions inherit it. No independent validation found | None | Leave out or consider much later with ranges |
| **Lactate threshold, performance condition** | Vendor estimates [G4]; no independent validation found in this search | None | Leave out |

### 4c. Privacy evidence (for sharing routes)

- **Endpoint privacy zones leak.** In 21 million public posts, about 16.5% of users had privacy zones; an attack exposed the protected location for 84% of them (Hassan et al., USENIX Security 2018) [E49]. A distance-and-street-grid attack on 1.4 million Strava activities recovered the hidden location for up to 85% of zones; bigger zones reduce success, sparse street grids make it easier, and exact distance values (0.1 m precision) drive the attack (Dhondt et al., ACM CCS 2022) [E50][E51].
- **Aggregated heatmaps leak too.** Strava's global heatmap revealed military bases in 2018 [E52].
- **Implication for Tensile.** A share image or GPX that hides the first and last few hundred metres is not enough if it also prints the exact distance. Trim by a varying length beyond a radius, round distances, and offer "hide map" (Section 6).

---

## 5. Recommendations

Effort: **S** about a day or two, **M** about a week, **L** several weeks. "Evidence" grades the health or adherence effect of the feature; many sharing features are graded on the technique they deliver (self-monitoring, reporting to others). Where a feature only shows or moves data Tensile already computes, it says so.

### 5a. Build now (ranked)

| # | What to build | UX reference | Evidence | Expected health effect | Effort | Where in Tensile |
|---|---|---|---|---|---|---|
| **B1** | **Cardio workout share card** (image): map snapshot with the route coloured as on screen and privacy trimming (B2), activity, date, distance, time, pace/speed, elevation gain, average HR, a zone bar (minutes per zone), the best 3–5 splits or all splits as a mini bar chart, optional strain and VO₂ max from that workout. Three layouts: full card, map-only, **transparent stats overlay** for the user's own photo. Share sheet only on tap | Strava (card and Sticker Stats), Garmin | Moderate (reporting progress to others, Harkin 2016 [E2]; tracking [E3]); weak for social features [E6] | Small adherence gain for those who share; makes existing metrics portable | M | `CardioWorkoutDetailView` toolbar share button; render with `ImageRenderer` and an `MKMapSnapshotter` image (a live `Map` does not render into `ImageRenderer`); layout in `App/Design/SummaryCard.swift` |
| **B2** | **Route privacy** (prerequisite for B1 and B5): Settings › Privacy › Route privacy. (a) Saved places (home, work; picked on a map, stored on device) with a radius (200 m–1 km, default 500 m): trim any route part within the radius **plus a random 50–200 m beyond it**, per workout, kept stable for that workout. (b) "Hide start and end everywhere" with the same trimming. (c) "Hide map" per share. (d) When trimming, **round the shown distance to 0.1 km/mi** and leave out exact start time (date only) by default | Strava privacy zones [S11], improved per [E49][E50] | Strong evidence for the risk; no health effect | Prevents real harm (home location) | S–M | AppCore: `RoutePrivacy` (pure, tested on Linux beside `CardioRoute`); Settings › Privacy; applied in B1, B5, B10 |
| **B3** | **Lifting session share card**: title, date, duration, working sets, total volume (in the user's unit), top 3 exercises with best set and ▲/▼ vs last time, **PRs** (e1RM marked "≈"), a front/back **muscle map** of hard sets, optional strain and average HR. Light, dark and transparent variants | Hevy share images [H4], Strava strength formats [S6] | Moderate (feedback, Weakley 2023 [E5]; reporting, [E2]) | Small adherence gain; motivation for lifters who share | S–M | `WorkoutSummaryView` (keep text share as a second option); `MuscleMap` reused |
| **B4** | **Weekly summary card** from the Monday review: days trained, strength days vs WHO's 2+, moderate/vigorous minutes vs 150–300 (vigorous counted double), hard sets per muscle group (mini map), top PRs, cardio distance by type, average sleep and recovery (off by default: health data). Shareable, and saved as "last week" in the review | Garmin weekly report, Strava monthly stats [S9] | Moderate (goal review and progress reporting, Michie 2009 [E1], Harkin 2016 [E2]; WHO targets strong [E12]) | Reinforces the weekly loop that already has evidence | S–M | `WeeklyReviewView` share button; numbers already in `WeeklyReviewData` |
| **B5** | **Export**: Settings › Data › Export. (a) **CSV** of all sets (one row per set: date, workout, duration, exercise, set order, set kind, weight kg, reps, RIR/RPE, notes; columns close to Strong's export so other apps can read it, checked against a real export before claiming compatibility), (b) **CSV** of cardio and sports (date, type, source, duration, distance, elevation gain, avg/max HR, minutes per zone, strain, effort, VO₂ max if any), (c) **CSV** of daily scores (strain, recovery, sleep, HRV, RHR, steps), (d) **JSON backup** of everything Tensile owns (SwiftData and stores), (e) per-workout **GPX** (route, elevation, time, HR via the Garmin TrackPoint extension) and **TCX** (keeps HR and laps for upload to Strava, Garmin Connect or TrainingPeaks [A7]), all privacy-trimmed by default with a "full route" switch. Files go to the share sheet or Files; nothing is uploaded | Strong (CSV), Garmin/Strava (GPX/TCX), Polar | None for health; addresses lost-data complaints (`competitors-2026-11.md` §2) | Trust and data portability; lets users use Strava without Tensile uploading | S (CSV/JSON) + S (GPX/TCX) | New `DataExport` service; GPX/TCX/CSV writers in AppCore with tests; Settings › Data; per-workout share menu |
| **B6** | **One activity calendar**: month grid (and a scrolling year strip) of every session, lifting, cardio and sports together, coloured by type, dot size by strain; tap a day for its workouts. Replaces the split between gym History and the 90-day cardio list | Garmin calendar, TrainingPeaks | Moderate (self-monitoring visibility [E1][E3]) | Helps users see consistency; supports the "consistency not streaks" policy | M | Fitness › Workouts › History (merge `WorkoutHistoryView` and `CardioHistoryView`), extend cardio beyond 90 days |
| **B7** | **Cardio personal bests**: fastest 1 km, 1 mile, 5 km, 10 km, half (runs; from GPS, elapsed time), fastest 10/20/40 km and longest ride, fastest 2 km row (indoor, from distance samples), longest walk/hike, biggest climb; this year and all time, "new best" line on the detail screen and on B1. Plain facts, as `PRHistory` does for lifts | Strava Best Efforts [S3][S4] | Weak–moderate (feedback and goal setting [E1][E5]; no cardio-specific trial) | Motivation from own progress without comparison to others | M | AppCore `CardioBests` (sliding window over `CardioRoute` distance/time); Fitness › Progress › Records (beside lift PRs) |
| **B8** | **Weekly intensity picture**: stacked bars of minutes per zone per week (12 weeks) with the WHO 150/300 band and vigorous minutes, plus a simple easy/moderate/hard split. No target ratio for lifters; for stamina goals, a note that most endurance training is easy (polarized evidence weak–moderate, trained athletes) | Garmin Load Focus, Polar | Strong for weekly minutes [E12][E13]; weak–moderate for intensity mix [E15][E16] | Helps users meet the guideline; makes "zone 2" concrete | S–M | Fitness › Today › Heart-rate zones (`ZonesDetailView`) gets a "Weeks" tab; Fitness › Training load |
| **B9** | **Charts as images**: a share button on the main trend charts (e1RM per lift, VO₂ max trend with error band, HRV 90 days, weight/waist trend, weekly sets per muscle, B8) rendering the chart with its title, range and caveat line | Hevy chart sharing [H4] | Moderate (reporting progress [E2]) | Lets users share with a coach or doctor | S each, M for all | `LiftProgressView`, `CardioDetailView`, HRV chart, `MusclesDetailView`, body measurements |
| **B10** | **Interval and lap breakdown** in the cardio detail and its share card: for the Watch interval session (and Apple/Garmin workouts with laps or segments), a table of work and recovery bouts with duration, average HR, peak HR, pace, and time in target band; heart-rate recovery after each bout | Garmin, Suunto [U1], Apple custom workouts | Strong for the session itself (intervals raise VO₂ max [E17]); none for the table | Makes the evidence-backed 4×4 session visible and checkable | S–M | `CardioWorkoutDetailView`; HKWorkout events/activities; `IntervalSession` |
| **B11** | **Pace/speed and elevation charts** on the cardio detail: pace (or speed) and HR over distance on one chart with a shared cursor that moves a marker on the map; elevation profile under it | Strava, Garmin | None (shows existing data) | Better understanding of a workout; no direct health effect | S–M | `CardioWorkoutDetailView` (Swift Charts; data already in `CardioRoute`) |
| **B12** | **Year in review** (also from any past year): totals by activity type, days active per month (calendar from B6), strength days and WHO weeks met, PRs and best efforts, VO₂ max and HRV change with caveats, biggest week. Shareable as a short series of cards | Strava Year in Sport [S9], Gentler Streak recaps | Weak (progress review [E2]; no trial of recaps) | Reflection; reinforces consistency | M | Fitness › Progress › Records (`PRYearView` grows a "Year" summary); shown once in early January |

Two smaller changes go with these:

- **e1RM honesty on cards and charts** (part of B3/B9): show "≈", compute only from sets of ≤ 10–12 reps, and note "estimate, varies by lift" (Nuzzo 2024 [E29]; LeSuer 1997 [E30]). Effort S, in `OneRepMax` and `SummaryCard`.
- **Health data off by default on cards**: recovery, sleep, HRV and body weight are opt-in per share; workout numbers are on. A card never shows calories by default (Shcherbina 2017 [E42]; O'Driscoll 2020 [E43]); a switch can add them as a range ("≈ 450–600 kcal").

### 5b. Consider later

| Feature | Reference | Evidence | Why later | Effort |
|---|---|---|---|---|
| **Routes and "race your route"**: detect repeated routes, compare times and pace on the same route; Watch pacer against your best | Apple Race Route [A1], Strava segments | Weak (acute lab effect, Corbett 2012 [E48]) | Useful for runners and riders, less for the lifting-first user; needs route matching | M–L |
| **Long-term load line** (42-day weighted cardio and muscular load as a description, beside the 7-vs-28-day card) without a "form" or "peak" number | TrainingPeaks PMC [T1], Strava F&F [S2], Polar [P1] | Weak as a predictor [E33]–[E35] | Adds a chart people know; risk of over-reading; current card already answers "more or less than usual" | S–M |
| **Private personal heatmap** of all routes (on device, never shareable with home areas) | Strava personal heatmaps | None; privacy risk if shared [E52] | Nice to have; low value for health | M |
| **Running power and form metrics display** when Apple Health holds them (no coaching) | Apple, Garmin | Weak / none [E44][E45] | Only for users who ask; risk of false precision | S |
| **Race goal and plan** (5 km–half) with weekly long run and intervals | Runna, Garmin Coach | Moderate for structured training generally; none for app plans specifically | Outside the core lifting-plus-health focus; Runna and Garmin do it well | L |
| **Accountability partner card**: a scheduled weekly card (local notification reminds; user taps to send) | `behaviour-change.md` §19 | Weak–moderate (reporting to others [E2]; support alone weak [E9]) | Do after B4 shows whether people share | S |
| **Multisport / brick sessions** recorded by Tensile's Watch | Apple, Suunto | None for health | Apple's Workout app already records them into Health, and Tensile reads them | M |
| **Chart overlays comparing two workouts** (same route or same lift) | Garmin, Strava | None | After B6/B11 | M |
| **FIT export** | Garmin, COROS | None | GPX/TCX cover most uses; FIT needs the FIT SDK and its licence terms checked | M |

### 5c. Leave out

| Feature | Seen in | Reason (evidence) |
|---|---|---|
| **ACWR / "injury risk" from load ratios** | Garmin (load ratio), many blogs | Conceptually and statistically flawed, no causal evidence (Impellizzeri 2020 [E36], 2021 [E37]; Lolli 2019 [E38]). Tensile's load card already describes, not predicts |
| **More composite scores: Body Battery, Training Readiness, "recovery time" countdown, stress energy** | Garmin, Whoop, Oura, Apple | 14 composite scores from 10 makers: undisclosed formulas, little validation, double-counted inputs (Doherty 2025 [E41]). Tensile has one recovery score with its limits stated; a second number would be an app-made number without evidence |
| **TSB "form", peaking day, "fresh/fatigued" labels** | TrainingPeaks, Strava | The fitness-fatigue model's parameters are unstable and its fatigue term adds no prediction [E33]–[E35]; TrainingPeaks says TSB is not a performance predictor [T2] |
| **Training Status labels (Productive/Unproductive/Peaking) from VO₂ max trends** | Garmin, COROS | Built on watch VO₂ max estimates with ±10 mL/kg/min limits for one person [E20][E21]; a weekly label would mostly show noise |
| **Calories burned as a headline or on share cards** | Most apps | Wrist devices err by 20–93% on energy expenditure [E42][E43]. Keep the Nutrition card's ranged estimate |
| **Running dynamics coaching (cut GCT, raise cadence)** | Garmin, Apple | Biomechanical injury risk factors are sparse and inconsistent [E44] |
| **Lactate threshold and performance-condition estimates** | Garmin | Vendor estimates, no independent validation found; users can enter tested zones under custom limits |
| **Race time predictor** | Garmin, COROS | Inherits VO₂ max estimate error [E20]; no validation found |
| **Public leaderboards, segments with KOMs, badges, streaks, kudos feed** | Strava, Hevy, NRC, Garmin | Gamification effect small and fades (Mazeas 2022 [E10]); broken streaks cut engagement (Silverman & Barasch 2023 [E11]); social features show no consistent activity gain [E6][E7]; needs a server; bloat |
| **Global or community heatmaps, public activity pages** | Strava | Location leaks at scale [E49]–[E52]; needs a server; Tensile uploads nothing |
| **Live location sharing during a workout** | Garmin LiveTrack, NRC | Needs a server and continuous location upload, against the no-upload rule; iOS's own Check In and Find My cover safety |
| **Precise "% recovered" per muscle** | Fitbod | No evidence for a percentage; Tensile's muscle map uses rest categories, keep it that way |
| **Cloud AI post-workout summaries** | Strava Athlete Intelligence [S5] | The app has no cloud AI; the on-device coach can write a line from the same numbers |

---

## 6. Share and export spec (privacy first)

**Rules for every share.**
1. Created only when the user taps Share; built on the phone; handed to the iOS share sheet or Files. The app uploads nothing and keeps no link.
2. A preview with switches before sharing: map on/off, health data on/off (recovery, sleep, HRV, weight; off by default), strain on/off, heart rate on/off.
3. Route privacy (B2) is applied to every map image and every GPX/TCX by default; "Full route" is a per-export switch with a warning line.
4. When the route is trimmed, distance is rounded to 0.1 km/mi and the start time is shown as a date only (Dhondt 2022 [E50]).
5. Images carry no location metadata (rendered images have none; keep it so if saving to Photos).
6. Every derived number on a card that is an estimate says so in a footer line: "e1RM ≈ estimate", "VO₂ max: Apple Watch estimate, ±10", "Strain: Tensile's own scale".
7. Units follow the user's settings (`WeightUnit`, locale for distance). Brand: Tensile wordmark small in a corner; never another app's names or marks.

**Formats.**

| Format | Content | Size / file | Where |
|---|---|---|---|
| Cardio card | Map (trimmed), activity icon, date, distance, time, pace/speed, elevation gain, avg HR, zone bar, splits mini-chart; optional strain, VO₂ max, best effort badge | 1080×1350 PNG (feed) and 1080×1920 (story); map-only and transparent-overlay variants | `CardioWorkoutDetailView` |
| Interval card | Bouts table, HR per bout, time in target | Same sizes | `CardioWorkoutDetailView` for interval sessions |
| Lifting card | Title, date, duration, sets, volume, top exercises with best sets and ▲/▼, PRs, muscle map (front/back), optional strain | Same sizes; transparent variant | `WorkoutSummaryView` |
| Weekly card | Days trained, strength days vs 2, active minutes vs 150–300, sets per muscle map, PRs, distance by type; health data opt-in | Same sizes | `WeeklyReviewView` |
| Chart image | Any trend chart with title, range and caveat | 1080×1080 PNG | Each chart's toolbar |
| Year in review | 4–6 cards: totals, calendar, PRs and bests, fitness trend, biggest week | Story size series | Fitness › Progress › Records |
| GPX 1.1 | Track with time, elevation, HR (Garmin TrackPoint extension); trimmed by default | `.gpx` per workout | Cardio detail › Share › Export route |
| TCX | Laps, HR, distance, cadence if present; trimmed by default | `.tcx` per workout | Same menu |
| CSV | Sets, cardio sessions, daily scores (three files, UTF-8, ISO dates, kilograms with a unit column) | `.csv`, zipped | Settings › Data › Export |
| JSON backup | All Tensile-owned data with a schema version | `.json` zipped | Settings › Data › Export; restore later |

---

## 7. References

### Products

- [G1] Garmin manual, Training Status (Firstbeat; VO₂ max, acute load and HRV status): https://www8.garmin.com/manuals/webhelp/GUID-C001C335-A8EC-4A41-AB0E-BAC434259F92/EN-US/GUID-44C7BB4B-EFF7-4A42-AC03-8A6AABB94807.html
- [G2] the5krunner, Garmin training features explained (Load Focus, acute load): https://the5krunner.com/garmin-features/training/
- [G3] Cycling Weekly, Garmin metrics explained (Training Readiness, Body Battery): https://www.cyclingweekly.com/fitness/garmins-health-tracking-metrics-explained-understand-what-your-smartwatch-is-telling-you
- [G4] Garmin Forerunner 965 manual, Performance Measurements (performance condition, lactate threshold, race predictor): https://www8.garmin.com/manuals-apac/webhelp/forerunner965/EN-SG/GUID-B1488BAE-8665-4AED-B686-28F8C85D2699-8828.html
- [G5] Garmin Forerunner 265 manual, Viewing your predicted race times: https://www8.garmin.com/manuals-apac/webhelp/forerunner265series/EN-SG/GUID-32FEEA35-2265-48DC-A53B-C8D08B4B7553-1167.html
- [A1] MacRumors, Workout app in watchOS 26 (custom workouts corner button, Race Route, Pacer): https://www.macrumors.com/2025/06/10/apple-watch-workout-app-watchos-26/
- [A2] DC Rainmaker, Apple Watch workout builder in iOS 26 / watchOS 26: https://www.dcrainmaker.com/2025/09/apple-watch-workout-builder-ios26-watchos26.html
- [A3] Apple Newsroom, watchOS 9 (Multisport, zones, running form, custom workouts): https://www.apple.com/my/newsroom/2022/06/watchos-9-delivers-new-ways-to-stay-connected-active-and-healthy/
- [A4] MacStories, watchOS 9 review (custom workouts, multisport transitions): https://www.macstories.net/stories/watchos-9-the-macstories-review/2/
- [A5] DC Rainmaker, Apple Training Load in watchOS 11: https://dcrainmaker.com/2024/07/apples-training-load-vitals-watchos11.html
- [A6] iMore, What is Training Load on watchOS 11: https://imore.com/health-fitness/apple-watch/what-is-training-load-on-watchos-11-the-new-feature-coming-to-apple-watch-that-will-change-your-workouts-forever
- [A7] Workout Data Exporter, Apple Health has no GPX export; GPX vs TCX for Strava (vendor page): https://workoutdataexporter.web.app/apple-health-gpx-export and https://workoutdataexporter.web.app/apple-health-to-strava
- [S1] the5krunner, Strava Relative Effort: https://the5krunner.com/2021/07/20/strava-relative-effort-everthing-you-need-to-know/
- [S2] Strava support, Fitness & Freshness: https://support.strava.com/hc/en-us/articles/216918477-Fitness-Freshness
- [S3] Strava support, Best Efforts (Running): https://support.strava.com/hc/en-us/articles/16601494390285-Best-Efforts-Running
- [S4] 9to5Mac, Strava expands Best Efforts to cycling (2024): https://9to5mac.com/2024/03/20/strava-app-expands-best-efforts-feature-for-cyclists/
- [S5] PR Newswire, Strava Athlete Intelligence: https://prnewswire.com/news-releases/stravas-athlete-intelligence-translates-workout-data-into-simple-and-personalized-insights-302266680.html
- [S6] Athletech News, Strava strength training update (May 2026): https://athletechnews.com/strava-strength-training-major-update/
- [S7] the5krunner, Strava strength training (May 2026): https://the5krunner.com/2026/05/21/strava-strength-training/
- [S8] the5krunner, Strava guided strength workouts and muscle map (Oct 2026): https://the5krunner.com/2026/10/15/strava-guided-strength-workouts/
- [S9] TechRadar, Strava Year in Sport: https://techradar.com/computing/software/stravas-year-in-sport-is-rolling-out-now-its-like-spotify-wrapped-for-your-activities ; Strava monthly stats: https://www.bikeradar.com/news/strava-monthly-activity-stats-animation/
- [S10] BikeRadar, Strava Sticker Stats (spring 2025): https://www.bikeradar.com/news/strava-sticker-stats-spring-2025-updates
- [S11] DC Rainmaker, Strava privacy features (hide start/end, hide map): https://dcrainmaker.com/2021/08/privacy-features-options.html ; Bikerumor: https://bikerumor.com/strava-privacy-zones-expand-with-new-edit-map-visibility-functions/
- [S12] GearJunkie, Strava 2025 AI routes: https://gearjunkie.com/technology/strava-updates-2025-ai-routes ; Wareable, route builder and zones: https://www.wareable.com/sport/strava-power-skills-training-zones-mobile-route-builder-update
- [S13] the5krunner, Runna under Strava: https://the5krunner.com/runna/
- [T1] TrainingPeaks help, Form (TSB): https://help.trainingpeaks.com/hc/en-us/articles/204071764-Form-TSB
- [T2] Same page: TSB "not as a predictor of performance but as a measure of how adapted an athlete is".
- [P1] Polar support, Training Load Pro: https://support.polar.com/en/training-load-pro
- [P2] Polar, Training Load Pro product page: https://www.polar.com/us-en/smart-coaching/training-load-pro
- [C1] COROS EvoLab: https://coros.com/evolab
- [U1] the5krunner, Suunto software update v2.50.26 (Jan 2026): https://the5krunner.com/2026/01/07/uunto-software-update-v2-50-26-january-2026/
- [U2] DC Rainmaker, Suunto January 2026 releases: https://www.dcrainmaker.com/2026/01/suunto-january-2026-releases-firmware-watches.html
- [R1] Tom's Guide, Runna features: https://www.tomsguide.com/wellness/running/this-is-the-running-app-im-using-to-train-for-my-sixth-marathon-and-it-just-got-even-better-for-beginners-too
- [N1] Nike newsroom, Nike Run Club features (audio-guided runs, live location sharing): https://about.nike.com/newsroom/releases/nike-run-club-app-new-features
- [GS1] 9to5Mac, Gentler Streak 2025 update (Activity Path views, RPE sync): https://9to5mac.com/2025/03/18/gentler-streak-update-health/ ; BGR: https://bgr.com/lifestyle/gentler-streak-gets-two-long-awaited-features-ahead-of-watchos-26
- [AT1] Athlytic, App Store listing: https://apps.apple.com/gb/app/id1543571755
- [H1] Hevy, workout rest timer and tracking: https://www.hevyapp.com/features/workout-rest-timer/
- [H2] Hevy, gym progress: https://www.hevyapp.com/features/gym-progress/
- [H3] Hevy, muscle group workout chart: https://www.hevyapp.com/features/muscle-group-workout-chart/
- [H4] Hevy, shareable images: https://www.hevyapp.com/features/shareable/
- [H5] Hevy help, Live Activity: https://help.hevyapp.com/hc/en-us/articles/35649846517399-How-to-Use-Hevy-s-Live-Activity-on-iOS-and-Android
- [ST1] Strong review (secondary): https://repreturn.com/strong-app-review/ ; App Store: https://apps.apple.com/DE/app/id464254577
- [F1] Fitbod help, Muscle Recovery: https://help.fitbod.me/hc/en-us/articles/360006269014-Muscle-Recovery
- [F2] Fitbod blog, Strava integration (muscle heat map on Strava): https://fitbod.me/blog/fitbod-strava-integration/
- [J1] JEFIT, Introducing BodyMap (Nov 2025): https://www.jefit.com/blog/introducing-bodymap-a-smarter-way-to-visualize-your-training

### Evidence

- [E1] Michie S, et al. Effective techniques in healthy eating and physical activity interventions: a meta-regression. Health Psychol 2009;28(6):690–701. https://doi.org/10.1037/a0016136
- [E2] Harkin B, et al. Does monitoring goal progress promote goal attainment? A meta-analysis of the experimental evidence. Psychol Bull 2016;142(2):198–229. https://doi.org/10.1037/bul0000025
- [E3] Ferguson T, et al. Effectiveness of wearable activity trackers to increase physical activity and improve health: a systematic review of systematic reviews and meta-analyses. Lancet Digit Health 2022;4:e615–e626. https://doi.org/10.1016/S2589-7500(22)00111-X
- [E4] Laranjo L, et al. Do smartphone applications and activity trackers increase physical activity in adults? Systematic review, meta-analysis and metaregression. Br J Sports Med 2021;55:422–432. https://doi.org/10.1136/bjsports-2020-102892
- [E5] Weakley J, et al. The effect of feedback on resistance training performance and adaptations: a systematic review and meta-analysis. Sports Med 2023;53(9):1789–1803. https://doi.org/10.1007/s40279-023-01877-2
- [E6] Tong HL, Laranjo L. The use of social features in mobile health interventions to promote physical activity: a systematic review. npj Digit Med 2018;1:43. https://doi.org/10.1038/s41746-018-0051-3
- [E7] Maher CA, et al. Are health behavior change interventions that use online social networks effective? A systematic review. J Med Internet Res 2014;16(2):e40. https://doi.org/10.2196/jmir.2952
- [E8] The role of Facebook in promoting a physically active lifestyle: systematic review and meta-analysis (2022). https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9408066/
- [E9] Zhang J, et al. Support or competition? How online social networks increase physical activity: a randomized controlled trial. Prev Med Rep 2016;4:453–458. https://doi.org/10.1016/j.pmedr.2016.08.008
- [E10] Mazeas A, et al. Evaluating the effectiveness of gamification on physical activity: systematic review and meta-analysis of randomized controlled trials. J Med Internet Res 2022;24(1):e26779. https://doi.org/10.2196/26779
- [E11] Silverman J, Barasch A. On or off track: how (broken) streaks affect consumer decisions. J Consum Res 2023;49(6):1095–1117. https://www.insead.edu/faculty-research/publications/journal-articles/or-track-how-broken-streaks-affect-consumer
- [E12] Bull FC, et al. World Health Organization 2020 guidelines on physical activity and sedentary behaviour. Br J Sports Med 2020;54:1451–1462. https://doi.org/10.1136/bjsports-2020-102955
- [E13] Ahmadi MN, et al. Vigorous physical activity, incident heart disease, and cancer: how little is enough? Eur Heart J 2022;43(46):4801–4814. https://doi.org/10.1093/eurheartj/ehac572
- [E14] Iannetta D, et al. A critical evaluation of current methods for exercise prescription in women and men. Med Sci Sports Exerc 2020;52(2):466–473. https://pubmed.ncbi.nlm.nih.gov/31479001/
- [E15] Rosenblat MA, Perrotta AS, Vicenzino B. Polarized vs. threshold training intensity distribution on endurance sport performance: a systematic review and meta-analysis of randomized controlled trials. J Strength Cond Res 2019;33(12):3491–3500. https://doi.org/10.1519/JSC.0000000000002618
- [E16] Oliveira PS, Boppre G, Fonseca H. Comparison of polarized versus other types of endurance training intensity distribution on athletes' endurance performance: a systematic review with meta-analysis. Sports Med 2024. https://doi.org/10.1007/s40279-024-02034-z
- [E17] Milanović Z, Sporiš G, Weston M. Effectiveness of high-intensity interval training (HIT) and continuous endurance training for VO2max improvements: a systematic review and meta-analysis of controlled trials. Sports Med 2015;45(10):1469–1481. https://doi.org/10.1007/s40279-015-0365-0
- [E18] Mandsager K, et al. Association of cardiorespiratory fitness with long-term mortality among adults undergoing exercise treadmill testing. JAMA Netw Open 2018;1(6):e183605. https://doi.org/10.1001/jamanetworkopen.2018.3605
- [E19] Lang JJ, et al. Cardiorespiratory fitness is a strong and consistent predictor of morbidity and mortality among adults: an overview of meta-analyses. Br J Sports Med 2024;58(10):556–566. https://doi.org/10.1136/bjsports-2023-107849
- [E20] Molina-Garcia P, et al. Validity of estimating the maximal oxygen consumption by consumer wearables: a systematic review with meta-analysis and expert statement of the INTERLIVE network. Sports Med 2022;52:1577–1597. https://doi.org/10.1007/s40279-021-01639-y
- [E21] Caserman P, et al. Apple Watch Series 7 VO2max estimates against a laboratory test (title paraphrased; as cited in `FitnessCheck.swift`, PMID 39083800). JMIR Biomed Eng 2024;9:e59459. https://doi.org/10.2196/59459
- [E22] Foster C, et al. A new approach to monitoring exercise training. J Strength Cond Res 2001;15(1):109–115. https://doi.org/10.1519/00124278-200102000-00019
- [E23] Haddad M, et al. Session-RPE method for training load monitoring: validity, ecological usefulness, and influencing factors. Front Neurosci 2017;11:612. https://doi.org/10.3389/fnins.2017.00612
- [E24] Larsen S, et al. The effectiveness of autoregulatory resistance training: a systematic review. PeerJ 2021;9:e10663. https://doi.org/10.7717/peerj.10663
- [E25] Hickmott LM, et al. The effect of load and volume autoregulation on muscular strength and hypertrophy: a systematic review and meta-analysis. Sports Med Open 2022;8:9. https://doi.org/10.1186/s40798-021-00404-9
- [E26] Halperin I, et al. Accuracy in predicting repetitions to task failure in resistance exercise: a scoping review and exploratory meta-analysis. Sports Med 2022;52:377–390. https://doi.org/10.1007/s40279-021-01559-x
- [E27] Zourdos MC, et al. Novel resistance training-specific rating of perceived exertion scale measuring repetitions in reserve. J Strength Cond Res 2016;30(1):267–275. https://doi.org/10.1519/JSC.0000000000001049
- [E28] Helms ER, et al. Application of the repetitions in reserve-based rating of perceived exertion scale for resistance training. Strength Cond J 2016;38(4):42–49. https://doi.org/10.1519/SSC.0000000000000218
- [E29] Nuzzo JL, Pinto MD, Nosaka K, Steele J. Maximal number of repetitions at percentages of the one repetition maximum: a meta-regression and moderator analysis of sex, age, training status, and exercise. Sports Med 2024;54(2):303–321. https://doi.org/10.1007/s40279-023-01937-7
- [E30] LeSuer DA, et al. The accuracy of prediction equations for estimating 1-RM performance in the bench press, squat, and deadlift. J Strength Cond Res 1997;11(4):211–213. https://doi.org/10.1519/00124278-199711000-00001 (DOI from memory, not re-checked this round)
- [E31] Schoenfeld BJ, Ogborn D, Krieger JW. Dose-response relationship between weekly resistance training volume and increases in muscle mass: a systematic review and meta-analysis. J Sports Sci 2017;35(11):1073–1082. https://doi.org/10.1080/02640414.2016.1210197
- [E32] Pelland JC, et al. The resistance training dose response: meta-regressions exploring the effects of weekly volume and frequency on muscle hypertrophy and strength gains. Sports Med 2026;56(2):481–505. Record: https://sponet.de/sponet/Record/4097139 ; preprint: https://sportrxiv.org/index.php/server/preprint/view/460
- [E33] Vermeire K, et al. The fitness-fatigue model: what's in the numbers? Int J Sports Physiol Perform 2022. https://pubmed.ncbi.nlm.nih.gov/35320776/
- [E34] Imbach F, et al. Training load responses modelling and model generalisation in elite sports. Sci Rep 2022;12:1586. https://doi.org/10.1038/s41598-022-05392-8
- [E35] Marchal et al. Statistical flaws of the fitness-fatigue sports performance prediction model. Sci Rep 2025. https://ouci.dntb.gov.ua/works/4EBvEq2l
- [E36] Impellizzeri FM, et al. Acute:chronic workload ratio: conceptual issues and fundamental pitfalls. Int J Sports Physiol Perform 2020;15(6):907–913. https://doi.org/10.1123/ijspp.2019-0864
- [E37] Impellizzeri FM, et al. What role do chronic workloads play in the acute to chronic workload ratio? Time to dismiss ACWR and its underlying theory. Sports Med 2021;51:581–592. https://doi.org/10.1007/s40279-020-01378-6
- [E38] Lolli L, et al. Mathematical coupling causes spurious correlation within the conventional acute-to-chronic workload ratio calculations. Br J Sports Med 2019;53:921–922. https://doi.org/10.1136/bjsports-2017-098110
- [E39] Granero-Gallegos A, et al. HRV-based training for improving VO2max in endurance athletes: a systematic review with meta-analysis. Int J Environ Res Public Health 2020;17(21):7999. https://doi.org/10.3390/ijerph17217999
- [E40] Plews DJ, et al. Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring. Sports Med 2013;43:773–781. https://doi.org/10.1007/s40279-013-0071-8
- [E41] Doherty C, et al. Readiness, recovery, and strain: an evaluation of composite health scores in consumer wearables. Transl Exerc Biomed 2025. https://doi.org/10.1515/teb-2025-0001 ; author commentary: https://www.ucd.ie/newsandopinion/news/2025/april/11/opinion-howtrustworthyisyourfitnesstrackerscore
- [E42] Shcherbina A, et al. Accuracy in wrist-worn, sensor-based measurements of heart rate and energy expenditure in a diverse cohort. J Pers Med 2017;7(2):3. https://doi.org/10.3390/jpm7020003
- [E43] O'Driscoll R, et al. How well do activity monitors estimate energy expenditure? A systematic review and meta-analysis of the validity of current technologies. Br J Sports Med 2020;54(6):332–340. https://doi.org/10.1136/bjsports-2018-099643
- [E44] Ceyssens L, et al. Biomechanical risk factors associated with running-related injuries: a systematic review. Sports Med 2019;49(7):1095–1115. https://doi.org/10.1007/s40279-019-01110-z
- [E45] Imbach F, et al. Validity of the Stryd power meter in measuring running parameters at submaximal speeds. Sports 2020;8(7):103. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7404478/
- [E46] Is running power a useful metric? Stryd running power near the maximal lactate steady state. Sensors 2023. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10649254/
- [E47] Gilgen-Ammann R, Schweizer T, Wyss T. Accuracy of distance recordings in eight positioning-enabled sport watches: instrument validation study. JMIR mHealth uHealth 2020;8(6):e17118. https://doi.org/10.2196/17118
- [E48] Corbett J, et al. Influence of competition on performance and pacing during cycling exercise. Med Sci Sports Exerc 2012;44(3):509–515. https://pubmed.ncbi.nlm.nih.gov/21900846/
- [E49] Hassan WU, Hussain S, Bates A. Analysis of privacy protections in fitness tracking social networks -or- you can run, but can you hide? USENIX Security 2018. https://www.usenix.org/system/files/conference/usenixsecurity18/sec18-hassan_0.pdf
- [E50] Dhondt K, Le Pochat V, Voulimeneas A, Joosen W, Volckaert S. A run a day won't keep the hacker away: inference attacks on endpoint privacy zones in fitness tracking social networks. ACM CCS 2022. https://lepoch.at/files/epz-inference-attacks-ccs22.pdf
- [E51] Dark Reading on [E50] (distance precision drives the attack): https://www.darkreading.com/application-security/popular-fitness-apps-leak-location-data-even-when-users-set-privacy-zones
- [E52] The Guardian, Fitness tracking app Strava gives away location of secret US army bases (Jan 2018): https://www.theguardian.com/world/2018/jan/28/fitness-tracking-app-gives-away-location-of-secret-us-army-bases

### Not verified this round

Product facts marked **(secondary)**, Strong's pricing tier for CSV export, Liftosaur's current Watch and sharing features, and the Strava Instant Workouts feature were not confirmed from vendor pages. [E30]'s DOI and [E21]'s exact title are from memory and the repo's earlier research, not re-checked here. [E8], [E35] and [E46] were read from search summaries only.
