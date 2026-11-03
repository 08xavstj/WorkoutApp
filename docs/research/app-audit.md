# Evidence audit of the app's numbers (November 2026)

Every constant, threshold, formula and rule in the files below, checked
against the published research. Strain, training load and the workout
planner are covered in `strain-science.md` and are not repeated here.

Files: `Packages/AppCore/Sources/AppCore/` RecoveryCalculator, PersonalBaseline,
SleepCalculator, SleepRegularity, SleepSessions, EnergyCalculator,
EnergyBalance, Goals, Nutrition, Micronutrients, Habits, Wellbeing,
HeartHealth, HeartRateComparison, HomeBloodPressure, LabMarkers,
MedicationKnowledge, BodyAge, MuscleRecovery (recovery constants only),
CheckIn, FitnessAdaptation (step goal), WeatherAdvice, PPGAnalyzer, and
`App/Services/VitalsModel.swift`.

Verdicts: **Supported** (matches the literature), **Tweak** (right idea,
change the number or the wording), **Wrong** (contradicted or mis-cited),
**App choice** (no study sets it; reasonable, must be labelled as the app's),
**No evidence either way**.

Evidence strength: strong / moderate / weak / mixed.

Work: small (one constant or a sentence), medium (a function and its tests),
large (new data or a new model).

### How the citations were checked

Each citation was checked with web search (abstracts and secondary
sources). Full-text fetches were blocked by the sandbox (PubMed, PMC,
Nature, journal and publisher hosts do not resolve), and the shared search
budget ran out before the last batch, so a few items are marked **from
memory, not re-verified this session**. Nothing below is invented; where a
number could not be confirmed it says so. Citations that were confirmed
to exist (title, authors, journal, year) are marked ✓ in the reference list.

---

## 1. The biggest problems, in order

1. **Recovery score ignores its own research rule.** The 7-day ln-HRV trend
   sitting *below* the SWC band (the trial trigger for "go easy") moves the
   score only from 57 to about 51, still "moderate". The strain target
   patches this elsewhere, so the card can say Moderate while the target
   says easy day. Make the band follow the SWC state: trend below normal →
   score capped at 33 (Low); within → 34-66; above → floor 67 only when
   RHR and sleep are not negative. The 34/67 cut-offs then have a basis
   (`RecoveryCalculator`, medium).
2. **Resting heart rate uses the day-time HealthKit value, not sleeping HR.**
   Garmin's and Apple's "resting HR" are computed differently, Apple's from
   daytime stillness. Training-monitoring studies use the night (or waking
   supine) value; sleeping HR is steadier and is what the illness studies
   used. Use the app's own `SleepingHeartRate.average` (per-minute HR during
   the main sleep, ≥ 60 samples) for the recovery baseline and the illness
   watch, with HealthKit RHR as the fallback, one source per baseline
   (medium).
3. **Ferritin "in range" at 12 ng/mL would be wrong for this user.** The Mayo
   range (men 24-336, women 11-307) is a population interval, not a health
   threshold; athlete reviews (Sim et al. 2019, after Peeling 2007) call
   ferritin < 35 µg/L stage-1 iron deficiency and < 20 µg/L stage 2, and
   WHO uses < 15 µg/L for everyone. Add a second, "for athletes" line:
   flag ferritin under 30 µg/L (both sexes) as "low for someone who trains",
   and note that ferritin rises with inflammation and hard training
   (`LabMarkers`, small).
4. **Caffeine cut-off is a step function and is stated as fact.** The 8.8 h /
   13.2 h figures are the meta-analysis model's averages (Gardiner 2023);
   a 2025 crossover trial by the same group found 100 mg four hours before
   bed did not measurably change sleep. Interpolate the cut-off by dose
   (hours = 8.8 + 0.04 × (mg − 107), clamped 6-14) and word it as
   "conservative; sensitivity varies a lot" (`Habits.CaffeineTiming`, small).
5. **Sleep regularity is scored on an unreachable scale.** The sleep score
   uses SRI/100, but the UK Biobank median is 81 and the bottom quintile
   starts at about 72. Map SRI 85+ → full marks, 60 → half, under 50 → 0
   (`SleepCalculator`, small).
6. **Interruptions are under-penalised relative to the NSF indicator.**
   NSF (Ohayon 2017) rates 0-1 awakenings over 5 min as good and 4+ as poor;
   the code gives 4 interruptions half marks (1 − n/8). Use 0-1 → 1.0,
   2-3 → 0.5, 4+ → 0 (small). Keep the 10-15 % weight, since wrist
   awake-detection is rough.
7. **The energy estimate claims ±10-15 %; the evidence says more.** Wearable
   and equation errors for individuals are 20-30 % (Shcherbina 2017 ✓; JMIR
   2022 review ✓ > 30 %). Say "±15-25 %, more on training days" in the README
   and the card. Also Katch-McArdle from a smart-scale body-fat reading
   inherits that scale's ±5-8 point error; prefer Mifflin-St Jeor unless
   body fat is from DXA or a 4-compartment method (small).
8. **Body age shows one decimal and no range.** No composite like this has
   been validated; only its parts have. Round to whole years and show
   "about 34 (29-39)" with the confidence label (small).
9. **Illness watch does not use the data it already collects.** The luteal
   phase raises sleeping temperature ~0.3-0.5 °C and RHR 2-4 bpm, which
   would trip "temperature +0.5" and "RHR +4" together → "Major signs". The
   morning check-in records cycle state: when "On my period" was logged in
   the last ~16 days, raise the temperature bar to +0.8 °C or require
   symptoms. Also require two consecutive days of a signal before "Major"
   without symptoms, as the wearable studies did (medium).
10. **Heat thresholds use "feels like", not WBGT, and the heat index maps
    badly to shade WBGT.** Open-Meteo gives temperature and humidity, so a
    WBGT estimate (Australian BoM approximation) is cheap; then ACSM's
    categories apply (moderate risk from WBGT 18-23 °C, high 23-28, very
    high 28-30, stop above 30 for unacclimatised people) (medium).
11. **Three citations need fixing**: "Sletten 2023 NSF consensus" is about
    sleep regularity, not catch-up sleep (cite Kitamura 2016 and Banks 2010
    instead); "Nes et al., MSSE 2014" is the mortality paper, the fitness
    norms are Loe 2013 and the non-exercise model is Nes 2011; "Quer et
    al., Nat Med 2020" is 2021 (27:73-77). "Liang 2018 Neuropsychiatr Dis
    Treat" and "Roehrs & Roth 2012 Sleep Med Rev" could not be confirmed
    under those journals (small).
12. **PPG screen over-states the study.** Plews 2017 validated phone PPG
    against ECG over 5-minute recordings; the case for a 60-second window
    rests on Esco & Flatt 2014 (ICC 0.98 vs 5 min at rest in athletes) and
    Munoz 2015. A 2025 athlete study found PPG-app rMSSD off by ~17 % vs ECG.
    Cite both, require ≥ 55 s of clean signal for a "good" reading, and say
    "spot check, about ±15 %" (small).

---

## 2. Per-file tables

