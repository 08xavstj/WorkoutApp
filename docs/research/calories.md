# Personal calories and macros: sex, age, body fat and training

Research round, November 2026. Asked for: "when using research and calculation for
calories, account for sex, age, etc. use the research." Code: `EnergyCalculator.swift`,
`Goals.swift` (`GoalPlanner`), `TrainingStatus.swift` (new), `CycleEnergy.swift` (new),
`Nutrition.swift`, `CalorieSafety.swift`; app side `DailyMetricsModel`, `GoalsView`,
`TodayView` (`CalorieDetailsSheet`), `WorkoutAppApp` (training status), `CoachView`.

Method: web search (abstracts, PubMed records, publisher pages); full-text fetches were
blocked by the sandbox. ✓ = title, authors, journal and year seen in a search result.
Evidence strength: strong / moderate / weak / app choice.

## Summary: what changed, for whom

| Person | Before | Now | Evidence |
|---|---|---|---|
| Lifted 2+ sessions a week for 6+ consistent months (logged in the app), aged 18-35 | Resting energy from Mifflin-St Jeor | **ten Haaf & Weijs** athlete equation (about +10-12% for most lifters) | Moderate |
| Same, with DXA/clinic body fat | Katch-McArdle | **Cunningham** (500 + 22 × lean mass) | Moderate |
| Everyone else, or no height | Mifflin-St Jeor | Unchanged | Strong |
| Losing, men < 15% / women < 23% body fat | Up to 1%/week | **Up to 0.75%/week** | Moderate direction, app cut-off |
| Losing, men < 10% / women < 18% | Up to 1%/week | **Up to 0.5%/week** | Moderate direction, app cut-off |
| Losing, 65 or older | Up to 1%/week | **Up to 0.5%/week** | Moderate |
| Gaining, 2+ years of consistent lifting | Up to 0.5%/week | **Up to 0.25%/week** | Moderate (narrative review) |
| 65+, endurance/health focus | Protein per meal 0.3 g/kg | **0.4 g/kg** per meal | Moderate |
| Women in the second half of the cycle | Nothing | **A note**: resting burn a little higher; target unchanged | Small effect, so note only |
| Daily protein by age or sex | 1.2-2.2 g/kg by goal | Unchanged (already meets the older-adult guidance) | Moderate |
| Energy-availability floor by sex | 30 kcal/kg FFM for both | Unchanged | Weak for a male-specific number |

The pace picker in Goals now hides rates above your personal maximum and says why; the
calorie target, the weekly ±100 kcal adjustment and "time to target" all use the capped
rate. The calorie details sheet names the resting-energy equation in use.

## 1. Resting energy: which equation for whom

| Equation | Inputs | Evidence | Use in the app |
|---|---|---|---|
| Mifflin-St Jeor | sex, age, height, weight | Frankenfield, Roth-Yousey & Compher, J Am Diet Assoc 2005 ✓: most accurate general equation in non-obese and obese adults (within 10% for most) | Default |
| ten Haaf & Weijs (weight-based) | sex, age, height, weight | PLoS One 2014 ✓: 90 recreational athletes aged 18-35 (5 sessions, 9 h a week), measured by indirect calorimetry; Mifflin, Harris-Benedict, WHO, Schofield and Owen were accurate (±10%) for fewer than half. O'Neill, Corish & Horner, Sports Med 2023 ✓ (meta-analysis, 29 studies, 1,430 athletes): the most accurate and precise equation, 80.2% within ±10% vs 41-64% for the others, and the only one without heterogeneity | Trained (intermediate/advanced) people aged 18-35 with a height |
| Cunningham (500 + 22 × lean mass) | lean mass | Cunningham, Am J Clin Nutr 1980 ✓; confirmed in recreational athletes by ten Haaf & Weijs 2014 ✓ | Trained people with DXA/clinic body fat |
| Katch-McArdle (370 + 21.6 × lean mass) | lean mass | Lean-mass equations need a good body-fat measurement; smart scales err by ±5-8 points (app-audit.md) | Untrained people with DXA/clinic body fat (unchanged) |
| Tinsley (24.8 × weight + 10; 25.9 × FFM + 284) | weight or FFM | Tinsley, Graybeal & Moore, Appl Physiol Nutr Metab 2019 ✓: built in a small group of muscular physique athletes, where most existing equations under-predicted; the authors asked for external validation, while the 2023 meta-analysis found ten Haaf the most accurate | Not used |
| Harris-Benedict | sex, age, height, weight | Less accurate than Mifflin in Frankenfield 2005 and in athletes (ten Haaf 2014) | Not used |

