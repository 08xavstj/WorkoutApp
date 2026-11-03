# Motivation, behaviour change and adherence: what the research says for Tensile

Research round, November 2026. Scope: what an app can do so one person trains
more, eats and sleeps better, and keeps doing it for years, and what backfires.
Code read for this: `App/Features/Today/TodayView.swift` (strain goal card,
coaching line), `App/Features/Fitness/FitnessView.swift` (encouragement text),
`App/Services/TrainerSuggestions.swift` (`coachingLine`), `App/Services/Reminders.swift`,
`App/Features/Today/HabitsCard.swift`, `App/Design/Theme.swift`,
`supabase/functions/coach/index.ts` (coach system prompt), `docs/checkin-questions.md`.

**Verification note.** Every reference marked **[V]** was checked this round by
web search (title, authors, journal, year, headline numbers). The web-search
budget ran out part-way through and PubMed is not reachable from this sandbox,
so references marked **[M]** are well-known papers cited from memory and were
*not* re-verified here. Check an [M] reference before quoting its numbers in the
app. No reference was invented; where I was not sure a study existed, it was left out.

## Summary

The evidence for long-term exercise adherence points the same way from several
directions. People keep training when the motivation is their own (intrinsic or
identity-based, not pressure or guilt; Teixeira 2012, Ntoumanis 2021), when the
behaviour has become a cued habit (Lally 2010), when they have made concrete
if-then plans for when and where they will train and what they will do when
life gets in the way (Gollwitzer & Sheeran 2006, d = 0.65; Bélanger-Gravel 2013
for physical activity, d = 0.31), and when they monitor progress against goals
they have set and review (Michie 2009; McEwan 2016, d = 0.55; Harkin 2016,
d = 0.40). Apps and trackers add roughly 1,500–1,900 steps a day over a few
months (Laranjo 2021; Gal 2018), and the apps that do best use personalised
messages and prompts, not generic ones. Engagement tricks mostly do not
translate into health: gamification's effect shrinks to g ≈ 0.15 at follow-up
(Mazeas 2022), financial incentives fade when withdrawn (Mitchell 2020), tangible
rewards can undermine intrinsic motivation (Deci 1999), and a broken streak
reduces engagement unless it can be repaired (Silverman & Barasch 2023).
Tensile already has the hard part, rich self-monitoring with feedback. What it
lacks is the planning and review layer: pre-committed training days with if-then
and coping plans, a weekly review that sets next week, a consistency measure
that forgives missed days, a kind relapse path, and coach language that
supports autonomy. Several current framings (the "x% to go" strain chase,
the red "low" recovery ring, the red "Over" calorie line) are the kind of
controlling or nocebo feedback the research warns against and should be softened.

## Recommendations at a glance

Evidence strength: **strong** = several meta-analyses or large RCTs agree;
**moderate** = one meta-analysis or consistent RCTs; **weak** = small or
observational studies; **mixed** = studies disagree. Effort: **small** = text,
prompt or colour changes (hours); **medium** = a new card or flow (days);
**large** = a new subsystem.

