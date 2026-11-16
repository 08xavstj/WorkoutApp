# Cleanup research: what to cut, what to copy, and the rules for the redesign (16 Nov 2026)

Follows `competitors.md`, `competitors-2026-11.md` and `ux-audit.md`. This one answers the owner's request for a cleaner, simpler app. Web research; sources at the end, with what couldn't be checked.

## Point of view

1. **The gap is subtraction, not features.** Every leader is adding surface (Whoop's social feed, Bevel's calendar and timeline, Oura's cardio load, Apple's Health Age). The only moves toward simplicity are Oura's cut from five tabs to three and Whoop's planned merge of four daily surfaces into one flow. Those are the two to copy.
2. **Apple is about to give away the generic health layer.** iOS 27.3 (in beta, expected December) adds Health Age, a readiness score, a Longevity tab, lab upload and camera movement tests. Tensile's defensible core is recovery-aware, plate-exact lifting and a private coach. Body age, the stress estimate, "all measures" and typed labs should sit deep or go.
3. **The recovery confusion was a model problem.** The 7-day trend picked a band and last night moved the number inside it, so no two-line explanation fitted. Fixed in this round (`RecoveryCalculator`): one smooth number, one rule.
4. **Reminders wear off in about four weeks, and clock reminders block habit formation.** The evidence supports fewer prompts tied to events.
5. **Don't replace the 5-minute breathing block with another ritual.** Evidence for 1-2 minute doses is thin.

## A. Worth copying (value for this owner ÷ effort)

| # | Idea | Who does it | Size |
|---|---|---|---|
| 1 | **One daily flow**: morning check-in, coach morning message and today's plan as one message and one screen; same in the evening | Whoop is merging Journal, Daily Outlook, Check-ins and Day in Review (planned); Oura's Today has one "daily highlight" | S-M |
| 2 | **Recovery as a verdict, then three rows against your own normal**, with the scale's midpoint stated | Athlytic ("50% simply means your HRV and RHR are close to baseline"); Apple Vitals (Typical / Outlier) | done in part |
| 3 | **A notification budget**: at most two a day outside doses and the rest timer; one quiet-hours setting for everything | Apple HIG | S |
| 4 | **Health tiles only when something is off**; a normal day is one row, "Vitals typical" | Apple Vitals alerts only when two or more overnight metrics are out of range | S |
| 5 | **A score plus a fixed short instruction** per band | Garmin ("Ready for challenges", "Good to go", "Time to slow down") | S |
| 6 | **Planned sessions in Apple Calendar** in place of workout reminder notifications | Bevel 3.2.8 | S-M |
| 7 | **Effort rating optional on set rows**; one tap completes a prefilled set | Hevy hides RPE until enabled; MacroFactor Workouts is weight, reps, tick | S |
| 8 | **One dose notification per time of day**, not per item | HIG: "Avoid sending multiple notifications for the same thing" | S-M |
| 9 | **Fixed key measures plus one "Show all" row**; no pin/reorder editor | NN/g: most users won't do the work of customising | S |
| 10 | **Weekly load as one plain word** in place of 7-day vs 28-day figures | Oura Cardio Effort (Light … Reaching) | S |
| 11 | **One-line check-in**, typed or dictated, mapped to fields by the on-device model | Whoop custom Journal (unconfirmed as shipped) | M |
| 12 | **Set intensity as % of estimated 1RM** on rows and history | Whoop (5 Nov) | S |
| 13 | **TipKit tips** in place of explainer cards and onboarding pages | Apple HIG; NN/g found tutorials didn't improve task performance | S |

Looked at and not recommended: social feeds, a timeline surface, coach-designed programs, sending workouts to cloud chatbots.

## B. Cut or hide