Decisions:
- **ten Haaf only for 18-35.** It was built and tested on 18-35-year-olds; a later review
  found it adequate in female athletes too. Outside that range the app does not
  extrapolate, so a 45-year-old lifter stays on Mifflin. This makes a step at 36; it is
  honest about where the evidence ends.
- **"Trained" comes from the app's own log** (`TrainingStatus`, app choice): untrained
  under 1 session a week over the last 8 weeks; novice under 2 a week or under 6
  consistent months (30-day blocks with 4+ sessions); intermediate 6-23 months; advanced
  24+. Six months matches the "resistance-trained (> 6 months)" definition in Helms,
  Zinn, Rowlands & Brown, IJSNEM 2014 ✓. Only sessions logged in the app count, so a
  long-time lifter who just installed it would read as a newer lifter at first. Settings ›
  Training › Lifting experience fixes that (`TrainingStatus.resolve`, app choice): with
  under 8 weeks of logged history the reported level is used; after that, the higher of the
  reported level and the log, unless the log shows training has stopped (untrained).
- **The 1.4 × BMR plausibility check keeps Mifflin.** The athlete equation runs about
  200 kcal higher for a young male lifter; using it would push the "physically
  impossible maintenance" bar up and reject real low maintenances during a long cut.
- **Age beyond the equations: no extra adjustment.** Pontzer et al., Science 2021 ✓:
  energy expenditure adjusted for fat-free mass is stable from 20 to 60 and falls after
  60 (the rate was not confirmed in the abstract). Mifflin's −5 kcal/year term already
  lowers older people's estimate; adding a second age penalty isn't supported.
- **The watch still wins** when Apple Health has a believable resting-energy average; the
  equation is the fallback and the name of the method is shown either way.

## 2. How fast to lose

General limit unchanged: about 0.5-1% of body weight a week (Helms, Aragon & Fitschen,
JISSN 2014 ✓; Garthe et al., IJSNEM 2011: elite athletes at 0.7%/week kept more lean mass
than at 1.4%/week; Ruiz-Castellano et al., Nutrients 2021 ✓: 0.5-1%/week in
resistance-trained athletes, with little direct evidence).

Personal limits:
- **Body fat.** The leaner you are, the larger the share of weight lost that is lean
  tissue: Forbes, Ann N Y Acad Sci 2000 ✓ ("an inverse curvilinear relationship between
  initial body fat and the proportion of weight loss consisting of lean tissue"; a larger
  deficit raises it too); Hall, Br J Nutr 2007 ✓ extended Forbes' equation to large
  changes. Reviews in lifters say the leaner the athlete, the smaller the deficit
  (Ruiz-Castellano 2021, review report). No study sets a body-fat cut-off, so the app's
  are an **app choice** at about the top of the ACE "athletes" band, women 8 points
  higher for essential fat: lean (men < 15%, women < 23%) → 0.75%/week; very lean (men
  < 10%, women < 18%) → 0.5%/week. Strength: moderate for the direction, none for the
  exact numbers.
- **Age 65+ → 0.5%/week.** Villareal et al., N Engl J Med 2017 ✓: 160 adults with obesity
  aged 65+; weight fell 9% in 26 weeks (≈0.35%/week) in every exercise group, but lean
  mass fell 2-3% with resistance or combined training vs ~5% with aerobic only. The
  ASN/TOS position statement (Villareal et al., Am J Clin Nutr 2005 ✓) asks for weight
  loss that minimises muscle and bone loss in older adults (its exact rate figures were
  not confirmed). 0.5 is the nearest picker option above the trial's rate. Moderate.
- **Sex.** No trial compares safe loss rates between men and women; only the body-fat
  cut-offs differ by sex.
