# Funny workout reminders (November 2026)

The owner asked for reminders "that are unique based on your data and encourage
you to work out while being funny", and that don't repeat. This is the research
behind what was built, the design, the guardrails, and what to tune after real use.

**In one paragraph.** The workout reminder that already existed (one per planned
session, 30 minutes before) now carries a line written from the day's own data,
in one of eight comic registers, from a library of 208 playful lines (plus 41
plain ones). No notification was added. A line never comes back within 60
reminders when anything else fits; the same register, opening or prop is never
used twice running. On a low-recovery, ill, painful, rest-mode or rest day the
reminder is plain and kind and does not push. When Apple Intelligence is on,
the on-device model writes about every other line, checked by the same rules;
nothing leaves the iPhone. What rests on evidence is the rotation, the
restraint and the guardrails. That the lines are *funny* is the owner's
preference: no study shows funny reminders get anyone to the gym.

Code: `Packages/AppCore/Sources/AppCore/WorkoutBanter*.swift` (rules, lines,
checks, tests in `WorkoutBanterTests`), `App/Services/WorkoutVoice*.swift`
(facts, saved lines, on-device model), `Reminders.scheduleWorkoutReminders`.

## 1. What the research says

How each source was checked is marked: **[F]** full text read, **[A]** abstract
or the publisher's summary read, **[S]** only a search-result summary seen (not
re-verified), **[D]** taken from this repo's earlier research docs (not
re-verified here).

### 1.1 How Duolingo picks and rotates reminders

Yancey & Settles, *A Sleeping, Recovering Bandit Algorithm for Optimizing
Recurring Notifications*, KDD 2020 **[F]**:

- Reminders are hand-written templates with slots for the user's own data
  ("Continue your 109 day Spanish streak"). Each has eligibility rules (a
  streak of 3+ days, a "streak wager", a stated travel motive), so on a given
  day only some can be sent. That is the "sleeping" part.
