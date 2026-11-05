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

## Open items (done in roadmap Phase 4, November 2026)
- Warm-up ramp calculator (2–3 sets at 50/70/85% rounded to your plates): `WarmUp` in AppCore, shown in the builder and prefilled as "W" sets (Ribeiro 2020; Fradkin 2010; ACSM 2009). The 50/70/85% pattern is coaching practice, not a tested optimum.
- Supersets for short sessions, instead of only trimming sets: `Supersets` pairs non-competing movements once sets are down to two, before any exercise is dropped; paired sets are estimated at ~60% of their separate time (Iversen 2021; Weakley 2017). Strength style keeps big lifts as straight sets.
- Training blocks (4–6 weeks, volume ramp, planned deload) under the HRV guidance: `TrainingBlock` (strength/balanced 5 weeks, muscle 6, sets ×1.0 → 1.25/1.4 then 0.6, RIR 3 → 1 then 3; Williams 2017, Bell 2023, Pelland 2026). A week that starts with 7-day HRV below normal repeats the previous week's sets; a low-recovery day still lowers the RPE inside the block. Stamina/health goals keep steady weeks.

## Pre-workout warm-up

The trainer offers an optional movement warm-up (`WarmUpRoutine` in AppCore, about 5–8 minutes) before the first lift, built from the muscles the session trains, with the lift's own ramp sets (`WarmUp`) after it. What the evidence supports, and what it doesn't:

| Question | What the research says | What the app does |
|---|---|---|
| Does a warm-up help lifting? | A general warm-up (beyond stretching) improved performance in 79% of the measures across 32 studies; the authors note few well-run randomised trials (Fradkin, Zazryn & Smoliga, J Strength Cond Res 2010, meta-analysis). Mechanisms are mostly muscle temperature plus metabolic and neural effects; much practice grew by trial and error (McGowan, Pyne, Thompson & Rattray, Sports Med 2015, narrative review). | A 2-minute "raise" step (march or jog in place), then movements for the session's muscles. The UI says the benefit is small. |
| Static stretching before lifting | Static stretching right before testing cut strength by about 5.4%, explosive performance by about 2%, power by about 1.9% (not significant); worst with longer total hold time, smallest at ≤45 s per muscle (Simic, Sarabon & Markovic, Scand J Med Sci Sports 2013, meta-analysis, 104 studies). Deficits are mainly confined to holds of 60 s or more; under 30 s about -1.1%, 30–45 s about -1.9% (Kay & Blazevich, Med Sci Sports Exerc 2012, systematic review, 106 studies). | Every default movement is dynamic (`isStatic == false`); `make` never returns a hold. A held stretch, if ever added, must stay at or under 30 s. |
| Dynamic movement | Dynamic stretching within minutes of activity gave a small-to-moderate performance gain; static or PNF stretching a small-to-moderate deficit, largest at ≥60 s (Behm, Blazevich, Kay & McHugh, Appl Physiol Nutr Metab 2016, systematic review). | Leg swings, bodyweight squats, hip hinges, lunges, ankle rocks; scap pull-ups, band rows, thoracic rotations; arm circles, band pull-aparts, scapular push-ups, cat-cow; dead bug. Band and bar movements only when the gym has them. |
| Order | RAMP: Raise, Activate and Mobilise, Potentiate (Jeffreys, Professional Strength and Conditioning 2007; standard in UKSCA/NSCA resources). The 2007 article was not re-verified in full text; the model is described in secondary sources and Jeffreys' 2018 book. | Raise first, then mobilise/activate movements large muscles → small; the potentiate step is the ramp sets already in the plan. |
| Injury | Stretching did not reduce sports injuries (RR 0.96, CI 0.85–1.10) while strength training cut them to about a third (RR 0.32) (Lauersen, Bertelsen & Andersen, Br J Sports Med 2014, meta-analysis, 25 trials). Static/PNF stretching had no clear effect on injuries and there are no injury data for dynamic stretching (Behm 2016). | The copy says a dynamic warm-up "may" cut injury risk and no more. The evidence is moderate for performance, weak for injury. |

Not covered by the evidence above: the exact movements and their 30–40 s durations are coaching practice, not tested optima; the routine's total length (5–8 min) follows common practice and the RAMP structure rather than a dose–response study.

Sources checked November 2026: [Simic 2013 (PubMed)](https://pubmed.ncbi.nlm.nih.gov/22316148/), [Kay & Blazevich 2012 (PubMed)](https://pubmed.ncbi.nlm.nih.gov/21659901/), [Fradkin 2010 (PubMed)](https://pubmed.ncbi.nlm.nih.gov/19996770/), [Behm 2016 (Northampton repository)](https://pure.northampton.ac.uk/en/publications/acute-effects-of-muscle-stretching-on-physical-performance-range-/), [Lauersen 2014 (BJSM)](https://bjsm.bmj.com/content/48/11/871), [McGowan 2015 (PubMed)](https://pubmed.ncbi.nlm.nih.gov/26400696/), [RAMP overview (Science for Sport)](https://www.scienceforsport.com/warm-ups/).