| Tensile feature | Decision | Why |
|---|---|---|
| 5-minute breathing | **Removed this round** | Asked for; in the best trial (5 min a day, 28 days, n=108) mood improved but HRV and resting heart rate didn't (Balban 2023) |
| Body age | Hide under Health; drop when iOS 27.3 ships | Apple's free Health Age uses the same inputs; a 2025 review of 14 composite scores found them untransparent and unvalidated (Doherty 2025) |
| Heart-rate stress estimate | Cut | The roadmap already lists daytime stress scores under "skip" |
| Four health tiles on Today | Outliers only (A4) | Duplicates Health; Oura moved these off the first screen |
| Nutrition card on Today | One line (calories and protein vs target); detail on tap | Cronometer is the logger |
| All measures (about 25 stats) | One row at the bottom of Health | Apple Health's Browse already does this |
| Stretch and workout reminders | Off by default; offer stretching on the workout summary; sessions to the calendar | Event cues built habits where clock reminders didn't (Stawarz 2015) |
| Check-in reminders plus coach messages | Merge (A1) | Two notifications for one thing |
| Labs, blood pressure in Log | Health › Records only | Low-frequency tasks shouldn't sit beside Start workout |
| Post-workout steps | One screen after Finish; muscle feedback optional | "Too many taps" is the top logging complaint |
| Blocks, block report, adaptive week, lift goals | Keep the logic; one line on This week ("Week 3 of 5") | Hevy and Strong show routines and history only |
| Evidence disclosures on every card | One "How this is worked out" link per detail page | NN/g: more than two disclosure levels has low usability |
| Settings (11 sections) | Aim for 6; move task options to the screens they affect | HIG: "Minimize the number of settings you offer" |
| Setup cards above the scores | At most one visible | The scores should be the first thing on screen |

## C. Rules for the redesign (checkable)

**Navigation**
1. No number's explanation is more than two levels below its tab root (NN/g, Progressive Disclosure).
2. Five tabs or fewer, single-word labels, never hidden or disabled (HIG Tab bars).
3. A tab badge only for something critical (HIG).

**Home screen**
4. The first screen answers in about five seconds: three scores, one sentence, one button, at most one banner above them. 57-70% of tracker sessions were glances of about five seconds (Gouveia 2015).
5. A measure is on Today only if it changes what he does today.
6. Normal values are one summary row; only outliers get a tile (Apple Vitals).

**Cards and lists**
7. Cards for mixed summaries that open a detail page; same-kind items (measures, records, history, settings) are list rows (NN/g, Cards).
8. Every empty state: status, one line on what the area is for, one button that fills it (NN/g).
9. No glass material in the content layer (HIG Materials).

**Type and colour**
10. No text under 11 pt; body 17 pt; system text styles; layouts survive 200% text (HIG Typography).
11. Contrast at least 4.5:1 up to 17 pt, light and dark (HIG Accessibility).
12. One meaning per colour; colour on controls only for status or the primary action (HIG Color).

**Charts**
13. Every chart has a headline that states the takeaway (HIG Charting data).
14. If it doesn't need analysing, it's a row, not a chart (HIG).
15. The same data uses the same chart type and colours everywhere.

**Wording**
16. Every score: verdict word, one sentence of reason, one action, before any breakdown.
17. Every app-made score says "estimate" and names its baseline (Doherty 2025).
18. A tip is one or two sentences and never shown to someone who has used the feature (HIG Offering help).

**Notifications**
19. Never two notifications for the same thing; never one whose only content is "open the app and do X" (HIG).
20. Time Sensitive only for something happening now or within the hour (rest timer, dose due) (HIG).
21. Permission asked after first use, with what the notifications will contain; every category editable in the app (NN/g; HIG).

**Workout**
22. During a live workout only workout information and controls. A set done as planned takes one tap; fields are prefilled (HIG Workouts, Entering data).

## D. How leaders explain a recovery score

| App | One line | Inputs named | Bands |
|---|---|---|---|
| Athlytic | "A daily score, on a 0-100% scale, that indicates how ready you are to perform today" | 2 (HRV, RHR vs 60 days) | "50% simply means your HRV and RHR are close to baseline" |
| Google / Fitbit | "A daily snapshot of your body's recovery status" | 3 | Low 1-29, Moderate 30-64, High 65-100 |
| Whoop | Green "primed for a high-Strain day" | 4 | 0-33, 34-66, 67-100 |
| Garmin | "A score and a short message" | 6 | five bands, each with a 2-4 word instruction |
| Oura | "How balanced your recovery and activity are" | 9, top ones first | Optimal, Good, Fair, Pay Attention |