- **Recomposition (not changed, noted).** Murphy & Koehler, Scand J Med Sci Sports 2022
  ✓: in a meta-regression, a deficit of about 500 kcal a day stopped lean-mass gains from
  resistance training (strength gains were unaffected). Already reflected in the
  "Lose fat, build muscle" goal's default 0.5%/week; not made a hard cap because the
  regression threshold is an average, not a personal limit.

**Body fat when there's no reading:** Deurenberg, Weststrate & Seidell, Br J Nutr 1991
✓: body fat % = 1.2 × BMI + 0.23 × age − 10.8 × (1 for men) − 5.4; standard error 4.1
points, slightly high in obesity, and high for muscular people (BMI counts muscle). Used
only for the pace limit, and the Goals text says it is a rough estimate from BMI. Weak.
CUN-BAE was not used (more complex, same BMI weakness).

## 3. How fast to gain

Iraki, Fitschen, Espinar & Helms, Sports 2019 ✓: a surplus of about 10-20% aiming for
0.25-0.5% of body weight a week for novice and intermediate bodybuilders; advanced lifters
should be more conservative. App: 0.5%/week maximum, 0.25%/week once advanced (2+ years
of consistent logged training; app choice). Sex: relative muscle growth is similar in
men and women (Roberts, Nuckols & Krieger, J Strength Cond Res 2020 ✓, no sex difference
in hypertrophy; Refalo et al., PeerJ 2025 ✓, relative increases similar, absolute slightly
favour men), and the limit is already a % of body weight, so it is the same for both.
Moderate (narrative review, practitioner consensus).

## 4. Protein by age and sex

- Daily: unchanged. Morton et al., BJSM 2018 ✓ (1.6 g/kg, upper CI 2.2); in a deficit
  2.3-3.1 g/kg lean mass (Helms 2014 IJSNEM ✓). Older adults: PROT-AGE (Bauer et al.,
  J Am Med Dir Assoc 2013 ✓) 1.0-1.2 g/kg, ≥ 1.2 when exercising (secondary summary),
  1.2-1.5 with acute or chronic disease. The app's lowest daily figure is already 1.2 g/kg
  (health/endurance), so age does not change the daily target. ESPEN (Deutz 2014) was not
  re-verified this round.
- Per meal: Moore et al., J Gerontol A 2015 ✓ (in nutrition.md): about 0.40 g/kg per meal
  for older men vs 0.24 g/kg for younger men. The app now gives 65+ users with an
  endurance/health focus 3 × 0.4 g/kg (= 1.2 g/kg, the PROT-AGE figure) instead of
  3 × 0.3; lifters already get ≥ 0.4 g/kg per meal. The 25-30 g per meal figure attributed
  to PROT-AGE was only seen in trade press, so it isn't quoted.
- Sex: the position stands give per-kg targets without a sex split, and the lean-mass
  rule in a deficit already accounts for women's higher body fat. No change.
- GLP-1 / medication floor (`MedicationsModel`, 2.0 g/kg reference weight): unchanged.

## 5. Menstrual cycle

Benton, Hutchins & Dawes, PLoS One 2020 ✓ (26 studies, 318 women): resting metabolic rate
is higher in the luteal phase, a small effect (effect size 0.33, 95% CI 0.17-0.49), and
smaller and non-significant in studies since 2000; risk of bias in how phase and RMR were
measured. Hurtová, Gimunová & Beníčková, Front Physiol 2026 ✓ (7 newer studies): about
30-120 kcal a day, ~3-5%, overlapping normal day-to-day variation. Energy intake was
similar across phases in a 2025 study (Smith et al.; not verified in detail).

Decision: **note only, no adjustment.** The effect is smaller than any equation's or
watch's error (±15-25%), sits inside the ±10% target band, and the 28-day measured
maintenance already averages over a whole cycle. When a woman's last logged period day
was 10-24 days ago (≈ cycle days 14-28 in a 28-day cycle with a 4-5 day period; app
approximation), the calorie sheet says resting burn runs a little higher and that eating
toward the top of the band is fine.

## 6. Minimum intake and energy availability by sex

