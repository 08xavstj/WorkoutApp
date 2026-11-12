# Exercise selection audit (2026-11)

Question: do the planner's exercise choices match what research says builds muscle? Prompted by a user noticing too little biceps and triceps work on push and pull days.

## Findings and what changed

### 1. Arms need their own exercises (changed)

- **Triceps.** Bench press alone grew the lateral head but barely the long head; a triceps extension, alone or with the bench, grew the whole muscle (Brandão et al., J Strength Cond Res 2020; 43 men, 10 weeks). Read from secondary summaries; the abstract confirms the design.
- **Biceps.** Curls grew the elbow flexors 11% against 5% for dumbbell rows (Mannarino et al., J Strength Cond Res 2021; 10 untrained men, one arm each). Small, so modest evidence.
- **Before:** push days had one triceps exercise ranked fifth (dropped at 30 minutes), pull days one curl ranked fourth, upper day B no curl under 75 minutes, full-body days no arm work at all.
- **Now:** a triceps extension and a curl rank straight after the first compound lifts on push, pull and upper days. Push and pull days have two arm exercises from 45-60 minutes. Full-body days get a curl (A) or triceps extension (B) as their first extra.
- **Which exercises.** Overhead triceps extensions grew the triceps about 1.4x more than pushdowns (Maeo et al., Eur J Sport Sci 2023), so overhead stays first; the second is a pushdown for a different arm position. Incline curls grew the upper elbow flexors more and preacher curls the lower part (Kassiano et al., Int J Sports Med 2025; 63 untrained women), so neither is "best": the second curl of a session is an incline or hammer curl for variety (Kassiano et al., J Strength Cond Res 2022, review).

### 2. Legs: leg curl and leg extension rank early (changed)

Squats grew the vasti and glutes but not the rectus femoris or hamstrings (Kubo et al., Eur J Appl Physiol 2019). Leg days now rank the leg curl and leg extension before the split squat, and the lower day has a leg extension (it had none). Already right: seated before lying leg curls (Maeo 2021), standing before seated calf raises (Kinoshita 2023), Romanian deadlift first for hamstrings at long length.

Not adopted: leaning back on the leg extension grew the rectus femoris more (Larsen et al. 2025; 22 untrained men, partly preprint). Worth a form tip later; not a planner rule.

### 3. Big lifts are done first (changed)

Slot lists are priorities (what a short session keeps). The session is now done compound lifts first, small lifts after, core last (`WorkoutPlanner.liftOrder`). Lifts done later lose reps and gain less strength; growth is similar either way (Nunes et al., Eur J Sport Sci 2021; Simão et al., Sports Med 2012). Before, a pull day did curls before its second row and a long upper day did triceps extensions before the overhead press.

### 4. Rows count for the upper back (bug fix)

The planner treated rows as lat exercises; the exercise library logs them as upper-back ("middle back") exercises with the lats helping. So planned row sets counted toward a lat target that logged row sets could only half meet, and pull days were capped as if pulldowns and rows were one muscle (a 75-minute pull day planned 54-59 minutes). Rows now plan as upper back first, lats second, matching the log. Pulldowns and pull-ups stay lat exercises.

### 5. Weekly targets match what a session holds (changed)

A muscle with one exercise in a session was promised 5 sets there; the planner gives one exercise 4. On a 60-minute upper day six muscles were promised 30 sets where about 20 fit, so weeks read as "missed sets". One-exercise muscles now count 4 a session.

### 6. Sharing a session's sets

When a muscle is over the per-session cap (10 sets), sets now come off its later exercises evenly (squat 4, split squat 3, leg extension 3, not 4/4/2). The first lift keeps its sets longest.

## Left as is

- Rear delts on upper day B: rows and pulldowns work them (Franke et al., J Sports Med Phys Fitness 2015, EMG; from memory), so the direct movement is the long session's extra. Side delts keep a lateral raise: presses don't train them well.
- Per-session caps mean a 90-minute push day plans about 70 minutes; the plan says so.

## The whole week

Standard: each major muscle group at least twice a week (ACSM position stand 2026; twice beat once for growth: Schoenfeld, Ogborn & Krieger, Sports Med 2016), about 10 or more weekly sets for the most growth (Schoenfeld, Ogborn & Krieger, J Sports Sci 2017), with about 4 still building muscle (Pelland et al., Sports Med 2026). Sets where a muscle helps count half (Pelland's fractional count).

Measured on the default splits (2-6 days, 45-75 minutes, full gym):

- **Before:** calves got nothing on 2-day full-body weeks or 45-minute push/pull/legs weeks and once a week on 3 days. Without the abs finisher, 45-minute weeks on 4-6 days had no abs work.
- **Now:** a calf raise and a core movement sit inside the first five movements of the leg, lower, pull and full-body lists. Every big muscle is trained twice a week on every split; calves at least once (twice from 3 days); abs every week (from the finisher when it's on).
- **Sets:** four or more hour-long days give every big muscle 8+ fractional sets (most 12-20). Two or three days, or 45-minute sessions, give about 3-8: over the minimum, under the 10-set band. That is what the time allows; the plan doesn't claim more.
- Chest on an upper/lower split has one press per upper day: 8 direct sets a week at 60 minutes, 10 at 75.

`WeeklyCoverageTests` holds these.

## Small lifts: reps before weight (changed)

A barbell curl moves 2.5 kg at a time: 10% at 25 kg, about three reps' worth of load, and the weight bounced between two plates near the lifter's limit. Single-joint lifts are now rep-first (`ProgressionMode.reps`: hold the weight, add a rep a session to two past the range, then step) when the next weight is over 5% heavier, on any equipment. Adding reps builds muscle and strength as well as adding load (Plotkin et al., PeerJ 2022). The ACSM's range for a step is 2-10% (2009 position stand); using the lower half for small lifts is the app's choice (the stand's own wording on small-muscle exercises couldn't be checked from the build sandbox). Compound lifts keep the 10% line.

## Default curl

Dumbbell curl first (the user's preference; no growth difference from a barbell is established). A curl already logged still comes first, so a lifter with barbell-curl history swaps once in a workout and the planner follows.
