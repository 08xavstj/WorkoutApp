# Daytime vitals (17 November 2026)

> **Removed 17 November 2026.** The view, its rules and its tests are gone from the app (`DaytimeVitals.swift`, `HealthKitClient+Daytime.swift`, `DaytimeVitalsView.swift` and the rest named below). The evidence audit (`evidence-audit-2026-11.md`, "Remove") found that it added a second daily set of HRV, resting heart rate and SpO₂ numbers with no decision attached: ambulatory HRV allows no clear vagal reading (Laborde 2017, below), meals, coffee, posture and heat move it as much as anything health-related, and more numbers that can't be acted on raise the risk of tracker-driven worry (orthosomnia case series, Baron 2017, as cited in the audit). This file is kept as the record of what was built and why it went.

The daytime counterpart of the overnight vitals: Health › All measures › Daytime vitals. Code: `Packages/AppCore/Sources/AppCore/DaytimeVitals.swift` (rules, with tests), `App/Services/HealthKitClient+Daytime.swift` (reads), `App/Features/Health/DaytimeVitalsView.swift` (screen).

Supersedes row 6.5 of `watch-features.md` ("Daytime Vitals view: not built"). The finding in §3.1 of that file stands: this is a vitals view, **not a stress score**.

## What the screen claims, and what it does not

- It shows heart rate at rest, HRV and blood oxygen from the minutes the wearer was awake and still, for today or yesterday, each beside the range the same value fell in over the previous 28 days **at the same hours of the day**.
- It names a day as inside, below or above that range. It gives no verdict, no score and no warning colour: outside the range is a grey chip.
- It says on the page that coffee, a meal, heat, posture and time on your feet move these numbers as much as sleep, alcohol, training, illness or tension do, and that the watch can't tell them apart.

## Evidence

| Point | Source | Checked? |
|---|---|---|
| Wearable stress algorithms built on daytime HRV have poor accuracy and reliability | Shterev 2025, systematic review (Univ. of Twente thesis); `watch-features.md` [B20] | Carried over from `watch-features.md`, not re-read |
| HRV recordings need: no meal or caffeine for 2 h, no alcohol for 24 h, no hard training the day before, 5 minutes in one posture, the same time of day each time; ambulatory HRV is possible but "clear vagal interpretation is then not feasible"; sections with movement are removed using the accelerometer | Laborde, Mosley & Thayer, Front Psychol 2017;8:213 | Read (PMC full text, first half) |
| HRV in about 8 million wrist-wearers changes through the day, highest in the early morning; the authors advise reading it at the same time each day | Natarajan et al., Lancet Digit Health 2020;2(12):e650-7 | Preprint title and press coverage only; hourly values not re-verified |
| Resting heart rate from a wrist device: lowest heart rate after at least 4 minutes of inactivity; heart rate "stabilised in most subjects after 4 minutes"; daytime lowest 54.5 bpm against 50.5 at night (3.9 bpm apart), n = 433 | Speed et al., PLOS Digit Health 2023;2(4):e0000236 | Read (PMC full text). Funded by Google |
| After an interval session HRV returned to baseline at 90 minutes or more in trained runners, about 30 in highly trained ones; exercise below the first ventilatory threshold disturbed it little | Seiler, Haugen & Kuffel, Med Sci Sports Exerc 2007;39(8):1366-73 | Abstract, via search summary |
| Full autonomic recovery: up to 24 h after easy, 24-48 h after threshold, 48 h or more after hard sessions | Stanley, Peake & Buchheit, Sports Med 2013;43:1259-77 | From memory and a search summary; not re-read |
| Cadence bands: 1-19 steps/min incidental, 20-39 sporadic, 40-59 purposeful, 100 or more moderate | Tudor-Locke et al., Br J Sports Med 2018;52:776-88 | Bands confirmed in search results; volume and pages from memory |
| Wearable HRV agrees with ECG at rest and worse as movement rises | Georgiou et al., Folia Med 2018;60(1):7-20 (systematic review, 18 devices) | Abstract, via search summary |
| Apple's `restingHeartRate` is "an estimation of the user's lowest heart rate during periods of rest", from "sedentary heart rate samples throughout the day"; the method is not published | Apple developer documentation, `HKQuantityTypeIdentifier.restingHeartRate` | Read |
| Series 12: heart rate every five seconds, HRV as often as every five minutes, a daytime view in Apple's Vitals app | Apple Newsroom, 9 Sep 2026; `watch-features.md` [C1] | Carried over, not re-read |

Nothing here has been run on a Series 12.

## Rules and constants (`DaytimeVitals`)

| Rule | Value | Basis |
|---|---|---|
| A minute is daytime rest when: awake; not in a workout; not within the margin after one; no exercise minute in it or the minutes before; under the step threshold in it and the minutes before | — | Laborde 2017 (remove movement; control activity) |
| Margin after a workout | 90 min | Seiler 2007 (trained runners). Nothing comparable found for lifting: the same margin is the app's choice |
| Margin after an exercise minute (Apple's green ring) | 10 min | App's choice; Seiler 2007 says light exercise disturbs little |
| Margin after a walking minute | 5 min | Speed 2023 (4 min), Laborde 2017 (5 min) |
| A minute counts as walking from | 20 steps | Tudor-Locke 2018, the first band above "incidental" |
| "Resting while awake" | 10th percentile of the still minutes | **App's choice.** Not Apple's method (unpublished), not Speed's (the minimum, which falls the longer the watch is worn) |
| Minutes needed for a heart-rate value | 30 | App's choice |
| HRV value | median of the still, awake readings | Median so one odd reading can't move the day |
| HRV readings needed | 12, from 3 or more clock hours | App's choice. Keeps a watch that reads every few hours on "not enough readings" |
| HRV measure | RMSSD if the day has enough, else SDNN; the usual range is always the same measure | Same preference as the overnight numbers |
| Blood-oxygen readings needed | 3 awake | App's choice |
| Usual range | 16th-84th percentile of the previous 28 days' values, at least 14 days | App's choice (the middle two thirds; mean ± 1 SD for a normal spread, as `PersonalBaseline` draws) |
| Same hours | an earlier day is reduced to the clock hours the shown day has readings in, and must cover two thirds of them | Laborde 2017 and Natarajan 2020 (same time of day); the two thirds is the app's choice |
| Chart: usual for an hour | median of the same hour on 7 or more earlier days in the same state (asleep or awake); none for a workout hour | App's choice |

## Known limits

- Sitting and standing look the same to these rules; so do the hour after a coffee or a meal and any other hour.
- A nap the watch did not record counts as awake.
- The 90-minute margin does not cover the day or two a hard session can take; the HRV card says so on a day with a workout.
- Blood oxygen is not matched by hour (too few readings).
- Daytime breathing rate is not shown. Apple Watch has recorded respiratory rate during sleep; whether a Series 12 writes daytime values was not checked.
