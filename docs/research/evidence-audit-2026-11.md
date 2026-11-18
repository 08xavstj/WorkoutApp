# Evidence audit of the whole app (17 Nov 2026)

The owner's request: "I want to follow what research and scientific articles are saying and making sure that we do the best to optimize to that to make sure we create an app that ensures the best chances to increase our health." He also asked to remove anything he asked for that the research advises against.

This audit checks every score, target, default, message and feature against the evidence, as the code stands today. It builds on `healthy-living-2026-11.md`, `cleanup-2026-11.md`, `qa-2026-11-17.md`, `strain-science.md`, `workout-science.md`, `health-metrics.md`, `longevity-insights.md` and the rest of `docs/research/`, and does not repeat what they settled.

**Not audited here** (being rebuilt by others): the weekly review (health floors, measured weekly changes, the target-weight hold, the drink limit); the weekly plan's busy week, hard cardio session, block variety and calendar; widgets; the insomnia path and catch-up sleep wording; the low-mood rule. Daytime vitals, Apple's scores, Longevity, Insights and the overnight HRV change were checked for evidence only, not for bugs.

**How sources were checked.** **[V]** = read at the source this round: the PubMed abstract through NCBI E-utilities, or the PMC full text where noted, with title, authors, journal, year and the quoted number checked. **[R]** = the PubMed record (title, authors, journal, year) was checked but the number quoted comes from elsewhere. **[NV]** = not verified this round (an earlier repo file, a summary, or memory). Most health evidence here is observational: people with the better number did better, which does not prove that changing the number changes the outcome. The text says so where it matters.

---

## Summary

The app's research base is strong. Most constants have a citation next to them, the hedging is honest, and most citations say what the code claims (see "Checked and sound"). The problems are in a few places where the app tells the owner he is doing better or worse than he is, and in several defaults that point away from the strongest evidence. These changes would do the most for his health, in order:

1. **Count cardio correctly, and put cardio in the default plan.** "Cardio minutes", "Weekly active minutes", the Intensity minutes stat and the Longevity "Active minutes" row all count heart rate during lifting sessions as aerobic activity. A man who lifts four or five times a week will usually pass the WHO 150-minute aerobic floor without doing any aerobic exercise. That is false reassurance on the single strongest lever he has: cardiorespiratory fitness (high vs low fitness, all-cause mortality HR 0.47; 11-17% lower per 1 MET; Lang 2024 [V]). On top of that, new weekly plans start with **0** easy cardio sessions. Count minutes outside lifting, and default to two 30-minute easy sessions.
2. **Stop grading heart-rate recovery after gym sessions with a cut-off from clinical treadmill tests.** The "Low / Fair / Good" label and the amber tone use Cole 1999's ≤12 bpm. That figure comes from symptom-limited exercise tests in patients referred for cardiac imaging (mean age 57) [V]. Applied to the end of a lifting session it will often read "Low" and suggest poor fitness or risk with no basis.
3. **Remove the unvalidated composites and duplicate scores:** body age, the heart-rate "Stress" stat, the Apple Readiness / Sleep score / Health Age entry and comparison screen, and the daytime vitals view. None changes what he should do. Each adds a number that can worry or falsely reassure. The app's own research already said to cut or hide most of them.
4. **Make the defaults match the app's own evidence.** Workout reminders are **on** by default although `cleanup-2026-11.md` and `healthy-living-2026-11.md` found that clock reminders hinder habit formation and that an established lifter responds least to prompts (Buyalskaya 2023 [V]). The weigh-in nudge asks for daily weighing, but the meta-analysis it cites found daily and weekly weighing worked the same (Madigan 2015 [V]).
5. **Fix two overstated claims that touch safety:** omega-3 is graded "moderate" for heart and general health with no mention of the dose-related atrial fibrillation risk (HR 1.25; 1.49 above 1 g/day; Gencer 2021 [V]). Sleep regularity copy says the mortality benefit starts "from roughly 85", when the cohort found it across everyone above the least regular fifth (SRI > 71.6), with risk falling steadily to the lowest at ≥ 87 (Windred 2024, full text [V]).
6. **Biggest gaps** the app has the data or the structure for: an aerobic floor that is counted correctly and planned by default; a "know your numbers" schedule for lipids (ApoB, Lp(a) once), glucose and blood pressure; saturated fat from Cronometer; and a validated mood questionnaire offered only when check-ins run low.

---

## Must fix

Each item gives where it is, what it does now, what the evidence says, and the exact change.

### M1. Lifting heart rate is counted as cardio (aerobic) minutes

- **Where:** `App/Services/VitalsModel.swift:1011` (`derived.intensityWeek` counts every heart-rate sample of the week, lifting included), `:1021-1029` (`intensityByDay`, same), `:479-488` (the "Intensity minutes" stat, "Goal reached"); `App/Features/Fitness/TrainingCards.swift:254-262` (`cardioLine`: "Cardio minutes, last 7 days"), `:270-305` (`WeeklyMinutesCard`); `App/Services/LongevityAssembler.swift:109` (Longevity "Active minutes" reads the same series).
- **Now:** every minute at 40-59% of heart-rate reserve during a gym session counts as moderate aerobic activity, and every minute at 60% or more as vigorous (×2). For a 30-year-old with resting HR 55 and max 187, 40% of reserve is about 108 bpm, which most lifting sessions exceed between sets. Four 50-minute sessions alone can show "Goal reached" and put Longevity's "Active minutes" on target. The same file already does it right for the VO₂ estimate (`:1012-1017`, `outsideLifting`), with the reason in a comment.
- **Evidence:** WHO 2020 sets aerobic activity (150-300 min moderate or 75-150 vigorous) and muscle-strengthening (2+ days) as **separate** recommendations (Bull 2020 [NV], well known). The mortality curves behind the aerobic floor are for aerobic or leisure activity (Garcia 2023: RR 0.69 at the 150-min equivalent [V]; Lee 2022: lowest risk at 150-300 vigorous or 300-600 moderate minutes [V]). Strength training has its own, separate curve (Momma 2022: 10-17% lower risk, J-shaped, largest at about 30-60 min/week [V]). Combined aerobic and strength activity did better than either alone (Momma 2022 [V]).
- **Change:** compute the weekly and daily counts from `outsideLifting` samples (the filter already used at `:1016`), and exclude logged gym sessions and Watch strength workouts. Rename the stat "Cardio minutes (outside lifting)". Keep a separate "Lifting minutes" figure for the strength floor, which already exists (`StrengthHealthFloor`). Footnote: "Heart rate during lifting isn't counted: the 150-minute guideline is for aerobic exercise, and lifting has its own guideline."
- **Applied 17 Nov 2026:** the week, the daily bars, the weekly review's basics (`intensitySplitByDay`) and Longevity's row all count heart rate outside logged gym sessions and Watch/Health strength workouts (`IntensityMinutes.outsideLifting`). One title everywhere, "Cardio minutes (outside lifting)" (`IntensityMinutes.title`, also `HealthFloors` and the Fitness card), with the footnote above (`IntensityMinutes.liftingNote`); the weekly change and the Insights lines say "cardio minutes".