IOC REDs consensus (Mountjoy et al., BJSM 2023 ✓): ≤ 30 kcal/kg FFM a day is the zone with
health effects, in both sexes. For men no separate threshold is established (Wasserfurth,
Palmowski, Hahn & Krüger, Sports Med Open 2020 ✓); short exposures to 15 kcal/kg lowered
leptin and insulin but not other metabolic hormones (Koehler et al., J Sports Sci 2016;
title confirmed via a reference list), and some reviews suggest 15-25 kcal/kg for men
(unnamed reviews; not verified). **Decision: keep 30 for everyone** (the conservative
choice; no agreed lower number). The absolute floors (1,500 / 1,200 kcal) stay as the
labelled clinical convention. `CalorieSafety` design unchanged.

## 7. Thermic effect and activity

TEF from macros (Westerterp 2004) is unchanged. Age differences in TEF are small and
inconsistent in the literature and were not pursued; NEAT is measured (steps), not
predicted. No change.

## 8. Worked examples

### Man, 25 (age assumed; the app uses Apple Health's age, else 30), 183 cm, 74 kg, lifts 4×/week for 6+ months

| Number | Before | Now |
|---|---|---|
| Training status | n/a | Intermediate (≥ 2/week over 8 weeks, ≥ 6 consistent months) |
| Resting energy (when the watch has none) | Mifflin 1,764 kcal | ten Haaf 1,976 kcal (+212) |
| Plausible-maintenance bar (1.4 × Mifflin) | 2,469 kcal | 2,469 kcal (unchanged on purpose) |
| Body fat for the pace limit | n/a | No reading: Deurenberg ≈ 16% (rough) |
| Fastest loss | 1%/week (0.74 kg) | 1%/week with the BMI estimate; **0.75%/week (0.56 kg)** if a scale reads e.g. 13% |
| Example target, measured maintenance 2,750, picked 1%/week | 2,750 − 814 = 1,936 → held at the safety minimum ≈ 2,094 (30 × 59.8 kg Boer FFM + ~300 kcal training) | Same with the BMI estimate; with a 13% reading 2,750 − 610 = **2,140** |
| Fastest gain | 0.5%/week | 0.5%/week (0.25%/week after 2+ years) |
| Protein | 118 g maintain/gain (1.6 g/kg), 163 g losing (2.2 g/kg; 2.6 g/kg lean mass with a body-fat reading) | Unchanged |
| Protein per meal | 30 g × 4 | Unchanged |

### Woman, 45, 165 cm, 68 kg

| Number | Before | Now |
|---|---|---|
| Resting energy | Mifflin 1,325 kcal | Mifflin 1,325 kcal (ten Haaf is only validated to 35, whatever her training) |
| Body fat for the pace limit | n/a | Deurenberg ≈ 35% (rough) |
| Fastest loss | 1%/week (0.68 kg) | 1%/week; 0.75% under 23% body fat, 0.5% under 18%; 0.5% from 65 |
| Safety minimum | ≈ 1,406 + training kcal (30 × 46.9 kg Boer FFM) | Unchanged |
| Protein | 1.6 g/kg (109 g) lifting, 1.2 g/kg (82 g) health | Unchanged |
| Protein per meal (health focus) | 20 g × 3 | Unchanged at 45; 27 g × 3 from 65 |
| Cycle | Nothing | Luteal note on days 10-24 after the last logged period day; target unchanged |

## References

