# Longevity page and Insights feed: evidence and rules (17 Nov 2026)

Apple's Health app gained a Longevity tab and an Insights tab in iOS 27.3. Apps get no API for either, so Tensile builds its own from data it already holds. This note records what went in, on what evidence, and what was left out. Code: `Packages/AppCore/Sources/AppCore/Longevity.swift`, `DailyInsights.swift`; `App/Features/Health/LongevityView.swift`, `InsightsFeedView.swift`; `App/Services/LongevityAssembler.swift`.

## Point of view

1. **No score.** A 2025 review of 14 composite health scores found them untransparent and unvalidated (Doherty 2025, cited in `cleanup-2026-11.md`), and the app already carries one hedged composite (`BodyAge`). The Longevity page is a list of single measures, each against its own published target. The only summary is a count ("7 on target · 4 close · 1 off target").
2. **"Linked with", not "adds years".** Nearly all of this evidence is observational. Blood pressure (trials of lowering it) and protein (trials of muscle gain) are the exceptions. Each measure carries a grade and a sentence on what kind of study stands behind it.
3. **Insights are week-scale and personal.** Today, Up next and the daily messages already cover today's recovery, strain range, bedtime and plan. The feed only says what changed over the last 7 days against the 28 before, or where a published line was crossed.

## Evidence grades

Same scale as `health-metrics.md`: **strong** = meta-analyses of trials, large pooled cohorts with consistent dose-response, or guideline consensus; **moderate** = one large cohort, or a guideline resting on weaker evidence; **limited** = weak, mixed or no published target.

## Longevity: areas, measures, targets

| Area | Measure | On target | Close | Off | Grade | Main sources |
|---|---|---|---|---|---|---|
| Heart and fitness | VO₂ max | ≥ 50th percentile for age and sex (≥ 75th with a stamina goal) | 25th to target | < 25th | Strong, observational | Laukkanen 2022; Mandsager 2018; Kokkinos 2022; FRIEND norms (Kaminsky 2015) |
| | Resting heart rate (14-day average) | < 60 bpm | 60-80 | > 80 | Moderate, observational | Zhang 2016 |
| Movement | Daily steps (30-day average of full days) | ≥ 8,000 (≥ 7,000 from age 60) | 5,000 to target | < 5,000 | Strong, observational | Ding 2025; Paluch 2022 |
| | Active minutes a week (moderate + 2 × vigorous) | ≥ 150 (≥ 300 with a stamina goal) | ≥ half the target | below half | Strong, observational | WHO 2020 (Bull); Lee 2022 |
| Strength | Strength days a week (4-week average) | ≥ 2 | 1 to 2 | < 1 | Strong, observational | Momma 2022; WHO 2020 |
| | Grip strength (if entered) | average or above for age and sex | below the age band | under the EWGSOP2 line | Moderate | Leong 2015; Bohannon 2006; EWGSOP2 |
| Sleep | Sleep length (14-night average) | 7-9 h (7-8 h from 65) | 6-10 h (5-9 h from 65) | outside that | Strong (consensus) | Watson 2015; Hirshkowitz 2015 |
| | Sleep Regularity Index | ≥ 81 | 74-80 | < 74 | Moderate, one cohort | Windred 2024 |
| Body and blood pressure | Waist-to-height | 0.4-0.5 | < 0.4 or 0.5-0.6 | > 0.6 | Strong (screening) | Ashwell 2012; Browning 2010 |
| | Blood pressure (7-day home average) | < 120/80 | 120-129 and < 80 | ≥ 130/80 | Strong, trials | Ettehad 2016; AHA/ACC 2025 |
| Nutrition | Fibre (7-day average) | ≥ 25 g | 20-25 g | < 20 g | Strong | Reynolds 2019 |
| | Protein (7-day average) | ≥ 90% of the goal's target | 70-90% | < 70% | Moderate for longevity (strong for muscle) | Morton 2018 |
| Alcohol | Standard drinks a week | 0-2 | 3-6 | 7+ | Moderate; the line itself is uncertain | CCSA 2023; GBD 2020 |
| Hearing | Headphone sound, % of the weekly limit | < 80% | 80-99% | ≥ 100% | Moderate (guideline) | WHO-ITU H.870; Livingston 2024 |
| Mood | 14-day check-in average | no target: tracked, never judged | | | Limited | Noetel 2024 (next step only) |

