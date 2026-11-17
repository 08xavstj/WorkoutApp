# Sleep window (insomnia path) and catch-up sleep wording: sources checked (17 Nov 2026)

Builds items 7 and 12 of `healthy-living-2026-11.md`. That file's author wrote the titration rule, the six-hour floor and the exclusions from memory. This file records what was checked at the source before building, and what the app chose where sources differ. Code: `Packages/AppCore/Sources/AppCore/SleepWindow.swift` (rules, tests in `SleepWindowTests.swift`), `SleepRegularity.MidpointShift.note(sleepDebt:sleepWindowOn:)`, `App/Services/SleepWindowStore.swift`, `App/Features/Today/SleepWindowView.swift`.

Marks: **[F]** full text read; **[A]** abstract read (PubMed E-utilities); **[N]** not re-verified (the page could not be fetched).

## The rules, by source

| Parameter | Kyle et al., Sleep 2014 [F] | AASM, Edinger et al., JCSM 2021 [F] | HABIT (Kyle et al., BMJ Open 2020 protocol [F]; Lancet 2023 [A]) | Spielman et al., Sleep 1987 [A] | App |
|---|---|---|---|---|---|
| First window | average sleep from 1 week of diaries; notes a variant of sleep + 30 min (Edinger 2001) | "initially limited to the average sleep duration" | set with the nurse from diaries (rule in a supplementary table [N]) | "marked restriction" | average of up to 14 tracker nights **+ 30 min** (the longer, more cautious variant) |
| Floor | 5 h; "some ... as low as 4.5 h", which "may lead to impairment greater than that observed" | none given | 5 h is commonly reported [N] | not in abstract | **6 h** (app's choice: no nurse or clinician watching) |
| Widen | ≥ 90%: +15 min | "increased or decreased based on sleep efficiency thresholds" | ≥ 85%: +15 min is commonly reported [N] | when efficiency improved | **≥ 85%: +15 min** (widen sooner) |
| Narrow | < 85%: −15 min | as above | ≤ 79%: −15 min, 80-84% no change, commonly reported [N] | — | **< 80%: −15 min**, 80-84% hold (narrow later) |
| Review | weekly | — | 4 weekly sessions | 8-week programme | weekly, on the week's average, ≥ 5 nights |
| Length | "often last for 6-8 w"; theirs 4 w | — | 4 weeks | 8 weeks | ends at the regular window or after **8 weeks**; after 4 judged weeks without widening, suggests a GP or sleep clinic |

Where the sources differ, every choice is the more cautious one: more time in bed, wider sooner, narrower later, never under six hours, a "Too sleepy" button that adds 15 minutes at once and blocks narrowing that week, rest mode holds the window. Perlis's manual and the European guideline's full text (Riemann et al., J Sleep Res 2023) could not be fetched [N]; the guideline's abstract was read [A] (CBT-I first line; actigraphy not recommended for routine assessment).

## Safety

- **Sleepiness and driving.** Polysomnographic sleep fell by 91, 78 and 69 min on nights 1, 8 and 22; sleepiness was raised in weeks 1-3 and vigilance lapses increased, all back to baseline at three months. "Patients are, therefore, advised not to drive or operate heavy machinery if they feel excessively sleepy." (Kyle 2014 [F]). The warning shows with the offer, on the running page and in last night's sheet.
- **Exclusions.** HABIT protocol [F]: pregnancy or planned within 6 months; another sleep disorder (restless legs, obstructive sleep apnoea, narcolepsy); dementia or mild cognitive impairment; epilepsy, schizophrenia or bipolar disorder; suicidal ideation with intent or an attempt within 2 months; cancer treatment or planned major surgery; night, evening, early-morning or rotating shift work; already receiving psychological treatment for insomnia. AASM 2021 [F]: may be contraindicated in high-risk occupations (drivers, heavy machinery), predisposition to mania/hypomania, poorly controlled seizure disorders, excessive daytime sleepiness. The app refuses on all of them, says why and points to a GP or sleep clinic.
- **Apnoea first.** The STOP-Bang screen (score ≥ 3 positive, Chung 2016, already in the app) must be answered within the last year; an Apple Watch apnoea flag in the last 30 nights, or breathing disturbances above his usual, also refuse. A flag or a daytime-sleep pattern (3+ of 14 main sleeps centred 08:00-20:00, app's choice) stops a running course.
- **Trackers.** In 42 adults with insomnia a Fitbit and a research actigraph "overestimated total sleep time and sleep efficiency" and caught only 39-45% of time awake (Kahawage et al., J Sleep Res 2020 [A]). So the owner's answers open the path; the data only raises the question (12 poor mornings in 28 days from his own check-ins, or tracker efficiency under 85% over 20+ of 28 nights); and the efficiency number is always called an estimate. The app's nightly efficiency runs from first asleep to last awake, which reads high: the error widens the window, never narrows it.
- **No tips.** Sleep-hygiene education added nothing to remission and relaxation may hinder (Furukawa et al., JAMA Psychiatry 2024, per `healthy-living-2026-11.md` [P]). The page has only the method: a fixed wake time, the window, bed only when sleepy, out of bed after what feels like about 20 minutes awake (AASM gives no number [F]; "about 20 minutes" is the usual handout wording [N]).
- **Words.** Never "treatment", "therapy" or "diagnosis" in the copy (tested). "This is a routine to try, not medical care."

## Consistency while it runs

Sleep debt is paused: last night's sheet shows the window instead of the debt plan and bed-by rows; Up next's bedtime row is "Bed from 23:45, up at 6:30" every day; the morning message drops the debt and short-night caffeine tips; the evening message says "Bed from …, when sleepy"; the post-workout note names the window, not "a full night's sleep"; the coach's sleep and recovery answers and its on-device facts keep to the window; the Insights feed drops "You're sleeping less"; the Monday review drops "In bed 30 minutes earlier"; the cut-and-sleep note keeps the slower rate but no longer points to the debt plan; the weekend-shift note says the fixed wake time wins.

## Catch-up sleep (item 12)

The National Sleep Foundation panel agreed that, "when insufficient sleep is obtained during the week/work days, weekend/non-work day catch-up sleep may be beneficial" (Sletten et al., Sleep Health 2023 [A], consensus, not a trial). With moderate or high sleep debt, a later weekend now reads "the weekend lie-in was probably worth it … Next time an earlier night repays it", which matches the debt plan ("go to bed earlier rather than sleeping in"). Otherwise the note is unchanged; with the sleep window on, the fixed wake time wins.

## References

- Edinger JD, et al. Behavioral and psychological treatments for chronic insomnia disorder in adults: an AASM clinical practice guideline. J Clin Sleep Med 2021;17(2):255-262. [F]
- Kahawage P, et al. Validity, potential clinical utility, and comparison of consumer and research-grade activity trackers in Insomnia Disorder I: in-lab validation against polysomnography. J Sleep Res 2020;29(1):e12931. [A]
- Kyle SD, et al. Sleep restriction therapy for insomnia is associated with reduced objective total sleep time, increased daytime somnolence, and objectively impaired vigilance. Sleep 2014;37(2):229-237. [F]
- Kyle SD, et al. Protocol for the HABIT trial. BMJ Open 2020;10(3):e036248. [F, main text; supplementary intervention table N]
- Kyle SD, et al. Clinical and cost-effectiveness of nurse-delivered sleep restriction therapy for insomnia in primary care (HABIT). Lancet 2023;402(10406):975-987. [A]
- Riemann D, et al. The European Insomnia Guideline: an update on the diagnosis and treatment of insomnia 2023. J Sleep Res 2023;32(6):e14035. [A]
- Sletten TL, et al. The importance of sleep regularity: a consensus statement of the National Sleep Foundation. Sleep Health 2023;9(6):801-820. [A, per healthy-living-2026-11.md]
- Spielman AJ, Saskin P, Thorpy MJ. Treatment of chronic insomnia by restriction of time in bed. Sleep 1987;10(1):45-56. [A]
- Not re-verified: Perlis ML, et al. Cognitive Behavioral Treatment of Insomnia: A Session-by-Session Guide (2005); Edinger JD, et al. JAMA 2001;285:1856-1864.
