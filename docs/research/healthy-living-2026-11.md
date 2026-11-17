# Healthy living: what other apps and the literature say Tensile should add (17 Nov 2026)

Question from the owner: "do more research on other apps and literature for health, working out, etc. on what features should be added to the app to encourage healthier living."

This follows `behaviour-change.md`, `competitors.md`, `competitors-2026-11.md`, `cleanup-2026-11.md`, `health-metrics.md`, `watch-features.md`, `roadmap.md` and `qa-2026-11-17.md`. It does not repeat what those ruled out, and it leaves out what is being built now by others: the daytime vitals view, the screen for Apple's Readiness, Sleep score and Health Age, the Longevity page, the Insights feed, heart-rate zone options and the Watch cardio mode, and the playful workout notifications.

**What exists already (checked in the code, not only the docs).** Most of `behaviour-change.md` has been built: a weekly plan with if-then lines and 15-minute short versions (`WeeklyPlan`, `PlannedDay`), a forgiving four-week consistency score with no chain to break (`Consistency`), a "Welcome back" lighter week after 7+ days off (`RestartPlan`, `ThisWeekCard`), the Monday review with three changes (`WeeklyReviewView`), one morning and one evening message with back-off when ignored (`CoachCheckIns`), a bed-by window (`BedtimeWindow`), sleep regularity and weekend shift (`SleepRegularity`), movement breaks and the post-meal walk (`MovementBreaks`), a weekly drinks total against Canada's tiers plus the owner's own next-morning effect (`AlcoholWeek`, `AlcoholEffect`), weigh-in nudge, rate limits and an energy-availability floor (`WeighInNudge`, `GoalPlanner.RateLimit`, `CalorieSafety`), Hide calories, mood with Apple Health State of Mind (`Mood`), strength days, intensity minutes and an adaptive step goal as stats (`StrengthDays`, `IntensityMinutes`, `StepGoal`). So the list below is short on purpose.

**How this was researched, and what the marks mean.**

- **[P]** The PubMed record (citation and abstract) was fetched and read this round through NCBI's E-utilities. Numbers quoted come from the abstract. Full texts were not read.
- **[W]** A vendor or press web page was fetched and read this round.
- **[S]** Seen only in a search-result summary this round (the page was not fetched, or the fetch failed).
- **[D]** Carried from an earlier Tensile research file with that file's own check; not re-checked now.
- **[M]** From memory; not checked.

[P] and [W] count as verified at the source. [S], [D] and [M] do not. Vendor claims are labelled as such; almost no app publishes controlled evidence that a feature changes health.

---

## Summary

