# Tensile roadmap from the November 2026 research round

Five research reports feed this plan. Read them for the evidence and the details:

- `behaviour-change.md`: motivation, habits, adherence; what backfires.
- `nutrition.md`: calorie tracking, food databases, nutrition coaching per goal.
- `competitors.md`: what Whoop, Oura, Garmin, Apple, Hevy, MacroFactor and others do; add/skip list.
- `health-metrics.md`: the measures with the strongest links to living longer and feeling better, with targets per goal.
- `app-audit.md`: every existing number checked against the literature, with the exact changes.
- Already applied: `strain-science.md` and `workout-science.md`.

Rule for everything below (now in CLAUDE.md): research first, cited next to the number, tailored to the user's goals, honest about weak evidence.

## Direct answers

**Calorie tracking:** already works through Cronometer → Apple Health → Tensile (energy balance, measured maintenance, goal targets, micronutrient flags). Logging food inside Tensile isn't there yet.

**Other apps' food databases:** not available. Cronometer, MyFitnessPal, MacroFactor, Lose It and the rest have no public API; Apple Health is the only legitimate channel and is already used. If in-app logging is ever wanted, the viable sources are USDA FoodData Central (free, public domain) plus Open Food Facts (free, credit required) with iOS barcode scanning: a 3–5 week build. Recommendation: keep Cronometer as the logger and add a Claude "quick estimate" fallback for unlogged meals, clearly marked as an estimate.

## Phase 1: fix what's there (1–2 weeks, all small)

Corrections from the audit, in order of impact. Each one is a constant or rule with a citation.

| # | Change | File | Why |
|---|---|---|---|
| 1 | Recovery bands follow the 7-day HRV trend: below normal → score capped at 33 ("Easy day"); within → 34–66; above → 67+ only if RHR and sleep aren't negative | RecoveryCalculator | Today a below-normal trend leaves the score "Moderate" while the target says easy day; the trend is the validated part (Plews 2013; Buchheit 2014) |
| 2 | Use the app's own sleeping heart rate as the resting HR for baselines and the illness watch, HealthKit RHR as fallback | RecoveryCalculator, VitalsModel | One consistent source; sleeping HR is the cleaner measure |
| 3 | Rename "Low recovery" to "Easy day"; drop the "x% to go, one more session closes the gap" strain framing; weekly calorie band instead of daily red "over" | TodayView, FitnessView, coach prompts | Controlling, deficit-focused feedback lowers intrinsic motivation (Deci 1999; Ntoumanis 2021) |
| 4 | Caffeine cut-off as a linear rule (8.8 h + 0.04 h per mg over 107, clamped 6–14 h), worded as a conservative average | Habits | Gardiner 2023 dose–response |
| 5 | Sleep score: regularity = (SRI − 50)/35; interruptions 0–1 full marks, 2–3 half, 4+ none; efficiency zero point 70%; deep+REM target by age | SleepCalculator | Windred 2024 SRI distribution; Ohayon 2017 norms |
| 6 | Energy: say ±15–25% (more on training days); Katch-McArdle only with clinic body fat; steps 0.00042 kcal/step/kg; TEF from macros | EnergyCalculator, README | Shcherbina 2017; ACSM walking equation |
| 7 | Body age shown as whole years with a ±5-year range | BodyAge, Biology | No wearable "age" is validated to the year |
| 8 | Illness watch: two consecutive days of a body signal before "Major" without symptoms; higher temperature bar in the luteal phase | Wellbeing | Fewer false alarms (Quer 2021; Mishra 2020) |
| 9 | Heat: estimate WBGT from temperature and humidity, ACSM bands; acclimation decays after 2–3 weeks | Habits, WeatherAdvice | Périard 2015; ACSM |
| 10 | Labs: ferritin "low for someone who trains" under 30 µg/L; add Lp(a) once in a lifetime, folate, magnesium, uric acid; ApoB every 1–2 years | LabMarkers | Sim 2019; Kronenberg 2022; Johannesen 2021 |
| 11 | Fibre target 25–29 g+ | Nutrition | Reynolds 2019 |
| 12 | Camera HRV: require 55 s of clean signal, say "about ±15%" | PPGAnalyzer, CameraHRV | Plews 2017; Esco & Flatt 2014 |

## Phase 2: motivation and the weekly loop (2–3 weeks, medium)

The behaviour-change evidence points at one structure: plan the week, do the sessions, review the week. Nothing here needs new sensors.

