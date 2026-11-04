# Strain: what the science says

Audit of the daily strain score (0–100%), the target-strain range and the
training-load trend, against the sports-science literature. November 2026.

Code: `Packages/AppCore/Sources/AppCore/StrainCalculator.swift`,
`StrainPlanner.swift`, `TrainingLoad.swift`, `HeartRateProfile.swift`, and the
target and max-HR learning in `FitnessAdaptation.swift`.

Verdicts: **Supported** (matches the literature), **Tweaked** (changed in this
pass), **App choice** (no study defines it; reasonable and documented),
**Open** (worth a decision, not changed here).

## How strain is computed

1. **Cardio load.** For each pair of heart-rate samples (gap ≤ 10 min, each
   reading counting for ≤ 2 min), Banister TRIMP = minutes × x × a·e^(b·x), where
   x is the fraction of heart-rate reserve. Men: a = 0.64, b = 1.92; women:
   a = 0.86, b = 1.67. Minutes below 30% of reserve add nothing.
2. **Lifting load.** For each logged gym session: session RPE (CR-10; 6.5 if
   unrated) × minutes (capped at 180) × `rpeToTrimp`. The session counts as the
   higher of this and the heart-rate TRIMP recorded during it, never both.
3. **0–100 mapping.** strain = 100 × (1 − e^(−load / 126)).
4. **Target.** From the recovery score (bands 0–33 / 34–66 / 67–100) and the
   median strain of your training days over 4 weeks (U): low → U−45…U−20,
   moderate → U−20…U, high → U…U+20 (U = 65 until there are 6 training days).
5. **Training-load trend.** Last 7 days' average daily load vs your usual,
   shown on the strain scale. "Steady" is 80–130% of usual and "spike" is over 150%.

## Verdicts