1. **There is not much left to add.** Tensile already uses the techniques with the best evidence in digital interventions: self-monitoring with almost no logging, goals, feedback, planning with if-then lines, weekly review, prompts that back off. Apps and trackers built on those add roughly 1,300 to 1,900 steps a day and about 1 to 2 kg of weight loss on average (Ferguson 2022; Laranjo 2021; Singh 2024), and the effect shrinks over time (Mönninghoff 2021). No further feature is likely to add as much again.
2. **The gaps are outside the lifting.** The weekly review talks about training, sleep debt, HRV, protein and weight. It does not check the plain health floors the evidence supports best: weekly moderate and vigorous minutes, steps, sleep regularity and drinks. All five numbers are already computed elsewhere in the app.
3. **The other gap is what happens when life gets in the way, before it happens.** The app handles a lapse after the fact (missed sessions move, a lighter week after seven days off). It has no way to plan a low-dose week in advance. The evidence that a third of the usual sets, or one hard set per lift, holds strength and muscle for months is decent (Bickel 2011; Spiering 2021), and every leading training app added a "life happened" control in the last two years (Runna, Apple's pausable rings, Peloton).
4. **Cardio fitness is the largest health lever a lifter usually leaves unused.** The planner only schedules easy cardio. One hard interval session a week is the best-supported way to raise VO₂ max (Milanović 2015; Wen 2019), and 15 to 20 vigorous minutes a week is linked to 16 to 40% lower mortality in device data (Ahmadi 2022).
5. **Several things should stay unbuilt or be dropped.** Breathing and relaxation (the component analysis of insomnia therapy found relaxation possibly counterproductive, and breathing apps had a median 0% of users left at day 30), sleep-hygiene tips, a post-workout "how did it feel" rating (the review behind that idea found no link for post-exercise affect), streaks and badges, social feeds, and a cloud coach.
6. **Conditional features cost nothing on a normal day.** An insomnia path, a weekly drink limit and a low-mood rule should exist only when the data or the owner's answers call for them. That fits the owner's dislike of nagging: nothing is shown until it applies.

---

## 1. What the apps do, and what is noise

Late 2026. "Helps" means there is independent evidence for the mechanism, not for the app. Where the only support is the vendor's own numbers, the table says so.

| App | What it does that plausibly keeps people active or healthy | Evidence that it works | Noise |
|---|---|---|---|
| **Apple** (Health, Fitness, watchOS 27) | Rings can be paused for a day up to 90 days without ending the streak, and goals can differ by weekday (watchOS 11) [W]. Workout Buddy; GymKit on iPhone with AirPods; iOS 27.3 Health redesign [S]. | None published for rings or pausing. The pause exists because users asked for rest and sick days for years. | Awards, monthly challenges, sharing competitions (gamification: small, fading effect). |
| **Oura** | Health Radar runs in the background and shows only patterns that merit attention; live workouts; lab uploads (June 2026) [W]. Advisor plans: one plan at a time, seven days at most, habits ticked yes or no on the Today tab [S]. | Vendor only. The one-plan, seven-day limit matches what goal-setting research supports (few, specific, reviewed goals). | Blood Pressure Signals (cuffless), GLP-1 timeline, Cumulative Stress. |
| **Garmin** (Connect, Connect+) | Daily suggested workouts, sleep coach, Health Status flags; nutrition logging added to Connect+ (Jan 2026) [S]. | Independent reviewer after a year: "still not worth paying for"; Active Intelligence "continues to restate thin insights" [W]. | AI summaries, paid reports. |
| **Google Health** (was Fitbit) | Gemini coach left preview on 19 May 2026; weekly plans that adjust; a Quick Access widget of up to six metrics that a reviewer called the cleanest feature in the release [W]. | None. A hands-on review reported the coach congratulating a tester on a sleep score of 99 when it was 85 [W]. | The coach chat as shipped; removed community features caused backlash [S]. |
| **Samsung Health** | Bedtime Guidance from the last three nights; Running Coach; Antioxidant Index (2025) [S]. | Vendor only. | Antioxidant Index, Energy Score. |
| **Polar, Coros** | Coros: heart-rate recovery, hybrid fitness mode, voice control, an MCP link to AI assistants (2026) [S]. Nothing new found for Polar. | None. | Not relevant to a lifter. |
| **Whoop** | Custom journal behaviours and a merge of four daily surfaces into one were announced for autumn; activity targets recommended from goals, and a social feature, "Humans", launched 12 Nov 2026 [W]. | The Humans press release gives no evidence that sharing changes behaviour; its figures describe daily wearers, not the feature [W]. | Social feed, age and pace-of-ageing numbers. |
| **Bevel** | Version 3 (May 2026): rebuilt Intelligence, Biological Age, health records; calendar sync of sessions (Nov) [S]. | None. | Biological age. |
| **Strava** | Instant Workouts (Jan 2026): suggestions sorted as Maintain, Build, Explore or Recover, each with its reason; strength log and muscle map; Lock Screen widgets [W]. | Vendor: "85% positive" feedback in the trial [W]. Social comparison helped in one RCT (Zhang 2016 [D]). | Feed, kudos, segments for a solo lifter. |
| **Runna** | "Not Feeling 100%": dial the plan back for 3 to 14 days at one of four levels, then choose how fast to return (slowly, balanced, quickly); Adapt for Heat (Jul 2026) [W]. | None published. The design matches the relapse literature: a planned, bounded reduction with a way back. | — |
| **Peloton IQ** | Weekly plan from goal, days and session length that "flexes with your needs"; weekly insights; rep counting and suggested weights on camera hardware [W]. | None: the vendor page has no outcome data [W]. | Form feedback claims, Teams. |
| **Zwift** | Week Streaks (weekly, not daily; running counts since Feb 2026), weekly goals in a unit you choose, a weekly planner, personalised recommendations [W][S]. | None published. Weekly streaks are the forgiving kind. | XP, levels, unlocks. |
| **Hevy, Strong, Fitbod, Ladder** | Covered in `competitors-2026-11.md`. Since then: Hevy sends workouts to cloud chatbots (Sep 2026) [S]; Ladder added nutrition logging [S]; nothing new found for Strong or Fitbod. | None. | Nutrition logging bolted onto lifting apps. |
| **Gentler Streak** | Rest-aware activity path; Home Screen widgets (v5.2) [W]; VO₂ max in Wellbeing (Mar 2026), a morning check-in notification, Siri questions (2026) [S]. | None published. | — |
| **MacroFactor** | Expenditure worked out from intake and weight trend; Weight Trend v2 (beta) smooths and revises past weigh-ins; label scanning; Workouts app (2026) [W]. | The mechanism (self-weighing plus feedback) has trial support (Wing 2006; Madigan 2015). | — |
| **Cronometer** | 92 nutrients; photo logging beta; guardrails on weight-goal setup (v4.53.1) [S]. | None. | — |
| **Noom** | Microhabits, a Maintenance Mode, a free GLP-1 companion (Jun 2026) [W][S]. | Vendor observational data only: more engaged members lose more. That is correlation; no control group [S]. | Lessons, "Seeds" rewards. |
| **Zoe** | App usable without the test kit; barcode "processed food risk" score; meal photo scores; daily streaks [S]. | Vendor. | Streaks, scores per meal. |
| **Sleep Cycle, Rise** | Sleep Cycle's new score (Mar 2026) weights Routine (regular timing) first, ahead of Duration and Quality [W]. Rise: sleep debt and suggested sleep times [S]. | Regularity predicts mortality better than duration in cohort data (Windred 2024). No trial shows that a regularity score changes it. | Smart alarms, sleep sounds, AI coach "Luma". |
| **Headspace, Finch, Streaks, Fabulous** | Headspace: Ebb, an AI companion with voice [S]. Finch: a virtual pet raised by small self-care tasks [S]. Streaks: tasks completed automatically from Apple Health [S]. Fabulous: routine "journeys" [S]. | Mental-health apps: small effects (g about 0.27), larger with CBT content (Linardon 2024). Real-world retention is very low: a median 3.3% of users at day 30, and 0% for breathing-exercise apps (Baumel 2019). | Companions, pets, journeys. |

**Patterns across the apps**

1. **Everyone added an AI coach; nobody published an outcome.** The one technical paper (Google's PH-LLM, Nature Medicine 2025) benchmarks answers against experts, not behaviour [P]. A three-week study found only a friendly, information-giving agent raised engagement, and a reflective one did not (Kumar 2025, n = 54) [P]. Tensile's rule-first, on-device coach is the defensible position.
2. **Streaks went weekly and pausable.** Apple added pausing and per-day goals; Zwift counts weeks. Tensile's consistency score already sits where the industry is heading.
3. **"Life happened" controls are the real 2025 to 2026 addition.** Runna's is the most complete: bounded, graded, with a return ramp. Tensile lacks a planned version (item 2 below).
4. **Sleep apps now put regular timing first.** Tensile already does.
5. **The surface users praise is the widget, not the chat.** Google's best-reviewed change was a widget; Gentler Streak, Strava and Zwift all added one.
6. **Labs, health records, biological age and social feeds spread everywhere.** None has evidence of changing behaviour, and Apple gives most of it away in iOS 27.3.
7. **Typical retention for health apps is single digits at day 30** (vendor benchmark blogs, 3 to 12% depending on source [S]); the reasons people give for stopping are data-entry burden and loss of interest (Krebs & Duncan 2015) [P].

---

## 2. What the literature says

Effect sizes: SMD, d and g are standardised differences (0.2 small, 0.5 medium). HR and RR are hazard and risk ratios from cohort studies, which show association, not proof of cause.

### 2a. Behaviour change in apps

| Topic | Finding | What it means for Tensile |
|---|---|---|
| Trackers and apps overall | Umbrella review of 39 reviews, 163,992 people: SMD 0.3 to 0.6 for activity, about 1,800 extra steps and 40 minutes more walking a day, about 1 kg (Ferguson 2022) [P]. 28 trials: SMD 0.35, 1,850 steps a day; text messages and personalisation helped (Laranjo 2021) [P]. Meta-meta-analysis: +1,329 steps a day, +55 min a week of moderate-to-vigorous activity, −1.9 kg, +0.57 servings of fruit and vegetables, insomnia severity SMD −0.90 (Singh 2024) [P]. | The base effect is real and already captured. |
| Does it last | 117 trials: effects persist but shrink; long-term SMD 0.25 for walking and 0.19 for moderate-to-vigorous activity; 80% of studies at high risk of bias (Mönninghoff 2021) [P]. Weight loss from apps: −2.2 kg at 3 months, −1.6 kg at 12 (Chew 2022) [P]. | Plan for maintenance, not for more features. |
| Which techniques | Self-monitoring plus one other self-regulation technique: 0.42 against 0.26 (Michie 2009) [P]. Apps with neither behavioural goals nor self-monitoring: g = 0.01; with either, +0.31; with both, no more than either (Eckerstorfer 2018) [P]. Monitoring progress: d = 0.40, more when recorded or reported to someone (Harkin 2016) [P]. | Goals and review are in place. Adding techniques on top has diminishing returns. |
| Implementation intentions | d = 0.65 overall, 0.31 for physical activity [D]. Writing down a date and a time raised flu-shot uptake by 4.2 points; a date alone, 1.5 (Milkman 2011) [P]. | Time, not only day, is the active part. Supports a calendar entry. |
| Gamification | Against the same app without game elements: +489 steps a day (the authors call it trivial), −0.7 kg, −1.9% body fat; 36 trials, n = 10,079 (Nishi 2024) [P]. g = 0.23 against active controls, 0.15 at follow-up (Mazeas 2022) [P]. Competition between people added 920 steps a day and was the only arm with an effect after it stopped (Patel 2019, n = 602) [P]. | Small. The part that works needs other people. Still not worth building. |
| Megastudy of 54 gym programmes | 61,293 gym members: 45% of four-week programmes raised weekly visits by 9 to 27%; the best one gave small rewards for coming back after a missed workout; only 8% had a measurable effect after the four weeks (Milkman 2021) [P]. | The moment after a miss is the one to design for. Expect little to last. |
| Habit formation | Review of 20 studies: median 59 to 66 days, means 106 to 154, range 4 to 335; morning and self-chosen habits form more strongly (Singh 2024b) [P]. Gym data, 12 million visits: a gym habit takes months, and predictable gym-goers respond less to interventions (Buyalskaya 2023) [P]. | An established lifter is the user least moved by prompts. Do not expect reminders to do much for the training itself. |
| Prompts and just-in-time interventions | Walking suggestions: +107% steps in the next 30 minutes at first, +24% on average; anti-sedentary prompts had no detectable effect (Klasnja 2019) [P]. A push made opening an app 3.9% more likely within 24 hours (Bidargaddi 2018) [P]. Review of 14 just-in-time systems: mixed, none powered to detect an effect (Hardeman 2019) [P]. A meta-analysis reporting g = 0.89 pooled 33 small, very different studies (Wang & Miller 2020) [P]. | No case for more or cleverer notifications. The one sedentary nudge a day is already generous. |
| Nudging in general | d = 0.45 across domains (Mertens 2022) [P]; a re-analysis found no evidence of an effect once publication bias is corrected (Maier 2022; title and journal confirmed, abstract not available) [P]. | Do not rely on defaults and framing tricks. |
| Chatbots | 19 trials, most low quality: SMD 0.28 for steps, 0.59 for fruit and vegetables, 0.44 for sleep duration (Singh 2023) [P]. No outcome trial of a large-language-model coach was found. | The coach stays a way to deliver planning and review, not a feature in itself. |
| Why people stop | 45.7% of app users had stopped using one: data entry, lost interest, hidden costs (Krebs & Duncan 2015) [P]. Pooled dropout in app trials 43% (Meyerowitz-Katz 2020) [P]. What goes with staying: personalised content, individualised reminders, a stable and simple design, personal support (Jakob 2022, 99 studies) [P]. | Burden and boredom are the two risks. Both argue for fewer inputs and some variety. |
| Self-compassion and lapses | Self-compassion correlates with health behaviours, r = 0.25 (Sirois 2015) [P]. Self-efficacy is the only consistent predictor of lapse and relapse (Roordink 2023) [P]. | Keep "what to do next", never "what was missed". Already the rule. |
| Affect | Feeling better during moderate exercise predicts later activity; how people feel after it had no relationship (Rhodes & Kates 2015, 24 studies) [P]. Music improves affect during exercise, g = 0.48 (Terry 2020) [P]. | Drop the planned post-workout rating (see section 4). |
| Variety | 121 inactive students: a high-variety programme was adhered to better over six weeks (Sylvester 2016) [P]. 21 trained men, eight weeks: varying exercises gave the same strength and size gains and better intrinsic motivation (Baz-Valle 2019) [P]. Review of 8 studies: systematic variation is fine, frequent random rotation may hinder gains (Kassiano 2022) [P]. | A little chosen variety at block boundaries; never random rotation. |

### 2b. Health targets

| Topic | Finding | What it means for Tensile |
|---|---|---|
| Steps | 7,000 a day against 2,000: all-cause mortality HR 0.53, cardiovascular disease 0.75, dementia 0.62, depressive symptoms 0.78; the curve bends at 5,000 to 7,000 (Ding 2025) [P]. Reaching 8,000 on one or two days a week went with almost the same benefit as on most days (Inoue 2023) [P]. | Judge steps as a weekly average, not a daily tick. |
| Moderate and vigorous minutes | 150 minutes a week: all-cause mortality RR 0.69; smaller gains up to twice that and little beyond (Garcia 2023) [P]. 15 to 20 vigorous minutes a week: 16 to 40% lower mortality HR; lowest risk at about 54 (Ahmadi 2022) [P]. In device data one vigorous minute matched about 4 moderate minutes for all-cause mortality and 8 to 9 for cardiovascular death and diabetes (Biswas 2025) [P]. | The app's "vigorous counts double" is conservative. Vigorous minutes deserve their own line. |
| Short vigorous bursts | Three one-to-two-minute bursts a day in people who do not exercise: 38 to 40% lower mortality (Stamatakis 2022) [P]. "Exercise snacks" improved fitness in inactive adults (g = 1.37, 6 trials), with no effect on body composition, blood pressure or lipids (Rodríguez 2026) [P]. | Evidence is from non-exercisers. Not a feature for someone who lifts four or five times a week. |
| Cardio fitness | Each 1-MET higher fitness: 11 to 17% lower all-cause mortality; high against low HR 0.47 (Lang 2024, 199 cohorts) [P]. Intervals raise VO₂ max by 5.5 mL/kg/min against no exercise and 1.2 more than steady endurance work (Milanović 2015) [P]; long intervals (2 minutes or more, 15 minutes or more of work, over 4 to 12 weeks) do most (Wen 2019) [P]. Cardio alongside lifting does not reduce muscle growth or maximal strength; explosive strength suffers when both are in one session (Schumann 2022) [P]. | One hard cardio session a week, on a different day from heavy legs. |
| Sitting | Light walking breaks lower post-meal glucose (d = −0.72) and insulin; standing does less (Buffey 2022, 7 one-day trials) [P]. 60 to 75 minutes a day of moderate activity removes the mortality risk of long sitting (Ekelund 2016) [P]. | Built. For an active person the marginal gain is small. |
| Strength, minimum dose | Any resistance training: 15% lower all-cause mortality, most at about 60 minutes a week (Shailendra 2022) [P]; 30 to 60 minutes a week (Momma 2022) [P]. One hard set of 6 to 12 reps, two or three times a week, still raised squat and bench in trained men (Androulakis-Korakakis 2020, 6 studies) [P]. A third or even a ninth of the previous volume held muscle size for 32 weeks in adults aged 20 to 35, not in older adults (Bickel 2011) [P]. Strength and size can be held for up to 32 weeks on one session a week and one set per exercise if the load is kept (Spiering 2021, narrative review) [P]. Four weekly sets per muscle is a workable floor (Iversen 2021) [P]. | A planned low-dose week costs almost nothing. Keep the load, cut the sets. |
| Breaks | Ten weeks off after ten weeks of training: size and strength came back within five weeks and the result at the end matched 20 weeks of continuous training (Halonen 2024, n = 42) [P]. | The restart card's message is right. |
| Sleep regularity | The four more-regular fifths had 20 to 48% lower all-cause mortality than the least regular; regularity predicted better than duration (Windred 2024) [P]. Expert consensus: regular timing matters, and when weekday sleep is short, weekend catch-up sleep may help (Sletten 2023) [P]. Review of 59 studies: irregular timing goes with depressive symptoms, higher BMI, insulin resistance, hypertension and cardiovascular events; all observational (Kalkanis 2025) [P]. | Keep regularity next to duration. Do not scold a lie-in in a week of short sleep. |
| Insomnia therapy, by component | 241 trials, 31,452 people: what adds to remission is cognitive restructuring (odds ratio 1.68), third-wave components (1.49), sleep restriction (1.49) and stimulus control (1.43). Sleep-hygiene education adds nothing (1.01). Relaxation may be counterproductive (0.81). In-person delivery helps (1.83) (Furukawa 2024) [P]. Brief nurse-delivered sleep restriction against sleep-hygiene advice: insomnia severity −3.05 points at six months, d = −0.74 (Kyle 2023, n = 642) [P]. Online and in-person CBT-I are equivalent on most outcomes (Knutzen 2024) [P]. Sleep restriction increases daytime sleepiness and slows reactions in the first weeks (Kyle 2014) [P]. | If the app ever helps with insomnia, it is a sleep window and a fixed wake time, with safety limits. Tips and breathing are filler. |
| Sleep trackers | Wearing a tracker improved perceived sleep quality slightly and did not change total sleep (Berryhill 2020) [P]. Some patients chase tracker numbers (Baron 2017, case series) [P]. | Sleep stays plain-worded; no new sleep numbers. |
| Alcohol tools | Personalised digital interventions: 23 g of alcohol a week less (about 3 UK units), 57 trials; goal setting, problem solving, behaviour substitution and a credible source went with larger effects (Kaner 2017) [P]. The best-tested app, Drink Less: −0.98 units a week in the primary analysis (not significant), −2.0 with multiple imputation, n = 5,602 (Oldham 2024) [P]. Its components had no effect one by one (Crane 2018) [P]. Alcohol suppresses overnight heart-rate recovery in proportion to the dose, in active and inactive people alike (Pietilä 2018) [P]. | A small effect, and only for someone who wants to cut down. A self-set limit plus the owner's own morning numbers is the whole feature. |
| Food nudges | Nutrition apps: g = 0.19 on behaviour (Villinger 2019) [P]. Fruit and vegetables: lower risk up to 800 g a day (Aune 2017) [P]. Fibre 25 to 29 g and protein about 1.6 g/kg are already in the app (Reynolds 2019; Morton 2018) [P]. | Nothing to add without food names from Cronometer. |
| Mood and stress | Exercise for depression: walking or jogging g = −0.62, yoga −0.55, strength training −0.49; low certainty (Noetel 2024) [P]. Across 97 reviews: about −0.43 for depression and anxiety, more at higher intensity (Singh 2023b) [P]. Mental-health apps: g = 0.28 for depression, 0.26 for anxiety, larger with CBT content (Linardon 2024) [P]. | Training is the app's mood tool. On low days suggest moving, not resting. |
| Daylight | Each extra hour outdoors: lower odds of depression, fewer insomnia symptoms (Burns 2021, 400,000 people) [P]. Brighter days and darker nights: lower mortality (Windred 2024b, 89,000 people) [P]. Both observational. | Worth a row in "What affects you", not a nudge. |
| Weight maintenance | Regain is the usual course (Hall & Kahan 2018) [P]. A self-regulation programme built on daily weighing cut the share regaining 2.3 kg or more over 18 months from 72% to 46% face to face and 55% online (Wing 2006) [P]. Self-weighing alone does little (−0.5 kg, not significant); inside a programme it adds 1.7 kg, more with accountability (Madigan 2015) [P]. | When the cut ends the app should switch to holding, with a band and a line to act on. |
| Disordered eating | Cross-sectional studies link diet and fitness apps to disordered eating, body-image concerns and compulsive exercise; no causal conclusion possible (Anderberg 2025, 38 studies) [P]. Men using a calorie app reported more symptoms (Linardon & Messer 2019, n = 122, cross-sectional) [P]. The one trial: a month of calorie tracking in low-risk undergraduate women did not raise eating-disorder risk (Hahn 2021) [P]. | Keep the safeguards and the Hide calories switch. The risk is real for some users and not shown for a low-risk one. |

### 2c. Findings that change earlier Tensile advice

1. **Post-workout feelings do not predict future activity** (Rhodes & Kates 2015). `behaviour-change.md` rec. 14 cited the same paper from memory as covering feelings during and after exercise. The abstract says only feelings during exercise predict later activity; a rating taken afterwards measures the part with no link. Drop it.
2. **Relaxation is not part of what makes insomnia therapy work, and sleep-hygiene advice adds nothing** (Furukawa 2024). `behaviour-change.md` rec. 18 named the right components (fixed wake time, stimulus control); the roadmap's paced-breathing session, since removed, would not have helped sleep.
3. **A lie-in after a short week is defensible** (Sletten 2023). The weekend-shift note in `SleepRegularity.MidpointShift.note` treats every shift over an hour the same.
4. **The gym habit of an established lifter makes him less responsive to prompts** (Buyalskaya 2023). Workout reminders being off by default is right.
5. **Vigorous minutes are worth more than double** in device data (Biswas 2025). One cohort; keep the constant, add a vigorous line.

---

## 3. Ranked shortlist

Ranked by expected health payoff, strength of evidence, and how little it adds to the screens. "Carried over" means an earlier file proposed it and it was not built; it is listed again only where it still earns its place.

| # | Feature | Evidence | Size | Fit in one line |
|---|---|---|---|---|
| 1 | Health floors in the weekly review | Strong (targets), moderate (review technique) | S | Five numbers the app already computes, on a screen that exists |
| 2 | Planned busy week (low-dose holding plan) | Moderate | M | A mode of the weekly plan; keeps load, cuts sets |
| 3 | One hard cardio session a week (carried over) | Strong (fitness and mortality), moderate (the session itself) | M | Extends `CardioPlanner`; the Watch cardio mode runs it |
| 4 | Weekly changes the app can measure, reported back | Moderate (review), weak (self-experiments) | M | Turns the review's three text fields into tracked items |
| 5 | Plan widget for Lock Screen, Home Screen and StandBy | None (usability) | S | Second widget beside `HRVWidget`; lets reminders stay off |
| 6 | Target weight reached: hold band and regain line | Moderate | S–M | New state after `GoalPlanner.weeksToTarget` hits zero |
| 7 | Insomnia path, shown only when it applies (carried over) | Strong | M | Narrows `BedtimeWindow` to a sleep window for a few weeks |
| 8 | Chosen variety at block boundaries | Weak to moderate | S | One more option in `BlockApplyCard` |
| 9 | A weekly drink limit the owner sets | Moderate, small effect | S | One number on `AlcoholEffectCard` |
| 10 | Low-mood rule in the morning message | Strong for exercise and mood, extrapolated | S | A branch in `CoachCheckIns.morning` |
| 11 | Planned sessions in Apple Calendar (carried over) | Moderate | S–M | Writes `WeeklyPlan.plannedDays` with EventKit |
| 12 | Catch-up sleep wording | Consensus statement | S | One condition in `MidpointShift.note` |
| 13 | "First session back" line | Moderate | S | One sentence in `CoachCheckIns.postWorkout` |
| 14 | Daylight as a "What affects you" factor | Weak | S | One entry in `CheckInInsights.factors` |

### 1. Health floors in the weekly review

- **What.** Replace the "Average day strain" line in the Monday review with one row, "Basics: 4 of 5", that opens to five checks for last week: moderate and vigorous minutes (150, with vigorous minutes shown on their own), strength days (2), average steps (7,000), sleep regularity, and drinks. The unmet one becomes the first suggested change.
- **Evidence.** Strong for the targets, all from cohort dose-response work and the WHO guideline (Garcia 2023; Ahmadi 2022; Momma 2022; Shailendra 2022; Ding 2025; Windred 2024; Bull 2020) [P]. Moderate for reviewing goals weekly (Michie 2009; Harkin 2016) [P]. No trial of this exact row.
- **Apps.** Apple's Longevity tab and Oura's weekly views show the same areas; Whoop is adding recommended activity targets [W].
- **Fit.** `WeeklyReviewView` (`lines`, `suggestedChanges`), with `IntensityMinutes` (`HeartHealth.swift`), `StrengthDays` (`TrainingTools.swift`), `StepGoal` (`FitnessAdaptation.swift`), `SleepRegularity` and `AlcoholWeek`. All the data is already read. If the Longevity page being built computes the same floors, both should call one function.
- **Size.** S.
- **Risk.** It could read as a score. Show ticks and the numbers, no percentage, no colour for a miss. A lifter will usually pass strength and may fail cardio and steps: that is the point.

### 2. Planned busy week

- **What.** A "Busy week" choice on the weekly plan, next to rest mode: one or two short sessions, each main lift for one or two hard sets at the usual load, about a third of the usual sets. The week counts as kept in the consistency score. It ends by itself; after three in a row the review asks whether to build again.
- **Evidence.** Moderate. One trial showed a third or a ninth of the volume held muscle for 32 weeks in adults aged 20 to 35 (Bickel 2011); a narrative review reaches the same conclusion and names load as the variable to keep (Spiering 2021); one hard set two or three times a week still improved trained men's squat and bench (Androulakis-Korakakis 2020); a ten-week break cost nothing by the end (Halonen 2024) [P]. All small studies. No trial of a "busy week" button in an app.
- **Apps.** Runna's "Not Feeling 100%" (3 to 14 days, four levels, a return ramp) [W]; Apple's pausable rings and per-day goals [W]; Noom's Maintenance Mode [S]; Peloton plans that "flex" [W].
- **Fit.** `WeeklyPlan` (a third mode or a flag beside `fixedDays` and `flexible`), `PlannedDay.shortVersionMinutes`, `TrainingBlock` (hold the week, as `isHeld` does), `VolumeProgression`, `Consistency.sessionsNeeded`, `ThisWeekCard` and `WeeklyPlanView` for the control. `RestartPlan` already builds a lighter week after the fact; this is the same plan chosen before. No new data.
- **Size.** M.
- **Risk.** It becomes the default. Bound it (one week at a time) and say plainly what it does: "holds what you have; does not build".

### 3. One hard cardio session a week (carried over from `roadmap.md` phase 3 and `health-metrics.md`)

- **What.** When cardio fitness has been flat for a block or sits below "good" for age, the weekly plan offers one interval session in place of one easy session: four rounds of four minutes hard with three easy, or a shorter version, on the bike or rower. It never lands on an easy-recovery day or the day before heavy legs.
- **Evidence.** Strong that fitness matters (Lang 2024) and that intervals raise it (Milanović 2015; Wen 2019) [P]; cohort support for a small weekly dose of vigorous minutes (Ahmadi 2022) [P]; no cost to muscle or maximal strength when sessions are separate (Schumann 2022) [P]. Where it goes in the week is an app choice.
- **New since the earlier files.** The device-based equivalence (Biswas 2025) and the vigorous-minutes dose (Ahmadi 2022) make the case in minutes, not only in VO₂ max, which a watch estimates slowly and only from outdoor walks and runs [M].
- **Apps.** Garmin's daily suggested workouts, Strava's Instant Workouts ("Build") [W], Zwift and Peloton plans.
- **Fit.** `CardioPlanner` (`EasyCardio` gains a hard kind), `WeeklyPlan.cardio`, `VO2Norms`, `VO2MaxEstimate`, `IntensityMinutes` for the vigorous count, and the Watch cardio mode now being built to run it with zone haptics.
- **Size.** M.
- **Risk.** Extra fatigue during a cut; leg soreness before squats. Offer, never schedule by default. Promise vigorous minutes, not a VO₂ max number.

### 4. Weekly changes the app can measure, reported back

- **What.** The review's three changes become choices the app can check without any ticking: last caffeine by a time, in bed by the window on N nights, wake time within an hour, protein at each meal, steps average, a hard cardio session, drinks under the limit. Next Monday the review says how many days each was kept and what moved, with the honest caveat that one week cannot prove anything. Free text stays possible, unmeasured.
- **Evidence.** Moderate for goal review and recorded progress (Michie 2009; Harkin 2016) [P]. Weak for personal experiments as such: no meta-analysis found. Self-chosen habits form more strongly (Singh 2024b) [P].
- **Apps.** Oura Advisor plans (one at a time, seven days, yes or no) [S]; Whoop's custom journal with its effect on recovery [W]; Noom microhabits (vendor data only) [S].
- **Fit.** `WeeklyPlan.changes` is `[String]` today; it needs a small typed model. Checks come from data already read (`CaffeineTiming`, `BedtimeWindow`, `SleepRegularity`, `ProteinMeals`, steps, `AlcoholWeek`). The comparison can reuse the patterns engine in `CheckIn.swift` (Welch t-test with false-discovery correction), which already refuses to claim an effect on too few days.
- **Size.** M.
- **Risk.** Three tracked things can feel like homework. Default to one; the owner chooses more. It also gives the app something different each week, which answers boredom without a notification.

### 5. Plan widget

- **What.** A Lock Screen, Home Screen and StandBy widget: today's session and time ("Push · 6 pm"), "Rest day", or after training the bed-by window. It shows "--" when the data is stale.
- **Evidence.** None for health. Usability: most tracker sessions are five-second glances (Gouveia 2015 [D]); cues in the environment supported habit where clock reminders did not (Stawarz 2015 [D]).
- **Apps.** Gentler Streak [W], Google Health (its best-reviewed 2026 change) [W], Strava [W], Zwift [S].
- **Fit.** `Widget/HRVWidget.swift` shows HRV and recovery only. `Shared/WatchFaceData.swift` already carries the next session for the Watch complication, and `WidgetSnapshot` in `Shared/SharedStore.swift` is the place to add it.
- **Size.** S.
- **Risk.** A widget that disagrees with the app is a top complaint about Bevel and Athlytic (`competitors-2026-11.md`). Prefer blank over stale.

### 6. Target weight reached: hold band and regain line

- **What.** When the weight trend reaches the target, the app offers "Hold here": the goal becomes maintain, calories move to measured maintenance, the weigh-in nudge stays weekly, and one line appears only if the trend sits more than about 2 kg above the target for two weeks, with two options (a short cut, or accept the new weight). Also ask for confirmation when a target is set below a BMI of 18.5 or the date implies a faster rate than `RateLimit` allows.
- **Evidence.** Moderate. Weighing with a rule for acting on a set regain cut regain of 2.3 kg or more from 72% to 46 to 55% over 18 months (Wing 2006) [P]; app weight loss fades by 12 months (Chew 2022) [P]; weighing helps inside a programme, not alone (Madigan 2015) [P]. The band width is an app choice based on the trial's 2.3 kg outcome.
- **Apps.** Noom Maintenance Mode [S], MacroFactor maintenance goals and trend [W], Cronometer's goal guardrails [S].
- **Fit.** `Goals.targetWeightKg`, `GoalPlanner.weeksToTarget`, `WeightPace`, `WeighInNudge`, `EnergyBalance`, the Nutrition line on Today and the weekly review. The data exists when weigh-ins reach Apple Health.
- **Size.** S–M.
- **Risk.** Weight vigilance can harm someone prone to disordered eating (Anderberg 2025) [P]. Trend only, never red, off with Hide calories or paused weight tracking, and no line during a planned gain.

### 7. Insomnia path, shown only when it applies (carried over from `behaviour-change.md` rec. 18)

- **What.** If the owner says he struggles to fall or stay asleep three or more nights a week, or sleep efficiency stays under 85% for four weeks, a card asks two questions (how often, and does it affect the day). If yes: a fixed wake time every day and a sleep window equal to his recent average sleep plus 30 minutes, never under six hours in bed, widened by 15 minutes each week that efficiency passes 85 to 90%. Bed only when sleepy; out of bed if awake about 20 minutes. Otherwise nothing is shown, ever.
- **Evidence.** Strong. Sleep restriction and stimulus control are among the components that add to remission; sleep-hygiene advice and relaxation are not (Furukawa 2024); brief sleep restriction beat hygiene advice, d = −0.74 (Kyle 2023); online delivery matches in-person on most outcomes (Knutzen 2024); digital CBT-I improved wellbeing in 1,711 adults (Espie 2019) [P]. The titration rule and the six-hour floor follow standard practice as I remember it [M]; clinics allow five.
- **New since the earlier file.** The component analysis and the HABIT trial. They say what to leave out as clearly as what to include.
- **Apps.** Sleepio and similar CBT-I programmes; Samsung Bedtime Guidance and Rise suggest times but do not restrict [S].
- **Fit.** `BedtimeWindow.compute` already produces a window from need and wake time; this mode replaces need with recent sleep. `SleepCalculator` has efficiency, `SleepDebtCard` shows it, `StopBang` exists to rule out apnoea first, and Up next already has a bedtime row.
- **Size.** M.
- **Risk.** Real ones. Daytime sleepiness and slower reactions in the first weeks (Kyle 2014) [P]: warn about driving. Not for shift work, suspected apnoea, bipolar disorder or seizure disorders [M]: say so and point to a clinician. A wrist tracker over-counts sleep in people lying awake [M], so the answers, not the tracker, should open the path.

### 8. Chosen variety at block boundaries

- **What.** At the end of a block the report offers, besides its fixes for stalled lifts, "Change one or two accessory lifts?" with the planner's alternatives for the gym. Main lifts stay.
- **Evidence.** Weak to moderate: same gains and better motivation with varied selection in 21 trained men (Baz-Valle 2019); better adherence with variety in beginners (Sylvester 2016); systematic variation is fine and frequent random rotation is not (Kassiano 2022) [P].
- **Apps.** Fitbod rotates automatically and is criticised for it; Ladder and Peloton change programmes by block.
- **Fit.** `NextBlockAdjustments.Swap`, `BlockReport.NextChange`, `BlockApplyCard`, `WorkoutPlanner.alternatives`. Today a swap is offered only for a stalled lift.
- **Size.** S.
- **Risk.** Progress history resets on a swapped lift. Limit to two accessories and keep the old lift's record.

### 9. A weekly drink limit the owner sets

- **What.** On the alcohol card, a limit he chooses ("up to 4 this week"). The card and the evening check-in show the count against it. Offered only when the four-week average is three or more a week.
- **Evidence.** Moderate, small effect: about 3 UK units a week less across 57 trials, with goal setting among the techniques linked to larger effects (Kaner 2017); the best-tested app's primary result was not significant (Oldham 2024) [P]. The owner's own morning HRV and heart-rate effect is already the feedback (Pietilä 2018 supports the mechanism) [P].
- **Apps.** Drink Less, Reframe, Sunnyside; Oura and Whoop show the next-morning effect.
- **Fit.** `AlcoholWeek`, `AlcoholEffectCard`, `AlcoholLogView`, the evening check-in, and item 4's checks.
- **Size.** S.
- **Risk.** An app is not the tool for dependence; one line pointing to a clinician if the count stays in the top tier.

### 10. Low-mood rule in the morning message

- **What.** After three low-mood mornings in a week, the morning message offers the easy session or a 20-minute walk and says why, where it would otherwise suggest rest. After two weeks of mostly low mornings it adds one sentence that this is worth raising with someone. No score.
- **Evidence.** Strong that exercise reduces depressive symptoms, strength training included (Noetel 2024; Singh 2023b) [P]. Applying it to a healthy person's bad week is an extrapolation. A 1-to-5 daily item has no validated cut-off [D].
- **Apps.** Gentler Streak and Headspace adjust tone; none publishes a rule.
- **Fit.** `CoachCheckIns.morning` and `morningTip` (they have no mood input today), `MorningCheckIn.mood`, `MoodSample` from Apple Health.
- **Size.** S.
- **Risk.** Sounding glib. Offer, give the reason, stop there.

### 11. Planned sessions in Apple Calendar (carried over from `cleanup-2026-11.md` A6)

- **What.** A switch that writes the week's sessions to one calendar and keeps them in step when the plan changes.
- **Evidence.** Moderate: plans with a date and a time work better than a date alone (Milkman 2011) [P]; implementation intentions for activity d = 0.31 [D].
- **Apps.** Bevel 3.2.8 [S], Zwift's weekly planner [S].
- **Fit.** `WeeklyPlan.plannedDays` has weekday, time and minutes. EventKit with write-only access.
- **Size.** S–M.
- **Risk.** Stale events after the adaptive week moves a session; update on every plan save.

### 12. Catch-up sleep wording

- **What.** When sleep debt is moderate or high, the weekend-shift note says the lie-in was probably worth it and suggests an earlier night instead next time. Otherwise unchanged.
- **Evidence.** Expert consensus (Sletten 2023) [P]. No trial.
- **Fit.** `SleepRegularity.MidpointShift.note`, with `SleepDebt.Level`.
- **Size.** S. **Risk.** None beyond keeping the two messages consistent.

### 13. "First session back" line

- **What.** When a session follows a missed planned session or seven or more days off, the post-workout message says so in one sentence.
- **Evidence.** Moderate: rewarding the return after a miss was the best of 54 programmes, and little lasted beyond four weeks (Milkman 2021) [P]. Tensile gives information, not a reward.
- **Fit.** `CoachCheckIns.postWorkout` (`PostWorkoutFacts` needs a days-since-last field), `AdaptiveWeek`.
- **Size.** S. **Risk.** None if it never mentions what was missed.

### 14. Daylight as a "What affects you" factor

- **What.** Days with more outdoor light become a factor tested against sleep and mood like the others. No goal, no nudge.
- **Evidence.** Weak: large observational studies (Burns 2021; Windred 2024b) [P].
- **Fit.** `timeInDaylight` is already read in `HealthKitClient`; add an entry to `CheckInInsights.factors` in `CheckIn.swift`. Needs an Apple Watch worn outdoors.
- **Size.** S. **Risk.** A spurious pattern; the existing statistics guard against it.

---

## 4. Earlier recommendations still unbuilt: do they stand?

| Earlier recommendation | Source file | Now |
|---|---|---|
| "How did it feel?" rating after each workout | `behaviour-change.md` rec. 14 | **Drop.** The cited review found no link for post-exercise affect; the owner already asked for fewer post-workout steps. |
| Motives ("why") asked once, used by the coach and the restart card | `behaviour-change.md` rec. 6 | Stands, low priority. One question once; moderate evidence (Ntoumanis 2021) [P]. Build only if the owner wants it (section 6). |
| Monthly PHQ-2 and GAD-2 | `health-metrics.md` | **Not now.** Screening helps when it leads to care; Apple Health has its own questionnaires [M]; it is another recurring prompt. Item 10 covers the practical part. |
| Preventive-care checklist | `health-metrics.md` | **Not now.** Country-specific, and measurement reminders already cover blood pressure, waist and grip. |
| Share card or weekly summary to one person | `behaviour-change.md` rec. 19, `competitors-2026-11.md` rec. 6 | Depends on the owner (section 6). Accountability has support (Harkin 2016; Madigan 2015) [P]; a feed does not. |
| Export and backup | `competitors-2026-11.md` rec. 4 | Stands. Not a health feature; protects the data everything else relies on. |
| Paced breathing | `roadmap.md` phase 4 | Stays removed (see 2c). |

**Owner's decision, 17 Nov 2026.** The owner asked for three of the items above (a "How did it feel?" rating after each workout, a monthly PHQ-2 and GAD-2, and a preventive-care checklist), then chose to follow this research and drop them; only item 10, the low-mood rule, was built. The rating is dropped because only feelings during exercise predict later activity and a rating taken afterwards measures the part with no link (Rhodes & Kates 2015), while adding a post-workout step he had asked to cut. The questionnaires are dropped because screening helps only when it leads to care, Apple Health already offers the PHQ-9 and GAD-7, and they would add another recurring prompt where item 10 covers the practical part. The checklist is dropped because recommendations differ by country and go stale, and the measurement reminders already cover blood pressure, waist and grip.

---

## 5. Not to build

| Feature | Who has it | Why not |
|---|---|---|
| Daily streaks, badges, points, levels, challenges | Apple, Zoe, Zwift, Noom, Finch | Against the same app without them: +489 steps a day and −0.7 kg (Nishi 2024); g = 0.15 at follow-up (Mazeas 2022). Apple had to add pausing. The consistency score is enough. |
| Social feed, followers, shared recovery | Whoop Humans, Strava, Hevy | Needs a server and other people. The only arm that lasted in STEP UP was competition between real people (Patel 2019). Whoop's own release offers no evidence. |
| Cloud coach, or sending workouts to chatbots | Google, Whoop, Oura, Hevy, Strava | No outcome trial; a reported wrong sleep score; against the app's privacy rule. |
| Breathing, meditation or relaxation sessions | Headspace, Apple, Whoop | Removed at the owner's request; relaxation may hinder insomnia therapy (Furukawa 2024); breathing apps kept a median 0% of users to day 30 (Baumel 2019). |
| Sleep-hygiene tips, lessons, "learn" content | Noom, Rise, Oura | Sleep-hygiene education added nothing (odds ratio 1.01). Lesson content has never been isolated in a trial [D]. |
| Exercise snacks, vigorous-burst prompts, more sedentary nudges | Garmin Move, Apple Stand | The evidence is in inactive people (Stamatakis 2022; Rodríguez 2026); anti-sedentary prompts had no detectable effect (Klasnja 2019). |
| Cleverer or more frequent notifications | Whoop, Garmin, Noom | Effects fade within weeks; just-in-time systems are unproven (Hardeman 2019); an established habit responds least (Buyalskaya 2023). |
| Post-workout mood or pleasure rating | — | No predictive value (Rhodes & Kates 2015); more taps. |
| Photo or barcode food logging, processed-food scores, a produce counter | Zoe, Google, Garmin, Ladder | Cronometer is the logger and sends nutrients, not food names. Photo logging needs a cloud model. |
| Daily weight or calorie targets shown as pass or fail | most calorie apps | Daily numbers are noise; the association with disordered eating is consistent in cross-sectional work (Anderberg 2025). |
| Cuffless blood pressure, antioxidant index, cumulative stress, energy gauges | Oura, Samsung, Whoop, Garmin | Unvalidated or needs hardware the owner does not have; already on the skip list. |
| Biological age, pace of ageing | Bevel, Whoop, Apple | Already hidden; Apple gives one away. |
| Lab ordering, clinician visits, health-record import | Whoop, Oura, Noom, Google | A business, not a feature; no behaviour evidence. |
| Smart alarm, sleep sounds, snore detection | Sleep Cycle, Rise | No outcome evidence. |
| Rewards, money, commitment contracts | megastudy arms | Only 8% of programmes had any effect after four weeks (Milkman 2021); incentives fade when withdrawn [D]. |
| Sleep restriction or a sleep target for everyone | — | Only for insomnia, with limits (item 7). For a normal sleeper it risks tracker-driven worry (Baron 2017). |

---

## 6. Open questions only the owner can answer

1. **Cardio.** Would he do one hard interval session a week, and on what (bike, rower, treadmill, outdoors)? Item 3 depends on a yes.
2. **What makes a week go wrong?** Work and travel (item 2), illness (rest mode exists), or boredom with the sessions (item 8)? The answer orders items 2 and 8.
3. **Boredom with what?** The exercises, the screens, or the messages? Item 4 gives a different small thing each week; item 8 changes the lifts; the notification work is already in hand.
4. **Sleep.** Does he have trouble falling or staying asleep three or more nights a week? If not, item 7 can wait until the data says otherwise.
5. **Alcohol.** Does he drink enough that a weekly limit would be useful, or is the tier chip enough?
6. **After the cut.** Is there a target weight, and does he want the app to switch to holding it and tell him if it drifts (item 6)?
7. **How many weekly changes** is he willing to have tracked: one, or the current three?
8. **Glances.** Does he use Lock Screen or Home Screen widgets, or StandBy? Does he keep a calendar he looks at? That decides items 5 and 11.
9. **Low mood.** Does he want the app to say anything when mornings run low, or to stay out of it?
10. **Another person.** Is there a training partner or friend he would send a weekly summary to? If not, the share card stays off the list.
11. **Time zones.** Does he fly across them more than once or twice a year? `qa-2026-11-17.md` leaves bed-by and caffeine times on home time after a long flight.

---

## 7. References

Marks as defined at the top. [P] and [W] were read at the source this round (PubMed abstract or the fetched page); the rest were not.

### Behaviour change, apps and engagement

- Baumel A, Muench F, Edan S, Kane JM. Objective user engagement with mental health apps: systematic search and panel-based usage analysis. J Med Internet Res 2019;21(9):e14567. [P]
- Bidargaddi N, et al. To prompt or not to prompt? A microrandomized trial of time-varying push notifications to increase proximal engagement with a mobile health app. JMIR Mhealth Uhealth 2018;6(11):e10123. [P]
- Buyalskaya A, Ho H, Milkman KL, Li X, Duckworth AL, Camerer C. What can machine learning teach us about habit formation? Evidence from exercise and hygiene. Proc Natl Acad Sci USA 2023;120(17):e2216115120. [P]
- Eckerstorfer LV, et al. Key elements of mHealth interventions to successfully increase physical activity: meta-regression. JMIR Mhealth Uhealth 2018;6(11):e10076. [P]
- Ferguson T, et al. Effectiveness of wearable activity trackers to increase physical activity and improve health: a systematic review of systematic reviews and meta-analyses. Lancet Digit Health 2022;4(8):e615-e626. [P]
- Gouveia R, Karapanos E, Hassenzahl M. How do we engage with activity trackers? UbiComp 2015. [D: search summary in `cleanup-2026-11.md`]
- Hardeman W, Houghton J, Lane K, Jones A, Naughton F. A systematic review of just-in-time adaptive interventions (JITAIs) to promote physical activity. Int J Behav Nutr Phys Act 2019;16:31. [P]
- Harkin B, et al. Does monitoring goal progress promote goal attainment? A meta-analysis of the experimental evidence. Psychol Bull 2016;142(2):198-229. [P]
- Jakob R, et al. Factors influencing adherence to mHealth apps for prevention or management of noncommunicable diseases: systematic review. J Med Internet Res 2022;24(5):e35371. [P]
- Khasentino J, et al. A personal health large language model for sleep and fitness coaching. Nat Med 2025;31(10):3394-3403. [P]
- Klasnja P, et al. Efficacy of contextually tailored suggestions for physical activity: a micro-randomized optimization trial of HeartSteps. Ann Behav Med 2019;53(6):573-582. [P]
- Krebs P, Duncan DT. Health app use among US mobile phone owners: a national survey. JMIR Mhealth Uhealth 2015;3(4):e101. [P]
- Kumar H, et al. Large language model agents for improving engagement with behavior change interventions: application to digital mindfulness. Proc ACM Hum Comput Interact 2025;9(7):CSCW438. [P]
- Laranjo L, et al. Do smartphone applications and activity trackers increase physical activity in adults? Systematic review, meta-analysis and metaregression. Br J Sports Med 2021;55(8):422-432. [P]
- Linardon J, Fuller-Tyszkiewicz M. Attrition and adherence in smartphone-delivered interventions for mental health problems: a systematic and meta-analytic review. J Consult Clin Psychol 2020;88(1):1-13. [P]
- Maier M, et al. No evidence for nudging after adjusting for publication bias. Proc Natl Acad Sci USA 2022;119(31):e2200300119. [P: record has no abstract; title and journal confirmed]
- Mazeas A, Duclos M, Pereira B, Chalabaev A. Evaluating the effectiveness of gamification on physical activity: systematic review and meta-analysis of randomized controlled trials. J Med Internet Res 2022;24(1):e26779. [P]
- Mertens S, Herberz M, Hahnel UJJ, Brosch T. The effectiveness of nudging: a meta-analysis of choice architecture interventions across behavioral domains. Proc Natl Acad Sci USA 2022;119(1):e2107346118. [P]
- Meyerowitz-Katz G, et al. Rates of attrition and dropout in app-based interventions for chronic disease: systematic review and meta-analysis. J Med Internet Res 2020;22(9):e20283. [P]
- Michie S, Abraham C, Whittington C, McAteer J, Gupta S. Effective techniques in healthy eating and physical activity interventions: a meta-regression. Health Psychol 2009;28(6):690-701. [P]
- Milkman KL, Beshears J, Choi JJ, Laibson D, Madrian BC. Using implementation intentions prompts to enhance influenza vaccination rates. Proc Natl Acad Sci USA 2011;108(26):10415-10420. [P]
- Milkman KL, et al. Megastudies improve the impact of applied behavioural science. Nature 2021;600(7889):478-483. [P]
- Mönninghoff A, et al. Long-term effectiveness of mHealth physical activity interventions: systematic review and meta-analysis of randomized controlled trials. J Med Internet Res 2021;23(4):e26699. [P]
- Nishi SK, et al. Effect of digital health applications with or without gamification on physical activity and cardiometabolic risk factors: a systematic review and meta-analysis of randomized controlled trials. EClinicalMedicine 2024;76:102798. [P]
- Ntoumanis N, et al. A meta-analysis of self-determination theory-informed intervention studies in the health domain. Health Psychol Rev 2021;15(2):214-244. [P]
- Patel MS, et al. Effectiveness of behaviorally designed gamification interventions with social incentives for increasing physical activity among overweight and obese adults across the United States: the STEP UP randomized clinical trial. JAMA Intern Med 2019;179(12):1624-1632. [P]
- Rhodes RE, Kates A. Can the affective response to exercise predict future motives and physical activity behavior? A systematic review of published evidence. Ann Behav Med 2015;49(5):715-731. [P]
- Roordink EM, et al. Predictors of lapse and relapse in physical activity and dietary behaviour: a systematic search and review on prospective studies. Psychol Health 2023;38(5):623-646. [P]
- Singh B, et al. Systematic review and meta-analysis of the effectiveness of chatbots on lifestyle behaviours. NPJ Digit Med 2023;6:118. [P]
- Singh B, et al. A systematic umbrella review and meta-meta-analysis of eHealth and mHealth interventions for improving lifestyle behaviours. NPJ Digit Med 2024;7:179. [P]
- Singh B, Murphy A, Maher C, Smith AE. Time to form a habit: a systematic review and meta-analysis of health behaviour habit formation and its determinants. Healthcare (Basel) 2024;12(23):2488. [P] (cited as Singh 2024b)
- Sirois FM, Kitner R, Hirsch JK. Self-compassion, affect, and health-promoting behaviors. Health Psychol 2015;34(6):661-669. [P]
- Stawarz K, Cox AL, Blandford A. Beyond self-tracking and reminders: designing smartphone apps that support habit formation. CHI 2015. [D: search summary in `cleanup-2026-11.md`]
- Sylvester BD, et al. Variety support and exercise adherence behavior: experimental and mediating effects. J Behav Med 2016;39(2):214-224. [P]
- Terry PC, Karageorghis CI, Curran ML, Martin OV, Parsons-Smith RL. Effects of music in exercise and sport: a meta-analytic review. Psychol Bull 2020;146(2):91-117. [P]
- Wang L, Miller LC. Just-in-the-moment adaptive interventions (JITAI): a meta-analytical review. Health Commun 2020;35(12):1531-1544. [P]
- Gollwitzer & Sheeran 2006; Bélanger-Gravel 2013; Zhang 2016; Deci 1999; Silverman & Barasch 2023; Lally 2010: see `behaviour-change.md`. [D]

### Activity, fitness and strength

- Ahmadi MN, Clare PJ, Katzmarzyk PT, del Pozo Cruz B, Lee IM, Stamatakis E. Vigorous physical activity, incident heart disease, and cancer: how little is enough? Eur Heart J 2022;43(46):4801-4814. [P]
- Androulakis-Korakakis P, Fisher JP, Steele J. The minimum effective training dose required to increase 1RM strength in resistance-trained men: a systematic review and meta-analysis. Sports Med 2020;50(4):751-765. [P]
- Baz-Valle E, Schoenfeld BJ, Torres-Unda J, Santos-Concejero J, Balsalobre-Fernández C. The effects of exercise variation in muscle thickness, maximal strength and motivation in resistance trained men. PLoS One 2019;14(12):e0226989. [P]
- Bickel CS, Cross JM, Bamman MM. Exercise dosing to retain resistance training adaptations in young and older adults. Med Sci Sports Exerc 2011;43(7):1177-1187. [P]
- Biswas RK, Ahmadi MN, Bauman A, Milton K, Koemel NA, Stamatakis E. Wearable device-based health equivalence of different physical activity intensities against mortality, cardiometabolic disease, and cancer. Nat Commun 2025;16:8315. [P]
- Buffey AJ, Herring MP, Langley CK, Donnelly AE, Carson BP. The acute effects of interrupting prolonged sitting time in adults with standing and light-intensity walking on biomarkers of cardiometabolic health: a systematic review and meta-analysis. Sports Med 2022;52(8):1765-1787. [P]
- Bull FC, et al. World Health Organization 2020 guidelines on physical activity and sedentary behaviour. Br J Sports Med 2020;54(24):1451-1462. [P]
- Ding D, et al. Daily steps and health outcomes in adults: a systematic review and dose-response meta-analysis. Lancet Public Health 2025;10(8):e668-e681. [P]
- Ekelund U, et al. Does physical activity attenuate, or even eliminate, the detrimental association of sitting time with mortality? A harmonised meta-analysis of data from more than 1 million men and women. Lancet 2016;388(10051):1302-1310. [P]
- Garcia L, et al. Non-occupational physical activity and risk of cardiovascular disease, cancer and mortality outcomes: a dose-response meta-analysis of large prospective studies. Br J Sports Med 2023;57(15):979-989. [P]
- Halonen EJ, et al. Does taking a break matter: adaptations in muscle strength and size between continuous and periodic resistance training. Scand J Med Sci Sports 2024;34(10):e14739. [P]
- Inoue K, Tsugawa Y, Mayeda ER, Ritz B. Association of daily step patterns with mortality in US adults. JAMA Netw Open 2023;6(3):e235174. [P]
- Iversen VM, Norum M, Schoenfeld BJ, Fimland MS. No time to lift? Designing time-efficient training programs for strength and hypertrophy: a narrative review. Sports Med 2021;51(10):2079-2095. [P]
- Kassiano W, et al. Does varying resistance exercises promote superior muscle hypertrophy and strength gains? A systematic review. J Strength Cond Res 2022;36(6):1753-1762. [P]
- Lang JJ, et al. Cardiorespiratory fitness is a strong and consistent predictor of morbidity and mortality among adults: an overview of meta-analyses representing over 20.9 million observations from 199 unique cohort studies. Br J Sports Med 2024;58(10):556-566. [P]
- Milanović Z, Sporiš G, Weston M. Effectiveness of high-intensity interval training (HIT) and continuous endurance training for VO2max improvements: a systematic review and meta-analysis of controlled trials. Sports Med 2015;45(10):1469-1481. [P]
- Momma H, Kawakami R, Honda T, Sawada SS. Muscle-strengthening activities are associated with lower risk and mortality in major non-communicable diseases: a systematic review and meta-analysis of cohort studies. Br J Sports Med 2022;56(13):755-763. [P]
- Paluch AE, et al. Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts. Lancet Public Health 2022;7(3):e219-e228. [P]
- Pelland JC, et al. The resistance training dose response: meta-regressions exploring the effects of weekly volume and frequency on muscle hypertrophy and strength gains. Sports Med 2026;56(2):481-505. [P] (the preprint cited in `competitors-2026-11.md` is now published)
- Rodríguez MÁ, et al. Effect of exercise snacks on fitness and cardiometabolic health in physically inactive individuals: systematic review and meta-analysis. Br J Sports Med 2026;60(2):133-141. [P]
- Schumann M, et al. Compatibility of concurrent aerobic and strength training for skeletal muscle size and function: an updated systematic review and meta-analysis. Sports Med 2022;52(3):601-612. [P]
- Shailendra P, Baldock KL, Li LSK, Bennie JA, Boyle T. Resistance training and mortality risk: a systematic review and meta-analysis. Am J Prev Med 2022;63(2):277-285. [P]
- Spiering BA, Mujika I, Sharp MA, Foulis SA. Maintaining physical performance: the minimal dose of exercise needed to preserve endurance and strength over time. J Strength Cond Res 2021;35(5):1449-1458. [P]
- Stamatakis E, et al. Association of wearable device-measured vigorous intermittent lifestyle physical activity with mortality. Nat Med 2022;28(12):2521-2529. [P]
- Wen D, et al. Effects of different protocols of high intensity interval training for VO2max improvements in adults: a meta-analysis of randomised controlled trials. J Sci Med Sport 2019;22(8):941-947. [P]

### Sleep

- Baron KG, Abbott S, Jao N, Manalo N, Mullen R. Orthosomnia: are some patients taking the quantified self too far? J Clin Sleep Med 2017;13(2):351-354. [P]
- Berryhill S, et al. Effect of wearables on sleep in healthy individuals: a randomized crossover trial and validation study. J Clin Sleep Med 2020;16(5):775-783. [P]
- Burns AC, et al. Time spent in outdoor light is associated with mood, sleep, and circadian rhythm-related outcomes: a cross-sectional and longitudinal study in over 400,000 UK Biobank participants. J Affect Disord 2021;295:347-352. [P]
- Espie CA, et al. Effect of digital cognitive behavioral therapy for insomnia on health, psychological well-being, and sleep-related quality of life: a randomized clinical trial. JAMA Psychiatry 2019;76(1):21-30. [P]
- Furukawa Y, et al. Components and delivery formats of cognitive behavioral therapy for chronic insomnia in adults: a systematic review and component network meta-analysis. JAMA Psychiatry 2024;81(4):357-365. [P]
- Kalkanis A, Lenkens D, Steiropoulos P, Testelmans D. Sleep regularity as an important component of sleep hygiene: a systematic review. Sleep Med Rev 2025;84:102203. [P]
- Knutzen SM, et al. Efficacy of eHealth versus in-person cognitive behavioral therapy for insomnia: systematic review and meta-analysis of equivalence. JMIR Ment Health 2024;11:e58217. [P]
- Kyle SD, et al. Sleep restriction therapy for insomnia is associated with reduced objective total sleep time, increased daytime somnolence, and objectively impaired vigilance. Sleep 2014;37(2):229-237. [P]
- Kyle SD, et al. Clinical and cost-effectiveness of nurse-delivered sleep restriction therapy for insomnia in primary care (HABIT): a pragmatic, superiority, open-label, randomised controlled trial. Lancet 2023;402(10406):975-987. [P]
- Sletten TL, et al. The importance of sleep regularity: a consensus statement of the National Sleep Foundation sleep timing and variability panel. Sleep Health 2023;9(6):801-820. [P]
- Windred DP, et al. Sleep regularity is a stronger predictor of mortality risk than sleep duration: a prospective cohort study. Sleep 2024;47(1):zsad253. [P]
- Windred DP, et al. Brighter nights and darker days predict higher mortality risk: a prospective analysis of personal light exposure in >88,000 individuals. Proc Natl Acad Sci USA 2024;121(43):e2405924121. [P] (cited as Windred 2024b)
- Sleep-window titration rule, the six-hour floor, the three-nights-a-week criterion and the exclusions in item 7: standard clinical practice as remembered. [M] Check against a current CBT-I manual before building.

### Alcohol, food, weight and mood

- Anderberg I, Kemps E, Prichard I. The link between the use of diet and fitness monitoring apps, body image and disordered eating symptomology: a systematic review. Body Image 2025;52:101836. [P]
- Aune D, et al. Fruit and vegetable intake and the risk of cardiovascular disease, total cancer and all-cause mortality: a systematic review and dose-response meta-analysis of prospective studies. Int J Epidemiol 2017;46(3):1029-1056. [P]
- Chew HSJ, et al. Sustainability of weight loss through smartphone apps: systematic review and meta-analysis on anthropometric, metabolic, and dietary outcomes. J Med Internet Res 2022;24(9):e40141. [P]
- Crane D, Garnett C, Michie S, West R, Brown J. A smartphone app to reduce excessive alcohol consumption: identifying the effectiveness of intervention components in a factorial randomised control trial. Sci Rep 2018;8:4384. [P]
- Hahn SL, et al. Introducing dietary self-monitoring to undergraduate women via a calorie counting app has no effect on mental health or health behaviors: results from a randomized controlled trial. J Acad Nutr Diet 2021;121(12):2377-2388. [P]
- Hall KD, Kahan S. Maintenance of lost weight and long-term management of obesity. Med Clin North Am 2018;102(1):183-197. [P]
- Kaner EF, et al. Personalised digital interventions for reducing hazardous and harmful alcohol consumption in community-dwelling populations. Cochrane Database Syst Rev 2017;9:CD011479. [P]
- Linardon J, Messer M. My fitness pal usage in men: associations with eating disorder symptoms and psychosocial impairment. Eat Behav 2019;33:13-17. [P]
- Linardon J, et al. Current evidence on the efficacy of mental health smartphone apps for symptoms of depression and anxiety: a meta-analysis of 176 randomized controlled trials. World Psychiatry 2024;23(1):139-149. [P]
- Madigan CD, Daley AJ, Lewis AL, Aveyard P, Jolly K. Is self-weighing an effective tool for weight loss: a systematic literature review and meta-analysis. Int J Behav Nutr Phys Act 2015;12:104. [P]
- Morton RW, et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults. Br J Sports Med 2018;52(6):376-384. [P]
- Noetel M, et al. Effect of exercise for depression: systematic review and network meta-analysis of randomised controlled trials. BMJ 2024;384:e075847. [P]
- Oldham M, et al. Effectiveness of a smartphone app (Drink Less) versus usual digital care for reducing alcohol consumption among increasing-and-higher-risk adult drinkers in the UK: a two-arm, parallel-group, double-blind, randomised controlled trial. EClinicalMedicine 2024;70:102534. [P]
- Pietilä J, et al. Acute effect of alcohol intake on cardiovascular autonomic regulation during the first hours of sleep in a large real-world sample of Finnish employees: observational study. JMIR Ment Health 2018;5(1):e23. [P]
- Reynolds A, et al. Carbohydrate quality and human health: a series of systematic reviews and meta-analyses. Lancet 2019;393(10170):434-445. [P]
- Singh B, et al. Effectiveness of physical activity interventions for improving depression, anxiety and distress: an overview of systematic reviews. Br J Sports Med 2023;57(18):1203-1209. [P] (cited as Singh 2023b)
- Villinger K, Wahl DR, Boeing H, Schupp HT, Renner B. The effectiveness of app-based mobile interventions on nutrition behaviours and nutrition-related health outcomes: a systematic review and meta-analysis. Obes Rev 2019;20(10):1465-1484. [P]
- Wing RR, Tate DF, Gorin AA, Raynor HA, Fava JL. A self-regulation program for maintenance of weight loss. N Engl J Med 2006;355(15):1563-1571. [P]
- Apple Health's built-in depression and anxiety questionnaires. [M]

### Apps and products

Fetched and read [W]:
- Apple, pausable rings and per-day goals: https://9to5mac.com/2024/12/31/watchos-11-fixes-easier-apple-watch-health-goals/
- Oura, Ring 5 software (Health Radar, live workouts, lab uploads): https://ouraring.com/blog/new-software-features/ (vendor)
- Garmin Connect+ after a year: https://the5krunner.com/2026/04/20/garmin-connect-plus-review/
- Google Health 5.0 (widget, coach errors, removed features): https://www.digitaltrends.com/computing/google-health-5-0-is-rolling-out-with-its-best-feature-up-front-and-its-worst-problems-buried/
- Whoop autumn plans (custom journal, merged daily flow, activity targets): https://gadgetsandwearables.com/2026/09/05/whoop-custom-journal-workout-tracking-update/
- Whoop Humans press release: https://via.tt.se/pressmeddelande/4639975/whoop-launches-whoop-humans-the-most-verifiably-human-social-network?publisherId=259167 (vendor)
- Strava Instant Workouts: https://endurance.biz/2026/industry-news/strava-rolls-out-instant-workouts-feature-for-subscribers-worldwide/
- Strava September 2026 update: https://the5krunner.com/2026/09/15/strava-september-update/
- Runna "Not Feeling 100%": https://support.runna.com/en/articles/13531498-how-to-use-not-feeling-100 (vendor)
- Peloton IQ: https://www.onepeloton.com/blog/what-is-peloton-iq (vendor)
- Zwift Week Streaks, weekly goals, running: https://zwiftinsider.com/?p=130029
- Gentler Streak 5.2 widgets: https://www.ithinkdiff.com/gentler-streak-v5-2-home-screen-widgets-rpe-insights/
- MacroFactor July 2026 newsletter: https://macrofactor.com/mm-july-2026/ (vendor)
- Noom free GLP-1 Companion: https://www.noom.com/in-the-news/noom-launches-free-version-of-its-powerful-glp-1-companion/ (vendor)
- Sleep Cycle Sleep Score: https://insider.fitt.co/press-release/sleep-cycle-launches-new-sleep-score-built-on-recent-research/ (vendor press release)

Search summaries only [S]:
- Oura Advisor plans (one plan, seven days, yes or no habits): https://www.technobezz.com/news/from-insights-to-action-build-a-personalized-plan-with-oura-advisor (fetch refused); Health Radar: https://ouraring.com/health-radar
- Google Health Coach rollout and pricing: https://www.techrepublic.com/article/news-fitbit-ai-coach-expands-ios-five-markets/
- Garmin nutrition logging: https://www.garmin.com/en-CA/blog/?p=32554
- watchOS 27 and iOS 27 fitness changes: https://support.apple.com/149077 ; https://9to5mac.com/2026/06/15/ios-27-basically-turns-your-iphone-and-airpods-into-an-apple-watch-at-the-gym/
- Samsung One UI 8 Watch: https://news.samsung.com/global/new-features-on-one-ui-8-watch-help-users-build-healthier-habits
- Coros 2026 updates: https://coros.com/us/stories/coros-metrics/c/june-2026
- Bevel 3: https://gadgetsandwearables.com/2026/05/16/bevel-3/
- Zwift spring 2026 and Progress widget: https://www.dcrainmaker.com/2026/03/zwift-announces-spring-summer-2026-new-features.html
- Gentler Streak 2026: https://9to5mac.com/2026/03/30/gentler-streaks-wellness-section-now-features-cardio-fitness-data/
- Hevy 3.1.14: https://appshunter.io/ios/app/hevy/id1458862350 ; Ladder nutrition: https://techcrunch.com/2025/10/27/workout-app-ladder-launches-nutrition-tracking-experience
- Cronometer: https://cronometer.com/blog/cronometer-updates-whats-new-improved
- Noom engagement report and microhabits: https://www.noom.com/in-the-news/people-who-use-noom-the-most-also-lose-the-most-weight/ (vendor)
- Zoe redesign: https://www.thegrocer.co.uk/news/nutrition-brand-zoe-launches-radically-redesigned-new-app/709452.article
- Rise: https://www.risescience.com/blog/rise-app-review (vendor)
- Headspace Ebb: https://www.t3.com/home-living/wellness/headspace-finally-launches-its-ebb-ai-companion-in-the-uk-heres-how-it-works
- Finch and Fabulous: https://makeheadway.com/blog/self-care-apps/ ; Streaks: https://apps.apple.com/app/id963034692
- Retention benchmarks: https://getstream.io/blog/app-retention-guide (vendor blog; sources disagree)

Not found or not checked: anything new in 2026 for Polar, Strong or Fitbod; the 2026 App Store Awards (not announced at the time of writing); whether Whoop's merged daily flow and custom journal have shipped; Strava's streak widget (one secondary mention, not confirmed on the page fetched).