- Frankenfield D, Roth-Yousey L, Compher C. Comparison of predictive equations for resting metabolic rate in healthy nonobese and obese adults: a systematic review. *J Am Diet Assoc* 2005;105:775-789. ✓
- ten Haaf T, Weijs PJM. Resting energy expenditure prediction in recreational athletes of 18-35 years: confirmation of Cunningham equation and an improved weight-based alternative. *PLoS One* 2014;9:e108460. ✓
- O'Neill JER, Corish CA, Horner K. Accuracy of resting metabolic rate prediction equations in athletes: a systematic review with meta-analysis. *Sports Med* 2023. ✓
- Tinsley GM, Graybeal AJ, Moore ML. Resting metabolic rate in muscular physique athletes: validity of existing methods and development of new prediction equations. *Appl Physiol Nutr Metab* 2019;44:397-406. ✓ (the brief named Eur J Clin Nutr; the journal is APNM)
- Cunningham JJ. A reanalysis of the factors influencing basal metabolic rate in normal adults. *Am J Clin Nutr* 1980;33:2372-2374. ✓
- Pontzer H et al. Daily energy expenditure through the human life course. *Science* 2021;373:808-812. ✓
- Helms ER, Aragon AA, Fitschen PJ. Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. *J Int Soc Sports Nutr* 2014;11:20. ✓
- Helms ER, Zinn C, Rowlands DS, Brown SR. A systematic review of dietary protein during caloric restriction in resistance trained lean athletes: a case for higher intakes. *Int J Sport Nutr Exerc Metab* 2014;24:127-138. ✓
- Garthe I et al. Effect of two different weight-loss rates on body composition and strength and power-related performance in elite athletes. *Int J Sport Nutr Exerc Metab* 2011;21:97-104. (✓ in app-audit.md)
- Ruiz-Castellano C, Espinar S, Contreras C, Mata F, Aragon AA, Martínez-Sanz JM. Achieving an optimal fat loss phase in resistance-trained athletes: a narrative review. *Nutrients* 2021;13:3255. ✓ (author list beyond the first from memory)
- Forbes GB. Body fat content influences the body composition response to nutrition and exercise. *Ann N Y Acad Sci* 2000;904:359-365. ✓
- Hall KD. Body fat and fat-free mass inter-relationships: Forbes's theory revisited. *Br J Nutr* 2007;97:1059-1063. ✓
- Villareal DT et al. Aerobic or resistance exercise, or both, in dieting obese older adults. *N Engl J Med* 2017;376:1943-1955. ✓
- Villareal DT et al. Obesity in older adults: technical review and position statement of the American Society for Nutrition and NAASO, The Obesity Society. *Am J Clin Nutr* 2005;82:923-934. ✓
- Murphy C, Koehler K. Energy deficiency impairs resistance training gains in lean mass but not strength: a meta-analysis and meta-regression. *Scand J Med Sci Sports* 2022;32:125-137. ✓
- Deurenberg P, Weststrate JA, Seidell JC. Body mass index as a measure of body fatness: age- and sex-specific prediction formulas. *Br J Nutr* 1991;65:105-114. ✓
- Iraki J, Fitschen P, Espinar S, Helms E. Nutrition recommendations for bodybuilders in the off-season: a narrative review. *Sports* 2019;7:154. ✓
- Roberts BM, Nuckols G, Krieger JW. Sex differences in resistance training: a systematic review and meta-analysis. *J Strength Cond Res* 2020;34:1448-1460. ✓
- Refalo MC, Nuckols G, et al. (Bayesian meta-analysis of sex differences in hypertrophy). *PeerJ* 2025. ✓ (title not recorded)
- Morton RW et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength. *Br J Sports Med* 2018;52:376-384. ✓
- Bauer J et al. Evidence-based recommendations for optimal dietary protein intake in older people: a position paper from the PROT-AGE Study Group. *J Am Med Dir Assoc* 2013;14:542-559. ✓
- Moore DR et al. Protein ingestion to stimulate myofibrillar protein synthesis requires greater relative protein intakes in healthy older versus younger men. *J Gerontol A* 2015;70:57-62. ✓
- Benton MJ, Hutchins AM, Dawes JJ. Effect of menstrual cycle on resting metabolism: a systematic review and meta-analysis. *PLoS One* 2020;15:e0236025. ✓ (the brief named "Dawson"; the author is Dawes)
- Hurtová, Gimunová, Beníčková. Resting metabolic rate fluctuations across the menstrual cycle: a systematic review. *Front Physiol* 2026. ✓
- Mountjoy M et al. 2023 IOC consensus statement on Relative Energy Deficiency in Sport (REDs). *Br J Sports Med* 2023;57:1073-1097. ✓
- Wasserfurth P, Palmowski J, Hahn A, Krüger K. Reasons for and consequences of low energy availability in female and male athletes: social environment, adaptations, and prevention. *Sports Med Open* 2020;6:44. ✓
- Koehler K et al. Low energy availability in exercising men is associated with reduced leptin and insulin but not with changes in other metabolic hormones. *J Sports Sci* 2016. (title from a reference list; authors and volume not re-verified)

Not verified this round: ESPEN expert group (Deutz 2014); the PROT-AGE 25-30 g per meal
figure; the exact post-60 decline rate in Pontzer 2021; Smith et al. 2025 on intake across
the cycle; any male-specific energy-availability number.