- **Novelty.** Earlier A/B tests showed that *new* templates lifted conversion
  even when they were no better in the long run. So a template just shown to a
  user gets a penalty that fades as it is forgotten: score − γ·0.5^(d/h), with
  d days since that user last saw it. They *guessed* the half-life h = 15 days
  ("the recency penalty should mostly decay within the span of a few weeks to
  a month") and fitted γ = 0.017. That is the "recovering" part.
- **The effect is real and small.** Always re-sending the last template cut
  the reward (a lesson within two hours of the reminder) by 0.5% relative to
  random choice; adding the recency penalty to the bandit added about 0.2
  percentage points offline (p < 0.1). The whole algorithm, against random
  choice among eligible templates, gave +0.5% daily active users, +0.4%
  lessons and +2% new-user retention at day 7 in a two-week A/B test.
- They chose recency over counting how often a template was used because it
  is simpler, and say so. Nothing in the paper is about humour or tone.

Duolingo's blog on the same work (Yancey & Settles, 3 Sept 2020) **[A]** puts
it plainly: "we had to explicitly teach the AI algorithm that learners don't
like seeing the same notification too often", with spacing borrowed from the
forgetting curve.

On streaks, Duolingo's own numbers (Yu, *Improving the streak*, 19 Nov 2020)
**[A]**: learners with a 7-day streak are 2.4 times as likely to come back the
next day (a correlation), and letting one lesson keep the streak, whatever the
daily goal, raised day-14 retention by 3.3% in an A/B test. Lowering the bar
for "showing up" helped more than raising the goal. Silverman & Barasch
(J Consum Res 2023) **[D]** found that showing an intact streak raises
engagement and showing a broken one lowers it.

Not verified: the often-quoted "These reminders don't seem to be working.
We'll stop sending them for now." I could not find a primary source for the
wording or the rule behind it, so nothing here relies on it, and the app's
own "going quiet" lines were written without it.

**Taken from this:** slots filled from the user's data; eligibility by fact;
never re-send what was just seen; let a line rest for weeks. **Not taken:**
the bandit (one user gives nothing to learn from), the daily streak (this app
has rest days and deliberately shows no breakable chain; `Consistency`), and
loss-framed streak reminders.

### 1.2 Humour, guilt and tone

- **Humour persuades a little, and mostly attitudes.** Walter, Cody, Xu &
  Murphy (Hum Commun Res 2018) **[A]**: 89 studies, r = .13 on persuasion
  overall, an inverted U (moderate humour beats heavy humour), stronger when
  the joke is related to the message. A systematic review of humour appeals in
  health messages (Health Communication, in press 2026; 62 experiments) **[S]**
  concludes humour can shift attitudes and behaviour but advises against it
  for severe conditions and vulnerable audiences, and notes it helps most with
  people who would otherwise not attend to the message. A small review of
  humour in public-health campaigns (13 studies) **[S]** found better attention
  and recall. **No study of humorous exercise reminders was found.** So:
  humour plausibly earns a glance at the notification; whether it earns a
  workout is unknown.
- **Guilt does not work for health.** Peng, Huang et al., *When guilt works*
  (Front Psychol 2023) **[F]**: guilt appeals have a small effect overall
  (g = 0.19, 26 studies), but in the two health studies the pooled effect was
  −0.01, and the authors write that guilt appeals in health contexts "were
  less effective than the control condition". Effects were weaker where the
  message stressed the person's own responsibility.
- **Controlling language provokes reactance.** Rains (Hum Commun Res 2013)
  **[A]**: across 20 studies reactance is anger plus counter-arguing, and it
  undoes persuasion. A 2026 meta-analysis of freedom-threatening language in
  health messages (Ma, Ebesu & Dillard) **[S]** reaches the same conclusion
  with a modest effect size.
- **Autonomy support: right direction, mixed in single-message experiments.**
  Over months, autonomous motivation predicts exercise adherence and
  guilt/pressure does not (Teixeira et al., IJBNPA 2012; Ntoumanis et al.,
  Health Psychol Rev 2021) **[D]**. But one-off message experiments are mixed:
  a 25,718-person multi-country experiment on distancing messages found
  autonomy-supportive wording lowered defiance yet did not change intentions
  (PNAS 2022; authors and journal from memory) **[S]**, and one 218-person
  study on physical-activity messages found autonomy-supportive language
  *lowered* intention through reactance, less so for people with a high need
  for autonomy (Eur J Health Psychol 2024) **[S]**. So "offer, don't order" is
  the safer default, not a proven booster.
- **After a missed session, kindness.** Self-compassion after an exercise
  setback goes with re-engaging and less rumination (Semenchuk, Strachan &
  Fortier, J Sport Exerc Psychol 2018) **[A]**; little fitness is lost in two
  to three weeks (Mujika & Padilla, Sports Med 2000) **[D]**.
- **Body talk.** Appearance motives go with worse adherence and well-being
  than autonomous ones (Teixeira 2012 **[D]**); weight stigma goes with
  avoiding exercise (Vartanian & Novak, Obesity 2011; **not re-verified**).

### 1.3 Fatigue, frequency and just-in-time prompts

- **HeartSteps**, Klasnja et al. (Ann Behav Med 2019) **[F]**: 37 adults, 6
  weeks, up to five randomised prompts a day. A walking suggestion raised the
  next 30 minutes' steps by 24% on average (p = .02), but by 107% on day 1,
  falling about 3% a day and undetectable by day 29. In exit interviews
  "participants explicitly told us that the suggestions became boring after
  2–4 weeks". The authors blame habituation.
- Bidargaddi et al. (JMIR mHealth 2018) **[A]**: in 1,255 users a tailored
  push raised next-24-hour app use, most at mid-day on weekends. Morrison et
  al. (PLoS One 2017) **[A]**: daily prompts did not put users off, and
  "intelligent" timing did not beat a fixed time. A review of push frequency in
  consumer apps (Wohllebe 2021) **[S]** found use rises with frequency while
  annoyance does too, on self-report data. None of these measured exercise
  over months.

**Taken from this:** a prompt's power decays in weeks whatever it says, so
variety can slow boredom but cannot replace restraint. Hence: no added
notifications, a line tied to a session the owner planned, and going quiet
when reminders go unanswered.

### 1.4 What other fitness apps do

- **CARROT Fit** built a product on insults ("judgmental", "will bad-mouth
  you"); reviewers in 2014–15 either enjoyed it or warned people with a
  history of disordered eating off it **[S]**. It jokes about the person and
  their weight: the opposite of the rule here.
- **Apple's Activity rings**: "You can still do it", "Close your rings". Press
  and users describe pressure and guilt on rest and sick days (Fortune, Jan
  2025) **[S]**; Apple has since added pausing rings and per-day goals.
- **Gentler Streak**: kind, rest-aware wording that users praise, and an App
  Store review that says "I get the same ones every day and grew really bored
  of them" **[S]**. Kind is not enough; it also has to vary.
- **Strong, Hevy, Fitbod** and similar loggers send plain "time for your
  workout" reminders at a fixed time (from use, not verified against current
  versions).

Nobody found does all three: data-specific, varied, and never at the person's
expense. That is the gap this fills.

## 2. The design

### 2.1 The facts (`WorkoutBanter.Facts`, built in `WorkoutVoice`)

| Fact | Where it comes from |
|---|---|
| Session name, length, short version, minutes until it starts | The planned slot (`WeeklyPlanStore.reminderSlots`); named "Leg day", "Push day" |
| Days since the last session | `WeeklyPlanStore.daysOff` |
| Sessions done and planned this week | `WeeklyPlan.Progress` |
| Weeks on plan in a row | `WorkoutBanterFacts.weeksInARow` over `WeekRecord`s (`Consistency.weekKept`) |
| A lift stuck at one weight, or close to its best, with its last top set and the next weight the gym can load | `WorkoutBanterFacts.lift` over the logged sessions (`LiftProgress.points`, `GymProfile.nextLoad`) |
| A muscle group without a set for 7–45 days | `MuscleModel.states`, `WorkoutBanterFacts.neglected` |
| Last session's standout: a record, or the most volume of the last 8 | `PRHistory.events`, `WorkoutBanterFacts.standout` |
| Recovery band, deload week, illness flagged, pain logged, rest mode | The app's own rules (`RecoveryCalculator`, `TrainingBlock`, `IllnessWatch`, `PainGuard`) |
| Hour and weekday of the session, weight unit | The slot and the gym profile |

A reminder for today gets all of it. A reminder written days ahead gets only
what will still be true (the session, the lift, weeks in a row, deload) and is
rewritten once on its own day when that day's data is in.

"Stuck" means three or more sessions at the same top weight over two or more
weeks **with no extra reps**; more reps at the same weight is progress and is
never teased. Weeks in a row are only ever mentioned while the run stands.
These thresholds are app choices about what is worth a joke, not training advice.

### 2.2 The lines (`WorkoutBanterLibrary`)

249 original lines: 208 playful across 21 situations (a planned session, the
short version, near a record, a stuck lift, back after 4–14 days, back after a
long break, start of the week, mid-week count, last of the week, weeks in a
row, a neglected muscle, after a record, after a big session, deload, high
recovery, morning, evening, Monday, Friday, weekend, the last call) and eight
registers (deadpan, absurd, mock-heroic, self-aware app, gym-bro parody,
understatement, bureaucratic notice, nature documentary); 41 plain ones for
the Plain tone and the caution states. Most have slots (`{session}`, `{lift}`,
`{last}`, `{next}`, `{stuckWeeks}`, `{done}`, `{planned}`…); three have none,
so there is always something to send. Weights are written in the owner's unit.

The joke is always on the barbell, the plates, the plan or the app itself.

### 2.3 Choosing (`WorkoutBanter.pick`)

1. Only lines whose situation fits today and whose slots all have a value,
   and that come out between 20 and 160 characters.
2. Within a situation, no line again until every eligible line of that
   situation has been used (kept per situation in the saved history).
3. Nothing used in the last 60 reminders, when anything else fits. Sixty is
   an app choice: four of Yancey & Settles' 15-day half-lives if a reminder
   went out daily, about 15 weeks at four sessions a week.
4. Never the line or the sentence just sent; then, while anything is left, not
   the last register, not the last two opening words, not the last prop (the
   barbell, the plates, the app…), not the last situation.
5. Among what is left, a weighted draw that favours lines using more of the
   day's data (a line about your stuck squat is picked over a general one
   most of the time when both fit).