### Where a line is the app's reading, not a published threshold

- **VO₂ max bands** are Mandsager's own groups (low < 25th, below average 25-49th, above average 50-74th, high 75-97.6th, elite above). Aiming a stamina goal at the "high" band is the app's choice; the percentiles come from FRIEND treadmill norms, not from Mandsager's cohort.
- **Resting heart rate**: Zhang reports 60-80 and > 80 bpm against "the lowest category", measured seated in clinics. A watch reads a few beats lower overnight, so the bands flatter a watch value a little. Stated in the app.
- **Steps**: "on target" reuses the app's starting goal (`StepGoal.standard`); 5,000 is the bottom of the bend Ding reports (about 5,000-7,000).
- **Active minutes**: "close" from half the target is the app's choice.
- **Sleep Regularity Index**: Windred gives the median (81.0), the interquartile range (73.8-86.3) and "top four fifths against the least regular fifth". The abstract gives no fifth cut-offs, so 74 (the lowest quarter) stands in for the least regular fifth. The app's index comes from watch sleep over a week, not accelerometry.
- **Sleep length**: the "may be appropriate" edges (6-10 h; 5-9 h from 65) are from the National Sleep Foundation paper's body and were **not re-verified** this round; the recommended ranges were.
- **Protein, alcohol (nights logged), headphones (80%)**: the shares and minimum-data rules are app choices, labelled as such in code.
- **Mood**: no study sets a target for a daily mood rating. A low two-week average only changes the next step ("if it stays low for two weeks or more, talking to a doctor is worth it"); the two-week window echoes the PHQ-2 and is not a screen.

### Goal tailoring

- Stamina goal: VO₂ max target moves to the top quarter and active minutes to 300 a week (no upper limit of benefit in Mandsager and Kokkinos; a little more benefit at 2-4 times the minimum in Lee 2022).
- Muscle or strength goal: on-target strength days say the health benefit levelled off around 30-60 minutes a week (Momma 2022), so extra sessions serve the training goal.
- Protein target is the goal's own (`DailyMetricsModel.proteinTarget`).
- Losing weight: the fibre next step notes it helps hold a deficit. Gaining: the waist next step asks for a monthly re-measure, and fibre notes the appetite cap.
- Age: steps (60+), sleep (65+), VO₂ max and grip norms. Sex: VO₂ max and grip norms.

### Left out, and why

- **Lab markers (ApoB, LDL, HbA1c, Lp(a))**: among the best-evidenced, but the right target depends on a person's overall risk, which is a clinician's call. They stay under Records › Lab results.
- **Lift-to-bodyweight ratios** (`StrengthForHealth`): the bands are an app choice from crowd-sourced tables. Not presented as longevity science.
- **HRV**: no accepted population target; it is read against the person's own baseline (and appears in the feed that way).
- **Body age / Health Age**: already on its own page; not duplicated.
- **Daylight, mindful minutes, sauna, cold exposure**: weak or single-cohort evidence (`health-metrics.md`).

## Insights feed: rules

A rule produces at most one line. All compare the last 7 days with the 28 before, unless noted. "Enter" turns a line on; it stays until the value passes "exit" (hysteresis).

