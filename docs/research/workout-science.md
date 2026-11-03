# Workout planner: evidence audit (November 2026)

What the trainer assumes when it builds a session, what the research says, and what changed. Plain language; citations are the ones in the code comments.

## Summary

Most of the planner already matched the literature: big lifts first, 10–20 hard sets per muscle per week, stopping 1–3 reps short of failure, rest of 2–3 min on big lifts and about 90 s on small ones, RPE-based load suggestions and a small day-to-day effort swing from recovery. Five things changed:

1. **Sessions now fit the time you picked.** Sets are trimmed (down to 2 per exercise, main lifts last) until the estimate fits, instead of overrunning.
2. **Progression handles big jumps.** A jump of up to 10% is taken as soon as you reach the top of the rep range (double progression). When the next weight is a bigger jump (light dumbbells, coarse stacks), the planner asks for 2 extra reps first and tells you so.
3. **Stretched-position exercises are preferred** where the evidence is clear: overhead triceps extensions over pushdowns, seated over lying leg curls, standing over seated calf raises.
4. **Time estimates use the real rest timer defaults** for your training style instead of fixed numbers.
5. **Citation comments** were added or corrected next to every rule (order, volume, effort, rest, autoregulation, RPE accuracy, recovery times).

## Assumption by assumption

| Area | What the code does | What the research says | Verdict | Change |
|---|---|---|---|---|
| Exercise order | Multi-joint lifts first | Early-session lifts gain more strength; growth doesn't depend on order (Nunes et al., Eur J Sport Sci 2021; ACSM 2009) | Supported | Citation added |
| Sets and reps by goal | Strength 3–6 reps heavy; muscle 6–15; balanced 6–12; endurance 10–20 | Load ranges from ~30% to 80%+ 1RM all build muscle; heavier is better for strength (Schoenfeld et al., 2017, 2021; Lopez et al., 2021) | Supported | None |
| Effort (RPE/RIR) | Big lifts 2–3 reps in reserve, small lifts closer to failure | Failure adds little for growth and nothing for strength; closer to failure helps hypertrophy more than strength (Refalo et al., 2024; Robinson et al., Sports Med 2024) | Supported | Citation updated |
| Recovery → effort | RPE 6.5 / 7.5 / 8 by recovery band, never skips | Autoregulation works for strength (Larsen et al., PeerJ 2021); HRV-guided benefits are small and mainly in endurance (Granero-Gallegos 2020; Manresa-Rocamora 2021) | Supported, kept small | Citation added |
| Rest | 2–3 min big lifts, ~90 s small | Singer et al., 2024; Schoenfeld et al., 2016; ACSM 2009 | Supported | Citation tidied |
| Weekly volume | 10–20 sets/muscle "good", 20+ "high if you recover", under 10 "low" | Dose–response with diminishing returns; ~4 sets already gives most of the strength gain (Schoenfeld 2017; Pelland et al., Sports Med 2026; ACSM 2026) | Supported | Comment updated |
| Frequency | Rotates focus so each muscle is hit ~2×/week | Frequency matters mostly through volume (Schoenfeld et al., 2016, 2019) | Supported | None |
| Progression | Next jump once top of range is hit at target effort | ACSM: add 2–10% when 1–2 reps over target are reached | Tweak | Big-jump rule (>10% needs +2 reps) |
| Session length | Fixed exercise count by minutes; estimate could overrun | Time-efficient training: fewer sets of big lifts, supersets (Iversen et al., Sports Med 2021) | Wrong (overran) | `fit` trims sets to the time |
| Exercise choice | Catalog order | Long-muscle-length work grows more: triceps overhead (Maeo 2023), seated leg curl (Maeo 2021), standing calf raise (Kinoshita 2023) | Tweak | Catalog reordered |
| RPE accuracy | Up to 4 reps in reserve counted in e1RM | Lifters misjudge by ~1 rep, worse far from failure (Halperin et al., Sports Med 2022) | Supported | Citation added |
| Muscle recovery | 48–72 h model; soreness overrides | Soreness tracks damage poorly (Nosaka et al., 2002) | Model, not measurement | Comment says so |
| Deloads | Suggested on high volume + poor recovery | Consensus: planned or reactive, both fine (Bell et al., 2023) | Supported | None |
| Warm-up | 5 min allowance; no ramp sets | Ramp sets help performance (Ribeiro et al., 2020) | Gap | Future: warm-up calculator rounded to plates |

## Open items (not done, for later)
- Warm-up ramp calculator (2–3 sets at 50/70/85% rounded to your plates).
- Supersets for short sessions, instead of only trimming sets.
- Training blocks (4–6 weeks, volume ramp, planned deload) under the HRV guidance.