| # | What | Why (evidence) | Strength | Goal tailoring | Effort |
|---|---|---|---|---|---|
| 1 | **Weekly review and next-week plan** (Sunday evening card + coach summary) | Self-monitoring works best combined with goal setting, feedback and *review of goals* (Michie 2009: 0.42 vs 0.26); goal review and feedback are among the techniques tied to maintenance (Samdal 2017); a new week is a "fresh start" landmark (Dai 2014) | Strong | Lose: weight trend vs pace, protein. Gain/muscle: hard sets per muscle, calories. Strength: e1RM on main lifts. Endurance: zone minutes. Health: strength days ≥ 2, 150 min, steps | Medium |
| 2 | **Pre-committed training days with if-then plans** ("Tue 6 pm, gym, upper A; if I miss it, Wed same time") | Implementation intentions d = 0.65 across 94 tests (Gollwitzer & Sheeran 2006); d = 0.31 for physical activity (Bélanger-Gravel 2013); explicit if-then wording and rehearsal help (Sheeran 2024 update); mental contrasting + if-then doubled activity over 4 months (Stadler 2009) | Strong | Days per week from goal and recovery: 2–3 (health), 3–4 (muscle/strength), plus cardio slots (endurance) | Medium |
| 3 | **Coping plans for known obstacles** ("if I'm sore in my legs, do upper body"; "if work runs late, 20-minute version") | Coping planning on top of action planning predicts maintenance (Sniehotta 2005); self-regulation and habit are two of the five maintenance mechanisms (Kwasnicka 2016) | Moderate | Obstacles differ: travel (health), low recovery (strength), hunger (lose) | Small |
| 4 | **Consistency score instead of a streak** (rolling 4-week "sessions done of planned", 3 of 4 counts as on plan; never show a broken chain) | Missing one day did not hurt habit formation (Lally 2010); a displayed broken streak cuts engagement, attenuated when repairable (Silverman & Barasch 2023); monitoring progress d = 0.40 (Harkin 2016); total weekly activity matters, not the pattern (dos Santos 2022) | Moderate | Target sessions per week from the goal; endurance adds cardio minutes | Small |
| 5 | **Autonomy-supportive coach language** (choice between two options, rationale, acknowledge feelings, no "should/must", no "you missed") | SDT-based interventions improve health behaviour via need support and autonomous motivation, not pressure (Ntoumanis 2021, 73 studies); intrinsic motivation predicts long-term adherence (Teixeira 2012, 66 studies); catalogue of 21 SDT techniques (Teixeira 2020) | Strong | Same style for all goals; content differs | Small |
| 6 | **"Why" and identity check-in** (onboarding + monthly: pick motives; coach reflects them; show "you're someone who trains 3× a week, 11 weeks running") | Identity–behaviour r = 0.44 (Rhodes 2016); identity interventions shift activity g = 0.61 in studies that measured it (Rhodes 2024); identified/intrinsic motives predict adherence, body/appearance motives are mixed (Teixeira 2012) | Moderate | Lose: steer from appearance to capability; health: longevity framing | Small |
| 7 | **Minimum version of every session** ("no time or energy: 15 minutes, 2 lifts, RPE 6") and open goals on low days ("see how it goes") | Specific hard goals can backfire for people who are not yet confident (Swann 2021); consistency builds the habit (Lally 2010; Gardner 2012); low recovery days should re-route, not stop (HRV-guided trials use "go easy", not "skip") | Moderate | Health/lose: walk option; strength: technique session | Small |
| 8 | **Fewer, smarter notifications**: one morning, one evening, none on rest days unless planned; skip if already done; back off after 2 ignored; tie workout reminders to the pre-committed slot | JITAIs work by timing and tailoring (Nahum-Shani 2018); the effect of repeated suggestions decays with habituation (Klasnja 2019: +107% early, +14% average); text/prompts help when personalised (Laranjo 2021); prompts raise short-term engagement (Bidargaddi 2018) | Moderate | Reminder content from goal (protein for muscle, steps for health) | Medium |
| 9 | **Morning briefing = plan with a choice, not a target to chase** ("Today: upper A (45 min) or easy ride. Recovery suggests keeping it controlled.") | Action planning + autonomy support (above); "x% to go" is a controlling, outcome-framed goal (Ntoumanis 2021; Swann 2021) | Moderate | Options from goal and gym | Medium |
| 10 | **Evening reflection = one win + mood/energy** (existing check-in plus "one thing that went well"; show the week's small wins) | Progress monitoring works better when recorded (Harkin 2016); attention to progress made keeps people going early, remaining distance later (Koo & Fishbach 2012, small-area hypothesis); mood tracks training stress (Saw 2016, already used) | Moderate | Wins by goal (hit protein; PR; 2nd strength day) | Small |
| 11 | **Relapse path after 7+ days off**: no guilt, shrink the plan, re-plan, remind that little fitness is lost in 2–3 weeks, offer a fresh start | Abstinence-violation / "what the hell" effect (Marlatt & Gordon 1985); self-compassion after a setback predicts getting back (Semenchuk 2018); fresh-start landmarks (Dai 2014); detraining under 4 weeks costs little (Mujika & Padilla 2000) | Moderate | Lose: avoid "damage" framing; strength: resume at 85–90% | Medium |
| 12 | **Progress views that survive plateaus**: rolling averages, smoothed e1RM, "expected plateau" note on weight, process metrics (sessions, sets, zone minutes) beside outcomes | Feedback on behaviour, not only outcome, is a core technique (Michie 2013); goal gradient and small-area effects (Kivetz 2006; Koo & Fishbach 2012); self-weighing is useful when the trend, not the reading, is shown (Zheng 2015; Steinberg 2015) | Moderate | Weight views only when lose/gain; e1RM for strength; sets for muscle | Medium |
| 13 | **Celebrate consistency, not intensity** (weekly "3 of 3 planned", "2nd strength day", "150 min reached"; not strain totals) | Rewards that are informational and immediate support intrinsic motivation; tangible/contingent ones undermine it (Deci 1999; Woolley & Fishbach 2018); strength days ≥ 2/week linked with lower mortality (Momma 2022, already cited in the app) | Moderate | Health: 2 strength days + 150 min; muscle: sets; endurance: minutes | Small |
| 14 | **How did it feel?** after each workout (1–5 pleasant) and let the planner favour what the user enjoys | Affect during/after exercise predicts future activity (Rhodes & Kates 2015); pleasure drops above the ventilatory threshold for most people (Ekkekakis 2011) | Moderate | Endurance: keep most cardio easy; muscle: rest-time and exercise choice | Small |
| 15 | **Weigh-in guidance by goal**: daily for lose/gain with the trend shown and readings hidden by default; weekly for maintain; off switch and an "I'd rather not see calories" mode | Frequent self-weighing associated with better weight control and few psychological harms in most studies (Zheng 2015); daily weighing RCT (Steinberg 2015); calorie counting and fitness tracking correlate with eating-disorder symptoms in some users (Simpson & Mazzeo 2017; Levinson 2017) | Moderate | Lose/gain only | Small |
| 16 | **Calorie framing as a weekly budget band**, "on track" instead of "Over" in red; protein first for muscle/gain | Same eating-disorder evidence; self-monitoring of diet works but burden and judgement reduce adherence (Burke 2011; Patel 2021) | Weak–moderate | Lose: weekly deficit band; gain: surplus band; maintain: hide by default | Small |
| 17 | **Temptation bundling** suggestion for cardio ("save the podcast/series for the bike") | Bundling raised gym attendance (Milkman 2014) | Weak | Endurance/health | Small |
| 18 | **Sleep: insomnia screen and CBT-I components** (if efficiency < 85% for 2+ weeks: fixed wake time, stimulus control, pointer to dCBT-I); hide sleep stages by default | Digital CBT-I: sleep efficiency +20% vs +6% TAU, d = 0.95 (Espie 2012); n = 3,755 (Freeman 2017) and n = 1,711 (Espie 2019) trials; non-inferior to face-to-face (Soh 2020); NICE MTG70; tracker-driven sleep anxiety, "orthosomnia" (Baron 2017) | Strong (CBT-I); weak (orthosomnia) | Same for all goals | Medium |
| 19 | **Optional accountability share** (weekly summary to one person) | Monitoring effects larger when progress is reported to someone (Harkin 2016); social comparison beat social support in one RCT (Zhang 2016) | Weak–moderate | Any | Large (skip for v1) |
| 20 | **Do not add badges, points, leagues or loss-framed streaks** | Gamification g = 0.23 vs active control, g = 0.15 at follow-up (Mazeas 2022); quality of evidence low (Johnson 2016); undermining effect (Deci 1999) | Moderate (against) | — | None |

## 1. Theory and evidence base

### Self-determination theory (SDT)
Teixeira et al. 2012 [V] reviewed 66 studies of exercise and SDT. Autonomous
motivation (doing it because it matters to you or you enjoy it) consistently
predicted exercise. Identified regulation ("it's important to me") predicted
*starting*; intrinsic motivation ("I enjoy it") predicted *long-term adherence*.
Body-shape and appearance motives, and introjected regulation (guilt, pressure),
were mixed or unhelpful. Ntoumanis et al. 2021 [V] pooled 73 SDT-based health
interventions: small-to-medium effects on motivation and behaviour, and the
behaviour change was carried by increases in need support and autonomous
motivation, not by controlled motivation. Teixeira et al. 2020 [M] list the
techniques: offer meaningful choice, give a rationale, acknowledge feelings,
use non-controlling language, avoid rewards and guilt, help the person set
their own goals, provide competence feedback.

What it means for an app: the coach's job is to help the user own the plan,
not to push. "You're 18% short of today's target" is controlling feedback;
"Here are two sessions that fit today; which do you fancy?" is need-supportive.

### Habit formation
Lally et al. 2010 [V]: 96 people repeated a new daily behaviour for 84 days;
automaticity rose along a plateauing curve, median 66 days to asymptote (range
18 to a modelled 254). Exercise habits formed about 1.5× slower than eating or
drinking ones. Missing a single day did not derail the process; frequent
inconsistency did. Gardner et al. 2012 [M] and Gardner 2015 [M]: habits are
cue-response links, so the app should help the user attach training to a stable
cue (time, place, after-work routine) and keep the *initiation* of the session
(getting to the gym) as the habit, since the session content can vary.

### Implementation intentions and planning
Gollwitzer & Sheeran 2006 [V]: 94 tests, d = 0.65 for "if situation X, then I
do Y" plans against goal intentions alone. Bélanger-Gravel 2013 [V]: 26 studies
in physical activity, d = 0.31 post-intervention and 0.24 at follow-up. The 2024
update (Sheeran, Listrom & Gollwitzer, 642 tests; via secondary summary [V])
found d = 0.27–0.66 across outcomes, better with explicit if-then format, high
motivation and rehearsal. Stadler, Oettingen & Gollwitzer 2009 [M]: a one-off
mental-contrasting-plus-if-then session roughly doubled women's weekly
activity, sustained over 4 months. Sniehotta et al. 2005 [M] separate *action
planning* (when, where, how) from *coping planning* (what if it goes wrong);
coping planning predicted maintenance in cardiac-rehab patients. Rhodes & de
Bruijn 2013 [M]: about 46% of people who intend to exercise don't; planning is
the main tool for closing that gap.

### Goal setting
Locke & Latham 2002 [M]: specific, challenging goals beat "do your best" when
the person is committed, gets feedback and has the ability. McEwan et al. 2016
[V]: 52 goal-setting interventions in physical activity, n = 5,912, d = 0.55.
But Swann et al. 2021 [M] argue that SMART-style specific goals suit people who
already train and can backfire for inactive or low-confidence people, for whom
open goals ("see how far you can walk") and learning goals do better. For a
lifter who already trains, specific weekly goals are fine; the risk is daily
*outcome* goals he cannot control (a strain number) rather than *behaviour*
goals he can (three sessions, protein target).

### Self-monitoring, feedback and prompts
Michie et al. 2009 [V]: 122 evaluations, 44,747 participants; self-monitoring
explained the most between-study variance, and interventions that combined it
with at least one other self-regulation technique (goal setting, feedback,
review of goals, prompting intention formation) had effect 0.42 vs 0.26.
Michie et al. 2013 [M] formalised the 93-technique taxonomy (BCTTv1); the
"self-regulation cluster" (goals, planning, monitoring, feedback, review)
recurs in every effective digital intervention. Burke, Wang & Sevick 2011 [V]:
22 studies, consistent association between self-monitoring and weight loss,
evidence judged weak for methodological reasons. Patel, Wakayama & Bennett 2021
[V]: 39 trials, 67 digital self-monitoring interventions; greater digital
self-monitoring was associated with weight loss in 74% of comparisons, but few
programmes achieved ≥ 75% days logged, so burden is the limiting factor.
Harkin et al. 2016 [V]: 138 experiments, n = 19,951; prompting progress
monitoring raised goal attainment d = 0.40, more when progress was physically
recorded or reported to others. Samdal et al. 2017 [M]: in overweight adults,
goal setting, self-monitoring and feedback were linked with effects, and goal
review and graded tasks with maintenance at follow-up.

Tensile's data pipeline (HealthKit, Cronometer, Garmin, check-ins) is
self-monitoring with almost no logging burden, which is the ideal case. What
the literature adds is the *loop*: goal → plan → monitor → feedback → review →
new goal.

### Social support and accountability
Harkin 2016 [V]: public reporting of progress increases the monitoring effect.
Zhang et al. 2016 [V] (RCT, 790 students, 11 weeks): social *comparison*
networks raised exercise-class attendance more than supportive networks, and
support alone did no better than control. Noom-style human coaching and group
chat have never been isolated in a trial. For a single-user app this is
optional; an "export weekly summary to a friend/coach" is the cheapest form.

### Relapse prevention and identity
Marlatt & Gordon 1985 [M]: a lapse becomes a relapse when the person reads it
as proof of failure (abstinence-violation effect). Semenchuk, Strachan &
Fortier 2018 [M]: people higher in self-compassion reported more adaptive
reactions and intentions after a recalled exercise setback. Kwasnicka et al.
2016 [M] (review of 100 theories): maintenance rests on five things:
motives that are the person's own, self-regulation skills, psychological and
physical resources, habit, and a supportive environment. Rhodes, Kaushal &
Quinlan 2016 [V]: exercise identity correlates with behaviour r = 0.44; Rhodes
et al. 2024 [V, abstract]: interventions shift identity g = 0.18, and in the 30
studies that also measured activity, g = 0.61. Clear's "identity-based habits"
(Atomic Habits, 2018) is a popularisation of this; the research version is
"act consistently, then let the self-view follow".

## 2. Digital interventions

### Just-in-time adaptive interventions and prompts
Nahum-Shani et al. 2018 [V] set out the JITAI framework: decision points,
tailoring variables, intervention options, and the principle that support
should arrive when the person is vulnerable *and* receptive. Klasnja et al. 2019
[V] (HeartSteps micro-randomised trial, 44 adults, 6 weeks): contextually
tailored walking suggestions raised 30-minute step counts by 107% at the start
and 14% averaged over the study, the decay attributed to habituation and burden.
Lesson: prompts work, but each one spends attention; send few, send them at a
moment the user can act, and stop when they are ignored. Bidargaddi et al. 2018
[M] (micro-randomised trial of push notifications): a prompt increased app
engagement in the following hours, with timing effects (mid-day and weekends
stronger in their sample). Morrison et al. 2017 [M] found no advantage of
"intelligent" timing over fixed times for a stress app, so timing should follow
the user's own planned slots rather than clever inference. Muench & Baumel 2017
[M] give a practical taxonomy of digital triggers (who, what, when, how often)
and warn about notification fatigue. Schembre et al. 2018 [M] review
just-in-time feedback for diet and activity: feedback is most useful when tied
to an action the user can take right then.

### Gamification, streaks, rewards and incentives
Johnson et al. 2016 [V]: 19–21 studies; 59% positive, 41% mixed, quality mostly
moderate or lower, few comparisons against a non-gamified version. Mazeas et al.
2022 [V]: 16 RCTs, n = 2,407, g = 0.42 overall, g = 0.23 against active
controls, g = 0.15 at ~14-week follow-up. Streaks: Silverman & Barasch 2023 [V]
(7 studies) show that *displaying* an intact streak increases later engagement
and displaying a broken one decreases it, independent of actual behaviour;
the drop is bigger when the user blames himself and smaller when the streak can
be repaired. That is the "broken streak" dropout problem, and it is why
Duolingo sells streak freezes. Rewards: Deci, Koestner & Ryan 1999 [V] (128
experiments): expected, tangible, performance-contingent rewards undermine
intrinsic motivation; positive verbal feedback enhances it. Woolley & Fishbach
2018 [M]: rewards that arrive *during* the activity (immediate, intrinsic to
it) increase persistence, delayed ones do not. Financial incentives: Mitchell
et al. 2020 [V] (23 RCTs, n = 6,074): +607 steps/day during incentives, +514
after in the pooled estimate, but only 4 of 18 studies showed a post-incentive
benefit by vote count. Patel et al. 2016 [M] (RCT): a loss-framed incentive
raised step-goal attainment (about 45% vs 30% of days) while gain-framed and
lottery incentives did not differ from control. Social comparison: Zhang 2016
above. Personalised vs generic messages: Noar, Benac & Harris 2007 [M] (57
studies) found tailored print messages work better than generic ones, with a
small overall effect; Laranjo 2021 [V] found text messaging and personalisation
features were the moderators that mattered in app trials.

### Apps for physical activity, weight and sleep
Romeo et al. 2019 [V]: 9 RCTs, +477 steps/day (not significant); shorter
(< 3-month) programmes and activity-only apps did better. Gal et al. 2018 [V]
(Sports Medicine – Open, not Preventive Medicine Reports): 18 RCTs, SMD 0.43 for
MVPA minutes and 0.51 for steps, high heterogeneity. Laranjo et al. 2021 [V]:
28 RCTs, n = 7,454, SMD 0.35 ≈ +1,850 steps/day over a mean 13 weeks. Flores
Mateo et al. 2015 [V]: 12 studies, −1.04 kg and −0.43 BMI vs control; activity
effect not significant. Self-weighing: Zheng et al. 2015 [V, title/journal
confirmed] (17 longitudinal studies) found frequent self-weighing associated
with better weight outcomes and, in most studies, no adverse psychological
effects; Steinberg et al. 2015 [M] (RCT) found daily weighing with trend
feedback improved weight loss and weight-control behaviours. Sleep: Sleepio's
digital CBT-I has the strongest evidence of any consumer sleep app: Espie 2012
[V] (n = 164; sleep efficiency +20% vs +6% treatment as usual, d = 0.95),
Freeman 2017 [V] (n = 3,755), Espie 2019 [M] (n = 1,711; better functional
health, wellbeing and sleep-related quality of life), Soh 2020 [V, via NICE]
non-inferior to face-to-face CBT-I, NICE MTG70 [V]. That evidence is for
*insomnia*, not for sleep scores in healthy people; for the latter there is no
trial showing a sleep score improves sleep, and Baron et al. 2017 [M] describe
patients made anxious by tracker data ("orthosomnia"). Draganich & Erdal 2014
[M] showed that telling people their sleep was poor (falsely) worsened their
cognitive test performance: sleep feedback carries a nocebo risk.

### AI coaching chat
Fitzpatrick et al. 2017 [V] (Woebot, n = 70, 2 weeks): CBT chatbot reduced
PHQ-9 depression vs an information control. Stein & Brooks 2017 [V] (Lark):
uncontrolled observational study, 2.38% weight loss over ~15 weeks, high
session counts. Noom: Chin et al. 2016 [V] is an observational analysis of
about 36,000 self-selected users (78% reported weight loss); Toro-Ramos et al.
2020 [M] is an RCT of Noom's diabetes-prevention programme with greater weight
loss than control. None of these isolate the chat or the "psychology lessons"
component. I could not find, with the searches available this round, a
published RCT of a large-language-model coach for exercise adherence; treat
LLM coaching as plausible but unproven, and judge it by whether it delivers the
techniques above (planning, review, autonomy support, feedback), which do have
evidence.

## 3. What successful apps do, and what the evidence says

| App feature | What it is | Evidence | Verdict for Tensile |
|---|---|---|---|
| Duolingo streaks + streak freeze | Daily-use chain; a purchasable "freeze" protects it | Streak display raises engagement until it breaks; repairability softens the drop (Silverman & Barasch 2023). No health outcome evidence; a learning app with daily units, unlike training with rest days | Don't copy the daily streak. If any chain is shown, make it weekly and self-healing (rec. 4) |
| Gentler Streak | Rest-aware "streak" that doesn't break on rest days; soft language | No published trials; design matches SDT and the forgiving-streak evidence | The right instinct; implement as a consistency score |
| Noom psychology lessons + coach | Daily CBT-flavoured reading, human coach, groups | Company-sponsored observational data and one DPP RCT; lesson content never isolated | Short, optional "why this works" notes in the coach are cheap; don't build a curriculum |
| Strava kudos, segments, clubs | Social comparison and support | Comparison beat support in one RCT (Zhang 2016); no Strava-specific trials | Single-user app: skip, or offer an export to a friend (rec. 19) |
| Whoop journal + monthly report | Behaviour tags correlated with recovery; monthly summary | Tensile already has the journal with better statistics (t-test + FDR). Monthly/weekly reports are a "review of goals" technique with meta-analytic support (Michie 2009) | Build the weekly review (rec. 1) |
| Apple rings and awards | Three daily goals, badges, challenges | Closing-rings adherence data is unpublished; badges are gamification (small, fading effect) | Keep rings as feedback, skip awards |
| Oura readiness nudges | "Your readiness is low, take it easy" | HRV-guided training trials used go/no-go on HRV, not a 0–100 score; no trial of the nudge itself | Keep the HRV-trend logic, change the framing (section 5) |
| Bevel | Scores + journal + coach, similar to Tensile | No published evidence | Nothing to copy beyond what Tensile has |

## 4. Recommendations in detail

### 1. Weekly review and next-week plan (medium)
Sunday evening (or the user's chosen day), a card on Home and a coach message:
what was planned vs done (sessions, protein days, sleep regularity), the one
number per goal that matters (weight trend vs chosen pace; hard sets per muscle;
e1RM trend; zone minutes; strength days and steps), what the check-in patterns
say changed recovery, and then *next week's plan* that the user confirms or
edits: which days, which sessions, one habit to keep. Keep it to one screen.
This is the goal → monitor → review → re-goal loop that Michie 2009 and Samdal
2017 identify, and the new week is a fresh-start landmark (Dai 2014). The coach
system prompt should receive "last week's plan and adherence" in the snapshot so
it can review rather than only advise.

### 2. Pre-committed training days with if-then plans (medium)
In Goals or the weekly review: pick days and times, name the session, and write
the if-then line the app proposes ("If it's Tuesday 6 pm, I go to the gym and do
Upper A. If I miss it, I do it Wednesday 6 pm."). Store the plan; reminders fire
only for planned slots (rec. 8); the morning briefing names the planned session.
Offer optional calendar export. Evidence: Gollwitzer & Sheeran 2006; Bélanger-
Gravel 2013; Stadler 2009; rehearsal matters, so show the plan back in the
morning briefing. Tailor the number of sessions to the goal and to the planner's
deload logic, and let the recovery logic move a session rather than cancel it.

### 3. Coping plans (small)
Ask once, in Goals, for the user's three usual obstacles (late work, sore legs,
travel, low energy, hangover) and store an if-then response for each, some of
which the app can generate from its own data ("sore in legs → upper body",
"low recovery → technique session under X% strain", "hotel → bodyweight
routine"). Show the matching coping plan in the morning briefing when the
condition is detected. Evidence: Sniehotta 2005; Kwasnicka 2016.

### 4. Consistency score instead of a streak (small)
Replace any idea of a daily chain with "On plan: 11 of the last 12 weeks" where
a week counts when ≥ 75% of planned sessions were done (or a minimum version,
rec. 7). Show the rolling 4-week adherence as a simple bar. Never show "streak
broken"; after a missed week show "1 week off; back on plan this week counts".
Evidence: Lally 2010 (single misses don't matter); Silverman & Barasch 2023
(broken-streak display reduces engagement; repairability helps); dos Santos 2022
[M] (weekend-warrior and regular patterns show the same mortality benefit for
the same weekly volume, so the pattern within the week is not what to police).

### 5. Autonomy-supportive coach language (small)
Edit `SYSTEM_PROMPT` in `supabase/functions/coach/index.ts` and
`CoachPrompt.onDeviceInstructions`, and the fixed strings in
`TrainerSuggestions.coachingLine`, `TodayView` (strain goal card) and
`FitnessView.encouragement`. Rules from Teixeira 2020 / Ntoumanis 2021:
offer two options and let the user choose; give the reason in one clause; use
"could" and "you might" over "should" and "need to"; acknowledge the feeling
("sore and short on sleep, so…"); never guilt ("you missed", "you're behind");
praise effort and consistency rather than outcomes; ask before prescribing when
the user hasn't asked for a plan. Concretely, "Your body needs extra care. Keep
it light" becomes "HRV is below your range, so today suits an easy session:
technique work or a Zone 2 ride. Which do you prefer?"; "x% to go: one more
session today will get you there" goes (section 5).

### 6. "Why" and identity check-in (small)
At onboarding and in the monthly review ask "Why does training matter to you
right now?" with options spanning SDT motives (feel strong, health for later,
look better, sport, mood, keep up with kids) and a free line. Pass it to the
coach ("motives") so it can connect advice to it, and show it on relapse
(rec. 11). On the weekly review, state the identity fact: "You've trained at
least twice a week for 14 weeks. That's a person who lifts." Evidence: Teixeira
2012 (identified/intrinsic predict adherence; appearance motives mixed); Rhodes
2016/2024. For a weight-loss goal, gently steer motive language from appearance
to capability and health, since appearance motives predicted dropout in several
Teixeira studies.

### 7. Minimum session and open goals (small)
Every planned session gets a "short version" the planner can produce (two
compound lifts, 2–3 sets, 15–20 min) and the morning briefing offers it when
recovery is low, the check-in says tired or sore, or the user taps "not today".
On such days the goal is open: "do the short version and see how it feels".
Evidence: Swann 2021 (open goals for low-confidence contexts); Lally 2010 and
Gardner 2012 (the habit is showing up); HRV-guided trials (go easy, not skip).

### 8. Fewer, smarter notifications (medium)
Today the app can send four or more a day (HRV reminder, morning check-in,
evening check-in, medication doses). Merge HRV entry into the morning check-in
notification; one morning and one evening prompt, both suppressed if already
done (partly implemented); a workout reminder 30–60 minutes before a planned
slot only; no reminders on unplanned days; if two consecutive prompts of a kind
are ignored, halve their frequency and say so in Settings; a weekly-review
prompt on the chosen evening. Use context the app already has (rest mode,
illness, travel by location change, sleep debt) to change the *content*, not to
send more. Evidence: Nahum-Shani 2018; Klasnja 2019 (decay); Bidargaddi 2018;
Muench & Baumel 2017; Morrison 2017 (fixed, user-chosen times are as good as
inferred ones).

### 9. Morning briefing (medium)
One card at the top of Home after the morning check-in: planned session (or
coping plan if the condition fired), the recovery reading in plain words
("HRV within your range; sleep 6 h 50"), one line of advice, and two buttons
(planned session / short version). No target percentage, no "to go". Evidence:
action planning and autonomy support above. Tailor the two options to goal and
gym.

### 10. Evening reflection and small wins (small)
Add one optional line to the evening check-in: "One thing that went well
today" (free text or quick picks the app can prefill: hit protein, trained as
planned, in bed on time, PR). Show the week's wins in the weekly review.
Evidence: Harkin 2016 (recording progress); Koo & Fishbach 2012 [M] (focus on
progress made early in a goal, on distance remaining when close); Saw 2016
(mood as an early overtraining marker, already in the morning check-in).

### 11. Relapse path (medium)
If no logged session or Garmin workout for 7 days and the user isn't in rest
mode or sick: a single kind notification ("Life happens. Want a lighter week to
get going again?"), and on opening the app a "Welcome back" card: no summary of
what was missed, a short restart plan (two short sessions this week, loads at
85–90% of last), a note that strength and VO₂max fall little in 2–3 weeks off
(Mujika & Padilla 2000 [M]), the user's own "why" (rec. 6), and a fresh-start
framing ("new week, new block"). Coach prompt: on return, do not list what was
missed; ask what got in the way and propose the smaller plan. Evidence: Marlatt
& Gordon 1985; Semenchuk 2018; Dai 2014.

### 12. Progress views that survive plateaus (medium)
Weight: show the trend line and the chosen-pace corridor, hide daily readings
by default, and when the trend is flat for 3+ weeks on a lose goal, say that
plateaus are normal and offer the two evidence-based moves (re-measure
maintenance from the logged data, which the app already does; or hold for a
diet break). Lifts: smoothed e1RM with "best 4-week average" rather than the
single peak; mark deload weeks so a dip reads as planned. Add process metrics
beside every outcome: sessions done, hard sets per muscle, zone-2 minutes,
protein days. Evidence: Michie 2013 (feedback on behaviour); Kivetz 2006 and
Koo & Fishbach 2012 [M] (people accelerate as they see progress toward a
goal); Zheng 2015 and Steinberg 2015 (trend feedback).

### 13. Celebrate consistency, not intensity (small)
What the app praises becomes what the user chases. Praise lines and weekly-
review highlights should name consistency (planned sessions done, second
strength day, 150 minutes, protein days, bedtime regularity) and skill (RPE
accuracy, technique session done on a low day). Keep strain as information.
Evidence: Deci 1999 (informational praise supports intrinsic motivation);
Woolley & Fishbach 2018; Momma 2022 and WHO 2020 already in the app.

### 14. "How did it feel?" (small)
After the workout summary, one 1–5 "pleasant–unpleasant" rating beside the
existing session RPE. Over weeks, let the planner prefer exercises and session
styles the user rates as pleasant, and keep most cardio prescriptions easy
unless the goal is endurance. Evidence: Rhodes & Kates 2015 [M] (affect during
exercise predicts later behaviour); Ekkekakis et al. 2011 [M].

### 15–16. Weight and calorie framing by goal (small)
Lose/gain: daily weigh-in encouraged, trend shown, readings hidden by default,
weekly change vs chosen pace; a "Pause weight tracking" switch. Maintain:
weekly. Calories: show a weekly budget band ("about 1,400 kcal under
maintenance this week, in the 1,000–2,000 band") rather than a daily "Over" in
red; protein first for muscle/gain goals. Add a "Hide calories" setting that
keeps protein and the energy-balance trend but removes the daily number.
Evidence: Zheng 2015; Steinberg 2015 [M]; Simpson & Mazzeo 2017 [M] and
Levinson 2017 [M] (calorie counting and fitness tracking associated with
eating-disorder symptoms in some users); Burke 2011 and Patel 2021 (adherence to
diet logging is the bottleneck, so reduce judgement and burden).

### 17. Temptation bundling (small)
One line in the endurance/health coaching: "keep a series or podcast for the
bike." Milkman, Minson & Volpp 2014 [M] found gym attendance rose when an
audiobook was available only at the gym. Weak evidence, zero cost.

### 18. Sleep: insomnia screen, CBT-I components, hide stages (medium)
If sleep efficiency has been under 85% or sleep-onset over 30 minutes for two
weeks, show a card: fixed wake time seven days a week, bed only when sleepy, up
if awake 20+ minutes, no clock-watching, and a pointer to digital CBT-I (NICE-
recommended). Otherwise keep the sleep score simple, show stages only on tap
with the "estimate" label (already done), and never call a night "poor" in red.
Evidence: Espie 2012 [V]; Freeman 2017 [V]; Espie 2019 [M]; Soh 2020 and NICE
MTG70 [V]; Baron 2017 [M]; Draganich & Erdal 2014 [M].

### 19. Optional accountability share (large, defer)
Export the weekly review as an image or text to send to a friend or a coach.
Harkin 2016 (reporting to others strengthens monitoring); Zhang 2016. Low
priority for a single-user app.

### 20. Don't build gamification (none)
No badges, points, leagues or loss-framed streaks: Mazeas 2022 (g = 0.15 at
follow-up), Johnson 2016 (low quality), Deci 1999, Silverman & Barasch 2023.
The rings and the consistency score are enough feedback.

## 5. What the app does now that may backfire

| Now | Where | Why it may backfire | Change |
|---|---|---|---|
| **"x% to go" chip, "Suggested to close the gap", "one more session today will get you there"** | `TodayView` StrainGoalCard, `FitnessView.encouragement` | A daily outcome target the user can't fully control, framed as a deficit; invites a second session to "hit the number", which is strain-chasing. HRV-guided training evidence supports "train as planned / go easy", not a daily load quota (see `docs/research/strain-science.md`, row 16). Controlling feedback lowers autonomous motivation (Ntoumanis 2021); specific outcome targets can backfire (Swann 2021) | Show the target band as information ("today's range"), make the planned session the goal, and never suggest a second session to close a gap. Move the "closing the gap" suggestions behind a "What else could I do?" tap |
| **Recovery ring red at < 34 with the label "Low"**; coaching line "Your body needs extra care" | `Theme.recoveryColors`, `TodayView`, `coachingLine` | Red + "low" is a stop sign and a diagnosis the score can't support (the 0–100 number is the app's own summary). Negative sleep/recovery feedback has measurable nocebo effects (Draganich & Erdal 2014) and tracker anxiety is documented (Baron 2017). It also pushes toward skipping rather than going easy | Relabel as "Easy day" / "Steady" / "Go"; use a cool colour (blue/teal) for easy days rather than red; keep red for illness watch only. Keep the plain-words HRV line |
| **"Over = eaten − daily target"**, daily calories left | `TodayView` energy card | Daily deficit framing and "over" judgement; for some users calorie tracking correlates with eating-disorder symptoms (Simpson & Mazzeo 2017; Levinson 2017). Daily numbers are noisy; the weekly balance is what moves weight | Weekly budget band, "on track" wording, hide-calories option; protein first for muscle/gain |
| **Target reached: "Anything more is a bonus"** | `FitnessView` | "Bonus" implies more strain is better | "Anything more is optional" (the Home card already says this) |
| **Up to four notifications a day** (HRV, morning, evening, doses) with fixed daily cadence | `Reminders.swift` | Habituation and burden decay the effect (Klasnja 2019); notification fatigue (Muench & Baumel 2017) | Merge HRV into the morning check-in, reminders only on planned days, back off when ignored |
| **"Weight is changing fast"** warning in Daily habits | `HabitsCard` | Good content (Helms 2014) but it sits beside caffeine and protein as a daily "habit"; on a gain goal it can read as a scold | Move it to the weekly review with the pace corridor |
| **Body age** with a headline number | Biology | Spiegelhalter-style "effective age" is persuasive but is a nocebo risk when it is older than chronological age and when the inputs are estimates; evidence that it changes behaviour is from one-off communication studies, not apps | Lead with the trend and the two biggest movers; keep the number secondary and labelled with its confidence (partly done) |
| **Sleep score with stage share** | Sleep sheet | Stage data from a wrist is rough (already weighted at 10% and labelled); showing a nightly "deep sleep" number still invites orthosomnia | Stages behind a tap; score narrative in plain words |
| **Coach prompt: "Lead with the recommendation"** | `index.ts` | Fine for questions, but on its own it produces directive advice in every reply | Add the autonomy-support rules (rec. 5): offer a choice, give the reason, ask when unsure, never guilt |

## 6. Suggested order of work

1. Text and prompt changes (recs 5, 13, section 5 rows 1–4, 9): a day.
2. Consistency score, minimum session, "how did it feel", motives field, evening
   win (recs 4, 6, 7, 10, 14): a few days, mostly `AppCore` + small cards.
3. Pre-committed days + coping plans + notification rework (recs 2, 3, 8): a
   week; new `TrainingPlan` model, reminder scheduling off the plan.
4. Weekly review + morning briefing + relapse path (recs 1, 9, 11): a week;
   they share one summary model and the coach snapshot gets `plan`, `adherence`
   and `motives` fields.
5. Weight/calorie framing and sleep card (recs 12, 15, 16, 18): a few days.
6. Skip 17 unless free; defer 19; never 20.

## References

[V] = verified this round by web search; [M] = cited from memory, not
re-verified this round (search budget exhausted, PubMed unreachable from the
sandbox). Check [M] entries before quoting their numbers in the app.

- Baron KG, Abbott S, Jao N, Manalo N, Mullen R. Orthosomnia: are some patients taking the quantified self too far? J Clin Sleep Med 2017;13(2):351–354. [M]
- Bélanger-Gravel A, Godin G, Amireault S. A meta-analytic review of the effect of implementation intentions on physical activity. Health Psychol Rev 2013;7(1):23–54. [V]
- Bidargaddi N, et al. To prompt or not to prompt? A microrandomized trial of time-varying push notifications to increase proximal engagement with a mobile health app. JMIR Mhealth Uhealth 2018;6(11):e10123. [M]
- Burke LE, Wang J, Sevick MA. Self-monitoring in weight loss: a systematic review of the literature. J Am Diet Assoc 2011;111(1):92–102. [V]
- Chin SO, et al. Successful weight reduction and maintenance by using a smartphone application in those with overweight and obesity. Sci Rep 2016;6:34563. [V]
- Dai H, Milkman KL, Riis J. The fresh start effect: temporal landmarks motivate aspirational behavior. Manag Sci 2014;60(10):2563–2582. [V]
- Deci EL, Koestner R, Ryan RM. A meta-analytic review of experiments examining the effects of extrinsic rewards on intrinsic motivation. Psychol Bull 1999;125(6):627–668. [V]
- dos Santos M, et al. Association of the "weekend warrior" and other leisure-time physical activity patterns with all-cause and cause-specific mortality. JAMA Intern Med 2022;182(8):840–848. [M]
- Draganich C, Erdal K. Placebo sleep affects cognitive functioning. J Exp Psychol Learn Mem Cogn 2014;40(3):857–864. [M]
- Ekkekakis P, Parfitt G, Petruzzello SJ. The pleasure and displeasure people feel when they exercise at different intensities. Sports Med 2011;41(8):641–671. [M]
- Espie CA, et al. A randomized, placebo-controlled trial of online cognitive behavioral therapy for chronic insomnia disorder delivered via an automated media-rich web application. Sleep 2012;35(6):769–781. [V]
- Espie CA, et al. Effect of digital cognitive behavioral therapy for insomnia on health, psychological well-being, and sleep-related quality of life: a randomized clinical trial. JAMA Psychiatry 2019;76(1):21–30. [M]
- Fitzpatrick KK, Darcy A, Vierhile M. Delivering cognitive behavior therapy to young adults with symptoms of depression and anxiety using a fully automated conversational agent (Woebot): a randomized controlled trial. JMIR Ment Health 2017;4(2):e19. [V]
- Flores Mateo G, Granado-Font E, Ferré-Grau C, Montaña-Carreras X. Mobile phone apps to promote weight loss and increase physical activity: a systematic review and meta-analysis. J Med Internet Res 2015;17(11):e253. [V]
- Freeman D, et al. The effects of improving sleep on mental health (OASIS): a randomised controlled trial with mediation analysis. Lancet Psychiatry 2017;4(10):749–758. [V]
- Gal R, May AM, van Overmeeren EJ, Simons M, Monninkhof EM. The effect of physical activity interventions comprising wearables and smartphone applications on physical activity: a systematic review and meta-analysis. Sports Med Open 2018;4:42. [V]
- Gardner B. A review and analysis of the use of "habit" in understanding, predicting and influencing health-related behaviour. Health Psychol Rev 2015;9(3):277–295. [M]
- Gardner B, Lally P, Wardle J. Making health habitual: the psychology of "habit-formation" and general practice. Br J Gen Pract 2012;62(605):664–666. [M]
- Gollwitzer PM, Sheeran P. Implementation intentions and goal achievement: a meta-analysis of effects and processes. Adv Exp Soc Psychol 2006;38:69–119. [V]
- Harkin B, et al. Does monitoring goal progress promote goal attainment? A meta-analysis of the experimental evidence. Psychol Bull 2016;142(2):198–229. [V]
- Johnson D, Deterding S, Kuhn KA, Staneva A, Stoyanov S, Hides L. Gamification for health and wellbeing: a systematic review of the literature. Internet Interv 2016;6:89–106. [V]
- Kivetz R, Urminsky O, Zheng Y. The goal-gradient hypothesis resurrected. J Mark Res 2006;43(1):39–58. [M]
- Klasnja P, et al. Efficacy of contextually tailored suggestions for physical activity: a micro-randomized optimization trial of HeartSteps. Ann Behav Med 2019;53(6):573–582. [V]
- Koo M, Fishbach A. The small-area hypothesis: effects of progress monitoring on goal adherence. J Consum Res 2012;39(3):493–509. [M]
- Kwasnicka D, Dombrowski SU, White M, Sniehotta F. Theoretical explanations for maintenance of behaviour change: a systematic review of behaviour theories. Health Psychol Rev 2016;10(3):277–296. [M]
- Lally P, van Jaarsveld CHM, Potts HWW, Wardle J. How are habits formed: modelling habit formation in the real world. Eur J Soc Psychol 2010;40(6):998–1009. [V]
- Laranjo L, et al. Do smartphone applications and activity trackers increase physical activity in adults? Systematic review, meta-analysis and metaregression. Br J Sports Med 2021;55(8):422–432. [V]
- Levinson CA, Fewell L, Brosof LC. My Fitness Pal calorie tracker usage in the eating disorders. Eat Behav 2017;27:14–16. [M]
- Locke EA, Latham GP. Building a practically useful theory of goal setting and task motivation: a 35-year odyssey. Am Psychol 2002;57(9):705–717. [M]
- Marlatt GA, Gordon JR (eds). Relapse Prevention. Guilford, 1985. [M]
- Mazeas A, Duclos M, Pereira B, Chalabaev A. Evaluating the effectiveness of gamification on physical activity: systematic review and meta-analysis of randomized controlled trials. J Med Internet Res 2022;24(1):e26779. [V]
- McEwan D, et al. The effectiveness of multi-component goal setting interventions for changing physical activity behaviour: a systematic review and meta-analysis. Health Psychol Rev 2016;10(1):67–88. [V]
- Michie S, Abraham C, Whittington C, McAteer J, Gupta S. Effective techniques in healthy eating and physical activity interventions: a meta-regression. Health Psychol 2009;28(6):690–701. [V]
- Michie S, et al. The behavior change technique taxonomy (v1) of 93 hierarchically clustered techniques. Ann Behav Med 2013;46(1):81–95. [M]
- Milkman KL, Minson JA, Volpp KGM. Holding the Hunger Games hostage at the gym: an evaluation of temptation bundling. Manag Sci 2014;60(2):283–299. [M]
- Mitchell MS, et al. Financial incentives for physical activity in adults: systematic review and meta-analysis. Br J Sports Med 2020;54(21):1259–1268. [V]
- Morrison LG, et al. The effect of timing and frequency of push notifications on usage of a smartphone-based stress management intervention: an exploratory trial. PLoS One 2017;12(1):e0169162. [M]
- Muench F, Baumel A. More than a text message: dismantling digital triggers to curate behavior change in patient-centered health interventions. J Med Internet Res 2017;19(5):e147. [M]
- Mujika I, Padilla S. Detraining: loss of training-induced physiological and performance adaptations. Part I: short term insufficient training stimulus. Sports Med 2000;30(2):79–87. [M]
- Nahum-Shani I, et al. Just-in-time adaptive interventions (JITAIs) in mobile health: key components and design principles for ongoing health behavior support. Ann Behav Med 2018;52(6):446–462. [V]
- NICE. Sleepio to treat insomnia and insomnia symptoms. Medical technologies guidance MTG70, 2022. [V]
- Noar SM, Benac CN, Harris MS. Does tailoring matter? Meta-analytic review of tailored print health behavior change interventions. Psychol Bull 2007;133(4):673–693. [M]
- Ntoumanis N, et al. A meta-analysis of self-determination theory-informed intervention studies in the health domain: effects on motivation, health behavior, physical, and psychological health. Health Psychol Rev 2021;15(2):214–244. [V]
- Patel ML, Wakayama LN, Bennett GG. Self-monitoring via digital health in weight loss interventions: a systematic review among adults with overweight or obesity. Obesity 2021;29(3):478–499. [V]
- Patel MS, et al. Framing financial incentives to increase physical activity among overweight and obese adults: a randomized, controlled trial. Ann Intern Med 2016;164(6):385–394. [M]
- Rhodes RE, de Bruijn GJ. How big is the physical activity intention–behaviour gap? A meta-analysis using the action control framework. Br J Health Psychol 2013;18(2):296–309. [M]
- Rhodes RE, Kates A. Can the affective response to exercise predict future motives and physical activity behavior? A systematic review of published evidence. Ann Behav Med 2015;49(5):715–731. [M]
- Rhodes RE, Kaushal N, Quinlan A. Is physical activity a part of who I am? A review and meta-analysis of identity, schema and physical activity. Health Psychol Rev 2016;10(2):204–225. [V]
- Rhodes RE, et al. Intervention effects on physical activity identity: a systematic review and meta-analysis. Health Psychol Rev 2024 (doi 10.1080/17437199.2024.2412996). [V, abstract]
- Romeo A, et al. Can smartphone apps increase physical activity? Systematic review and meta-analysis. J Med Internet Res 2019;21(3):e12053. [V]
- Samdal GB, Eide GE, Barth T, Williams G, Meland E. Effective behaviour change techniques for physical activity and healthy eating in overweight and obese adults; systematic review and meta-regression analyses. Int J Behav Nutr Phys Act 2017;14:42. [M]
- Saw AE, Main LC, Gastin PB. Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures. Br J Sports Med 2016;50(5):281–291. (already cited in `docs/checkin-questions.md`)
- Semenchuk BN, Strachan SM, Fortier M. Self-compassion and the self-regulation of exercise: reactions to recalled exercise setbacks. J Sport Exerc Psychol 2018;40(1):31–39. [M]
- Sheeran P, Listrom O, Gollwitzer PM. Implementation intentions meta-analysis update (642 tests), 2024. [V via secondary summary; locate the journal before citing]
- Silverman J, Barasch A. On or off track: how (broken) streaks affect consumer decisions. J Consum Res 2023;49(6):1095–1117. [V]
- Simpson CC, Mazzeo SE. Calorie counting and fitness tracking technology: associations with eating disorder symptomatology. Eat Behav 2017;26:89–92. [M]
- Sniehotta FF, Scholz U, Schwarzer R. Bridging the intention–behaviour gap: planning, self-efficacy, and action control in the adoption and maintenance of physical exercise. Psychol Health 2005;20(2):143–160. [M]
- Soh HL, Ho RC, Ho CS, Tam WW. Efficacy of digital cognitive behavioural therapy for insomnia: a meta-analysis of randomised controlled trials. Sleep Med 2020;75:315–325. [V via NICE]
- Stadler G, Oettingen G, Gollwitzer PM. Physical activity in women: effects of a self-regulation intervention. Am J Prev Med 2009;36(1):29–34. [M]
- Stein N, Brooks K. A fully automated conversational artificial intelligence for weight loss: longitudinal observational study among overweight and obese adults. JMIR Diabetes 2017;2(2):e28. [V]
- Steinberg DM, Bennett GG, Askew S, Tate DF. Weighing every day matters: daily weighing improves weight loss and adoption of weight control behaviors. J Acad Nutr Diet 2015;115(4):511–518. [M]
- Swann C, et al. Updating goal-setting theory in physical activity promotion: a critical conceptual review. Health Psychol Rev 2021;15(1):34–50. [M]
- Teixeira PJ, Carraça EV, Markland D, Silva MN, Ryan RM. Exercise, physical activity, and self-determination theory: a systematic review. Int J Behav Nutr Phys Act 2012;9:78. [V]
- Teixeira PJ, et al. A classification of self-determination theory-based techniques for health behavior change. Motiv Sci 2020;6(4):438–455. [M]
- Toro-Ramos T, et al. Mobile delivery of the Diabetes Prevention Program in people with prediabetes: randomized controlled trial. JMIR Mhealth Uhealth 2020;8(7):e17842. [M]
- Woolley K, Fishbach A. It's about time: earlier rewards increase intrinsic motivation. J Pers Soc Psychol 2018;114(6):877–890. [M]
- Zhang J, Brackbill D, Yang S, Becker J, Herbert N, Centola D. Support or competition? How online social networks increase physical activity: a randomized controlled trial. Prev Med Rep 2016;4:453–458. [V] (2016, not 2015)
- Zheng Y, et al. Self-weighing in weight management: a systematic literature review. Obesity 2015;23(2):256–265. [V, title/journal; author list not confirmed]