### RecoveryCalculator.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| ln transform of HRV | `log(rmssd)` | Ln rMSSD normalises the skew; standard in Plews 2012/2013, Buchheit 2014 ✓ (strong) | Supported | None |
| 7-day rolling average vs baseline | mean of last ≤ 7 nights, ≥ 3 nights | Plews 2012 EJAP; Plews 2014 IJSPP (weekly averages beat single days; ≥ 3-4 values a week needed) (moderate) | Supported | Show "n of 7 nights" when < 5 |
| SWC = 0.5 × SD of ln HRV | `0.5 * max(sd, 0.05)` | Javaloyes 2019 IJSPP used a 4-week baseline ± 0.5 SD; Hopkins' SWC convention; Buchheit 2014 discusses SWC (moderate; the "0.5" line in Plews 2013 was not visible in the abstract) | Supported | None. Keep the citation as Javaloyes 2019 + Buchheit 2014 |
| Baseline window 30 days, minimum 14 nights per signal | 30 / 14 | Javaloyes 2019: 4-week baseline. Plews 2014: validity needs most days measured. No study sets 14 (weak) | App choice | Keep; say "4 weeks" in UI once nights ≥ 28 |
| Weights: trend 0.35, last night 0.20, RHR 0.25, sleep 0.20 | as listed | None. Trials use the HRV trend only; RHR is less sensitive than HRV (Buchheit 2014); subjective wellness tracks load well (Saw 2016 BJSM) | App choice | Make the HRV-trend state set the band (problem 1); weights then only move within band |
| z floor for HRV SD 0.10, RHR SD 1.5 bpm | 0.10 / 1.5 | Day-to-day SD of ln rMSSD ≈ 0.10-0.20 in athletes; RHR SD 2-4 bpm (moderate) | Supported | None |
| Sleep z = (score − 75)/12 | population anchor | No source; this is the only input not compared with the user's own baseline | Tweak | z = (score − mean of user's last 30 sleep scores)/max(sd, 6); fallback to (75, 12) until 14 nights |
| Logistic 1/(1+e^−(1.5z+0.3)) | score 57 at z = 0 | None | App choice | Fine. Note asymmetry: "high" needs z ≥ +0.27, "low" needs z ≤ −0.64 |
| Bands 34 / 67 | fixed | No evidence for the cut-offs | App choice | Tie to SWC state (problem 1) |
| Missing HRV | weights re-normalised; score from RHR + sleep | Reasonable | Supported | Contributors sheet already lists what was used; add "no HRV last night" line |
| RHR source | HealthKit `restingHeartRate` daily average | Night HR is steadier; Garmin RHR already is a sleep-period minimum; Apple's is a daytime estimate; illness studies used sleep-period HR (Natarajan 2020 ✓, Mishra 2020 ✓) | Tweak | Prefer `SleepingHeartRate.average` of the main sleep; fallback HealthKit; one source per baseline (problem 2) |
| "Needs about 4 nights" (README) | text | Code needs 14 | Wrong (stale text) | Update README |

### PersonalBaseline.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Band = mean ± 1 SD of previous 60 days, latest 7 excluded, ≥ 14 points | as listed | Plews 2012/2013 (band concept); excluding the recent week is a sound guard against drift (moderate) | Supported | None |
| Band width (±1 SD) differs from Recovery's ±0.5 SD | 1 SD vs 0.5 SD | Both legitimate; they answer different questions | Tweak (wording) | Label charts "typical range (±1 SD)" and Recovery "training-decision band (±0.5 SD)" so the two "normal ranges" don't contradict |

### SleepCalculator.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Weights 50/25/10/15 (45/20/10/10 + 15 regularity) | as listed | None sets them | App choice | Keep; already labelled as the app's |
| Sleep need 8 h default, user 6-11 h | 8 | Watson 2015 ✓: ≥ 7 h for adults; Kitamura 2016 ✓: mean individual optimum ≈ 8.4 h in young men (secondary) (strong for ≥ 7) | Supported | Offer "learn my need": median of alarm-free nights over 30 days, clamped 7-9.5 h (medium) |
| Need rises with previous-day strain | 0 (off) | No study links need to training load; Walsh 2021 BJSM consensus (athletes 7-9 h+) is qualitative | Supported (off) | Keep off |
| Efficiency: full marks ≥ 85 %, zero at 65 % | 0.85 / 0.65 | NSF (Ohayon 2017 ✓): ≥ 85 % good; < 74 % poor | Tweak | Zero at 70 %: `(eff − 0.70)/0.15` |
| Deep + REM target 40 % | 0.40 | Normal adult N3 ≈ 13-23 %, REM ≈ 20-25 % (AASM; Ohayon 2004 meta-analysis), both fall with age; wrist staging kappa ≈ 0.2 (Schyvens 2025, cited) | Tweak | Age-scaled target: 40 % under 40, 35 % 40-59, 30 % 60+. Keep 10 % weight and the "estimates" label |
| Interruptions: awake ≥ 5 min; score 1 − n/8 | 5 min / 8 | NSF: awakenings > 5 min, 0-1 good, 4+ poor | Tweak | 0-1 → 1.0, 2-3 → 0.5, ≥ 4 → 0 (problem 6) |
| Regularity = SRI/100 | linear | Windred 2024 ✓: median SRI 81, bottom quintile < ~72 | Tweak | (SRI − 50)/35 clamped 0-1 (problem 5) |
| Main-sleep window: −1 h / +30 min for in-bed and awake | 60 / 30 min | App choice | App choice | None |
| `SleepConsistency` spread: 20 min → 100, 2 h → 0 | linear | Display only; NSF regularity consensus (Sletten 2023 ✓ exists; content not fetched) treats ~1 h night-to-night variability as the upper end of "regular" | App choice | Fine for display |

### SleepRegularity.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| SRI formula, noon-to-noon days, consecutive-day pairs | 200p − 100 | Phillips 2017 Sci Rep ✓ (strong) | Supported | None |
| 5-min epochs | 300 s | Phillips used 1-min epochs; 5-min changes the value by < 1 point | Supported | None |
| Minimum 4 pairs (5 nights) | 4 | Windred used ≥ 5 valid days (secondary); fine | Supported | None |
| Sleep debt window 14 nights, running balance, cap 20 h | 14 / 20 | Van Dongen 2003 ✓ (14 nights of 6 h ≈ a night without sleep); Kitamura 2016 ✓ (debt recovered over days; 1 h ≈ 4 days) (moderate) | Supported | None |
| "Longer nights pay the debt down (Sletten 2023 NSF consensus)" | comment | Sletten 2023 is the regularity consensus; recovery-sleep evidence is Banks 2010 Sleep and Kitamura 2016 | Wrong citation | Re-cite (problem 11) |
| Levels < 1 / < 3 / < 6 h; payback 30-60 min/night ≤ 14 nights | as listed | No study; Kitamura's recovery pace (≈ 15 min/night per hour of debt) is slower than the plan | App choice | Keep; label "a plan, not a prescription" |
| `BeatToBeat` RMSSD: RR 0.3-2.0 s, 20 % ectopic filter, ≥ 180 s, ≥ 30 pairs | as listed | Task Force 1996 (5 min standard); Munoz 2015 (ultra-short valid); 20 % successive-difference filter is a common artefact rule (moderate) | Supported | None |

### SleepSessions.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Session gap 90 min | 90 min | None; night awakenings are almost always shorter | App choice | None |

### EnergyCalculator.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Mifflin-St Jeor | 10W + 6.25H − 5A + 5/−161 | Frankenfield 2005 ✓ (within 10 % for most adults) (strong) | Supported | None |
| Katch-McArdle when body fat known | 370 + 21.6 × LBM | FFM equations do better in muscular athletes (Tinsley 2019 JSCR, from memory), but only with a good body-fat measurement; BIA scales err by ±5-8 points | Tweak | Use it only when the body-fat source is DXA/clinic, or average the two; label which was used (problem 7) |
| Keytel 2005 no-VO₂max equation, coefficients | male −55.0969 + 0.6309HR + 0.1988W + 0.2017A; female −20.4022 + 0.4472HR − 0.1263W + 0.074A (kJ/min) | Keytel 2005 ✓, R² 0.73 without VO₂max; derived for steady submaximal exercise (moderate) | Supported | None. Individual error is large; say so |
| Applied only ≥ 30 % HRR, ≤ 2 min per sample | 0.30 / 2 | Keytel is not valid at rest; consistent with StrainCalculator | Supported | None |
| Lifting MET floor 6.0 (RPE ≥ 7) / 3.5, net of 1 MET | 6.0 / 3.5 | Compendium codes 02054 (vigorous, 6.0) and 02060 (multiple exercises 8-15 reps, 3.5); 2024 values not fetched, from memory | Supported | None |
| TEF 10 % of intake | 0.10 | Westerterp 2004 (≈ 10 %; protein 20-30 %, carbs 5-10 %, fat 0-3 %) (strong) | Tweak | When macros exist: 0.25 × protein kcal + 0.075 × carb kcal + 0.02 × fat kcal; high-protein lifters sit at 12-15 % |
| Steps 0.00057 kcal/step/kg net | 0.00057 | ACSM walking equation: net VO₂ = 0.1 × speed; at 100 steps/min, 0.8 m steps → ≈ 0.0004 kcal/kg/step | Tweak | 0.00042; cite ACSM metabolic equation |
| 100 steps per raised-HR minute | 100 | Tudor-Locke 2020 BJSM ✓ (100 steps/min ≈ moderate) | Supported | None |
| Measured resting energy from watch, 800-4000 kcal | range | Sanity bound | App choice | None |
| "±10-15 % error" (README) | text | Shcherbina 2017 ✓: no device under 20 %; JMIR 2022 review ✓: > 30 % | Wrong | "about ±15-25 %, more on training days" |