| Rule | Area | Enter | Exit | Minimum data |
|---|---|---|---|---|
| Resting heart rate | Heart | weekly mean ≥ 1 SD and ≥ 2 bpm from the 4-week mean | < 0.5 SD or < 1 bpm | 4 of 7 days, 14 of 28 |
| HRV | Recovery | ≥ 1 SD and ≥ 5% | < 0.5 SD or < 2.5% | same |
| Sleep length | Sleep | ≥ 30 min a night | < 15 min | same |
| Sleep regularity | Sleep | index < 74, or ≥ 87 | ≥ 78, or < 83 | an index |
| Steps | Fitness | ≥ 20% and ≥ 1,000 a day (full days) | < 10% or < 500 | same as above |
| VO₂ max | Fitness | ≥ 1.5 ml/kg/min against about two months ago | < 0.75 | 2 readings in each window |
| Active minutes | Fitness | reaches 150 after a week under it; or < 75 | < 120; or ≥ 100 | 5 of 7 days plus the week before |
| Strength | Fitness | 4 weeks each with 2+ days; or 10 days without after 3+ sessions in the month before | 3 of 4 weeks and a session this week; or under 8 days | logged sessions |
| Overnight vitals | Vitals | breathing rate ≥ 1 SD and ≥ 0.8/min up; or both breathing rate and blood oxygen close to usual | half of that | 4 of 7 nights, 14 of 28 |
| Protein | Nutrition | ≥ 100% of target, or < 80% | < 90%, or ≥ 88% | 4 logged days, a target |
| Fibre | Nutrition | < 20 g, or ≥ 25 g | ≥ 22 g, or < 23 g | a 7-day average |
| Alcohol | Habits | 3+ standard drinks more or fewer than the usual week | < 1.5 | 4 of 7 evenings, 10 of 28 |
| Mood | Habits | weekly average moves 0.25 (on -1...1) | < 0.125 | 4 of 7, 8 of 28 |
| Headphones | Habits | ≥ 100% of the weekly limit | < 85% | a value |
| Personal pattern | Habits | the top check-in pattern exists | it changes | from `CheckInInsights` |

Then:

- **Cooldown.** A line shows at most 3 days running, then rests 7 days from its last showing. Standing good news ("protein is on target", "4 weeks with 2+ strength days", the personal pattern) shows 2 days and rests 21; "vitals in your usual range" shows 1 day and rests 10; VO₂ max rests 14.
- **Cap.** At most 4 lines, 2 per area, 2 amber. One per area is picked first so the list is varied.
- **No contradiction.** One line per subject. If resting heart rate and HRV point opposite ways, only the larger is shown. "A steady week" shows only when nothing else does and never names a measure with an active change.
- **Never empty without a reason.** No data: "Needs about three weeks of watch data…". Lines resting: "Nothing new today…".
- **Same day, same feed.** Lines already shown today are kept on a refresh.
- **For you.** One or two suggestions from the Longevity page: the off-target measure with the strongest evidence, then one of the others, changing weekly. Measures already in today's list are skipped. With nothing off target it offers a missing strong-evidence measure (waist, blood pressure, VO₂ max).

Basis for the trigger sizes: a 7-day average against the person's own normal variation is the established way to read noisy daily wearable values (Plews 2013, for HRV; already used by the recovery score). One day-to-day standard deviation for a weekly mean is about 2.6 standard errors. **These sizes are statistical choices by the app, not clinical thresholds, and no trial tested them**, nor the cooldown lengths or the cap. Repeated prompts lose effect within weeks (Klasnja 2019), which is the reason for cooldowns.

No line makes a medical claim; a test checks the copy for "diagnos", "disease", "you have" and similar.

## Citations

Checked this round against the PubMed record (title, authors, journal, year, and the numbers quoted in the app):

