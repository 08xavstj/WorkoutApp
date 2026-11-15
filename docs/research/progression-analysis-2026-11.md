# Why weights weren't going up (2026-11)

A user reported that workouts weren't raising the weights from previous sessions. Sets were replayed the way the app records them (the plan's rep goal on set 1, a 0-4+ "reps left" tap after each set, the next set's goal from `RepGoal`, reps falling across sets) for a lifter getting 0.4-0.8% stronger a session. `RealisticLoggingTests` keeps that replay.

## What was wrong

### 1. A session was read as a set nobody did (main cause)

`LiftHistory.make` summarised a session as the **fewest reps** at the top weight with the **hardest rating**. That worked while every set had the same rep goal. Since rep goals move set by set, the two numbers come from different sets:

| Set | Logged | |
|---|---|---|
| 1 | 62.5 kg × 9, 4+ left | the plan's goal; goal rises to 11 |
| 2 | 62.5 × 11, 2 left | |
| 3 | 62.5 × 11, 1 left | |
| 4 | 62.5 × 11, 1 left | |

Read as "9 reps at RPE 9": a little harder than planned, so the plan repeated 62.5 × 9. In the replay a bench press stayed at 62.5 × 9 for nine sessions while the lifter got 5% stronger; the weight moved only when the in-session change raised it.

**Now:** the set that showed the most reps to failure (reps done + reps left) stands for the session, with its own rating; on a tie, the set with more reps, whose rating is the more accurate one (Halperin et al., Sports Med 2022). Above: 11 reps at RPE 8. Reps at a fixed weight fall across sets anyway (Willardson & Burkett, J Strength Cond Res 2006). When a set at the top weight has no rating, the old reading stays (every set must reach the reps). Which set stands for a session is the app's choice; the ACSM's rule (add 2-10% after one to two reps over the target, position stand 2009) doesn't say which sets.

### 2. Reps past the top of the range didn't count

A rep goal can go two past the range. 12 reps with one left in a 6-10 range, target 1.5 in reserve, was "half a point too hard": weight held. **Now** reps past the top trade for effort, one rep per RPE point (Zourdos et al., J Strength Cond Res 2016): 12 with one left reads as 11 with two left, and the weight goes up. Only while the reps stay at or over the top.

### 3. A merely easy set forced a weight step

A set at least two reps easier than planned moved the weight up at least one step, even when the 1RM estimate said the step was too big. The replay hit this once sessions were read correctly: 16 kg × 8 with 3 left (about 11 to failure) went to 18 kg dumbbells, where 7 was the limit, and stayed there for weeks. **Now** the forced step is kept for "4 or more left" (the estimate is then only a floor); with a counted reserve the estimate decides, and the reps go up instead.

## Result in the replay (12 weeks, strength +12%)

| Lift | Before | After |
|---|---|---|
| Bench press | weight moved only mid-session; plan stuck at × 9 | 62.5 → 72.5 kg, a step every 3-4 sessions |
| Lat pulldown | stuck at × 8 with 4+ left on set 1 | 60 → 70 kg, first sets near the target |
| Dumbbell curl | 14 → 16 kg | 14 → 16 → 18 kg, the last step after reaching 14 reps |

## Still by design

- A deload week and the first week of a block ask for more reps in reserve, so the weight waits there.
- Small lifts on coarse steps build reps to two past the range before the weight moves (`ProgressionMode.reps`).
- Targets sit on half points (RPE 8.5) and the rating is whole reps, so "one left" at the top of the range holds the weight and "two left" moves it.