### M2. No cardio in the default weekly plan

- **Where:** `App/Features/Today/WeeklyPlanView.swift:33` (`cardioCount = 0`) and `:296` (`?? 0` for a plan with no template).
- **Now:** a new plan has no easy cardio unless the owner adds it. Once M1 is fixed, a lifting-only week will usually show well under 150 aerobic minutes.
- **Evidence:** cardiorespiratory fitness is the strongest, most consistent fitness predictor of mortality (Lang 2024, overview of meta-analyses covering 20.9 million observations: high vs low HR 0.47; 11-17% lower per 1 MET [V]). Cardio alongside lifting does not reduce muscle growth (SMD −0.01) or maximal strength (−0.06); explosive strength suffers only when both are in the same session (Schumann 2022, 43 studies [V]). As little as 15-20 vigorous minutes a week went with 16-40% lower mortality (Ahmadi 2022 [V]). All observational except Schumann.
- **Change:** default `cardioCount` to 2 (2 × 30 min, the `EasyCardio.standardMinutes`) for every goal, with the existing rest-day placement and the bike first for muscle and strength goals. In the picker footer: "Two easy sessions add about 60 of the 150 weekly aerobic minutes and don't cost muscle (Schumann 2022)." The owner can set 0. (The hard interval session is being built separately; it should count toward the same aerobic total.)
- **Applied 17 Nov 2026:** `EasyCardio.defaultSessionsPerWeek = 2` for every goal, with the footer line. A plan already saved for the week keeps its count. A new week (the editor, "Same as last week", the weekly review) carries last week's sessions over; a last plan with none counts as a choice only if it was saved after this change (`EasyCardio.startingSessions`, `carriedOver`), otherwise the two sessions apply.

### M3. Heart-rate recovery graded with a clinical-test cut-off