### EnergyBalance.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Weight EWMA 10 %/day, gap-adjusted | 0.1 | Hacker's Diet convention; any 7-14 day smoother works | App choice | None |
| Weekly change from least squares over ≥ 4 weigh-ins, ≥ 10 days | 4 / 10 | Sensible; daily noise 1-2 kg | Supported | None |
| 7,700 kcal per kg | 7700 | Hall 2011 Lancet: adequate over weeks, wrong for long-term prediction (moderate) | Supported | None |
| 14 fully logged days, 28-day window | 14 / 28 | Practice in adaptive-TDEE apps; under-reporting is the main error (Burrows 2019) | App choice | None |
| Partial day < 70 % of median or < 50 % of expenditure; floor 800 kcal | as listed | None | App choice | None |
| Creatine water 1 kg, ramp 7 d (loading) / 28 d | 1 / 7 / 28 | Kreider 2017 ✓: 1-2 kg; Hultman 1996 ✓: 3 g/day saturates in ~28 d | Supported | None |
| "Wrist trackers miss energy by > 30 %" | text | JMIR 2022 ✓ | Supported | None |

### Goals.swift and Nutrition.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Loss rate options 0.25-1 %/week | list | Helms 2014 ✓; Garthe 2011 ✓ (0.7 %/wk kept more lean mass than 1.4 %) (moderate) | Supported | None |
| Gain rate 0.25-0.5 %/week | list | Iraki 2019 ✓ | Supported | None |
| Protein 1.6 g/kg (muscle/strength), 1.2 (health/endurance), 2.2 (losing) | as listed | Morton 2018 ✓ (breakpoint 1.62, CI to 2.2); ISSN 2017 1.4-2.0; endurance athletes 1.2-1.6 | Tweak | Endurance focus → 1.4 g/kg; health → 1.2-1.6 range shown |
| Deficit: 2.6 g/kg lean mass | 2.6 | Helms 2014 ✓ 2.3-3.1 g/kg FFM | Supported | None |
| Adjusted weight when BMI > 30 (BMI-25 weight + 40 % excess) | 0.4 | Clinical convention for adjusted body weight; not from a protein trial | App choice | Label it |
| Calorie floors 1500 / 1200 | floors | Clinical convention (very-low-calorie diets need supervision); no outcome study | App choice | Keep |
| Goal suggestion: body fat > 22/32 % → lose; < 12/20 % → gain | cut-offs | ACE categories; no outcome basis | App choice | Keep, worded as a suggestion |
| Training-style reps/RPE | enum | Covered by planner audit | – | – |

### Micronutrients.swift

All RDA/AI, EAR and UL values were checked against the IOM/NASEM DRI
tables (from memory; the tables were not fetchable). Every value matches:
vitamin C 90/75 (EAR 75/60, UL 2000); vitamin D 15 µg (20 µg > 70; EAR 10;
UL 100 µg); zinc 11/8 (EAR 9.4/6.8; UL 40); iron 8 / 18 (EAR 6 / 8.1; UL 45);
magnesium 400-420 / 310-320 (EAR 330-350 / 255-265); potassium AI 3400/2600
(NASEM 2019); sodium AI 1500, CDRR 2300; calcium 1000/1200 (EAR 800/1000;
UL 2500/2000); B12 2.4 (EAR 2.0); folate 400 (EAR 320); vitamin A 900/700
(EAR 625/500); selenium 55 (EAR 45; UL 400); fibre AI 38/25 and 30/21 over 50.

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| "Low" = below EAR; AI-only nutrients < 70 % of AI | rule | IOM 2000 (DRI applications): EAR cut-point method is for groups; for one person a 7-day mean below the EAR means "probably inadequate" | Supported | Keep "may be" wording |
| 4 logged days minimum, 7-day average | 4 / 7 | IOM: ≥ 7 days for most nutrients; iron, vitamin A need far more | Tweak | Say "a week of logging is a rough guide"; for vitamin A and iron require 7 days |
| Vitamin A UL not applied to total vitamin A | nil | Correct: UL is for preformed retinol | Supported | None |
| Magnesium UL absent | nil | UL (350 mg) applies to supplements only | Supported | None |
| Athlete-specific needs | none | ACSM/AND/DC 2016 joint position: no RDA change for most; iron for female and endurance athletes (ferritin, not intake); calcium 1500 mg with low energy availability/amenorrhoea; sodium replacement with heavy sweating (moderate) | Tweak | Add a "training" note: iron → check ferritin (labs); sodium "may be low" is suppressed on days with > 60 min of exercise or heat |
| Effect texts (vit C, D, zinc, iron, magnesium) | text | Hemilä & Chalker 2013; Jolliffe 2025; Hemilä 2017; Sim 2019 ✓; Arab 2023 (from memory) | Supported | None |

### Habits.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Caffeine: 107 mg → 8.8 h, 217 mg → 13.2 h before bed; −45 min TST | constants | Gardiner 2023 ✓ (24 studies; −45 min TST, −7 % efficiency, +9 min latency, +12 min WASO confirmed; the 8.8/13.2 h figures are the paper's model estimates, from memory). Gardiner 2025 crossover trial: 100 mg at 4 h before bed had no measurable effect, 400 mg at 12 h did (secondary) (moderate, wide individual variation) | Tweak | Linear by dose (problem 4); word as "conservative average" |
| Large-dose step at 180 mg | 180 | None | App choice | Replaced by the linear rule |
| Default bedtime 23:00 | 1380 min | Fallback only | App choice | None |
| Alcohol: dose-dependent HRV/HR effect; REM disrupted from ~2 drinks | text | Pietilä 2018 ✓ (recovery −9/−24/−39 points for low/moderate/high); Gardiner 2025 ✓ (REM disruption from ≤ 0.5 g/kg) (strong) | Supported | None |
| Personal comparison: ≥ 5 nights each side, Welch p < 0.05 | 5 / 0.05 | Sound for a descriptive comparison | App choice | Say "linked with", not "causes" |
| Protein per meal 0.4 g/kg × 4 | 0.4 / 4 | Schoenfeld & Aragon 2018 ✓ | Supported | None |
| Weight pace: loss > 1 %/wk; gain > 1.5 × plan + 0.1; non-gain > 0.5 %/wk | as listed | Helms 2014 ✓; Iraki 2019 ✓ | Supported | None |
| Heat: hot ≥ 28 °C feels-like, very hot ≥ 35; target −10/−15, halved when acclimatised | constants | ACSM uses WBGT (Roberts 2021 ✓ consensus; from memory: WBGT 18-23 moderate, 23-28 high, 28-30 very high, > 30 cancel for unacclimatised). Heat index ≈ 28 °C sits around WBGT 24-26 in sun, so the bands are in the right region but shade/sun make a 3-5 °C WBGT difference | Tweak | Estimate WBGT from T, RH (and solar if available) and use ACSM bands (problem 10) |
| Acclimatised after 10 hot training days in 14 | 10 / 14 | Périard 2015 ✓ (most adaptation in 7-14 days; sweat changes in 3-4 days); Périard 2021 Physiol Rev (moderate-strong) | Supported | Also decay: lose it after ~2-3 weeks away from heat (Daanen 2018) |
| Hot-day advice text | text | Roberts 2021 ✓ | Supported | None |