- Laukkanen JA, Isiozor NM, Kunutsor SK. Mayo Clin Proc 2022;97(6):1054-73. 37 cohorts, 2,258,029 people; RR 0.89 per 1-MET; top vs bottom third 0.55.
- Mandsager K, et al. JAMA Netw Open 2018;1(6):e183605. 122,007 patients; low vs elite HR 5.04; below vs above average 1.41; elite vs high 0.77; percentile groups as above.
- Kokkinos P, et al. J Am Coll Cardiol 2022;80(6):598-609. 750,302 veterans; lowest risk near 14 METs; least fit HR 4.09.
- Kaminsky LA, Arena R, Myers J. Mayo Clin Proc 2015;90(11):1515-23 (FRIEND).
- Zhang D, Shen X, Qi X. CMAJ 2016;188(3):E53-63. 46 studies, 1,246,203 people; RR 1.09 per 10 bpm; 60-80 bpm 1.12; > 80 bpm 1.45.
- Reimers AK, Knapp G, Reimers CD. J Clin Med 2018;7(12):503.
- Ding D, et al. Lancet Public Health 2025;10(8):e668-81. 7,000 vs 2,000 steps: HR 0.53; inflection about 5,000-7,000.
- Paluch AE, et al. Lancet Public Health 2022;7(3):e219-28. 15 cohorts, 47,471 adults; plateau 8,000-10,000 under 60, 6,000-8,000 from 60.
- Bull FC, et al. Br J Sports Med 2020;54(24):1451-62 (WHO guideline).
- Lee DH, et al. Circulation 2022;146(7):523-34. 116,221 adults, 30 years; 19-25% lower mortality at the guideline.
- Momma H, et al. Br J Sports Med 2022;56(13):755-63. 16 studies; 10-17% lower risk; maximum at about 30-60 min a week.
- Leong DP, et al. Lancet 2015;386(9990):266-73. 139,691 people, 17 countries; HR 1.16 per 5 kg lower grip; stronger predictor than systolic pressure.
- Watson NF, et al. Sleep 2015;38(6):843-4 (7 or more hours; wording confirmed on the AASM page).
- Hirshkowitz M, et al. Sleep Health 2015;1(1):40-3 (recommended ranges only).
- Windred DP, et al. Sleep 2024;47(1):zsad253. 60,977 adults; median SRI 81.0 (IQR 73.8-86.3); 20-48% lower all-cause mortality in the top four fifths.
- Ashwell M, Gunn P, Gibson S. Obes Rev 2012;13(3):275-86. 31 papers.
- Browning LM, Hsieh SD, Ashwell M. Nutr Res Rev 2010;23(2):247-69. 78 studies; mean boundary 0.50.
- Ettehad D, et al. Lancet 2016;387(10022):957-67. 123 trials, 613,815 people; per 10 mmHg: major events RR 0.80, mortality 0.87.
- Reynolds A, et al. Lancet 2019;393(10170):434-45. 185 prospective studies, 58 trials; 15-30% lower; greatest at 25-29 g.
- Morton RW, et al. Br J Sports Med 2018;52(6):376-84. 49 trials, 1,863 people; plateau at 1.62 g/kg.
- GBD 2020 Alcohol Collaborators. Lancet 2022;400(10347):185-235.
- Canadian Centre on Substance Use and Addiction. Canada's Guidance on Alcohol and Health, 2023 (the CCSA's own page: 2 or fewer a week, 3-6, 7 or more).
- Noetel M, et al. BMJ 2024;384:e075847. 218 trials, 14,170 people.
- Wen D, et al. J Sci Med Sport 2019;22(8):941-7. 53 trials.

Checked via secondary summaries only (shown in the app as "not re-verified" where they are a measure's source):

- Jones DW, et al. 2025 AHA/ACC high blood pressure guideline. Hypertension 2025;82:e212. Categories unchanged from 2017 according to several summaries.
- WHO-ITU H.870 (2018, revised 2022): 80 dB for 40 hours a week for adults, from a trade summary.
- Livingston G, et al. Lancet 2024;404(10452):572-628. The record was checked; that hearing loss is one of the 14 factors and among the largest comes from summaries of the report.

Not re-verified this round (carried from `health-metrics.md` or the existing code): Bohannon 2006; EWGSOP2 (Cruz-Jentoft 2019); Kroenke 2003 (PHQ-2); Plews 2013; Klasnja 2019; the National Sleep Foundation "may be appropriate" ranges.

## What could not be built from the data

Apple's tabs also cover hearing tests, metabolic labs and mental-health questionnaires. Tensile has headphone exposure but no audiogram, labs but no risk model to set their targets, and a mood rating but no validated questionnaire. Each is listed above as left out or as "tracked, not judged" instead of being approximated.
