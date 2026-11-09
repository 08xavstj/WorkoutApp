# Workout prescription audit (November 2026)

The question: does the trainer build the right workouts for a man in his 30s who lifts at a commercial gym in kg, wears an Apple Watch, and wants to lose fat, build muscle and get stronger? He reports that sessions have been too short, too easy, about half the weight he can lift, 15 reps, too few sets and missing abs. Women, older lifters, novices, dumbbell-only gyms, barbell-only home gyms and machine-only gyms are checked too.

Scope: `Packages/AppCore` (WorkoutPlanner, LoadEstimator, Equipment/GymProfile, TrainingBlock, VolumeProgression, MuscleCoverage, AbsFinisher, WarmUp, WarmUpRoutine, Autoregulation, TrainingTools, WeeklyPlan, Goals) plus how the app shows and logs weights (`App/Features/Workout`, `App/Features/Trainer`, `App/Features/Coach`, `App/Services/GymStore.swift`). This was a read-only audit. No code was changed, and Swift wasn't available in the sandbox, so every number below was worked by hand from the code. Before a fix ships, each finding marked **(verify with a test)** should get a failing test first.

---

## 1. Research summary

The strongest sources come first: position stands, then meta-analyses, then single trials. "App choice" means no study gives that number.

### Volume (sets per muscle per week)
- **More weekly hard sets grow more muscle, with diminishing returns.** Schoenfeld, Ogborn & Krieger, J Sports Sci 2017;35:1073 (dose-response meta-analysis: 10+ sets/muscle/week beat fewer). Pelland et al., Sports Med 2026;56(2):481-505 (67 studies; hypertrophy keeps rising past about 20 fractional sets/week with diminishing returns; strength levels off much sooner; **fractional counting**, where an indirect set counts as 0.5, fit best). [sponet record](https://sponet.de/sponet/Record/4097139?lng=en), [SportRxiv preprint](https://sportrxiv.org/index.php/server/preprint/view/460), [commentary](https://train.fitness/personal-trainer-blogs/not-all-sets-are-created-equal). Critique: the volume-hypertrophy curve rests on about 35 hypertrophy studies ([Steele et al. preprint 2026](https://d296qbqev3kq48.cloudfront.net/wp-content/uploads/2026/04/27080050/pre_print.pdf)).
- **Per-session ceiling**: the benefit of piling sets into one session flattens after roughly 6-10 fractional sets per muscle (Pelland 2026 per-session analysis; Remmert et al., SportRxiv 2025 preprint). This is the evidence behind `VolumeProgression.sessionCap` = 10.
- **ACSM 2026 position stand** (overview of 137 systematic reviews, Med Sci Sports Exerc 2026, doi 10.1249/MSS.0000000000003897): train every major muscle group **at least 2 days/week**; strength responds best to **heavy loads (≥80% 1RM)**, full range of motion, 2-3 sets per exercise, done at the start of the session, ≥2 sessions/week. Failure, equipment type, time under tension and periodization did not consistently change outcomes. [ACSM news](https://www.newswise.com/articles/acsm-unveils-landmark-2026-resistance-training-guidelines-first-update-in-17-years), [infographic](https://acsm.org/wp-content/uploads/2026/03/Resistance-Training-Position-Stand-infographic.pdf), [McMaster record](https://experts.mcmaster.ca/scholarly-works/3873753), [NFPT commentary](https://nfpt.com/beyond-the-guidelines-what-the-2026-acsm-position-stand-gets-right-and-what-it-changes-for-personal-trainers/).

### Frequency
- When volume is equal, frequency has little effect on hypertrophy (Schoenfeld, Grgic & Krieger, J Sports Sci 2019;37:1286). With volume not equal, 2×/week beat 1×/week (Schoenfeld, Ogborn & Krieger, Sports Med 2016;46:1689). Frequency does affect strength (Grgic et al., Sports Med 2018;48:1207; Pelland 2026). In practice, 1×/week caps how many productive sets a muscle can get, because of the per-session ceiling above.

### Load and rep range by goal
- **Hypertrophy** is similar from about 30% to 85% 1RM when sets go near failure (Schoenfeld et al., JSCR 2017;31:3508; Lopez et al., MSSE 2021;53:1206).
- **Strength** gains are larger with heavy loads: ≥80% 1RM, about 1-6 reps (Schoenfeld 2017; Lopez 2021; ACSM 2026).
- For "muscle + strength" together, the usual evidence-based structure is heavy main lifts (≈3-6 or 4-8 reps) plus moderate accessories (8-15). Both adaptations are covered, and heavy work is specific to strength (Schoenfeld 2017; ACSM 2026).

### Effort (proximity to failure)
- Hypertrophy rises as sets end closer to failure. Strength barely changes across 0-5 RIR (Robinson et al., Sports Med 2024;54:2209; [FAU summary](https://www.fau.edu/newsdesk/articles/muscle-growth-strength-study), [Abertay record](https://rke.abertay.ac.uk/en/publications/exploring-the-dose-response-relationship-between-estimated-resist/)). Failure vs non-failure makes no clear difference to hypertrophy (Refalo et al., Sports Med 2023;53:649). In an RCT, 0 vs 1-2 RIR gave similar growth (Refalo et al., J Sports Sci 2024).
- Lifters misjudge RIR by about 1 rep, more on high-rep sets and far from failure (Halperin et al., Sports Med 2022;52:377). The RIR-based RPE scale works reasonably near failure (Helms et al., Strength Cond J 2016;38(4):42; Zourdos et al., JSCR 2016;30:267).
- So 0-2 RIR suits hypertrophy-focused sets, and 1-3 RIR suits heavy compounds. RIR 3-4 is a deliberately easy day.

### Progression
- ACSM 2009 (Ratamess et al., MSSE 2009;41:687): add **2-10%** once the target reps are beaten by 1-2 reps on two consecutive sessions. Novices can progress faster.
- Adding reps and adding load gave similar muscle and strength gains over 8 weeks (Plotkin et al., PeerJ 2022;10:e14142).
- Epley: each rep in reserve ≈ 3.3% of 1RM, so moving the target from 10 reps to 6 reps at the same RIR means about **11% more weight**, not 2.5%.

### Rest
- 3 min beat 1 min for strength and size in trained men (Schoenfeld et al., JSCR 2016;30:1805). Rest over 2 min is better for strength in trained lifters (Grgic et al., Sports Med 2018;48:137). Rest over 60 s gives slightly more hypertrophy, with little extra past about 90 s (Singer et al., Front Sports Act Living 2024).

### Exercise selection and range of motion
- Training at long muscle lengths: overhead triceps extensions grew the triceps more than pushdowns (Maeo et al., EJSS 2023). Seated leg curls beat lying leg curls (Maeo et al., MSSE 2021;53:825). Leg extensions with the seat reclined grew the rectus femoris more (Pedrosa et al., EJSS 2022). Standing calf raises beat seated for the gastrocnemius (Kinoshita et al., 2023). Full ROM ≥ partial overall, and lengthened partials are at least as good, best shown for calves (Wolf et al., IJSC 2023; Kassiano et al., JSCR 2023). The evidence is small and mixed for regional growth ([summary](https://www.strongerbyscience.com/stretch-mediated-hypertrophy/), [overview](https://getfitcraft.com/science/lengthened-partials-research)).
- Some exercise variation spreads regional growth (Kassiano et al., JSCR 2022, review). Too much rotation slows strength gains on the main lifts.
- Order: lifts done first gain the most strength. Growth doesn't depend on order (Nunes et al., EJSS 2021; ACSM 2026).
- Unilateral and bilateral training give similar strength and size overall, with gains specific to the task trained (meta-analytic evidence. I didn't re-verify it in this pass, so treat the claim as moderate).

### Dumbbell vs barbell loads
- Dumbbell bench 1RM (both dumbbells together) is about **17% below** barbell bench (Saeterbakken et al., JSCR 2011;25:2312), so about **0.41-0.42 × barbell per hand**. Standing dumbbell press is about 7% below standing barbell press, and seated dumbbell press about 10% below (Saeterbakken & Fimland, JSCR 2013). [Secondary summary](https://breakingmuscle.com/the-overhead-press-the-actual-difference-between-seated-standing-dumbbell-and-barbell-0/). These come from secondary summaries; I couldn't open the originals.

### Strength standards (first-time loads)
- Crowd-sourced and coaching tables (ExRx, Symmetric Strength, Strength Level) are the only data. They are not studies and the spread between people is wide. For an 85 kg man, approximate 1RM levels are: bench about 0.7 × BW "beginner", ~1.0 "novice", ~1.3 "intermediate"; squat about 0.9 / 1.3 / 1.7; deadlift about 1.1 / 1.6 / 2.0. For women, about 55-65% of the male ratios on upper-body lifts and about 70-75% on lower-body lifts (Roberts, Nuckols & Krieger, JSCR 2020: relative gains are similar between sexes).

### Warm-up, deload, concurrent training, older adults
- Specific warm-up sets improve strength and power performance (Fradkin et al., JSCR 2010;24:140; Ribeiro et al., JSCR 2020). The ramp percentages are coaching practice.
- Deloads: Delphi consensus is about 1 week at reduced volume and/or intensity (Bell et al., Sports Med Open 2023). One RCT found a 1-week break gave no hypertrophy advantage and slightly less strength (Coleman et al., PeerJ 2024). Both planned and fatigue-triggered deloads are defensible.
- Concurrent training (cardio for fat loss): interference mainly hits explosive strength and lower-body hypertrophy when cardio is high in volume, running-based, and done near lifting (Wilson et al., JSCR 2012;26:2293; Schumann et al., Sports Med 2022;52:601). Separating them by about 6 h or more, or using cycling, reduces it.
- Older adults: progressive, moderate-to-heavy training 2-3×/week plus **power (fast concentric) work** and balance (Fragala et al., NSCA position statement, JSCR 2019;33:2019).
- Time-efficient training: fewer sets of multi-joint lifts, supersets, staying near failure (Iversen et al., Sports Med 2021).

---

## 2. Worked example: what this user actually gets

Assumptions: 85 kg man, goals lose + muscle + strength, recovery 70%, block week 1, kg commercial gym preset, 4 days/week (the default for muscle/strength goals, `WeeklyPlan.swift:252-256`), upper/lower × 2, 60 min, abs finisher 5 min.

- Style: goals contain both `.strength` and `.muscle`, so `GoalPlanner.trainingStyle` returns **`.muscle`** (`Goals.swift:342-347`). The strength goal is ignored.
- Effort: block week 1 is RIR 3, so session RPE is 7. Compounds get `min(8.5, 7 + 0.5)` = **RPE 7.5**, reps **6-10**. Isolation gets RPE 8.5, reps **10-15** (`WorkoutPlanner.swift:608-610`).
- Upper day at 60 min: bench 4, barbell row 3, OHP 4, pulldown 3, curl 3, overhead triceps 3. That's 20 working sets plus 3 + 3 ramp sets, about 60 min. Worked through `applySetGoals` (chest goal 5, lats 5, shoulders 5, biceps 5, triceps 5) and then `fit`.
- **No lateral raise, rear-delt, fly or core work** in either upper day. Those only come in at 75 min (`extraSlot`) or, for core, in Pull/Lower/Full.
- Chest gets 4 direct sets per upper day, so 8 per week, under the app's own 10-set floor. Side and rear delts get 0 direct sets per week.
- First-time loads (no history, intermediate, `LoadEstimator`):
  - Bench: 85 × 0.5 × 1.3 = 55.3 kg "1RM". For 10 reps at 2.5 RIR: 55.3 / (1 + 12.5/30) = 39.0, × 0.85 = **32.5 kg × 10**. A realistic intermediate (≈105 kg 1RM) does about 74 kg for 10 at 2.5 RIR, so this is **44%**.
  - Back squat: 85 × 0.75 × 1.3 = 82.9, giving 58.5, × 0.85 = **47.5 kg**. A realistic ≈140 kg 1RM does about 99 kg, so this is **48%**.
  - With the default `trainingStatus` `.novice` (`WorkoutBuilderView.swift:258`) the multiplier is 1.0 and the loads drop further: bench **25 kg**, squat **37.5 kg**.
- After the first session at 32.5 × 10 @ RPE 5 (8 reps left over the target), the next session suggests **35 × 6** (one 2.5 kg jump, back to the bottom of the range). Autoregulation never moves set 2 off set 1.

This reproduces all six complaints: half the weight, 15 reps, too easy, too few sets, no abs outside the finisher, and (on short picks) sessions that end early.

---

## 3. Ranked findings

Severity: **Critical** = the prescription is wrong for the stated goal on default settings. **High** = wrong for many users or stalls progress. **Medium** = suboptimal, or wrong in some setups. **Low** = polish or wording.

| # | Severity | Finding | Where |
|---|---|---|---|
| 1 | Critical | First-time loads come out at about 25-50% of realistic | `LoadEstimator.swift:58, 64-70, 101-102, 189-205` |
| 2 | Critical | A too-light start can't recover: progression ignores a big RIR gap, and autoregulation skips set 1 and sets over 12 reps | `WorkoutPlanner.swift:1259-1301`; `Autoregulation.swift:28, 101-102` |
| 3 | High | "Muscle + strength" maps to the muscle style; no heavy (≥80% 1RM) work | `Goals.swift:342-347`; `WorkoutPlanner.swift:601-614` |
| 4 | High | A load step resets reps to the bottom of the range: about 2.5-3 reps easier than the target | `WorkoutPlanner.swift:1268-1269, 1301` |
| 5 | High | Isolation lifts on set progression never add weight once weekly set goals apply **(verify with a test)** | `Autoregulation.swift:196-204`; `WorkoutPlanner.swift:738-746, 1271, 840-844, 1008-1020` |
| 6 | High | 3- and 5-day weeks default to push/pull/legs: each muscle about 1×/week, under ACSM 2026's ≥2× and capped at 10 sets/week | `WeeklyPlan.swift:258-276`; `VolumeProgression.swift:282-289` |
| 7 | Medium-High | Upper / Full body slot lists leave out side and rear delts, chest isolation and (Full) vertical pull below 75 min | `WorkoutPlanner.swift:72-95` |
| 8 | Medium-High | Abs are missing from most sessions; coach-made plans skip the finisher and the weekly set goals | `WorkoutPlanner.swift:74-79`; `CoachView.swift:260-276` |
| 9 | Medium | Weekly volume restarts at 10 sets/muscle whatever you were doing, and after any 2-week gap | `VolumeProgression.swift:4, 268`; `TrainingBlock.swift:189-205` |
| 10 | Medium | Unilateral exercises are timed as one set but take two | `WorkoutPlanner.swift:1343, 1366-1385` |
| 11 | Medium | Bodyweight lifts (pull-ups, dips, push-ups) get no progression at all | `WorkoutPlanner.swift:623-651` |
| 12 | Medium | Equipment-limited gyms lose key patterns; catalog missing staples (hip thrust, Bulgarian split squat, deadlift, chest-supported row…) | `WorkoutPlanner.swift:116-237` |
| 13 | Medium | Dumbbell weights: "per hand" shown in headers but not on set rows or stepper; volume counts one hand; kg preset dumbbells and stack steps unrealistic | `ActiveWorkoutView.swift:1587, 1657, 1905`; `WorkoutSummary.swift:119`; `Equipment.swift:151-154` |
| 14 | Medium | Double progression keys off the single best set, not every working set | `App/Services/GymStore.swift` (`LiftHistory.make`) |
| 15 | Medium | Warm-ups: 9 of 30 min go to ramp sets in short sessions; in full-body, the first upper-body lift gets only one feeler set | `WarmUp.swift:35-56`; `WorkoutPlanner.swift:1086-1098` |
| 16 | Medium | Women's and older adults' starting standards and programming | `LoadEstimator.swift:189-205`; no age input to `plan` |
| 17 | Low-Medium | Long sessions (90-120 min) can't be filled and sessions under 20 min are thin; the note covers it but the pick is still offered | `WorkoutPlanner.swift:1023-1048, 900-904` |
| 18 | Low | Easy-week stacking: RIR 3 week 1 + RIR 4 low-recovery floor + deload | `WorkoutPlanner.swift:522-541`; `TrainingBlock.swift:136-154` |
| 19 | Low | Push day runs three presses before any isolation; Pull day has two biceps isolations | `WorkoutPlanner.swift:74-75` |
| 20 | Low | Rest: muscle style gives squats and deadlifts the same 2 min as presses | `TrainingTools.swift:25-31` |
| 21 | Low | Same jump rule upper and lower; novices could add load faster | `WorkoutPlanner.swift:1174-1181` |
| 22 | Low | Doc drift: workout-science.md says each muscle gets ~2×/week and "no ramp sets" | `docs/research/workout-science.md:24, 32` |

---

## 4. Findings in detail

### 1. Critical: first-time loads are 25-50% of realistic
**What the code does.** The body-weight fallback uses 1RM fractions from the "untrained" column, rounded down: bench 0.5 × BW, squat 0.75, RDL 0.9, OHP 0.35, row 0.5 (`LoadEstimator.swift:189-205`). `statusMultiplier` gives `.untrained` and `.novice` the same 1.0, intermediate 1.3 and advanced 1.6 (`:64-70`). The target is then taken at the **top** of the rep range plus RIR (`:101`), and cut again to **85%** (`:58, :102`). The same 85% applies when converting from a related lift you have logged.

**Why it's wrong.** Even the beginner columns of the coaching tables sit higher, about bench 0.7 / squat 0.9 / deadlift 1.1 × BW for men. The novice column is about 1.4× beginner, not 1.0×, and intermediate about 1.85×. On top of that, three conservative steps stack: low fractions, the top of the range, and ×0.85. The worked example gives 32.5 kg bench and 47.5 kg squat for a trained 85 kg man. The default status is `.novice` when the user hasn't set one, which gives 25 kg / 37.5 kg. The UI note "start here and adjust after set 1" doesn't help, because autoregulation won't act on set 1 (finding 2).

**Change.**
- Use beginner-column fractions as the floor, and per-status fractions instead of a multiplier. Men: bench 0.7 / 1.0 / 1.3 / 1.6; squat 0.9 / 1.3 / 1.7 / 2.1; RDL (about 0.8 × deadlift) 0.9 / 1.25 / 1.6 / 2.0; OHP 0.45 / 0.6 / 0.8 / 1.0; barbell row 0.6 / 0.85 / 1.1 / 1.35; for untrained / novice / intermediate / advanced. Women: about 0.6 × the male upper-body values and about 0.75 × lower-body. Cite them as crowd-sourced strength standards, not studies, and say so in the UI.
- Estimate at the **middle** of the rep range (8 for 6-10), not the top. Use `conservativeFraction` 0.9 for history-based conversions and 0.85 only for the body-weight fallback.
- Ask "how long have you lifted?" before the first plan, and offer an optional "what do you bench/squat for 5?" field. Even one logged set beats any table.
- Tests: an 85 kg intermediate man gets a bench starting load within 55-75 kg for 6-10 reps at RIR 2-3. The same lifter with `.untrained` stays at 40 kg or less.

### 2. Critical: a too-light start never catches up
**What the code does.** For a lift with history, `progression` checks only `lastReps` against the range and whether `lastRPE` ≤ today's target (`effortHeld`, `WorkoutPlanner.swift:1259`). At the top of the range it takes **one** smallest jump (`:1301`). The e1RM path runs only when last time's reps went past the top (`:1298`). A set of 10 reps at RPE 5 with a target of RPE 7.5 is treated the same as one at RPE 7.5. During the session, `Autoregulation.nextSet` returns nil when the logged set is the first working set (`setNumber > 1`) or has more than 12 reps (`Autoregulation.swift:28, 101-102`). It also moves at most one jump of ≤10%, once per exercise.

**Why it's wrong.** RIR carries the information that the load is too light. A 32.5 kg × 10 @ RPE 5 bench implies an e1RM of 32.5 × (1 + 14/30) ≈ 48 kg. The RPE is capped at 4 RIR, so the real e1RM is likely higher. The right next load for 6-10 reps at RIR 2.5 is about 48 / 1.42 ≈ 34 kg the first time, and it keeps climbing only one step each session. Climbing from 25 kg to 70 kg at 2.5 kg per session at the top of the range takes about 18 jumps × 3-4 sessions each, which is months of "too easy". Set 1 of a first exposure is where autoregulation matters most (Hickmott et al., Sports Med Open 2022: RPE-based load adjustment works as well as fixed loading). The 12-rep limit rules out every 10-15 isolation set in the muscle style. Halperin et al. 2022 show errors grow with reps, which argues for a wider tolerance, not for switching it off.

**Change.**
- `progression`: when `lastRPE` is known and `(10 − lastRPE) − (10 − rpe) ≥ 2`, the last set was clearly easier than planned. In that case, compute the load from that session's e1RM (RIR uncapped up to 6, flagged as low accuracy) for `targetReps` at today's RIR. Allow it to move up to +15% upper body / +20% lower body per session, and up to +30% for the first 3 exposures of a lift. Lines 1294-1301.
- `Autoregulation.nextSet`: allow set 1 to adjust when the lift's load came from `LoadEstimator` or from fewer than 3 logged sessions. Allow up to 2 jumps when the gap is ≥3 reps. Raise `maxReps` to 20, with `toleranceReps` 1.5 above 12 reps.
- Tests: a 25 kg first session logged at 10 @ RPE 5 makes the next session suggest ≥32.5 kg. A logged set 1 at RPE 5 against a target of 7.5 makes set 2 suggest +2 jumps.

### 3. High: "muscle + strength" drops the strength goal
**What the code does.** `trainingStyle` returns `.strength` only when muscle isn't also chosen (`Goals.swift:343`), so this user gets `.muscle`: compounds 6-10, isolation 10-15, and no set at ≥80% 1RM. Fat loss doesn't change the style at all.

**Why it's wrong.** ACSM 2026 says strength gains are maximised by ≥80% 1RM. Hypertrophy is load-independent (Schoenfeld 2017; Lopez 2021), so heavy main lifts cost nothing for muscle. A 6-10 range at RIR 2.5 works out to about 65-72% 1RM. Isolation at 10-15 is evidence-supported for muscle, but the user experiences it as "15 reps", and the high reps make RIR estimates worse (Halperin 2022). During fat loss, heavy loading helps keep strength and muscle (ACSM 2026; general consensus, low-certainty evidence).

**Change.**
- Add `TrainingStyle.strengthAndMuscle` (or treat `.balanced` this way) for `focuses ⊇ {muscle, strength}`. The first compound of the session gets 4-6 reps @ RIR 2 (RPE 8), other compounds 6-10 @ RIR 2, isolation 8-12 @ RIR 1. Rest 3 min on the first compound, 2-2.5 min on others, 90 s on isolation.
- Change `.muscle` isolation from 10-15 to **8-12** (core 10-15). Keep 12-20 for the endurance style.
- Fat loss: keep the lifting prescription the same. Volume can drop toward the bottom of the band (10-12 sets) when the deficit is aggressive (>0.75% BW/week). Mark that as low-certainty evidence.
- Update `GoalsView.swift:224`'s style text and `TrainingBlock.length(for:)`.

### 4. High: a load step makes the next session too easy
**What the code does.** On reaching the top, `progression` returns `Progression(load: next, targetReps: reps.lowerBound)` (`WorkoutPlanner.swift:1301`; rep and set modes at `:1269`). With 6-10 reps: 80 × 10 @ RPE 7.5 becomes **82.5 × 6** next time.

**Why it's wrong.** 80 × 10 at 2.5 RIR implies an e1RM of about 113 kg. At 82.5 kg you could do about 11 reps to failure, so 6 reps leaves about **5 RIR** against a target of 2.5. The user then needs 4 more sessions to climb back to 10. ACSM 2009 sizes the jump at 2-10%. The planner instead takes the smallest jump and resets reps to the bottom, so the weight moves about 2.5% and the reps fall about 40%.

**Change.** After a step, set `targetReps` to the reps the e1RM predicts at today's RIR, clamped to the range: `min(upper, max(lower, floor(30 × (e1RM / load − 1)) − RIR))`. That gives 82.5 × 8. Alternatively, size the jump so it lands at `lower + 2` reps, capped at 10% (`routineJumpFraction`), and take that jump rounded to what the gym can load. Update `progressionNote` ("+2.5 kg: aim for 8").

### 5. High: set-mode isolation lifts stall (verify with a test)
**What the code does.** `ProgressionMode.suggested` gives `.sets` to isolation lifts when the next jump is ≤10%, for example machine/stack ≥50 kg in 5 kg steps or dumbbells ≥20 kg in 2 kg steps (`Autoregulation.swift:196-204`). In `.sets` mode the rep target caps at the top of the range (`WorkoutPlanner.swift:1271`). The load only steps up when `lastSets ≥ 5` or reps ≥ top + 2 (`:738-746`). With weekly goals (always passed from the builder when a weekly plan exists), `applySetGoals` sets the exercise's sets to the muscle's share, typically 3 (`:1008-1020`). Earned sets are then dropped for targeted muscles (`:840-844`). The user never gets the 5th set, is never asked for 17 reps, and sees "Same weight: hit 15 reps to add a set" every week.

**Change.** Option (a): drop `.sets` as a default. Use `.load` with the big-jump extra reps for every loaded lift and keep `.sets` only as an opt-in. Option (b): in `.sets` mode, let `earnedLoadStep` trigger when `lastReps ≥ upper` at the effort target on **the sets planned that day**, whatever the count. Add a test: leg extension 60 kg (machine 5 kg steps), weekly quad goal 3 sets, three sessions at 15 reps @ target. The fourth session should suggest 65 kg.

### 6. High: 3-day and 5-day weeks train each muscle about once a week
**What the code does.** `focusRotation` returns push/pull/legs for 3, 5 and 6 days (`WeeklyPlan.swift:262-276`). It returns upper/lower for 2 days. `sessionCap` limits a session to 10 direct sets per muscle (`VolumeProgression.swift:282-289`). On a 3-day week each muscle gets one session, so at most 10 sets/week: the bottom of the app's own 10-20 band. Five days gives legs once. `workout-science.md:24` says the rotation hits each muscle "~2×/week".

**Why it's wrong.** ACSM 2026: every major muscle group ≥2 days/week. Frequency matters for strength (Grgic 2018; Pelland 2026). The per-session ceiling means 1×/week can't reach 12-20 productive sets.

**Change.** Use **full body ×3** for 3 days, or upper / lower / full. Use **full body ×2** for 2 days. For 5 days use upper / lower / push / pull / legs. Keep PPL for 6 days (PPL ×2). For novices and older adults, prefer full body at 2-3 days. Fix the doc line.

### 7. Medium-High: muscle coverage gaps in Upper and Full Body
**What the code does.** Upper is `[horizontalPress, horizontalRow, verticalPress, verticalPull, biceps, triceps]`, with `extraSlot` = lateral raise only at ≥75 min. Full is `[squat, horizontalPress, horizontalRow, hinge, verticalPress, core]` (`WorkoutPlanner.swift:72-95`). On the default 4-day U/L at 60 min, the week has **0 direct sets** for side delts, rear delts and chest isolation, 8 for chest, and the core slot only in Lower. Full body has a vertical press but no vertical pull below 75 min. Pressing then outweighs pulling for the shoulder girdle.

**Change.**
- Give each focus an A/B variant that alternates week to week or session to session.
  - Upper A: flat press, row, vertical pull, lateral raise, biceps, triceps.
  - Upper B: incline press, vertical pull, row (chest-supported), OHP, rear delt, triceps/biceps.
  - Full A: squat, bench, pulldown, RDL, lateral raise, core.
  - Full B: leg press or split squat, OHP or incline, row, leg curl, rear delt, core.
- Put `.lateralRaise` before `.biceps` in Upper.
- Swap Full's `.verticalPress` for `.verticalPull` and let B carry the press.
- Use `MuscleCoverage` (it already tracks side and rear delts lumped as "shoulders") to split `.shoulders` into front/side/rear, so rear delts aren't credited by pressing.

### 8. Medium-High: abs missing
**What the code does.** `.core` is the 6th slot in Pull/Lower/Full only. Below 60 min (≤5 exercises) it never makes the cut. Push/Legs/Upper never include it. The abs finisher (default 5 min = 2 moves × 2 sets) is only added in `WorkoutBuilderView`. `CoachView.swift:260-276` builds plans **without** the finisher, without `muscleSetGoals` and without `prioritySlots`. So "ask the coach for a workout" gives a different, abs-free plan from the builder.

**Change.** Have one shared `PlanRequest` builder used by both the builder and the coach, so they get the same goals, priority slots and finisher. Keep the finisher default at 5 min. Make sure it's on for every focus, including when sessions start from Today or a weekly plan day. That gives 4 sets × 3-4 sessions = 12-16 sets/week, inside 10-20. Prefer loaded flexion (cable crunch) and hanging leg raises over 20-30 s planks for the muscle goal (Contreras & Schoenfeld 2011, narrative review; low evidence).

### 9. Medium: weekly volume ignores your history
**What the code does.** `VolumeProgression.startingSets = 10` for every muscle in week 1 of every block (`:4, :268`). It adds 1-2 sets/week. Strength and balanced styles cap at 16 (`ceiling`). `TrainingBlock.advanced` restarts a block after **2 weeks away** (`TrainingBlock.swift:189, 200`), and also every 5-6 weeks.

**Why it's wrong.** A lifter used to 15-18 sets drops to 10 every block: "too few sets". The meta-analyses support starting around current volume and adding to it (Pelland 2026: diminishing but positive returns). `fill`'s second pass helps only when the session has spare time.

**Change.** Start week 1 at `clamp(median of the last 4 weeks' fractional sets for that muscle, 10, ceiling − 4)`. After a break of 2-3 weeks, start at 80% of that. Restart only after 4+ weeks away. Mujika & Padilla 2000 found strength kept for about 3 weeks of detraining.

### 10. Medium: unilateral sets are timed as one
**What the code does.** `estimatedMinutes` counts every set as `workSecondsPerSet` = 45 s plus rest (`WorkoutPlanner.swift:1343, 1366-1385`). Split squats, walking lunges, one-arm dumbbell rows and one-arm overhead extensions take about twice the work time, so each set runs 45 s or more longer than estimated. Four sets of split squats run about 3-4 min over.

**Change.** Add `isUnilateral` to `CatalogExercise` (split squat, lunge, one-arm row, one-arm extension, kettlebell swing one-arm, Pallof press). Count `2 × workSecondsPerSet` for those. Optionally add a short 15-20 s switch rest.

### 11. Medium: bodyweight lifts don't progress
**What the code does.** `prescribe` only runs progression when `choice.load != nil` (`WorkoutPlanner.swift:623`). Pull-ups, chin-ups, dips, push-ups and walking lunges get the static range ("6-10") every time, with no target reps, no progression note and no step to added weight. `ProgressionMode.suggested` returns `.reps` for them, but it's never applied.

**Change.** For load-nil exercises, apply rep progression from `lastReps` (+1 per session up to the top + 2). Then suggest "add 2.5-5 kg on a dip belt", or the next harder variant (push-up → feet-elevated → weighted, chin-up → weighted). Below the bottom of the range, suggest an assisted machine or band. Record added weight as the load.

### 12. Medium: equipment fallbacks and missing staples
**What the code does.** Checked against the catalog (`WorkoutPlanner.swift:116-237`):
- **Dumbbells-only** (`homeDumbbells`: DB, bench, pull-up bar, bands): no leg curl or leg extension → hamstring and quad isolation silently dropped. Goblet squat needs a **kettlebell** (`Goblet_Squat` load `.kettlebell`), so DB users get "Dumbbell Squat". No Bulgarian split squat, single-leg RDL, DB hip thrust, Nordic curl or DB leg curl. Calves: DB calf raise. Everything else is fine.
- **Barbell-only home gym** (barbell, rack, bench, pull-up bar): no lateral raise or rear delt (needs DB/cable/bands); no chest fly; triceps falls to **bench dips** (hard on the shoulder; no barbell skull crusher or close-grip bench in the catalog); no leg curl.
- **Machines-only** (machines + cable): **no hip hinge at all** (RDL/DB RDL/KB swing need free weights; no back extension, glute-ham raise or hip-thrust machine). Incline press falls to feet-elevated push-ups. Single-leg falls to bodyweight walking lunges.
- **Missing staples everywhere**: hip thrust or glute bridge (glutes are never the primary muscle of any slot, so `MuscleCoverage` can't target them), conventional or trap-bar deadlift, front or hack squat, chest-supported row / T-bar, incline DB curl or preacher curl (long-length biceps), seated calf raise (soleus), adductors, back extension, reverse pec deck, machine lateral raise, Smith squat, landmine press.
- **Redundant**: Pull day's `biceps` and `hammerCurl` slots (two curls) when there's no second back exercise below 75 min.

**Change.** Add catalog entries with the right `requires`:
- `Dumbbell_Goblet_Squat` (`.dumbbell`)
- `Bulgarian split squat` (`.dumbbell, .bench`)
- `Barbell_Hip_Thrust` (`.barbell, .bench`), `Dumbbell hip thrust`
- `Barbell_Deadlift`
- `Hack/front squat`
- `Chest-supported DB row` (`.dumbbell, .bench`)
- `Incline DB curl`
- `Seated calf raise` (machine)
- `Back extension` (bodyweight/station)
- `Nordic curl` (bodyweight)
- `Close-grip bench` / `Barbell skull crusher` (`.barbell, .bench`), ahead of bench dips
- `Reverse pec deck` (machine)
- `Machine lateral raise`
- `Band leg curl` (`.bands`)

Add a `.hipThrust` slot to Lower/Legs (glutes primary). Replace Pull's `hammerCurl` with a second row/pull variant below 75 min.

### 13. Medium: dumbbell display, logging and gym presets
**What the code does.**
- Dumbbell loads are per hand everywhere in AppCore (`Equipment.swift:176`, `PlannedExercise.load`, `LoadEstimator` factors ≈0.4/hand, consistent with Saeterbakken 2011's ~17% deficit). e1RM and progression are per-hand throughout, which is correct and consistent.
- **UI:** headers say "24 kg per hand" (`Prescription.load`). The **set rows and the stepper show just "kg"** (`ActiveWorkoutView.swift:1587, 1657, 1905`), so a user may log 48 (the pair).
- Volume and tonnage count one hand (`WorkoutSummary.volume`), so dumbbell volume is half what it should be next to barbell volume.
- kg preset dumbbells run 2-50 kg in 2 kg steps (`Equipment.swift:151`). Many commercial kg racks go 2.5 kg steps above 10 kg and up to 50-60 kg. 50 kg per hand caps a strong DB bench.
- Cable stacks of 5 kg steps (`:153`) make light cable work a 50-100% jump (5 → 10 kg lateral raise). That forces rep mode up to 17 reps: "15 reps".

**Change.**
- Label the weight stepper and rows "kg / hand" when `Prescription.isPerHand(kind)`, and warn if a logged dumbbell weight is above the gym's heaviest dumbbell (suggests the user entered the pair).
- Count dumbbell volume ×2 (the per-hand weight × 2 hands; one-arm exercises ×1).
- Offer dumbbell rack presets "2-10 by 1, then 12.5-50 by 2.5" and "2-60 by 2".
- Add `WeightStack.addOn: Double?` (e.g. 1.25 or 2.5 kg magnets) to `achievableLoads`.
- Smith machine: `smithBarWeight` 10 kg is fine, but the bar weight varies (counterbalanced 6-15 kg). Ask during gym setup.

### 14. Medium: double progression uses only the best set
**What the code does.** `LiftHistory.make` keeps the top set by e1RM as `lastReps`/`lastRPE`. 10/8/7 reps across three sets therefore counts as "hit the top (10)" and the weight goes up.

**Change.** Store `lastRepsAllSets = min reps over working sets at the top weight`. Trigger the load step when every working set hits the top at RPE ≤ target + 0.5, or when the last set reaches top − 1 (a lenient variant). That's the ACSM 2009 rule of beating the target on the working sets.

### 15. Medium: warm-up sets: time and coverage
**What the code does.** The first compound gets 50% × 8, 70% × 5, 85% × 2. Every later compound gets 70% × 3. Each ramp set is costed at 30 s + 60 s rest (`WarmUp.swift:35-38`; `TrainingTools.swift:39`; `WorkoutPlanner.swift:1086-1098`). A 30-min upper session (4 compounds) spends 4.5 + 3 × 1.5 = **9 min** on ramp sets, so about 30% of the session. That's partly why short sessions feel thin. In full body, squat gets the full ramp, but bench (a different region) gets one 70% feeler.

**Change.** Give the full ramp to the first compound of each region (lower / upper push / upper pull). Skip the feeler for a later compound that trains the same muscles as one already done (e.g. incline after flat bench, RDL after squat at <60% of the squat). Below 30 min, use a 2-step ramp (50% × 5, 75% × 3) with 30-45 s rest. For loads ≥100 kg add a fourth step (90% × 1). Keep calling the percentages coaching practice (Fradkin 2010; Ribeiro 2020).

### 16. Medium: women, older lifters, novices
- **Women:** female fractions (bench 0.3, squat 0.5 × BW) sit under even beginner standards. See finding 1 for the replacement. Rep ranges, RIR and volume don't need to change by sex (Roberts et al. 2020: similar relative gains).
- **Older adults (60+):** there's no age input to `plan`. Add: ≥2 full-body days, the first compound at RIR 2-3, one power-intent set ("lift fast, 40-60% 1RM × 3-5") for the lower body, a balance or single-leg option, and longer warm-ups (Fragala et al., NSCA 2019). Keep `LoadEstimator` conservative (0.85) for age ≥60 or untrained.
- **Novices:** full body 2-3×/week (finding 6). Allow faster load progression, +5 kg lower / +2.5 kg upper each session while reps hold (ACSM 2009, novice progression). Keep the 6-10 / 8-12 ranges.

### 17. Low-Medium: 15-120 min realism
For reference, a straight compound set in the muscle style costs 0.75 + 2.0 min, an isolation set 0.75 + 1.5, plus 2 min transitions. That matches typical gym cycle times.

| Pick | Exercises | Approx. working sets | Notes |
|---|---|---|---|
| 15 min | 2-3 (fit drops to ≥2) | 5-6 supersetted | Ramp sets eat 3-4.5 min; use the 2-step ramp (finding 15) |
| 30 min | 4 | 10-12 (supersets) | 9 min of ramp sets now |
| 45 min | 5 | 14-16 | no core |
| 60 min | 6 | 18-20 | worked example above |
| 75 min | 7 | 24-26 | adds `extraSlot` |
| 90-120 min | 7 + 1 extra | ≈28-30 then stops | `sessionCap` 10 / muscle and `maximumSetsPerExercise` stop `fill`; a 120-min pick runs about 85-95 min. `lengthNote` says so |

**Change.** Cap the picker at 90 min, or say up front "past ~90 min more sets add little (Pelland 2026 per-session ceiling); we planned 85". For 120 min with cardio, offer a cardio block instead (concurrent training: Schumann 2022).

### 18. Low: easy weeks stack up
Week 1 is RIR 3 (RPE 7). Low recovery takes it to RPE 6 / RIR 4 (`targetRPE(recovery:block:)` floor 6). The deload is RIR 3 at 60% of the sets. A missed week restarts at week 1. HRV-guided autoregulation has small, uncertain benefits for lifting (Larsen 2021; existing comments). **Change:** set the floor to RPE 6.5 (RIR 3.5) and start the block at RIR 2 for compounds in the muscle and strength-and-muscle styles. Robinson 2024: growth is better closer to failure, and strength isn't hurt.

### 19. Low: session composition
Push: `horizontalPress, verticalPress, inclinePress` puts three pressing compounds first, which is heavy on the front delts. Under 60 min, put `lateralRaise` before `inclinePress`, or replace incline with a fly on alternate sessions. Pull: one row and one pulldown is fine, but two curls (finding 12) is redundant.

### 20. Low: rest on heavy lower-body lifts
In the muscle style, 2 min for squats and deadlifts is short of what keeps reps up. Schoenfeld 2016 and Grgic 2018 support ≥2-3 min for heavy multi-joint lifts. **Change:** 150-180 s for `.squat` and `.hinge` compounds in every style except endurance. Keep 120 s for upper compounds and 90 s for isolation.

### 21. Low: jump sizes
The 10% routine cap is shared by upper and lower body. ACSM 2009 suggests smaller increments for upper-body lifts (≈2.5-5%) than lower (≈5-10%). With finding 4's e1RM-sized step, this mostly sorts itself out. Optionally cap upper-body barbell steps at 5% and lower at 10%.

### 22. Low: doc drift
`docs/research/workout-science.md:24` says "Rotates focus so each muscle is hit ~2×/week" (not true for 3/5-day PPL). Line 32 says "no ramp sets" (since added). Update both after fixing finding 6.

---

## 5. What's already right
- Compounds first (Nunes 2021). Lengthened-position picks for triceps, hamstrings and calves (Maeo 2021/2023; Kinoshita 2023). Rest by style matches Singer 2024 / Schoenfeld 2016.
- Loads respect the gym's plates, dumbbells and stacks (`load(atMost:)`, `nextLoad`, `plateBreakdown`). Per-hand dumbbell math is consistent across AppCore. Dumbbell bench and press per-hand ratios (0.40) match Saeterbakken 2011/2013 within a few percent.
- Weekly targets use fractional set counting (secondary = 0.5) in `MuscleCoverage.setsThisWeek`, as Pelland 2026 found best. Session cap 10 matches the per-session ceiling.
- The abs finisher's content mix (flexion, leg raise, anti-extension, anti-rotation) is sensible. It says spot reduction doesn't work (Vispute 2011), and gives 12-16 sets/week when it runs.
- The deload design (about half the sets, same weights) matches Bell 2023. The UI calls it "planned", not "needed".

## 6. Suggested fix order
1. Findings 1 + 2 together (starting loads + catching up). This fixes "half weight" and "too easy" for new and returning users.
2. Finding 3 (strength-and-muscle style) and finding 4 (rep target after a step).
3. Finding 5 (set-mode stall), test first.
4. Findings 6-8 (frequency, slot variants, abs/coach parity).
5. The rest.

Each change needs AppCore tests (`swift test --package-path Packages/AppCore`) and a citation comment next to the constant, per CLAUDE.md.