### Wellbeing.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Water base 3.7 / 2.7 L (total water incl. food) | NASEM 2004 AI | AI, not a requirement; ~20 % from food (from memory; search did not reach it) | Supported | Confirm whether Cronometer's Health "Water" includes food moisture; if it is drinks only, base should be 3.0 / 2.2 L |
| + 0.75 L per exercise hour (max 3 L); + 0.5 / 1.0 L at ≥ 27 / 32 °C | constants | Sawka 2007 ACSM (sweat 0.5-2 L/h; replace to limit loss to < 2 % BW) (moderate) | Supported | None |
| "HR up 3-8 bpm per 1 %" | text | Montain & Coyle 1992 ✓ (HR rises linearly with dehydration, r = 0.99); Heaps 1994: +10 bpm at 0.9 %, +18 at 2.8 % | Tweak | "about 3-5 bpm per 1 % at rest, more in the heat" |
| Mood/focus at ~1.5 % | text | Armstrong 2012 J Nutr (1.36 % in women) (moderate; not reached by search) | Supported | None |
| Hyponatraemia > ~1 L/h for hours | text | Hew-Butler 2015 ✓ consensus | Supported | None |
| "Behind" if < 70 % of linear 7 am-9 pm expectation, from 11 am | rule | No study; drinking to thirst is adequate for sessions < 1-2 h (Goulet 2011; Kenefick 2018) | App choice | Soften to "a bit behind" and drop "can make your resting heart rate read higher tonight" (no evidence) |
| Illness watch: RHR ≥ max(2 SD, 4 bpm) above baseline | rule | Mishra 2020 ✓ (63 % flagged pre-symptom from RHR residuals); Natarajan 2020 ✓ (RR and RHR up, HRV down; AUC 0.77); Shapiro 2021 ✓; Quer 2021 ✓ (sensors + symptoms AUC 0.80 vs 0.72) (moderate) | Supported | Use sleeping HR; require 2 consecutive days for "Major" without symptoms (problem 9) |
| Breathing ≥ max(2 SD, 1 /min) | rule | Natarajan 2020 ✓ (RR rises ~1-3 /min around onset; exact figure not confirmed) | Supported | None |
| Temperature ≥ +0.5 °C vs 14-night mean | 0.5 | Smarr 2020 ✓ (ring temperature flagged fever onset in 93 % of cases, ~3 days early; threshold not confirmed); Grzesiak 2021 ✓ (exists) | Supported | Add cycle adjustment (problem 9) |
| HRV ≤ −20 % only with another signal | −20 % | Hirten 2021 JMIR (HRV changes up to 7 days before diagnosis; from memory) | App choice | Keep |
| Two signals → Major; alcohol ≥ 2 or strain ≥ 80 explains unless symptoms | rule | Matches the multi-signal designs; alcohol and heavy training are the known false-positive sources | Supported | None |
| Deload: stall ≤ 0.5 % over 2 weeks in ≥ 50 % of lifts; "half the sets" | rule | Bell 2023 Sports Med Open Delphi ✓ (deload ≈ 1 week, ~50 % volume) | App choice, consistent | None |

### HeartHealth.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| HRR: peak = max of last 3 min; 1-min value ±30 s; < 12 bpm "Low" | 12 | Cole 1999 NEJM ✓ (≤ 12 bpm abnormal after a maximal test with a walking cool-down) (strong for that protocol) | Tweak | Compute only after cardio workouts whose last 3 min averaged ≥ 70 % HRR; skip gym sessions (end time is imprecise, HR not elevated). Labels 20/30 are app choice |
| "Heart rate above resting" 0-100, full scale 35 % HRR, waking 7-22, < 50 % HRR | constants | None | No evidence | Keep as "experimental" (UI already says so) |
| Intensity minutes: 40-59 % / ≥ 60 % HRR; vigorous ×2; 150/week | ACSM; WHO 2020 | Supported (strong) | None |
| Sleeping HR: lowest 5-min average | 5 min | Common practice | Supported | Use it for recovery (problem 2) |
| RHR labels < 55 / 65 / 75 | cut-offs | Population medians ≈ 65 bpm (Quer 2020 Fitbit cohort, from memory); Zhang 2016 ✓ risk +9 % per 10 bpm | App choice | None |
| Body-fat labels 6/14/18/25 and 14/21/25/32 | ACE categories | ACE is a trade body, not a study | App choice | Cite ACE in UI |
| VO₂max labels at 0.8/0.95/1.1/1.25 × FRIEND median | multipliers | Kaminsky 2015 medians match memory; the multipliers are not FRIEND percentiles | Tweak | Use FRIEND 20/40/60/80th percentiles per decade (medium) |

### HeartRateComparison.swift

No health constants. MAD, bias and Pearson r are the right descriptive
statistics for two devices. Suggest adding Bland-Altman limits (bias ±
1.96 SD), which is what device-validation papers report. Small.

### HomeBloodPressure.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Categories < 120/80, 120-129/< 80, 130-139 or 80-89, ≥ 140/90, ≥ 180/120 | ACC/AHA 2017 | Kept in 2025 AHA/ACC ✓ (130/80 threshold confirmed) (strong) | Supported | None |
| Home protocol: 2 readings, morning and evening, 7 days, discard day 1, ≥ 12 readings | rule | ESH 2021 practice guidelines (Stergiou et al., J Hypertens 2021) (from memory; not reached) (strong) | Supported | None |
| Home average judged on office thresholds | rule | AHA/ACC 2025 ✓: home threshold = 130/80 (same as office). ESC 2024 ✓: home ≥ 135/85 = hypertension, 120/70-134/84 elevated | Tweak | Add one line: "European guidelines call a home average high from 135/85" and flag diastolic 70-79 as ESC-elevated only when the user picks ESC |
| Day-1 discard only when ≥ 2 days | rule | ESH | Supported | None |
| Severe ≥ 180/120 advice | text | AHA | Supported | None |

### LabMarkers.swift

Ranges are typical adult values; the UI says the lab's range wins and
"this tracks results; it doesn't diagnose" (LabsView lines 110, 284). Good.

| Marker | Code | Evidence | Verdict | Change |
|---|---|---|---|---|
| LDL < 100 mg/dL (2.6) | high: 100 | NCEP ATP III "optimal"; ESC/EAS 2019: < 116 low risk, < 100 moderate, < 70 high, < 55 very high; AHA/ACC 2018 has no targets | Tweak | Show "optimal < 100; < 116 is the European low-risk goal" |
| HDL ≥ 40 / 50 | low: 40/50 | ATP III; metabolic-syndrome criteria | Supported | None |
| Total < 200 | high: 200 | ATP III | Supported | None |
| Triglycerides < 150 (1.7) | high: 150 | ATP III; ESC 2019 | Supported | None |
| ApoB < 100 mg/dL (1.0 g/L) | high: 100 | ESC/EAS 2019 ✓ (< 100 moderate, < 80 high, < 65 very high risk) | Supported | Add "< 80 if high risk" in the about text |
| Lp(a) | missing | EAS 2022 consensus (Kronenberg et al., Eur Heart J 2022): > 50 mg/dL or > 125 nmol/L = high; 30-50 grey zone; measure once (from memory) | Add | New marker: mg/dL high 50, nmol/L high 125 |
| HbA1c < 5.6 % (38 mmol/mol) | high: 5.6 | ADA Standards 2025: 5.7-6.4 prediabetes, ≥ 6.5 diabetes (two tests) (from memory) | Supported | Reword "6.5 % or more suggests diabetes" → "6.5 % is the diagnostic threshold doctors use; it needs a repeat test" |
| Fasting glucose 70-99 (3.9-5.5) | range | ADA | Supported | None |
| Ferritin 24-336 / 11-307 | Mayo | Sim 2019 ✓ (athletes: < 35 stage 1, < 20 stage 2, < 12 stage 3; from memory); WHO 2020 < 15 | Tweak | Athlete line: < 30 µg/L "low for someone who trains" (problem 3); note acute-phase rise |
| Haemoglobin 13.2-16.6 / 11.6-15.0; haematocrit 38.3-48.6 / 35.5-44.9 | Mayo | Mayo (from memory) | Supported | Note: endurance training dilutes plasma (athlete Hb runs ~0.5 g/dL lower) |
| Vitamin D 20-50 ng/mL (50-125 nmol/L) | range | IOM 2011 (≥ 20 adequate; > 50 concern); Endocrine Society 2024 ✓ no longer defines thresholds and advises against routine testing in healthy adults | Supported | Add that sentence; athletes have no proven higher need |
| B12 200-900 pg/mL | range | Typical lab; 200-300 is a grey zone (MMA/holoTC needed) | Tweak | Add "200-300: borderline, ask about a follow-up test" |
| TSH 0.4-4.0 | range | Typical (Mayo 0.3-4.2) | Supported | None |
| Testosterone 264-916 ng/dL (9.2-31.8 nmol/L); women 15-70 | Travison 2017 harmonised, men 19-39 non-obese | Travison 2017 (from memory; search did not reach it); Bhasin 2018 ✓ uses 264 as the diagnostic lower limit | Supported | Note "range is for men 19-39; falls ~1 %/year after" |
| hs-CRP < 1 / 1-3 / > 3 mg/L | high: 3 | Pearson 2003 AHA/CDC (from memory) | Supported | Add "> 10 = acute inflammation, repeat in 2 weeks" |
| Creatinine 0.74-1.35 / 0.59-1.04 mg/dL | Mayo | Mayo | Supported | None (creatine note already there) |
| eGFR ≥ 60 | low: 60 | KDIGO 2024 (from memory) | Supported | Reword "is chronic kidney disease" → "is the definition doctors use for CKD"; mention cystatin C for muscular people |
| ALT 7-55 / 7-45; AST 8-48 / 8-43 | Mayo | ACG 2017 (Kwo et al.): healthy ALT upper limit ≈ 29-33 men, 19-25 women (from memory) | Tweak | Add "a 'healthy' ALT is under ~33 (men) / 25 (women), even if the lab range goes higher" |
| Folate, magnesium, uric acid | missing | Serum folate ≥ 4 ng/mL (deficient < 3); magnesium 1.7-2.3 mg/dL (serum reflects status poorly); uric acid Mayo 3.7-8.0 / 2.7-6.1 mg/dL, crystals form above ~6.8 (from memory) | Add | Three new markers with those ranges |
| Sex-specific and lab variation | handled | UI says the lab's range wins | Supported | None |