1. **Weekly review (Monday):** strain vs target, sleep debt and regularity, HRV/RHR trend, sets per muscle, protein and calories, weight pace, then three changes for the coming week that the user confirms. Self-monitoring plus goal review is the best-supported combination (Michie 2009; Harkin 2016).
2. **Pre-committed training days with if-then plans:** "Tuesday 6 pm, push; if I'm late, the 15-minute version." Implementation intentions (Gollwitzer & Sheeran 2006, d≈0.65) and coping plans (Sniehotta 2005).
3. **Consistency score** over 4 weeks (3 of 4 planned sessions counts), never a broken-chain streak (Lally 2010).
4. **A 15-minute version of every session** on low days; HRV-guided trials say go easy, not skip (Swann 2021 on open goals).
5. **Notifications:** one morning briefing (merge the HRV reminder), one evening reflection (one win + mood), workout reminders only for planned slots, back off after two ignored (Nahum-Shani 2018; Klasnja 2019).
6. **Coach language:** two options plus a reason, no "should/behind/missed"; autonomy-supportive (Teixeira 2012; Ntoumanis 2021). Prompt and fixed strings.
7. **Restart path** after 7+ days off: no guilt, smaller plan, the user's own "why", "little fitness is lost in two weeks" (Mujika 2000).
8. **Bed-by window** each night from need, debt, regularity and tomorrow's plan (Mah 2011; Windred 2024).
9. **Weigh-in cadence nudge** (daily or several times a week, Zheng 2015) and a ±10% flexible band on calorie targets with weekly auto-adjustment (Conlin 2021; MacroFactor-style loop already half built).

Do not add badges, points, loss-framed streaks or leaderboards (Mazeas 2022: g≈0.15 and fades).

## Phase 3: measures with the biggest health payoff (2–4 weeks, small to medium each)

From `health-metrics.md`, for a lifter in his 20s–40s:

1. **VO2 max trend** as the Fitness headline, with a VO2-only fitness age line; nudge 1–2 long-interval sessions when flat (Mandsager 2018; Kokkinos 2022).
2. **Weekly moderate/vigorous minutes** against a 150 floor / 300 best band (WHO 2020; Lee 2022).
3. **Strength health floor:** 2 days and 30–60 min a week, kept even in deloads (Momma 2022).
4. **Sleep regularity** promoted next to duration; weekday/weekend midpoint shift with a 1-hour target (Windred 2024).
5. **Waist circumference and waist-to-height ratio** (target < 0.5), monthly reminder, replacing BMI in body age (Ashwell 2012).
6. **Home blood pressure** repeat every 3–6 months (already built; add the reminder).
7. **Cut × sleep-debt rule:** when sleep debt is high while cutting, say the deficit is costing muscle and ease the rate (Nedeltcheva 2010).
8. **Alcohol weekly total** against Canadian tiers (0–2 low risk, 3–6 moderate, 7+ high).
9. **Protein by goal and age** (already built) plus per-meal spread (0.4 g/kg × 4) and carbs scaled to training days (Schoenfeld & Aragon 2018; Burke 2011).
10. **Low energy availability flag** under 30 kcal/kg fat-free mass during hard cuts (IOC REDs 2023).
11. **Grip strength** twice a year by manual entry; **STOP-Bang** sleep-apnoea screen once a year next to overnight SpO2.
12. **Cold plunge warning on lifting days** (blunts muscle growth, Roberts 2015; Piñero 2024) and sauna dose copy (Laukkanen 2015).

## Phase 4: training structure and HealthKit plumbing (3–5 weeks, medium to large)

1. **Training blocks:** 4–6 week mesocycles (volume ramp, RIR 3→1, planned deload) under the HRV guidance (Williams 2017 for strength; weaker for hypertrophy).
2. **Supersets and an "I have N minutes" session budget** (Iversen 2021), on top of the set trimming already added.
3. **Warm-up ramp calculator** rounded to the user's plates (Ribeiro 2020).
4. **Paced-breathing session** (~6 breaths/min) offered on low-recovery or high-stress days, with HR before and after (Laborde 2022).
5. **Apple Health plumbing:** write session RPE as workout effort score and check-in mood as state of mind; read sleep-apnoea events, time in daylight and the iOS 26 Medications API.
6. **Movement-break and post-meal-walk nudges** from the hourly step timeline and meal size (Buffey 2022).
7. **Strength-for-health card:** relative e1RM against age/sex bands, labelled as an app choice (García-Hermoso 2018).
8. **Quick-estimate food logging** through Claude on Supabase, written to Apple Health under Tensile's name, flagged as an estimate and down-weighted in maintenance.

## Skip, with reasons

Pace-of-ageing and DNA-methylation ages; daytime "stress" and "resilience" scores; Body Battery-style gauges; cuffless blood pressure; glucose monitors for non-diabetics (PREDICT shows variability, no outcome evidence); Noom colour coding; social features and gamification; program libraries; smart alarms; injury-risk ratios; testosterone optimisation; vitamin D as a performance lever; body-fat to one decimal from scales or photos; "zone 2 is best" coaching; posture, screen-time and eye metrics; ultra-processed-food tracking until food names are available.

## Tensile's edge to protect

Plate-exact planning from the user's own gym; statistically tested personal patterns (t-test with FDR); lifting counted in strain and recovery with a muscle map; measured maintenance with partial-day and creatine handling; medication effects on HR, HRV and sleep; caffeine, alcohol, heat and illness handled together; on-device photo privacy; device-agnostic through Apple Health; a coach that returns startable workouts; evidence labels and a refusal to fake numbers.