- **Where:** `Packages/AppCore/Sources/AppCore/HeartHealth.swift:3-5` (doc) and `:39-46` (`label`: <12 "Low", 12-20 "Fair", 20-30 "Good", 30+ "Excellent"); `App/Services/VitalsModel.swift:336-360` (status and `.caution` tone below 12, for Apple's value and for the app's own measurement); `:985-997` (measured after **every** workout of 10+ minutes, lifting included).
- **Now:** after a gym session the "peak" is the highest heart rate in the last 3 minutes, often a rest period. The one-minute drop is then small, and the stat reads "Low" in amber.
- **Evidence:** Cole 1999 defined abnormal recovery (≤12 bpm at 1 min) in 2,428 patients referred for **symptom-limited** exercise testing with thallium imaging (mean age 57). It predicted mortality (adjusted RR 2.0) [V]. The figure depends on a maximal graded test and on its protocol (Cole's cohort walked a cool-down). It does not transfer to the end of a lifting session or an easy workout. The code's claim "linked with poorer fitness" also misquotes the paper, which is about mortality.
- **Change:** remove `HeartRateRecovery.label` and the tone thresholds. Show the one-minute drop only for workouts with a sustained high peak (at least 3 minutes at 80% or more of heart-rate reserve, e.g. intervals or a hard run), and never for strength workouts. Compare it only with the owner's own previous values ("19 bpm, your usual 17-24"), with the footnote: "Clinical cut-offs come from maximal treadmill tests and don't apply to everyday workouts." Change the doc comment to: "A slow fall after a maximal exercise test predicted mortality in patients referred for testing (Cole et al., NEJM 1999); there's no validated cut-off for everyday workouts."
- **Applied 17 Nov 2026:** label and tone thresholds removed; measured only after 3+ minutes at 80%+ of heart-rate reserve in a workout of 10+ minutes that doesn't overlap lifting (`HeartRateRecovery.measureHardEfforts`); Apple's own one-minute value is no longer shown (it can't be tied to a hard effort). The stat reads "Your usual 17-24" (middle half of earlier values, kept in a small log as the heart-rate window holds only two weeks) with the clinical-cut-off footnote, and a neutral tone. Cole 1999 re-checked on PubMed.

### M4. Workout reminders on by default

- **Where:** `App/Services/UserSettings.swift:247` (`workoutRemindersOn ... ?? true`); also `:248-249` (playful tone and on-device lines on by default).
- **Now:** once notification permission exists (from doses or any other reminder), a reminder goes out 30 minutes before every planned session.
- **Evidence:** gym-goers whose attendance is already predictable responded **less** to an intervention to increase attendance (Buyalskaya 2023, 12 million gym visits [V]). Activity prompts lose their effect within about four weeks (Klasnja 2019 [R]; numbers in `cleanup-2026-11.md`). Clock reminders supported repetition but hindered automaticity (Stawarz 2015 [NV]). The app's own decisions were "Stretch and workout reminders: off by default" (`cleanup-2026-11.md` §B) and "Workout reminders being off by default is right" (`healthy-living-2026-11.md` §2c.4).
- **Change:** `?? false`. Keep the playful tone and fresh lines as the style **when he turns reminders on** (the owner asked for them; no evidence of harm with the guardrails in `funny-nudges-2026-11.md`). Offer the switch once, after the first planned week: "Want a heads-up 30 minutes before planned sessions?"

### M5. Weigh-in nudge asks for daily weighing and misquotes its source

- **Where:** `Packages/AppCore/Sources/AppCore/WeighInNudge.swift:17` (title "Weigh in most mornings") and `:35` (detail: "daily beat weekly by little (Zheng 2015; Madigan 2015)").
- **Evidence:** Madigan 2015: self-weighing alone had no clear effect (−0.5 kg, 95% CI −1.3 to 0.3). Added to a programme it gave −1.7 kg. "There was no significant difference in the interventions with weekly or daily weighing", and accountability helped [V]. Frequent weighing and diet-app use go with disordered-eating symptoms in cross-sectional studies (Anderberg 2025; Linardon & Messer 2019 [NV], via `healthy-living-2026-11.md`).
- **Change:** title "Weigh in a few mornings a week". Detail: "Weighing regularly helps inside a plan like this one; daily and weekly weighing worked about the same (Madigan 2015). Three or four mornings a week keep the trend line honest; read the trend, not the number." Leave `daysWithoutWeighIn = 3` as it is (needed for the trend). The header comment at `:6-8` is already right.
- **Applied 17 Nov 2026:** title and detail as above; Madigan 2015 re-checked on PubMed.

### M6. Omega-3 graded "moderate" for heart and general health, with no AF warning

- **Where:** `Packages/AppCore/Sources/AppCore/SupplementKnowledge.swift:516` (claim), `:522` ("it's a long-term health habit"), `:523` (cautions).
- **Evidence:** in cardiovascular outcome trials, marine omega-3 supplements raised atrial fibrillation risk: HR 1.25 overall, 1.12 at ≤1 g/day, 1.49 above 1 g/day, and +11% per extra gram (Gencer 2021, 7 RCTs, 81,210 people [V]). The event reduction "at prescription doses" is from icosapent ethyl in people at high risk on statins (REDUCE-IT [NV]). Large primary-prevention trials of 1 g/day in the general population showed no clear benefit (VITAL, ASCEND [NV]).
- **Change:** split the claim. "Triglycerides" stays moderate. Rename "Heart and general health" to "Heart events in people at high risk (prescription EPA)" and grade it moderate. Add "Heart health in healthy people: none shown (VITAL, ASCEND)". Replace `expect` with "No felt effect. In healthy people, trials haven't shown fewer heart events; oily fish twice a week is the food-first option." Add a caution: "In heart trials, fish-oil supplements slightly raised the risk of atrial fibrillation, more above 1 g a day (Gencer 2021). Ask your doctor if you have palpitations or a heart-rhythm condition."
- **Applied 17 Nov 2026:** claims, `expect` and the atrial-fibrillation caution as above. Gencer 2021, VITAL (HR 0.92, 0.80-1.06), ASCEND (rate ratio 0.97) and the REDUCE-IT record re-checked on PubMed.

### M7. Sleep regularity: the benefit threshold is misquoted

- **Where:** `Packages/AppCore/Sources/AppCore/SleepRegularity.swift:154-171` ("the mortality benefit sat in the top quintiles, from roughly 85 up"; `indexNote` "85+ is linked to better health"); `SleepCalculator.swift:30-32, 95-101` (regularity marks full at 85, none at 50); `Longevity.swift:586-587` (target 85, low 74; `longevity-insights.md` says 81/74).
- **Evidence (Windred 2024, full text [V]):** quintile cut-offs 71.65 / 78.56 / 83.16 / 87.31. The **top four quintiles (SRI 71.6-98.5)** had 20-48% lower all-cause mortality than the bottom one. The relationship was monotonic, and the lowest risk was in the top quintile (≥ 87.3: HR 0.70 fully adjusted, 0.52 minimally). The sample was aged 62.8 on average. The clearest step is leaving the bottom fifth; 85 is not where the benefit starts.
- **Change:** `indexNote`: under 72, "In the least regular fifth (under 72); regular sleepers above that had 20-48% lower mortality (Windred 2024). A steady wake time moves it most." 72-86: "Above the least regular fifth; risk kept falling up to the most regular (87+) (Windred 2024)." 87+: "Among the most regular fifth (87+) (Windred 2024)." Constants: `benefitIndex = 87` (top-quintile edge, used only for "most regular"), `Longevity.sleepRegularityLow = 72` (was 74, the stand-in from the abstract), Longevity on target ≥ 78 (the second quintile's upper edge; the app's choice). Leave the sleep-score mapping (50→0, 85→full) as an app choice, and say in its comment that it is not Windred's threshold.

---

## Remove

### Features to remove

| Feature | Where | Why |
|---|---|---|
| **Heart-rate "Stress" stat** | `VitalsModel.swift:364-376`; `HeartHealth.swift:49-112` (`StressEstimate`) | Its own code says no study has validated heart-rate elevation alone as stress, and lists caffeine, heat, posture and digestion as confounders. The title still says "Stress". `cleanup-2026-11.md` decided "Cut" and the roadmap lists daytime stress scores under "skip". There's no action to take and a real chance of worry. |
| **Body age** | `BodyAge.swift`; `App/Features/Health/KeyMeasuresSection.swift`, `AppleHealthAgeCard.swift` | A composite with app-chosen weights (60% fitness, Gompertz conversion, caps), which its own header calls unvalidated. A 2025 review of composite health scores found them untransparent and unvalidated (Doherty 2025 [NV]; not found on PubMed). It adds nothing beyond the single measures on the Longevity page, each of which has its own target. `cleanup-2026-11.md` said to drop it when iOS 27.3 ships. CLAUDE.md: "don't present app-made numbers as science". |

### Features the owner asked for this session: verdicts

| Feature | Verdict | Reason |
|---|---|---|
| **Daytime vitals view** | **Remove** | It adds a second daily set of HRV, resting HR and SpO₂ numbers, with no decision attached. The app's own research says ambulatory HRV allows no "clear vagal interpretation" (Laborde 2017, via `daytime-vitals.md`) and that wearable daytime-stress measures have poor accuracy. Meal, coffee, posture and heat move it as much as anything health-related. More numbers that can't be acted on raise the risk of tracker-driven worry (orthosomnia case series, Baron 2017 [R]). If he wants to keep it, keep it two levels deep with no chips. |
| **Apple's Readiness, Sleep score and Health Age screen** | **Remove** | Apple publishes no method or validation for any of the three (`apple-scores-2026-11.md`). Getting them in means a screenshot or typing every day, and data-entry burden is the top reason people quit health apps (Krebs & Duncan 2015 [NV]). Showing two competing readiness or sleep scores for the same day, plus a correlation between them, invites score-checking instead of action. People in interviews already found single scores "did not match how they felt" (Ibrahim 2024 [NV]). Apple shows its own numbers in its own apps. |
| **Longevity page** | **Keep** (after M1 and M7) | It is the best-evidenced screen in the app: single measures, each with its own published target, a grade, "linked with" wording, and no composite. Fix the active-minutes source (M1) and the regularity line (M7). |
| **Insights feed** | **Keep, smaller** | Feedback on recorded progress has trial support (Harkin 2016, d = 0.40 [NV, via repo]). The rules use the person's own baseline, with hysteresis and cooldowns. Cap at 2 lines instead of 4 (cleanup rule: the first screen should read in about five seconds), and send nothing as a notification. |
| **Heart-rate zone options** | **Keep, simplified** | No harm; the default (heart-rate reserve) is the better-founded scale. Fixed percentages of any kind match individual thresholds poorly (`workout-zones-2026-11.md` [1]). Keep Tensile (default) and Custom (for a lab test). Percent-of-max adds a second scale where each heart rate lands about a zone higher; drop it, or keep it under "More". The Apple option helps the numbers match the wrist; keep it if he uses it. |
| **Watch cardio mode** | **Keep** | It is how the app's biggest gap (aerobic fitness) gets done. The easy target follows ACSM's moderate band, and the copy says it can't find thresholds and points to the talk test. |
| **Playful workout reminders** | **Keep as an opt-in style; default off** (M4) | No study shows funny reminders get people to the gym (the app's own doc says so). The guardrails (plain and kind on low-recovery, ill, pain or rest days; no guilt; rotation) make harm unlikely. The evidence is against clock reminders by default for an established lifter, not against their tone. |
| **Widgets** (not audited; verdict only) | **Keep the plan widget; take the single-night HRV number out of `HRVWidget`** | No health evidence either way; usability supports glanceable cues. A one-night HRV on the Lock Screen invites reading noise: the 7-day trend is the validated signal (Plews 2012 [R]; Javaloyes 2019 [V]). Show recovery, or the 7-day trend, instead. |

*Applied 17 Nov 2026:* **Insights feed**: at most 2 lines (`DailyInsights.maxShown`); nothing in the feed is sent as a notification (no notification code reads it). **Heart-rate zone options**: percent of maximum dropped; Settings offers Tensile, Apple Health and Custom. A saved percent-of-max choice reads as Tensile's; the type still decodes the old value. The Watch skips percent-of-max zones a phone sent earlier, and its no-phone fallback is now Tensile's scale from age with a stand-in resting rate of 60 (app's choice).

---

## Should change

Weaker-evidence or lower-stakes improvements.

1. **Steps: judge the week, not the day, and stop raising the goal past the plateau.** `VitalsModel.swift:461-466` shows "Goal reached / X to go" for today. `StepGoal.maximumGoal = 12_000` (`FitnessAdaptation.swift:158`). Paluch 2022: mortality risk fell until 8,000-10,000 steps a day under 60 and 6,000-8,000 from 60 [V]. Ding 2025: the curve bends at 5,000-7,000, and "10 000 can still be a viable target for those who are more active" [V]. Both studies use average daily steps. Change: show the 7-day average against the goal, and set `maximumGoal = 10_000` (8,000 from 60).

   *Applied 17 Nov 2026: the status is the last 7 full days' average against the goal (`StepGoal.weekStatus`, from 4 days); the goal stops at 10,000 under 60 and 8,000 from 60. Paluch 2022 re-checked on PubMed.*
2. **Rest-day wording "up to 25%".** `ScoresCard.swift:136` reads like a cap on movement. No guideline sets an upper limit on light or moderate activity, and Lee 2022 found no harm at 2-4 times the guideline [V]. Change the subtitle to "Rest day · keep it easy". Keep the rule that hard training waits for a session day.

   *Applied 17 Nov 2026: "Rest day · keep it easy".*
3. **Hydration "Behind".** `Wellbeing.swift:83-104` judges logged water against the National Academies adequate intake, which is a median intake, not a requirement (the code says so). The water Cronometer logs leaves out coffee, tea and other drinks unless they are logged as water, so "Behind" mostly measures logging. Change: show litres logged with no status, and keep only the "very high" warning (hyponatraemia; Hew-Butler 2015 [NV]).

   *Applied 17 Nov 2026: litres with no status; only "Very high" shows a chip. The even-pace mark is gone.*
4. **Planned deloads.** `TrainingBlock.swift:11-15` says the Coleman 2024 RCT "found no advantage". In fact a week off at the midpoint gave **less** strength gain (isometric and dynamic) and the same hypertrophy as continuous training [V]. The Delphi consensus is coaches' opinion (Bell 2023 [V]). The app's deload is half the sets at the same weights, not a week off, so the trial doesn't test it directly. Change the comment to say this. Make the block's last week "an easier week if you feel run down; otherwise carry on" (reactive), keeping `DeloadAdvisor` for stalls. Also: `TrainingBlock.swift:7` cites Williams 2017 for "periodised beats non-periodised". The newer ACSM 2026 position stand (137 reviews) found periodisation "did not consistently impact training outcomes" [V]. Cite ACSM 2026 and call the ramp an app choice.

   *Applied 17 Nov 2026: comments corrected (Coleman 2024 and ACSM 2026 re-checked on PubMed; the ramp is the app's choice). The last week now carries on at the last building week's sets, and is the easier week when HRV is below normal as it starts or when he taps "Take an easier week" (Fitness › Progress › Strength); he can switch back. Blocks saved before keep their planned deload.*
5. **Ashwagandha grades.** `SupplementKnowledge.swift:390-391` grades stress and sleep "moderate". The cited meta-analysis rated certainty low, and the entry lists liver-injury signals. By the file's own scale (weak = few small trials, mixed or industry-funded), these are "weak". Change both to `.weak`.

   *Applied 17 Nov 2026: both `.weak`.*
6. **Fitness age and the relative-strength bands.** "Fitness age" (`FitnessAdaptation.swift`, `Biomarkers.fitnessAge`) is another single-number translation of a watch estimate whose error is about ±16% (Apple Watch Series 7 vs lab: MAPE 15.8%, ICC 0.47, under-reading fit people; Caserman 2024 [V]). Show the FRIEND percentile only. `StrengthForHealth` labels crowd-sourced lift-to-bodyweight bands a "health marker". Relabel them "training standards (crowd-sourced, not health targets)".
7. **Weekly aerobic band wording for muscle and strength goals.** `FitnessAdaptation.swift`, `WeeklyActivityBand.line`: "For your goal the 150-minute floor is enough; more cardio is optional." For health, Lee 2022 found 3-13% lower mortality at 2-4 times the minimum of moderate activity [V], and Garcia 2023 found smaller further gains up to twice the floor [V]. Change to: "150 is the floor; 150-300 adds a little more health benefit and doesn't cost muscle (Schumann 2022)."

   *Applied 17 Nov 2026: wording as above. Lee 2022 and Schumann 2022 re-checked on PubMed.*
8. **Count vigorous minutes on their own line.** Device data put one vigorous minute at about 4 moderate minutes for all-cause mortality and 8 for CVD mortality (Biswas 2025 [V]). 15-20 vigorous minutes a week went with 16-40% lower mortality, lowest at about 54 (Ahmadi 2022 [V]). Keep "×2" for the WHO total (conservative) and show "Vigorous: N min (aim 20+)" beside it. One cohort; observational.

   *Checked 17 Nov 2026: already matches. Vigorous minutes have their own line beside the ×2 total ("Vigorous: N min. 15-20 a week went with 16-40% lower mortality in one wearable cohort (Ahmadi 2022). A link, not proof."), on the Health stat, the Fitness card and Longevity. No change.*
9. **Bed-by window length.** `BedtimeWindow.swift`: need ÷ 0.9 plus up to 60 min of repayment can mean 9 h 20 min in bed. For a normal sleeper that is fine. More time in bed than sleep ability is what sleep restriction removes in insomnia (Furukawa 2024 [R]). Cap the repayment at 30 minutes when sleep efficiency over the last two weeks is under 85%. Evidence weak; app choice.

   *Applied 17 Nov 2026: repayment capped at 30 minutes when the last two weeks' sleep efficiency (asleep ÷ sleep onset to final wake, 7+ nights) is under 85% (`BedtimeWindow.lowEfficiencyMaxRepaymentMinutes`). That span leaves out time to fall asleep, so it reads a little high. Furukawa 2024 record checked; app choice.*
10. **Protein per meal "ceiling".** `Nutrition.swift:67` (0.55 g/kg "ceiling"). Schoenfeld & Aragon 2018 give 0.55 g/kg as the top of a range for spreading 2.2 g/kg over 4 meals, not a limit on muscle protein synthesis. A 2023 trial found 100 g in one meal gave a larger, longer anabolic response than 25 g (Trommelen 2023 [NV]). Daily total is what the meta-analysis supports (Morton 2018 [V]). Change the comment and UI to "a way to spread the day's target", with no ceiling.

   *Applied 17 Nov 2026: no ceiling; three logged meals now split the day three ways whatever the size. The Nutrition line says "one way to spread the day; the daily total matters most".*
11. **Home blood-pressure repeat interval.** `HomeBloodPressure.swift:110-115`: every 6 months when normal. USPSTF 2021 screens adults 18-39 with normal BP and no risk factors every 3-5 years, and yearly from 40 or with risk factors [NV]. Change normal → 12 months. That lowers the burden and keeps the check.

   *Applied 17 Nov 2026: 12 months when normal, 3 above normal; Longevity's next step says "in a year". USPSTF 2021 not re-verified.*
12. **Doc fixes.** `SleepCalculator.swift:16` says the need is 8 h by default (the app uses 7.5 h, `UserSettings.swift:117`). `CaffeineTiming` (`Habits.swift:9-15`) says the 8.8/13.2 h figures are "from memory": they are now verified (Gardiner 2023 [V]), and Gardiner 2025 is verified too: 100 mg at 4 h had no measurable effect; 400 mg affected sleep within 12 h [V].

   *Applied 17 Nov 2026: both comments corrected; Gardiner 2023 and 2025 re-checked on PubMed.*
13. **HRV-guided "easy day" for lifting.** The rule comes from endurance trials (Kiviniemi 2007: a drop below the 10-day mean − SD meant low intensity [V]; Javaloyes 2019, n = 17, no between-group difference [V]). The meta-analysis found only small, non-significant fitness benefits (SMD 0.20; Manresa-Rocamora 2021 [V]). The code already hedges. Keep the change to effort small (it is: RPE 6.5 / 7.5 / 8), and never turn a planned lift into rest on HRV alone.

   *Applied 17 Nov 2026: effort change unchanged. HRV below normal on its own (recovery 34+) now eases a planned lift but never makes it a rest or recovery day (`TrainingDayPlanner.restWorthy`, all three week types).*

---

## Gaps

Ranked by expected health effect × strength of evidence, for this owner (a man who lifts 4-5 times a week and wears an Apple Watch and an Oura ring).

| # | Gap | Evidence | Expected effect | Data needed / has it? | Where it fits |
|---|---|---|---|---|---|
| 1 | **An aerobic floor that is counted correctly and planned by default**, with a vigorous-minutes line (M1, M2, Should change 7-8) | **Strong** (observational, very consistent): CRF high vs low HR 0.47 (Lang 2024 [V]); 150 min aerobic ≈ RR 0.69 (Garcia 2023 [V]); 15-20 vigorous min/week 16-40% lower (Ahmadi 2022 [V]); no cost to muscle (Schumann 2022 [V]) | **Large.** For a lifter the usual unmet guideline is aerobic, not strength | Heart rate, workouts and lifting windows: **yes**. Nothing new to read | `IntensityMinutes` (outside lifting), `WeeklyPlanView` default, `WeeklyActivityBand`, Longevity "Active minutes", Watch cardio mode; the hard session being built feeds the same total |
| 2 | **"Know your numbers" schedule for cardiovascular risk**: lipid panel with ApoB every 4-6 years (sooner if raised), **Lp(a) once in life**, HbA1c or fasting glucose, alongside the existing BP check | **Strong**: LDL is causal (Ference 2017 EAS consensus [R]); "testing Lp(a) concentration at least once in adults" (Kronenberg 2022 EAS [V]); lipid assessment in adults 20+ (Grundy 2018 [R]); BP-lowering trials (Ettehad 2016, via Longevity [V in repo]) | **Large over a lifetime** if it finds raised Lp(a), familial hypercholesterolaemia or early dysglycaemia, all silent at 30 | Lab results typed in: **yes** (`LabMarkers`, `LabsModel`); needs a "last tested" date per marker and due rules | Health › Records › Lab results; one "due" row in Longevity's "missing strong-evidence measure" slot; the measurement-reminder mechanism already used for BP (one notification per due date, off by default) |
| 3 | **Saturated fat from the food log**, weekly share of energy against under 10% | **Moderate**: cutting saturated fat for 2+ years lowered combined CV events 17% (RR 0.83; NNT 56 in primary prevention), with little effect on mortality (Hooper 2020 Cochrane [V]); WHO 2023 saturated-fat guideline <10% of energy [NV] | Moderate | Cronometer can export saturated fat to Apple Health (`dietaryFatSaturated`) [NV: check on the phone]; the app **doesn't request it today** (`HealthKitClient` reads total fat only) | `Micronutrients`/`Nutrition` weekly check beside sodium and fibre; a Longevity nutrition row; never a daily pass/fail |
| 4 | **A validated mood screen when check-ins run low**: PHQ-9 / GAD-7, offered only after 2 weeks of mostly low mornings, with a "talk to someone" line | **Moderate-strong as policy**: USPSTF recommends screening adults for depression (B) and anxiety under 65 (B) (USPSTF 2023 [V]); benefit depends on follow-up care | Moderate (rare event, large if present) | Daily mood check-ins: **yes**; the questionnaires are public-domain items | `Mood`, the morning check-in. Coordinate with the low-mood rule being built (excluded here) |
| 5 | **A dependable fitness measurement**: Apple's VO₂ estimate needs outdoor walks or runs and is off by about ±16% (Caserman 2024 [V]); a lifter who cycles indoors gets few readings | **Moderate** (measurement, not outcome) | Moderate: makes gap 1 visible and the trend believable | Apple VO₂ max: yes but sparse. A quarterly standardised outdoor walk or run, or a submaximal test, would fill it | `VO2MaxEstimate`, `CardioFitness.trend`; a quarterly "fitness check" row, not a notification |
| 6 | **Preventive-care basics**: yearly flu vaccine, colorectal screening from 45, skin checks if at risk | **Strong for each (USPSTF / CDC) [NV]**; small effect at 30 | Small now, larger later | Not in Apple Health; needs a typed date | One optional checklist under Records; `healthy-living-2026-11.md` put it "not now" because of burden. Revisit at 40 |

Not gaps: sleep duration and regularity, alcohol, sodium, fibre, protein, steps, strength floor, blood pressure and sleep apnoea (STOP-Bang, Apple's notifications) are all covered.

---

## Checked and sound

- **Recovery** (`RecoveryCalculator`): compared with your own 30-night baseline; 7-day ln HRV against mean ± 0.5 SD as the easy-day rule (Kiviniemi 2007 [V], Javaloyes 2019 [V], Plews 2012 [R]); honest that the 0-100 scale is the app's own.
- **Sleep need** default 7.5 h (Watson 2015, "7 or more" [R]); **sleep debt** levels set on the average nightly shortfall and labelled an app scale; **bed-by window** fixes the wake time, as regularity evidence suggests (Windred 2024 [V]).
- **Caffeine cut-off**: 8.8 h for 107 mg and 13.2 h for 217.5 mg match Gardiner 2023 exactly [V]; the "conservative average" note matches Gardiner 2025 [V].
- **Protein** 1.6 g/kg for muscle (Morton 2018: no further gain above 1.62 g/kg [V]); 2.2 g/kg or 2.3-3.1 g/kg lean mass in a deficit (Helms 2014 [NV]); **rate limits** 0.5-1%/week loss and 0.25-0.5%/week gain; **calorie floor** plus the energy-availability guard (IOC REDs 2023 [NV]) with the obesity exception; **Hide calories**.
- **Cut and sleep** advice: Nedeltcheva 2010's 55% and 60% figures are quoted correctly [V].
- **Training volume** 10-20 hard sets per muscle per week, ramp capped at 20, deload floor 4 (Pelland 2026: more volume more growth, diminishing returns, with fractional counting of indirect sets [V]; ACSM 2026: hypertrophy enhanced at ≥ 10 sets a week, strength at ≥ 2 sessions a week and ≥ 80% 1RM [V]).
- **Rest** 2-3 min on big lifts and about 90 s on small ones (Singer 2024: a small benefit above 60 s, none detected above 90 s [V]); **concurrent cardio** low-impact and kept off heavy-leg days (Schumann 2022 [V]).
- **Steps floor** 7,000 (Ding 2025: 7,000 vs 2,000, HR 0.53 [V]); **strength floor** 2 days and 30-60 min (Momma 2022 [V]).
- **Blood-pressure categories and severe line** (2025 AHA/ACC guideline: the record is verified [V]; categories from summaries [NV]); the 7-day home protocol; cuffless estimates not used.
- **Alcohol**: CCSA 2023 tiers, with GBD caveats [NV]; the next-morning personal effect; REM disruption from about two drinks (Gardiner 2025 alcohol meta-analysis [V]).
- **Illness watch**: needs several signals and two days, eases off when alcohol or hard training explains the change (Mishra 2020 [R]; Quer 2021 and Mason 2022 [NV]).
- **Stretching, warm-up, abs finisher, medications, labs, STOP-Bang, hearing**: claims are hedged and sourced; nothing found that changes advice.
- **Longevity page** structure (no composite, graded evidence, "linked with").

---

## References

### Verified at the source this round [V]

PubMed abstract via E-utilities unless marked "full text".

- Ahmadi MN, et al. Vigorous physical activity, incident heart disease, and cancer: how little is enough? Eur Heart J 2022;43(46):4801-14. PMID 36302460. 15-20 min/week VPA 16-40% lower mortality; nadir 53.6 min/week.
- Bell L, et al. Integrating deloading into strength and physique sports training programmes: an international Delphi consensus approach. Sports Med Open 2023;9:87. PMID 37730925. Expert coaches' consensus; no outcome data.
- Biswas RK, et al. Wearable device-based health equivalence of different physical activity intensities. Nat Commun 2025;16:8315. PMID 41057301. 1 vigorous minute ≈ 4.1 moderate minutes (all-cause), 7.8 (CVD mortality).
- Buyalskaya A, et al. What can machine learning teach us about habit formation? PNAS 2023;120(17):e2216115120. PMID 37068252. More predictable gym-goers less responsive to an intervention.
- Caserman P, et al. Accuracy of smartwatch-based VO2max estimation, Apple Watch Series 7. JMIR Biomed Eng 2024;9:e59459. PMID 39083800. MAPE 15.8%, ICC 0.47, under-reads fit people.
- Cole CR, et al. Heart-rate recovery immediately after exercise as a predictor of mortality. N Engl J Med 1999;341:1351-7. PMID 10536127. Symptom-limited tests, 2,428 patients, mean age 57; ≤12 bpm abnormal; adjusted RR 2.0.
- Coleman M, et al. Gaining more from doing less? A one-week deload period during supervised resistance training. PeerJ 2024;12:e16777. PMID 38274324. A week off: less strength gain, same hypertrophy.
- Currier BS, et al. ACSM Position Stand. Resistance training prescription for muscle function, hypertrophy, and physical performance in healthy adults: an overview of reviews. Med Sci Sports Exerc 2026;58(4):851-72. PMID 41843416. ≥ 10 sets/week for hypertrophy; ≥ 2 sessions/week and ≥ 80% 1RM for strength; periodisation and failure not consistently important.
- Ding D, et al. Daily steps and health outcomes in adults: a systematic review and dose-response meta-analysis. Lancet Public Health 2025;10(8):e668-81. PMID 40713949. 7,000 vs 2,000: HR 0.53; inflection at 5,000-7,000.
- Garcia L, et al. Non-occupational physical activity and risk of CVD, cancer and mortality: a dose-response meta-analysis. Br J Sports Med 2023;57:979-89. PMID 36854652. RR 0.69 at 8.75 mMET-h/week (≈ 150 min).
- Gardiner C, et al. The effect of caffeine on subsequent sleep: a systematic review and meta-analysis. Sleep Med Rev 2023;69:101764. PMID 36870101. −45 min total sleep; 8.8 h (107 mg) and 13.2 h (217.5 mg).
- Gardiner CL, et al. Dose and timing effects of caffeine on subsequent sleep: a randomized clinical crossover trial. Sleep 2025;48(4):zsae230. PMID 39377163. 100 mg up to 4 h before bed no effect; 400 mg within 12 h affects sleep.
- Gardiner C, et al. The effect of alcohol on subsequent sleep in healthy adults. Sleep Med Rev 2025;80:102030. PMID 39631226. REM disruption from ≤ 0.5 g/kg (about 2 drinks).
- Gencer B, et al. Effect of long-term marine ω-3 fatty acid supplementation on the risk of atrial fibrillation. Circulation 2021;144:1981-90. PMID 34612056. HR 1.25; 1.49 above 1 g/day.
- Hooper L, et al. Reduction in saturated fat intake for cardiovascular disease. Cochrane Database Syst Rev 2020;8:CD011737. PMID 32827219. Combined CV events RR 0.83; all-cause mortality RR 0.96.
- Javaloyes A, et al. Training prescription guided by heart-rate variability in cycling. IJSPP 2019;14(1):23-32. PMID 29809080. n = 17; 4-week baseline; no between-group differences.
- Javaloyes A, et al. HRV-guided training vs block periodization in well-trained cyclists. J Strength Cond Res 2020;34(6):1511-8. PMID 31490431.
- Kiviniemi AM, et al. Endurance training guided individually by daily heart rate variability measurements. Eur J Appl Physiol 2007;101:743-51. PMID 17849143. A drop below the 10-day mean − SD meant low intensity or rest.
- Kronenberg F, et al. Lipoprotein(a) in atherosclerotic cardiovascular disease and aortic stenosis: an EAS consensus statement. Eur Heart J 2022;43:3925-46. PMID 36036785. Test Lp(a) at least once in adults.
- Lang JJ, et al. Cardiorespiratory fitness is a strong and consistent predictor of morbidity and mortality among adults. Br J Sports Med 2024;58:556-66. PMID 38599681. High vs low HR 0.47; 11-17% per MET.
- Lee DH, et al. Long-term leisure-time physical activity intensity and mortality. Circulation 2022;146:523-34. PMID 35876019. Nearly maximal benefit at 150-300 VPA or 300-600 MPA min/week; no harm above.
- Madigan CD, et al. Is self-weighing an effective tool for weight loss? Int J Behav Nutr Phys Act 2015;12:104. PMID 26293454. Alone −0.5 kg (NS); no difference between weekly and daily.
- Manresa-Rocamora A, et al. HRV-guided training for cardiac-vagal modulation, aerobic fitness and endurance performance. IJERPH 2021;18:10299. PMID 34639599. VO₂max SMD 0.20 (NS).
- Momma H, et al. Muscle-strengthening activities and non-communicable diseases and mortality. Br J Sports Med 2022;56:755-63. PMID 35228201. 10-17% lower; J-shaped, largest at about 30-60 min/week.
- Morton RW, et al. Protein supplementation and resistance training: meta-analysis and meta-regression. Br J Sports Med 2018;52:376-84. PMID 28698222. No further FFM gain above 1.62 g/kg/day.
- Nedeltcheva AV, et al. Insufficient sleep undermines dietary efforts to reduce adiposity. Ann Intern Med 2010;153:435-41. PMID 20921542. Fat share of loss −55%; fat-free mass loss +60%.
- Paluch AE, et al. Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts. Lancet Public Health 2022;7:e219-28. PMID 35247352. Plateau 8,000-10,000 under 60; 6,000-8,000 from 60.
- Pelland JC, et al. The resistance training dose response: meta-regressions on weekly volume and frequency. Sports Med 2026;56(2):481-505. PMID 41343037. Volume: more gains with diminishing returns; frequency matters for strength, not clearly for hypertrophy.
- Schumann M, et al. Compatibility of concurrent aerobic and strength training for skeletal muscle size and function. Sports Med 2022;52:601-12. PMID 34757594. Hypertrophy SMD −0.01, maximal strength −0.06, explosive −0.28.
- Singer A, et al. Give it a rest: inter-set rest interval duration and muscle hypertrophy. Front Sports Act Living 2024;6:1429789. PMID 39205815. Small benefit above 60 s; nothing detected above 90 s.
- US Preventive Services Task Force. Screening for anxiety disorders in adults. JAMA 2023;329:2163-70. PMID 37338866. B recommendation under 65.
- US Preventive Services Task Force. Screening for depression and suicide risk in adults. JAMA 2023;329:2057-67. PMID 37338872. B recommendation for depression.
- Windred DP, et al. Sleep regularity is a stronger predictor of mortality risk than sleep duration. Sleep 2024;47(1):zsad253. PMID 37738616. **PMC full text**: quintile cut-offs 71.65/78.56/83.16/87.31; top four quintiles 20-48% lower mortality; monotonic; top quintile HR 0.70 (full model).

### PubMed record checked, numbers from elsewhere [R]

- Baron KG, et al. Orthosomnia. J Clin Sleep Med 2017;13:351-4. PMID 27855740.
- Ference BA, et al. Low-density lipoproteins cause atherosclerotic cardiovascular disease (EAS consensus). Eur Heart J 2017;38:2459-72. PMID 28444290.
- Furukawa Y, et al. Components and delivery formats of CBT for chronic insomnia. JAMA Psychiatry 2024. PMID 38231522.
- Grundy SM, et al. 2018 AHA/ACC guideline on the management of blood cholesterol. J Am Coll Cardiol 2019;73:e285-350. PMID 30423393.
- Jones DW, et al. 2025 AHA/ACC guideline for high blood pressure in adults. Hypertension 2025;82(10):e212-316. PMID 40811516. The record and scope were checked; the category cut-offs come from summaries.
- Kaminsky LA, et al. Updated reference standards for cardiorespiratory fitness (FRIEND). Mayo Clin Proc 2022. PMID 34809986.
- Klasnja P, et al. HeartSteps micro-randomized trial. Ann Behav Med 2019;53:573-82. PMID 30192907.
- Mishra T, et al. Pre-symptomatic detection of COVID-19 from smartwatch data. Nat Biomed Eng 2020;4:1208-20. PMID 33208926.
- Plews DJ, et al. Heart rate variability in elite triathletes. Eur J Appl Physiol 2012;112:3729-41. PMID 22367011.
- Shcherbina A, et al. Accuracy in wrist-worn, sensor-based measurements of heart rate and energy expenditure. J Pers Med 2017;7(2). PMID 28538708.
- Stamatakis E, et al. Vigorous intermittent lifestyle physical activity and mortality. Nat Med 2022;28:2521-9. PMID 36482104.
- Watson NF, et al. Recommended amount of sleep for a healthy adult (AASM/SRS). Sleep 2015;38(6):843-4. PMID 26039963.
- Zheng Y, et al. Self-weighing in weight management. Obesity 2015;23:256-65. PMID 25521523.

### Not verified this round [NV]

- Anderberg 2025; Linardon & Messer 2019 (disordered eating and apps): from `healthy-living-2026-11.md`.
- ASCEND and VITAL omega-3 trials; REDUCE-IT: from memory.
- Bull FC, et al. WHO 2020 guidelines on physical activity and sedentary behaviour. Br J Sports Med 2020;54:1451-62.
- Canadian Centre on Substance Use and Addiction. Canada's Guidance on Alcohol and Health, 2023: checked in `longevity-insights.md`, not this round.
- Doherty 2025 (composite health scores): cited in `cleanup-2026-11.md`; **not found on PubMed** under that author with these terms. Treat as unconfirmed until the record is found.
- Hew-Butler T, et al. Exercise-associated hyponatremia consensus. Clin J Sport Med 2015.
- Helms ER, et al. 2014 (IJSNEM; JISSN); Garthe 2011; Iraki 2019 (rates and protein in a deficit): carried from the code.
- Ibrahim 2024; Krebs & Duncan 2015; Harkin 2016: from `cleanup-2026-11.md` and `healthy-living-2026-11.md`.
- IOC REDs consensus (Mountjoy 2023): from the code.
- Laborde S, et al. Front Psychol 2017: from `daytime-vitals.md`.
- Quer 2021; Mason 2022 (illness detection): from the code.
- Stawarz K, et al. CHI 2015 (clock reminders vs event cues): not indexed in PubMed.
- Trommelen J, et al. Cell Rep Med 2023 (100 g protein meal): from memory.
- USPSTF 2021 blood-pressure screening intervals; CDC influenza vaccination; USPSTF 2021 colorectal screening from 45: from memory.
- WHO 2023 saturated and trans fat guideline (< 10% of energy): from memory.
- Whether Cronometer writes `dietaryFatSaturated` to Apple Health: to check on the phone.