What the app may say: "in range / above / below the reference range", what
the marker reflects, and the thresholds guidelines use. It must not say
"you have X"; the two sentences flagged above (HbA1c, eGFR) are the only
ones that read like a diagnosis.

### MedicationKnowledge.swift

| Class | Claim | Evidence | Verdict | Change |
|---|---|---|---|---|
| Beta-blocker | lowers RHR and max HR "by 20-30 %" | Max HR falls ~20-35 bpm, i.e. 10-20 %; RHR 10-25 % (ACSM 11th ed.; Wonisch 2003, from memory) | Tweak | "by roughly 10-30 bpm, depending on dose" |
| Beta-blocker | raises HRV | Well established (vagal indices rise) (moderate) | Supported | None |
| Rate-limiting CCB | lower HR, hypotension | FDA labels | Supported | None |
| Stimulant | RHR +a few bpm, BP up; sleep worse; HRV lower | Liang 2018 (HR ≈ +5 bpm, SBP ≈ +2; the journal in the code could not be confirmed, likely IJERPH 2018;15:1789); Kidwell 2015 Pediatrics (from memory) ✓-ish | Tweak citation | Check the Liang reference |
| SSRI | little HRV effect; REM suppression | Kemp 2010 ✓ (TCAs reduce HRV; others "benign") but Licht 2010 (NESDA) found SSRIs lower HRV too | Tweak | "mixed: most studies small effect" |
| SNRI/TCA | HR up, HRV down | Kemp 2010 ✓ | Supported | None |
| GLP-1 | ~40 % of weight lost was lean; RHR +2-4 bpm; protein 2.0 g/kg | STEP 1 DXA (n = 140): lean −9.7 % vs fat −19.3 %; the ~40 % share is derived, not stated (secondary) ✓-ish. Wegovy label: mean RHR +1-4 bpm (from memory). ISSN 2017 ✓ | Tweak | "up to ~40 % (derived from the DXA substudy)"; "+1-4 bpm"; use the lean-mass protein rule from Goals when body fat is known |
| Metformin | blunts VO₂max and hypertrophy gains in older adults | Konopka 2019; Walton 2019 (from memory, both Aging Cell) | Supported | Keep "older adults" caveat |
| Statin | aches mostly not caused; ~1 in 15 | CTT 2022 Lancet (from memory: > 90 % of reported symptoms not due to statin) | Supported | None |
| NSAID | 1200 mg/day ibuprofen × 8 weeks blunted hypertrophy | Lilja 2018 ✓ (7.5 % vs 3.7 % quadriceps volume) | Supported | Add "a 2023 follow-up found little effect at over-the-counter doses" |
| Fluoroquinolone | tendon rupture, boxed warning | FDA (boxed since 2008, strengthened 2016) | Supported | "boxed warning since 2008" |
| Corticosteroid | insomnia, myopathy, hyperglycaemia | labels | Supported | None |
| Sedating antihistamine | next-day grogginess, slight HR rise | labels | Supported | None |
| Benzo/Z-drug | "reduces deep sleep" | True for benzodiazepines; Z-drugs change SWS little. Roehrs & Roth 2012 as "Sleep Med Rev" could not be confirmed | Tweak | "Benzodiazepines reduce deep sleep; Z-drugs much less"; fix citation |
| Diuretic, alpha-blocker, clonidine, thyroid, isotretinoin, albuterol | label effects | FDA labels | Supported | None |
| Antipsychotic | weight/appetite, sedation, HR | Pillinger 2020 ✓ Lancet Psychiatry 7:64-77 | Supported | None |
| Gabapentinoid | more slow-wave sleep | Foldvary-Schaefer 2002 (from memory) | Supported | None |
| Melatonin | onset ~7 min faster | Ferracioli-Oda 2013 (7.06 min; from memory) | Supported | None |
| Creatine | all four claims | Kreider 2017 ✓; Hultman 1996 ✓; Antonio 2021; Delpino 2022 (from memory) | Supported | None |
| Testosterone | more gains; haematocrit; tendon caution | Bhasin 2018 ✓; tendon risk evidence is from supraphysiological use (weak) | Tweak | Mark tendon caution as "weak evidence" |

### BodyAge.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Fitness age: VO₂max 54.4/43.0 at 25, −0.40/−0.30 per year, × 0.6, clamp ±12 | constants | Loe 2013 ✓ (HUNT3 norms; ~3.5 mL/kg/min per decade to 50, then 8 %/decade). "Nes 2014" is the mortality paper; the non-exercise model is Nes 2011 ✓ | Tweak citation | Cite Loe 2013 for norms; keep slopes; 0.6 and the clamp are app choices (already said) |
| RHR hazard 1.09 per 10 bpm above 60; Gompertz 8 years | 1.09 / 8 | Zhang 2016 CMAJ ✓ (RR 1.09, 95 % CI 1.07-1.12); Spiegelhalter 2016 "effective age" ✓ | Supported | None |
| Sleep < 6 h: hazard 1.12 once; 9 h+ flagged | 1.12 | Cappuccio 2010 ✓ | Supported | None |
| Steps 0.6 yr per 1,000 from 7k/6k to plateau 10k/8k | constants | Paluch 2022 ✓ (risk plateau 8-10k < 60, 6-8k ≥ 60); the per-1,000 conversion is approximate | App choice | None |
| Body-fat years −0.5 / 1 / 2.5 / 4.5 | heuristic | No mortality study by body-fat % | App choice (labelled) | None |
| BMI hazards 1.51/1.13/1.0/1.07/1.20/1.45/1.94/2.76 | table | Global BMI Mortality Collaboration 2016 ✓ (matches) | Supported | None |
| Total clamp ±20; one-decimal output | 0.1 | No validation of the composite | Tweak | Whole years with ±5 range (problem 8) |
| Confidence by factor count and freshness | rule | App choice; UI shows label, reason and "not a medical test" | Supported | None |
| Inputs (VitalsModel): sleep = 7-night average | 7 | Noisy | Tweak | 30-night average |