| # | Assumption | Verdict | Evidence |
|---|---|---|---|
| 1 | Banister TRIMP with sex-specific constants (0.64/1.92, 0.86/1.67) | **Supported** | Banister 1991 (in *Physiological Testing of the High-Performance Athlete*, 2nd ed., pp. 403–425); Morton, Fitz-Clarke & Banister, J Appl Physiol 1990. The weightings follow the typical lactate curve. |
| 2 | Summing minute by minute instead of using the session's average HR | **Supported** | With an exponential weighting, an average HR undercounts intervals. Summing short stretches is the standard fix. |
| 3 | Banister rather than Edwards (1993, 5 zones × weights 1–5 on %HRmax) or Lucia (3 zones set by ventilatory thresholds, weights 1/2/3; Lucia et al., MSSE 2003) | **Supported** | All three agree closely (e.g. taekwondo: Edwards vs Banister r = 0.89). Lucia's zones need lab-measured VT1/VT2, which the app doesn't have. Banister is continuous, so it has no step changes at zone edges. |
| 4 | iTRIMP (Manzi et al., MSSE 2009 and Am J Physiol 2009) | **Not adopted** | It tracks performance better than generic TRIMP, but it needs each person's lab HR–lactate curve. Studies were small (n = 8). |
| 5 | Ignore minutes below 30% of reserve | **Supported** | 30–39% HRR is "light" in ACSM's Guidelines (10th ed., 2018). Banister TRIMP was built for training sessions, not 16 hours of daily living. |
| 6 | Heart-rate reserve (Karvonen) for intensity | **Supported** | %HRR tracks %VO₂ reserve (Swain & Leutholtz, MSSE 1997). ACSM sets intensity in %HRR. |
| 7 | Zones 1–5 = 50–60…90–100% of **reserve** | **App choice** | Edwards' bands are on %HRmax. Using reserve keeps the zones consistent with the TRIMP. Zones are for display only and don't feed strain. Comment added. |
| 8 | Max HR = Tanaka, 208 − 0.7 × age, for both sexes | **Supported** | Tanaka et al., JACC 2001 (351 studies, n = 18,712; no sex difference). Gellish et al., MSSE 2007 (longitudinal): 207 − 0.7 × age. Nes et al., Scand J Med Sci Sports 2013 (HUNT): 211 − 0.64 × age, SEE 10.8 bpm. They differ by ≤ 5 bpm under 60. Each is off by ~10 bpm for an individual. Comment added. |
| 9 | Learning max HR from observed peaks (best ≥ 3-minute sustained plateau; accepted only above the estimate and ≤ estimate + 15; expires after a year) | **Supported** | Measured beats predicted, given the ~10 bpm SD. Requiring a sustained plateau rejects optical artefacts. Using it only above the estimate is right, because a lower field peak usually means you didn't go all-out. Users with a truly low max must enter it by hand (Settings already allows this). |
| 10 | Resting HR = today's HealthKit resting HR (or the baseline mean) | **Open** | Karvonen assumes a stable resting value. The app rebuilds all 28 cached days whenever today's resting HR changes, and an elevated value (illness, alcohol) slightly *lowers* every %HRR. Using the 30-day baseline would be steadier. This is App-side (`DailyMetricsModel` / `UserSettings.heartRateProfile`); not changed. |
| 11 | Session-RPE × minutes for lifting | **Supported** | Foster et al., JSCR 2001: sRPE regressions for cycling and basketball nearly overlap, so the method is valid across modes. Haddad et al., Front Neurosci 2017: 36 validity studies, valid and reliable across sports. For resistance training: Day et al., JSCR 2004 (ICC 0.88; tracks intensity); Sweet et al., JSCR 2004 (tracks %1RM; may underrate the hardest sets). |
| 12 | HR undercounts lifting, so count max(HR load, sRPE load) | **Supported** | HR is a poor intensity marker for weight training, HIT and plyometrics (Foster 2001; Haddad 2017). Taking the max avoids double-counting and still credits a circuit session whose HR really is high. |
| 13 | **Converting sRPE to TRIMP: `rpeToTrimp`** | **Tweaked, 0.25 → 0.33** | sRPE is meant to put equal perceived effort on one scale. So the factor should equal the Banister TRIMP that one sRPE unit corresponds to in cardio. Using ACSM's %HRR↔RPE bands (moderate 40–59% ≈ RPE 12–13 ≈ CR-10 3; vigorous 60–89% ≈ RPE 14–17 ≈ CR-10 5–7), TRIMP per sRPE unit is ≈ 0.28 at moderate (50%), 0.34–0.40 at hard (75%) and 0.42 at very hard (87%). Foster 2001 also found sRPE scores "noticeably higher" in absolute terms than HR-zone scores. At 0.25, a lifting hour counted only ~70% of a run that felt equally hard. 0.33 is the conservative end of the "hard" range. Borresen & Lambert (IJSPP 2008) found sRPE and TRIMP correlate at r = 0.76 but diverge at intensity extremes, so this is an equivalence at typical training intensities, not an exact law. |
| 14 | Default session RPE 6.5 when unrated | **App choice** | Studies put typical resistance sessions at roughly CR-10 4–7, depending on %1RM (Day 2004; Sweet 2004). 6.5 is at the upper end. With the new factor, an unrated hour is ≈ 64%. Left alone; see open questions. |
| 15 | 0–100 mapping 100(1 − e^(−L/126)) | **App choice, sound** | No study defines a 0–100 TRIMP scale. The curve is monotone, starts linear and saturates: 1 h at 75% HRR ≈ 62%, 2 h ≈ 86%, a marathon-type day (≈ 550–600 TRIMP) ≈ 99%. Diminishing returns near the top are sensible for a daily score. Above about 500 TRIMP, days become hard to tell apart, which is acceptable for a percentage. Unchanged. |
| 16 | Target strain from recovery (FitnessAdaptation.swift, not edited) | **Partly supported** | HRV-guided training (7-day ln rMSSD vs a smallest-worthwhile-change band: Plews 2012; Javaloyes, IJSPP 2019) does at least as well as fixed plans: VO₂max ES ≈ 0.19–0.40 (Granero-Gallegos et al., IJERPH 2020); SMD ≈ 0.20 for VO₂max and performance, not significant, with fewer non-responders (Manresa-Rocamora et al., IJERPH 2021). But those protocols are essentially binary: train as planned when HRV is in the normal range, go easy when it is below. They don't set a graded load target. The app's three bands are its own summary. In particular, the **moderate** band (34–66) caps the target at your usual training day. That is more conservative than the trials, where "within normal" means "do the planned session". And "high recovery → up to U+20" has no direct trial support, though it is mild. See open questions. |
| 17 | Target scaled to your usual training strain; gradual progression | **Supported in spirit** | Large, rapid jumps in load are the plausible risk, not high load itself (Gabbett, BJSM 2016). |
| 18 | ACWR used only as a description, not as an injury predictor | **Supported** | Impellizzeri et al., IJSPP 2020 ("no evidence supporting the use of ACWR"); Impellizzeri et al., Sports Med 2021 ("Time to dismiss ACWR"). |
| 19 | **"Usual" window included the current week (coupled)** | **Tweaked: now uncoupled** | Lolli et al., BJSM 2019: with this week inside the 4-week average, the ratio is pulled toward 1 and can't pass 4, and the correlation is partly spurious. Their example: 1.45 coupled vs 1.71 uncoupled. Now "usual" = the days before this week (21 of 28), so "50% more than usual" means exactly that. Thresholds unchanged; their meaning is descriptive. |
| 20 | Rolling averages rather than EWMA | **Supported (either is defensible)** | Williams et al., BJSM 2017 proposed EWMA. Sampson et al., BJSM 2017 found no evidence that either is better, and Murray et al., BJSM 2017 found both flag spikes. Averages are easier to explain. |
| 21 | Monotony and training strain (Foster, MSSE 1998: monotony = weekly mean / SD of daily load; strain = weekly load × monotony; illness clustered above individual thresholds) | **Open** | Not implemented. Note the name clash: Foster's "training strain" is a weekly metric, while the app's "strain" is a daily load score. |
| 22 | **Apple Watch exercise minutes fill heart-rate gaps** | **Added (app choice on cautious evidence)** | Outside workouts an Apple Watch saves heart rate only about every 5 minutes (Apple's 2024 heart-rate white paper, as quoted secondhand; not re-verified), and each reading counts for at most 2 minutes, so a short walk was mostly missed (strain stayed near 0 after 12 exercise minutes). Each exercise minute that no counted reading covers, outside logged gym sessions, now adds one minute of Banister TRIMP at 40% of reserve, the bottom of ACSM's "moderate" band; Apple's exercise minute marks about brisk-walk intensity, and Abt et al. (JMIR Cardio 2018) tested it against 40% of VO₂ reserve. Validation studies find exercise minutes imprecise (roughly 20–30% error, modest correlation with research accelerometers), so the credit is a floor at the bottom of the band, never double-counted with heart rate. 12 such minutes ≈ 5% strain. |

### How commercial wearables describe this (sanity check only)

- One major watch maker's "training load" is effort rating (1–10, estimated
  from HR for cardio and entered by hand for strength) × duration, compared
  over 7 vs 28 days. That is essentially sRPE.