The draw is seeded from the day ("2027-01-11"), so the same day, facts and
history always give the same line, and it can be tested. In a simulated year
of *daily* reminders the tests require: no register twice running, no line or
sentence again within 60 days, at least 150 different lines and 300 different
sentences, and no line more than six times. At four sessions a week that is
roughly each line three times a year at most.

The history keeps the last 400 reminders in a small JSON file
(`workout-voice.json`), not in SwiftData.

### 2.4 Pending reminders don't use lines up (`WorkoutBanter.reconcile`)

The app reschedules its reminders every time it opens. Each pending reminder
keeps its line while the line is still true (same tone, still fits, reads the
same with today's numbers). A line counts as used only once its reminder's
time has passed. A reminder removed before it fired (trained early, plan
changed, switched off) gives its line back. A pending line changes only when
it has to: its own day arrives with better data (once), a number in it is no
longer true, a caution state appears, or the tone is switched.

### 2.5 The notification

Title: what and when, as before ("Legs at 18:00"). Body: the line. If the
owner wrote an if-then plan for the day ("If I'm late, the 15-minute
version"), it shows as the subtitle, because coping plans are one of the
better-supported techniques in the app (behaviour-change.md rec. 3) and should
not be lost to a joke. In the Plain tone with an if-then plan, the plan is the
body, exactly as it was. Title at most 40 characters and body at most 160 are
app choices: Apple publishes no truncation limit; 160 stays within about four
lines of a banner at the default text size.

### 2.6 Going quiet (`WorkoutReminderCadence`)

The "pause after two unanswered" rule stays, with a voice and a way back:

- After one unanswered reminder, the next is the **last call**. It says once,
  kindly, that reminders go quiet after it ("After this I'm going quiet, like
  a barbell at night. Train or open the app and I'm back."), and it is the
  only reminder left pending, so the quiet starts by itself even if the app is
  never opened again.
- After two, **quiet**. Training or confirming a plan brings everything back.
  Opening the app brings reminders back **one at a time**; if that one goes
  unanswered too, the next quiet lasts 3 days, then 7, then 14, with no second
  last call. One answered reminder resets it all.
- Once the last call (or the single reminder) has gone out, nothing more is
  queued behind it until it is answered or the day is over.

This is the missed-session follow-up, inside the existing one-a-day cap. The
"back after N days" lines are the other half: when a session was missed, the
next reminder may say how long it has been (4–14 days, never as a reproach)
or, after 15 days, say nothing about the number at all.

One limit, unchanged from before: these rules run when the app runs. A week of
reminders queued while things were going well will still go out if the app is
never opened again; then nothing follows, because a new week needs a new plan.

### 2.7 On-device variation (`WorkoutVoiceWriter`, `WorkoutVoiceModel`)

When Apple Intelligence is available and "Fresh lines" is on, about every
other playful reminder (by the day's seed) may be written by the on-device
model. The library line is scheduled first; the model is asked afterwards in a
background task, never at launch, with a 20-second limit, one request at a
time, once per reminder and set of facts. The prompt holds training-log facts
only (session, the week's count, a lift, a muscle group; never recovery,
illness or pain) and three library lines as examples of the voice. The reply
replaces the library line only if it passes every check in §3 plus: one line,
at most three sentences, not at least 60% the same words as any of the last 60
reminders or the examples, and not the same opening as the last reminder. A
replaced library line was never sent, so it is not used up. If the facts
change before the reminder fires, the model's line is dropped.

The app is complete without the model. Small on-device models are not
reliably funny; the library is the part that was read and tested, which is why
it keeps at least half of what is seen (app choice).

### 2.8 Settings

Settings › Notifications › Reminders, under "Workout reminders": **Reminder
tone** (Playful / Plain), **Fresh lines from Apple Intelligence** (shown only
when the model is available and the tone is Playful), and **Show me one**,
which writes a line from today's data without using it up and says what it was
written for, or why it is plain today.

**Default: Playful.** The owner asked for it, and the evidence neither
requires nor forbids it. Plain is one tap away and is also what every caution
state uses regardless of the setting.

**Workout reminders themselves are off by default** (2026-11 evidence audit,
M4): gym-goers whose attendance is already predictable responded less to a
nudge to go (Buyalskaya et al. 2023), and clock reminders support repetition
more than habit (Stawarz et al. 2015). A choice already stored is kept, and
Playful is the style once they are switched on. Switching them back on, or
turning rest mode on, starts the going-quiet rules afresh.

## 3. Guardrails (`WorkoutBanterGuard`; every one has a test)

| Rule | Why |
|---|---|
| Nothing about bodies, body weight, food, eating or looks | §1.2: appearance motives and weight stigma work against exercise; a joke there has a cost and no upside |
| No guilt or shame, no insults, no "should", "must", "missed", "streak"; the app is never sad at you | §1.2: guilt appeals did nothing for health, controlling language provokes reactance; "the mascot is sad" is guilt in a costume |
| Low recovery, illness flagged, pain logged, rest mode, rest day: one plain, kind line that never pushes and always says resting or going easy is fine | The app's own safety rules already decided the day; the reminder must not argue with them |
| Nothing about training through illness or pain, in any tone | Same |
| On a deload week no line asks for a record | The plan says light |
| Every number in the line is one the facts hold, digits or words | An invented "three weeks" is the app making up data about the owner |
| No slot left unfilled; 20–160 characters; no emoji | It has to fit and read cleanly |
| No other product's name or mascot | Asked for; also avoids borrowing someone else's voice |
| A long break is never counted out loud (15+ days) | The number reads as a reproach however it is worded |

The word lists are the app's own. No study tested them; they err on the side
of dropping a harmless line (a model line that mentions "protein" is dropped).
The owner's own names (a session called "Full body", a lift) are taken out
before the word check, so they never trip it. After a review found model
lines like "Never skip leg day", "Don't miss it", "Last time you quit early"
and "noodle legs" passing, skip/miss/quit/give up and thin-limb words
(noodle, chicken, scrawny, puny, twig) were added; "arms" and "legs" alone
stay allowed because library lines name muscles and "Leg day".

**What the guard cannot do.** A word list and a number check catch the usual
ways a line goes wrong, not every one. A model line can still invent a claim
in words no list holds ("the barbell saw you leave early"). The limits on
that risk are elsewhere: only training-log facts go into the prompt, model
lines are at most every other reminder, a model line is dropped as soon as
the facts it was written from change, and "Fresh lines from Apple
Intelligence" can be switched off.

**Easy-day wording.** The low-recovery state also covers a 7-day HRV below
normal with an ordinary score, so its lines say "Today's numbers point to an
easy day", never "Recovery is low".

## 4. What is not known

- Whether funny reminders change how often anyone trains. Nothing found says
  so. Expect at most what HeartSteps saw for any prompt: an early effect that
  fades in weeks. The honest case for the feature is that the owner wanted it
  and that a reminder which is pleasant to read is less likely to be switched off.
- Whether rotation matters at this scale. Duolingo measured a 0.5% difference
  across hundreds of millions of sends; one person cannot feel that as an
  effect on behaviour. The owner *can* feel repetition as annoyance, which is
  the reason for the rotation here.
- Whether the on-device model's lines are funny, or even usually pass the
  checks. This could not be run here (no iPhone); the acceptance rate is logged
  on device (`workout-voice` log category) and should be looked at.
- Humour is personal. Gym-bro parody or the bureaucratic register may grate.

## 5. What to tune after watching real use

1. **Which registers land.** Delete or rewrite what doesn't; a register can
   be dropped by removing its lines. Retired ids must not be reused.
2. **The model.** Read the log for how often its line is accepted. If it is
   rarely accepted or rarely good, turn the share down (`generatedEvery`) or
   the default off. If its lines pass but are bland, raise `temperature`; if
   they are mostly dropped for stray numbers, lower it.
3. **The 60-reminder window** and the weight given to data-rich lines. If a
   long plateau makes the squat jokes feel like nagging, raise the window or
   add a cap per situation per week.
4. **Small groups first.** "Weeks in a row" and "mid-week count" fit most days
   and have 8–10 lines each; they will be the first to feel familiar. Add
   lines there before anywhere else.
5. **The last call.** Whether it reads as kind or as a guilt trip is a matter
   of taste the owner should check on a real Lock Screen.
6. **Subtitle clutter.** If title + if-then line + joke is too much, show the
   if-then line only in the Plain tone.
7. **Pending reminders when the app isn't opened.** If a week of unanswered
   reminders ever happens in practice, cap how many are queued ahead (now 7).
8. **Thresholds** for "stuck" (3 sessions, 2 weeks), "close to a record" (97%
   of the best estimated 1RM) and "neglected" (7–45 days).

## Sources

- Yancey KP, Settles B. A Sleeping, Recovering Bandit Algorithm for Optimizing Recurring Notifications. KDD 2020. research.duolingo.com/papers/yancey.kdd20.pdf **[F]**
- Yancey K, Settles B. "Hi, it's Duo": the AI behind the meme. Duolingo Blog, 3 Sept 2020. **[A]**
- Yu A. Improving the streak: forming habits one lesson at a time. Duolingo Blog, 19 Nov 2020. **[A]**
- Klasnja P, et al. Efficacy of contextually tailored suggestions for physical activity: a micro-randomized optimization trial of HeartSteps. Ann Behav Med 2019 (PMC6401341). **[F]**
- Peng W, Huang Q, et al. When guilt works: a comprehensive meta-analysis of guilt appeals. Front Psychol 2023;14:1201631. **[F]** (first half of the text; the health subgroup and discussion)
- Walter N, Cody MJ, Xu LZ, Murphy ST. A priest, a rabbi, and a minister walk into a bar: a meta-analysis of humor effects on persuasion. Hum Commun Res 2018;44(4):343–373. **[A]**
- Rains SA. The nature of psychological reactance revisited: a meta-analytic review. Hum Commun Res 2013;39(1). **[A]** (title from memory)
- Semenchuk BN, Strachan SM, Fortier M. Self-compassion and the self-regulation of exercise: reactions to recalled exercise setbacks. J Sport Exerc Psychol 2018;40(1):31–39. **[A]**
- Bidargaddi N, et al. To prompt or not to prompt? JMIR Mhealth Uhealth 2018;6(11):e10123. **[A]**
- Morrison LG, et al. The effect of timing and frequency of push notifications on usage of a smartphone-based stress management intervention. PLoS One 2017;12(1):e0169162. **[A]**
- Ma, Ebesu, Dillard. Psychological reactance in persuasive health communication: a meta-analysis (2026). **[S]**
- Health message outcomes of humor appeals: a systematic review. Health Communication, in press 2026. **[S]**
- A systematic review of humour-based strategies for addressing public health priorities (13 studies). **[S]**
- A global experiment on motivating social distancing during the COVID-19 pandemic (n = 25,718). PNAS 2022 (journal from memory). **[S]**
- The effects of choice and autonomy-supportive language in health messages (physical activity, n = 218). Eur J Health Psychol 2024. **[S]**
- Wohllebe A. Consumer acceptance of app push notifications: systematic review on the influence of frequency (journal and year not checked). **[S]**
- Teixeira PJ, et al. IJBNPA 2012; Ntoumanis N, et al. Health Psychol Rev 2021; Silverman J, Barasch A. J Consum Res 2023; Mujika I, Padilla S. Sports Med 2000. **[D]** (docs/research/behaviour-change.md)
- Vartanian LR, Novak SA. Internalized societal attitudes moderate the impact of weight stigma on avoidance of exercise. Obesity 2011. **Not re-verified.**
- Press on CARROT Fit (2014–15), Gentler Streak (reviews, 9to5Mac) and Apple's Activity rings (Fortune, 24 Jan 2025). **[S]**