### MuscleRecovery.swift (recovery constants)

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Time constants 36 h (big) / 26 h (small); fatigue 8/set; fresh at 85 % | constants | After 10 hard sets a big muscle reads "fresh" at ~60 h, small at ~43 h. Trained men: strength back by 48-96 h after sets to failure, 24-48 h when not to failure (Morán-Navarro 2017 ✓; Ferreira 2017 ✓; Bishop 2008); Schoenfeld 2016 ✓ (2×/week ≥ 1×/week) (moderate) | App choice, consistent | Scale by effort: RPE ≥ 9.5 (to failure) × 1.3 time constant, RPE < 7 × 0.6 (already) |
| Secondary muscles 0.5 | 0.5 | Pelland (cited) | Supported | None |
| Cardio: one set-equivalent per 10 min, max 6 | heuristic | None | App choice | None |

### CheckIn.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Fever/body aches → rest; other symptoms → light | rule | "Neck check" (expert consensus; no trial) | Supported (weak) | None |
| Soreness ≥ 5 with areas → train the other half; ≥ 7 → lighter | rule | Soreness tracks damage poorly (Nosaka 2002, cited) but subjective wellness tracks load well (Saw 2016 BJSM) | App choice | None |
| Rested ≤ 2 → moderate effort | rule | Saw 2016 | Supported | None |
| Patterns: ≥ 7 days each side, |diff| ≥ 0.5 pooled SD, Welch t, BH FDR 0.10 | rule | Sound; SWC idea from Plews 2013 | Supported | Word insights as "linked with" (nights with alcohol are also late nights); FDR 0.10 is lenient, fine for personal hints |
| Factor thresholds: 300 mg caffeine, meal after 21:00, stress ≥ 4, water < 2 L | constants | None | App choice | None |
| Caffeine presets 95/63/120/200/47/34 mg | USDA / labels | Supported | None |
| Standard drink 14 g; ABV defaults | NIAAA | Supported | None |

### FitnessAdaptation.swift (step goal)

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Floor 7,000; default 8,000 (< 60) / 7,000 (≥ 60); max 12,000; goal = median + 1,000 | constants | Ding 2025 ✓ (7k vs 2k: ~47 % lower mortality, modest gains beyond); Paluch 2022 ✓ (plateau 8-10k / 6-8k) (strong) | Supported | Endurance focus: allow max 15,000; otherwise none |

### WeatherAdvice.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Heat 28 / 35 °C feels-like | constants | See Habits (WBGT) | Tweak | Same WBGT change |
| Cold ≤ 0 / ≤ −10 °C | constants | ACSM cold position stand (frostbite risk rises below wind-chill −27 °C; longer warm-up advice is sensible) | App choice | None |
| AQI > 100 / > 150 | EPA | Supported | None |
| UV ≥ 3 / ≥ 8 | WHO | Supported | None |
| Morning light 10-30 min within 3 h of sunrise; dim 2 h before bed; short days < 10 h | constants | Brown 2022 PLoS Biol ✓ (≥ 250 lux daytime, ≤ 10 lux evening); Burns 2021 ✓ | Supported | None |

### PPGAnalyzer.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Phone-camera PPG vs ECG | "1-minute readings closely matched ECG (Plews 2017)" | Plews 2017 ✓: 29 subjects, 5-min recordings, TEE ≈ 6 % CV, "trivial" differences vs ECG. 60-s validity: Esco & Flatt 2014 ✓ (ICC 0.98 at rest vs 5 min; worse post-exercise); Munoz 2015. 2025 athlete study: PPG app rMSSD MAPE 17.5 % vs ECG, chest strap 2 % (moderate) | Tweak | "Phone PPG matches ECG closely over 5 minutes (Plews 2017); 60-second readings agree well with 5-minute ones at rest (Esco & Flatt 2014). Expect about ±15 %" (problem 12) |
| Minimum 20 s, 40 clean intervals, quality × min(1, length/60) | constants | Esco & Flatt: 60 s acceptable, 30 s noticeably worse | Tweak | Require ≥ 55 s of clean signal for "good"; show "short reading" otherwise |
| Band-pass 0.7-3.5 Hz; refractory 0.33 s; 300-2000 ms; 20 % of local median | constants | Standard PPG practice | Supported | None |
| Posture/breathing not controlled | – | Plews used guided breathing; HRV4Training protocol: seated or supine, same each day, before caffeine | Tweak | Add "same position, right after waking, before coffee" to the steps |
| Resample 60 Hz, parabolic peak refinement | constants | Needed at 30 fps (33 ms timing resolution) | Supported | None |

### App/Services/VitalsModel.swift

| Item | Code value | Evidence | Verdict | Change |
|---|---|---|---|---|
| Stress estimate: waking 7-22, excludes workouts, < 50 % HRR, full scale 35 % | constants | No study; UI says "Experimental" | No evidence | Keep labelled |
| HRR from workouts ≥ 10 min, peak in last 3 min | rule | Cole 1999 ✓ protocol was a maximal test | Tweak | Cardio only, peak ≥ 70 % HRR |
| RHR tone ≤ 65 good, ≤ 80 neutral | cut-offs | App choice | App choice | None |
| SpO₂ ≥ 95 normal; breathing 12-20 | ranges | Standard adult ranges | Supported | None |
| Temperature vs 14-night mean, ±0.5 °C | rule | Smarr 2020 ✓ | Supported | Cycle adjustment |
| Sleep "Enough" ≥ 7 h | 7 | Watson 2015 ✓ | Supported | None |
| Body-age inputs: RHR 14 d, sleep 7 n, steps 30 d | windows | – | Tweak | Sleep 30 nights |
| Illness RHR baseline needs ≥ 7 nights | 7 | Less than recovery's 14 | App choice | Use 14 for consistency |

---

## 3. Goal tailoring

- **Recovery / sleep**: no goal dependence in the evidence; keep one rule.
- **Energy**: lose → TEF from macros matters more (high protein); gain →
  Katch-McArdle bias matters more (lean mass rising). Show the method used.
- **Protein**: muscle/strength 1.6-2.2 g/kg; endurance 1.4-1.6; health 1.2;
  losing 2.3-3.1 g/kg lean mass (already); GLP-1 users the same lean-mass rule.
- **Labs**: lifters → ALT/AST, creatinine, CK notes after easy days (present);
  endurance or female → ferritin athlete line; everyone → ApoB/Lp(a) once.
- **Heat**: endurance focus gets the WBGT target cut; lifting indoors ignores it.
- **Steps**: endurance focus may go above 12,000; health focus keeps 7-12k.

## 4. Does the UI explain uncertainty?

| Area | Current UI | Verdict |
|---|---|---|
| Recovery | "Still learning your normal" until 14 nights; contributors sheet says the score is the app's own summary | Good; add "no HRV last night" line |
| Sleep stages | "estimates" chip | Good |
| Sleep regularity | "15 % of your sleep score" | Add "typical good sleepers score 75-85" once the mapping changes |
| Energy | Home card explains watch vs formula; README says ±10-15 % | Fix the number (±15-25 %) |
| Body age | Confidence label, reason, "not a medical test" | Good; add a range |
| Illness watch | Hedged messages; "Alcohol or hard training can also cause this" | Good; add cycle note |
| Caffeine | Hard cut-off time | Add "conservative; varies a lot between people" |
| Blood pressure | "A log, not a diagnosis"; cuffless warning | Good |
| Labs | "Your lab's range wins; doesn't diagnose" | Good; fix two sentences |
| Camera HRV | "spot check, not comparable to overnight" | Good; fix the Plews sentence, add ±15 % |
| Stress estimate | "Experimental" | Good |
| Muscle recovery | "a model, not measured" in code comment | Put one line in the muscle map legend |

---

## 5. References

✓ = existence and key figures confirmed by search in this session.
(m) = from memory; the host could not be fetched and the search budget
ran out. None are invented; please spot-check the (m) ones when implementing.

