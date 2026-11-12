# Stretching: how much, how often, and what it's for (2026-11)

Built as a 5-minute daily routine, separate from the workouts (`Stretching` in AppCore, `StretchView` in the app).

## What stretching does

| Claim | Verdict | Source |
|---|---|---|
| Improves flexibility (range of motion) | Yes, large effect over weeks | Ingram et al., Sports Med 2025;55:597-617 (188 studies, 8,095 adults) |
| Lifting through a full range does the same | Yes, about as much | Afonso et al., Healthcare 2021;9:427; Alizadeh et al., Sports Med 2023;53:707-722 (both from memory) |
| Speeds recovery or reduces next-day soreness | No | Afonso et al., Front Physiol 2021;12:677581 (11 RCTs); Warneke et al. 2025 |
| Prevents injuries in general | Not supported | Warneke et al., J Sport Health Sci 2025;14:101067 (Delphi consensus, 20 researchers) |
| Fixes posture | No | Warneke et al. 2025 |
| Builds muscle | Not meaningfully | Warneke et al. 2025 |

So the app says stretching is for flexibility, and doesn't pick stretches to "recover" yesterday's muscles.

## Dose

- **Weekly total.** Gains levelled off at about 10 minutes a week of stretching (Ingram 2025 abstract; the university's press release gives about 8 minutes per muscle per week and 3-4 minutes in one session). Weekly time mattered where time per session didn't, from about 5 minutes a week per muscle (Thomas et al., Int J Sports Med 2018;39:243-254).
- **Frequency and intensity.** Sessions per week, how hard you pull, age, sex and training status didn't change the result (Ingram 2025). So a missed day can be made up.
- **Holds.** 30 seconds was as good as 60 (Bandy & Irion, Phys Ther 1994;74:845-850). The ACSM asks for 10-30 s holds adding up to 60 s per stretch, at least 2-3 days a week, to tightness not pain (Garber et al., Med Sci Sports Exerc 2011;43:1334-1359).
- **Timing.** Over 60 s of static stretching per muscle lowers strength for a while (Behm et al., Appl Physiol Nutr Metab 2016;41:1-11), so not just before lifting.

Not checked against full texts from the build sandbox: the Delphi statement's exact duration recommendations and Ingram's per-muscle versus total wording. The app's numbers stay inside both readings.

## What the app does

- **5 minutes a day:** five stretches, each 2 × 30 s (30 s a side for one-sided ones), with 6 s to change position. 35 minutes a week.
- **Seven areas:** calves, chest, lats, hip flexors, hamstrings, glutes, inner thighs. Two stretches each, alternated.
- **Weekly minutes per area:** 5 each (Thomas's floor). With focus areas picked: 8 for those (Ingram's level-off), 3 for the rest. The 3 is the app's choice.
- **Today's five:** the areas furthest behind their minutes over the last 7 days, the longest unstretched first on a tie.
- **Lifting credit:** an area lifted through a long range that week (Romanian deadlift: hamstrings; squat: glutes, inner thighs; split squat: hip flexors, glutes; presses and flyes: chest; pulldowns: lats; calf raises: calves) is credited 2 minutes a session, up to half its target, so the routine goes to areas the lifting didn't reach. The evidence is that lifting improves range of motion about as much as stretching; the minute-for-minute rate is the app's choice.
- **Reminder:** daily at a chosen time (20:30 by default), skipped once done, and moved to an hour after a planned session when it would fall within 90 minutes before it. Off in rest mode.

## Seeing progress

- **How it feels.** After a session each stretch can be rated very tight, tight, a little tight or easy. Most of the range gained in the first weeks is stretch tolerance: the same position feels easier before the muscle itself changes (Weppler & Magnusson, Phys Ther 2010;90:438-449). With four ratings over two weeks an area shows its trend (its first three ratings against its last three). A self-rating: a trend for the user, not a measurement. The four steps and the thresholds are the app's choice.
- **Reach check, about every four weeks.** A standing toe touch (knees, shins, ankles, toes, fingertips on the floor, palms flat) and, optionally, the knee-to-wall distance in cm. Toe-touch and sit-and-reach tests track hamstring flexibility moderately well (Mayorga-Vega et al., J Sports Sci Med 2014;13:1-14, meta-analysis); the knee-to-wall lunge is a reliable measure of ankle range (Bennell et al., Aust J Physiother 1998;44:175-180). Both cited from memory.

## Photos

Each stretch has a photo from the public-domain free-exercise-db, bundled with the app (15 files, about 360 KB) so they show without a connection. The stretches were chosen to match photos that show one person with no special equipment.

## Not done

- Focus areas are the user's own pick (the feel ratings show which are tight). Lower starting flexibility goes with bigger gains (Ingram 2025), which is why tight areas are the ones to pick.
- No stretching inside workouts: warm-ups there are ramp sets and movement (`WarmUpRoutine`).