Patterns: one sentence saying what the score is for; three to six inputs; everything relative to the person's own baseline, with "normal" placed on the scale; a fixed short instruction per band. In interviews with 17 Whoop and Oura users, scores "sometimes did not match how they felt" and people used their own judgment (Ibrahim 2024).

## E. Notifications: the numbers

| Finding | Number | Source |
|---|---|---|
| Activity prompts work, then fade | +107% steps in 30 min on day 1, decaying 3% a day, no effect by day 29; 2.4 prompts a day | Klasnja 2019 (HeartSteps) |
| A prompt's pull on app use is small | 3.9% more likely to open the app in 24 h | Bidargaddi 2018 |
| Daily vs occasional prompts | Viewed more, no change in overall use; smart timing no better | Morrison 2017 |
| Clock reminders vs event cues | Reminders supported repetition but hindered automaticity | Stawarz 2015 |
| Self-reported tolerance (survey, n=1,000) | 37% would disable at 2-5 a week, 33% at 6-10 | Localytics 2017 (secondary) |
| Why people quit health apps | 45.7% had stopped using one: data-entry burden, lost interest | Krebs & Duncan 2015 |

No trial of user-chosen quiet hours was found; the support is platform design and the HIG's in-app control rule. No controlled trial of 1-2 minute breathing sessions was found either.

**Proposed defaults:** one morning message (recovery verdict, plan, any check-in question); one evening message only when there is something to act on; doses grouped per time of day; rest-end and dose-due the only time-sensitive ones; everything pauses after two ignored in a row; one quiet-hours setting.

## F. Competitor changes since early November

- **Whoop**: 1RM estimates shipped 5 Nov; "Humans" social feed 12 Nov.
- **Bevel**: Fall release (30 Sep): redesigned Fitness with pin/reorder/hide, Training Calendar, Muscular Load, Routines, Personal Records, Timeline; 3.2.8 (about 11 Nov) calendar sync.
- **Hevy**: 3.2.x; notes pinned to an exercise, routine or workout; "send workout to ChatGPT & Claude".
- **Strava**: coach-designed strength workouts with live set and rep tracking (15 Oct).
- **Oura**: Cardio Effort and automatic VO₂ max (20 Oct).
- **Apple**: iOS 27.3 Health adds "For You" and on-device camera movement evaluations.
- Nothing new found for Strong, RP Hypertrophy, Alpha Progression, Juggernaut AI, Ladder, Boostcamp, Athlytic, Garmin.

## Sources

Read directly: Apple HIG (Notifications, Managing notifications, Charting data, Settings, Onboarding, Offering help, Workouts, Entering data, Tab bars, Materials, Color, Typography, Accessibility); NN/g (push notifications, progressive disclosure, cards, empty states, onboarding, customization); help pages for Oura, Athlytic, Bevel, Google, Garmin, MacroFactor, Hevy; Klasnja et al. 2019 and Balban et al. 2023 (full text); Lachowicz 2026 and Ibrahim 2024 (abstracts); Releasebot, Gadgets & Wearables, the5krunner, 9to5Mac, MacRumors, Athletech News.

Via search summaries only: Morrison 2017, Bidargaddi 2018, Stawarz 2015, Alkhaldi 2016, Krebs & Duncan 2015, Gouveia 2015, Doherty 2025, Fincham 2023, the Localytics survey; Apple Sleep Score points and Vitals wording; Whoop bands; Hevy release notes.

Could not verify: whether Whoop's daily-flow merge has shipped; the on-screen wording of Apple's readiness score; tap counts per set in Hevy and Strong; any trial of 1-2 minute breathing or of quiet hours. Claims about Fitbod, Harvee and "best app" rankings come from vendor or affiliate pages.