Recovery and HRV
- Plews DJ, Laursen PB, Kilding AE, Buchheit M. Heart rate variability in elite triathletes, is variation in variability the key to effective training? Eur J Appl Physiol 2012;112:3729-41. (m)
- Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M. Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring. Sports Med 2013;43:773-81. ✓
- Plews DJ, Laursen PB, Le Meur Y, et al. Monitoring training with heart-rate variability: how much compliance is needed for valid assessment? Int J Sports Physiol Perform 2014;9:783-5. ✓ (title seen)
- Buchheit M. Monitoring training status with HR measures: do all roads lead to Rome? Front Physiol 2014;5:73. ✓
- Javaloyes A, Sarabia JM, Lamberts RP, Moya-Ramon M. Training prescription guided by heart-rate variability in cycling. Int J Sports Physiol Perform 2019;14:23-32. (m)
- Esco MR, Flatt AA. Ultra-short-term heart rate variability indexes at rest and post-exercise in athletes: evaluating the agreement with accepted recommendations. J Sports Sci Med 2014;13:535-41. ✓
- Plews DJ, Scott B, Altini M, Wood M, Kilding AE, Laursen PB. Comparison of heart-rate-variability recording with smartphone photoplethysmography, Polar H7 chest strap, and electrocardiography. Int J Sports Physiol Perform 2017;12:1324-8. ✓
- Munoz ML, et al. Validity of (ultra-)short recordings for heart rate variability measurements. PLoS One 2015;10:e0138921. (m)
- Saw AE, Main LC, Gastin PB. Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures. Br J Sports Med 2016;50:281-91. (m)

Sleep
- Watson NF, et al. Recommended amount of sleep for a healthy adult: joint consensus statement of the AASM and SRS. Sleep 2015;38:843-4. ✓
- Ohayon M, et al. National Sleep Foundation's sleep quality recommendations: first report. Sleep Health 2017;3:6-19. ✓ (thresholds from press summary and memory)
- Ohayon MM, et al. Meta-analysis of quantitative sleep parameters from childhood to old age. Sleep 2004;27:1255-73. (m)
- Phillips AJK, et al. Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing. Sci Rep 2017;7:3216. (m; cited in code)
- Windred DP, et al. Sleep regularity is a stronger predictor of mortality risk than sleep duration. Sleep 2024;47:zsad253. ✓ (median 81; bottom quintile < 71.6 from a secondary source)
- Kitamura S, et al. Estimating individual optimal sleep duration and potential sleep debt. Sci Rep 2016;6:35812. ✓
- Van Dongen HPA, et al. The cumulative cost of additional wakefulness. Sleep 2003;26:117-26. (m)
- Banks S, Van Dongen HPA, Maislin G, Dinges DF. Neurobehavioral dynamics following chronic sleep restriction: dose-response effects of one night for recovery. Sleep 2010;33:1013-26. (m)
- Sletten TL, et al. The importance of sleep regularity: a consensus statement of the National Sleep Foundation sleep timing and variability panel. Sleep Health 2023;9:801-20. (m; exists, but is about regularity)
- Walsh NP, et al. Sleep and the athlete: narrative review and 2021 expert consensus recommendations. Br J Sports Med 2021;55:356-68. (m)

Energy and nutrition
- Frankenfield D, Roth-Yousey L, Compher C. Comparison of predictive equations for resting metabolic rate in healthy nonobese and obese adults. J Am Diet Assoc 2005;105:775-89. ✓
- Keytel LR, et al. Prediction of energy expenditure from heart rate monitoring during submaximal exercise. J Sports Sci 2005;23:289-97. ✓
- Herrmann SD, et al. 2024 Adult Compendium of Physical Activities. J Sport Health Sci 2024;13:6-12. ✓ (resistance-training values from memory)
- Westerterp KR. Diet induced thermogenesis. Nutr Metab 2004;1:5. (m)
- Tudor-Locke C, et al. Walking cadence (steps/min) and intensity in 21-40 year olds: CADENCE-adults. Br J Sports Med 2020. ✓ (cited in code)
- Shcherbina A, et al. Accuracy in wrist-worn, sensor-based measurements of heart rate and energy expenditure in a diverse cohort. J Pers Med 2017;7:3. ✓
- Germini F, et al. Accuracy and acceptability of wrist-wearable activity-tracking devices: systematic review. J Med Internet Res 2022;24:e30791. ✓ (author name not confirmed)
- Hall KD, et al. Quantification of the effect of energy imbalance on bodyweight. Lancet 2011;378:826-37. (m)
- Helms ER, Aragon AA, Fitschen PJ. Evidence-based recommendations for natural bodybuilding contest preparation. J Int Soc Sports Nutr 2014;11:20. (m)
- Garthe I, et al. Effect of two different weight-loss rates on body composition and strength. Int J Sport Nutr Exerc Metab 2011;21:97-104. (m)
- Iraki J, et al. Nutrition recommendations for bodybuilders in the off-season. Sports 2019;7:154. (m)
- Morton RW, et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains. Br J Sports Med 2018;52:376-84. (m)
- Schoenfeld BJ, Aragon AA. How much protein can the body use in a single meal? J Int Soc Sports Nutr 2018;15:10. (m)
- Jäger R, et al. ISSN position stand: protein and exercise. J Int Soc Sports Nutr 2017;14:20. (m)
- Kreider RB, et al. ISSN position stand: creatine. J Int Soc Sports Nutr 2017;14:18. (m) · Hultman E, et al. J Appl Physiol 1996;81:232-7. (m)
- Thomas DT, Erdman KA, Burke LM. Nutrition and athletic performance (AND/DC/ACSM joint position). Med Sci Sports Exerc 2016;48:543-68. (m)
- IOM/NASEM Dietary Reference Intakes (vitamins 1997-2001, electrolytes/water 2004, calcium/vitamin D 2011, sodium/potassium 2019). (m)

Habits, heat, hydration
- Gardiner C, et al. The effect of caffeine on subsequent sleep: a systematic review and meta-analysis. Sleep Med Rev 2023;69:101764. ✓ (TST −45 min confirmed; 8.8/13.2 h from memory)
- Gardiner C, et al. Dose and timing effects of caffeine on subsequent sleep: randomized crossover trial. Sleep 2025. (secondary; from the ACU thesis summary)
- Gardiner C, et al. The effect of alcohol on subsequent sleep in healthy adults: systematic review and meta-analysis. Sleep Med Rev 2025;80:102030. ✓
- Pietilä J, et al. Acute effect of alcohol intake on cardiovascular autonomic regulation during the first hours of sleep. JMIR Ment Health 2018;5:e23. ✓
- Périard JD, Racinais S, Sawka MN. Adaptations and mechanisms of human heat acclimation. Scand J Med Sci Sports 2015;25(S1):20-38. ✓
- Périard JD, Eijsvogels TMH, Daanen HAM. Exercise under heat stress. Physiol Rev 2021;101:1873-979. (m)
- Roberts WO, et al. ACSM expert consensus statement on exertional heat illness. Curr Sports Med Rep 2021;20:470-84. (m; WBGT bands from memory)
- Daanen HAM, Racinais S, Périard JD. Heat acclimation decay and re-induction. Sports Med 2018;48:409-30. (m)
- Sawka MN, et al. ACSM position stand: exercise and fluid replacement. Med Sci Sports Exerc 2007;39:377-90. (m)
- Montain SJ, Coyle EF. Influence of graded dehydration on hyperthermia and cardiovascular drift during exercise. J Appl Physiol 1992;73:1340-50. ✓
- Armstrong LE, et al. Mild dehydration affects mood in healthy young women. J Nutr 2012;142:382-8. (m)
- Hew-Butler T, et al. Statement of the Third International Exercise-Associated Hyponatremia Consensus. Clin J Sport Med 2015;25:303-20. (m)
- Kenefick RW. Drinking strategies: planned drinking versus drinking to thirst. Sports Med 2018;48(S1):31-7. (m)

Illness watch
- Mishra T, et al. Pre-symptomatic detection of COVID-19 from smartwatch data. Nat Biomed Eng 2020;4:1208-20. ✓
- Natarajan A, Su HW, Heneghan C. Assessment of physiological signs associated with COVID-19 measured using wearable devices. npj Digit Med 2020;3:156. ✓
- Quer G, et al. Wearable sensor data and self-reported symptoms for COVID-19 detection. Nat Med 2021;27:73-7. ✓ (year is 2021)
- Shapiro A, et al. Characterizing COVID-19 and influenza illnesses in the real world via person-generated health data. Patterns 2021;2:100188. ✓
- Smarr BL, et al. Feasibility of continuous fever monitoring using wearable devices. Sci Rep 2020;10:21640. ✓
- Grzesiak E, et al. Assessment of the feasibility of using noninvasive wearable biometric monitoring sensors to detect influenza and the common cold before symptom onset. JAMA Netw Open 2021;4:e2128534. ✓
- Hirten RP, et al. Use of physiological data from a wearable device to identify SARS-CoV-2 infection and symptoms. J Med Internet Res 2021;23:e26107. (m)