- Another's "cardio load" is TRIMP-based. Its 7-day load is compared with a
  28-day "tolerance", and muscle and perceived load are separate scores.
- A daily 0–100% load score with a saturating curve, sRPE for lifting, and
  7-vs-28-day comparison all fit what the industry publicly describes. No
  proprietary formulas were used.

## What changed

- `StrainCalculator.rpeToTrimp`: **0.25 → 0.33** (row 13). An hour of lifting
  at RPE 8 goes from ≈ 61% to ≈ 72%; 45 min at RPE 7 goes from ≈ 46% to ≈ 56%.
  An hour of lifting rated 6 now carries about the same load as an hour of
  cardio at 75% of reserve. `StrainPlanner.liftingLoad` uses the same factor, so
  planner estimates move with it.
- `TrainingLoadCalculator.evaluate`: "usual" now leaves out the current 7 days
  (row 19). Still needs 14 days of history (7 of usual).
- Citation comments for the TRIMP constants, the 30% floor, max-HR formulas,
  %HRR and zones. No other formula changes.

Tests: `liftingCountsEvenWithLowHeartRate` expected 57–69%, now 66–77%,
because of the intentional factor change. New tests:
`liftingAndCardioThatFeelEquallyHardCountAboutTheSame`,
`usualLeavesOutThisWeek` and `uncoupledRatioIsNotCapped`.

## Open questions

1. **Recovery bands for the target** (row 16): consider letting moderate
   recovery reach up to U (or U+5), and keeping the "go easy" range for when
   the HRV 7-day trend is *below* normal, which is the trial rule. That logic
   lives in `FitnessAdaptation.swift`.
2. **Resting HR for strain**: use the rolling baseline rather than today's
   value (row 10).
3. **Default RPE 6.5** for unrated gym sessions: 5–6 ("hard") would match
   typical study values better. Prompting for a rating is better still.
4. **Today's partial day** is in the 7-day window of the trend (the App passes
   28 days including today), so the acute average reads low early in the day.
5. Optionally add Foster's weekly monotony as a variety cue.