Heart, blood pressure, body age
- Cole CR, et al. Heart-rate recovery immediately after exercise as a predictor of mortality. N Engl J Med 1999;341:1351-7. (m)
- Kaminsky LA, et al. Reference standards for cardiorespiratory fitness measured with cardiopulmonary exercise testing (FRIEND). Mayo Clin Proc 2015;90:1515-23. (m)
- Zhang D, Shen X, Qi X. Resting heart rate and all-cause and cardiovascular mortality in the general population: a meta-analysis. CMAJ 2016;188:E53-63. ✓
- Loe H, et al. Aerobic capacity reference data in 3816 healthy men and women 20-90 years. PLoS One 2013;8:e64319. ✓
- Nes BM, et al. Estimating VO2peak from a nonexercise prediction model: the HUNT Study. Med Sci Sports Exerc 2011;43:2024-30. ✓ · Nes BM, et al. A simple nonexercise model of cardiorespiratory fitness predicts long-term mortality. Med Sci Sports Exerc 2014;46:1159-65. ✓
- Cappuccio FP, et al. Sleep duration and all-cause mortality: meta-analysis. Sleep 2010;33:585-92. (m)
- Paluch AE, et al. Daily steps and all-cause mortality: meta-analysis of 15 cohorts. Lancet Public Health 2022;7:e219-28. (m)
- Ding D, et al. Daily steps and health outcomes in adults: systematic review and dose-response meta-analysis. Lancet Public Health 2025. (m)
- Global BMI Mortality Collaboration. Body-mass index and all-cause mortality. Lancet 2016;388:776-86. (m)
- Spiegelhalter D. How old are you, really? Communicating chronic risk through "effective age". BMC Med Inform Decis Mak 2016;16:104. (m)
- Whelton PK, et al. 2017 ACC/AHA hypertension guideline. Hypertension 2018;71:e13-115. (m) · 2025 AHA/ACC guideline (home threshold 130/80) ✓ · McEvoy JW, et al. 2024 ESC guidelines for elevated blood pressure and hypertension. Eur Heart J 2024;45:3912-4018. ✓
- Stergiou GS, et al. 2021 ESH practice guidelines for office and out-of-office blood pressure measurement. J Hypertens 2021;39:1293-302. (m)

Labs
- Mach F, et al. 2019 ESC/EAS dyslipidaemia guidelines. Eur Heart J 2020;41:111-88. ✓ (ApoB goals)
- Kronenberg F, et al. Lipoprotein(a) in atherosclerotic cardiovascular disease and aortic stenosis: EAS consensus statement. Eur Heart J 2022;43:3925-46. (m)
- Pearson TA, et al. Markers of inflammation and cardiovascular disease (AHA/CDC). Circulation 2003;107:499-511. (m)
- American Diabetes Association. Standards of Care in Diabetes 2025. Diabetes Care 2025;48(S1). (m)
- Sim M, Garvican-Lewis LA, Cox GR, et al. Iron considerations for the athlete: a narrative review. Eur J Appl Physiol 2019;119:1463-78. ✓ (thresholds from memory, after Peeling 2007)
- Institute of Medicine. Dietary Reference Intakes for Calcium and Vitamin D. 2011. (m) · Demay MB, et al. Vitamin D for the prevention of disease: Endocrine Society guideline. J Clin Endocrinol Metab 2024;109:1907-47. ✓ (no thresholds for healthy adults)
- Travison TG, et al. Harmonized reference ranges for circulating testosterone levels in men of four cohort studies. J Clin Endocrinol Metab 2017;102:1161-73. (m)
- Bhasin S, et al. Testosterone therapy in men with hypogonadism: Endocrine Society guideline. J Clin Endocrinol Metab 2018;103:1715-44. (m)
- KDIGO 2024 clinical practice guideline for CKD. Kidney Int 2024;105(4S). (m)
- Kwo PY, Cohen SM, Lim JK. ACG clinical guideline: evaluation of abnormal liver chemistries. Am J Gastroenterol 2017;112:18-35. (m)
- Mayo Clinic Laboratories reference values (ferritin, haemoglobin, haematocrit, creatinine, ALT, AST, uric acid, magnesium, folate). (m)

Medications
- Kemp AH, et al. Impact of depression and antidepressant treatment on heart rate variability. Biol Psychiatry 2010;67:1067-74. ✓ · Licht CMM, et al. Longitudinal evidence for unfavorable effects of antidepressants on heart rate variability. Biol Psychiatry 2010;68:861-8. (m)
- Wilding JPH, et al. Once-weekly semaglutide in adults with overweight or obesity (STEP 1). N Engl J Med 2021;384:989-1002. ✓ (DXA substudy n = 140)
- Konopka AR, et al. Metformin inhibits mitochondrial adaptations to aerobic exercise training in older adults. Aging Cell 2019;18:e12880. (m) · Walton RG, et al. Metformin blunts muscle hypertrophy in response to progressive resistance exercise training in older adults (MASTERS). Aging Cell 2019;18:e13039. (m)
- Lilja M, et al. High doses of anti-inflammatory drugs compromise muscle strength and hypertrophic adaptations to resistance training in young adults. Acta Physiol 2018;222:e12948. ✓
- Cholesterol Treatment Trialists' Collaboration. Effect of statin therapy on muscle symptoms. Lancet 2022;400:832-45. (m)
- Liang EF, et al. The effect of methylphenidate and atomoxetine on heart rate and systolic blood pressure. Int J Environ Res Public Health 2018;15:1789. (m; the code's journal could not be confirmed)
- Kidwell KM, et al. Stimulant medications and sleep for youth with ADHD: a meta-analysis. Pediatrics 2015;136:1144-53. (m)
- Pillinger T, et al. Comparative effects of 18 antipsychotics on metabolic function. Lancet Psychiatry 2020;7:64-77. ✓
- Ferracioli-Oda E, Qawasmi A, Bloch MH. Meta-analysis: melatonin for the treatment of primary sleep disorders. PLoS One 2013;8:e63773. (m)
- Foldvary-Schaefer N, et al. Gabapentin increases slow-wave sleep in normal adults. Epilepsia 2002;43:1493-7. (m)
- Delpino FM, et al. Influence of age, sex, and type of exercise on the efficacy of creatine supplementation on lean body mass. Nutrition 2022;103-104:111791. (m)
- Wonisch M, et al. Influence of beta-blocker use on percentage of target heart rate exercise prescription. Eur J Cardiovasc Prev Rehabil 2003;10:296-301. (m)
- Bell L, et al. Integrating deloads into strength and physique sports training programmes: an international Delphi consensus. Sports Med Open 2023;9:87. (m)

Muscle recovery
- Schoenfeld BJ, Ogborn D, Krieger JW. Effects of resistance training frequency on measures of muscle hypertrophy. Sports Med 2016;46:1689-97. (m)
- Morán-Navarro R, et al. Time course of recovery following resistance training leading or not to failure. Eur J Appl Physiol 2017;117:2387-99. ✓
- Ferreira DV, et al. Dissociated time course between peak torque and total work recovery following bench press training in resistance trained men. Physiol Behav 2017;179:143-7. ✓ (title seen)
- Bishop PA, Jones E, Woods AK. Recovery from training: a brief review. J Strength Cond Res 2008;22:1015-24. (m)

Light and air
- Brown TM, et al. Recommendations for daytime, evening, and nighttime indoor light exposure. PLoS Biol 2022;20:e3001571. (m)
- Burns AC, et al. Time spent in outdoor light is associated with mood, sleep, and circadian rhythm-related outcomes. J Affect Disord 2021;295:347-52. (m)
- US EPA Air Quality Index; WHO Global Solar UV Index. (m)
