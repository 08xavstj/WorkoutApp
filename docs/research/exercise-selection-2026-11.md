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

## Known gap

Barbell curls in a barbell-only gym move in 2.5 kg steps, about 10% of the load, so the weight can bounce between two plates near the lifter's limit. Small lifts would do better with rep-first progression on steps over about 5% (the ACSM's 2-10% range, lower end for small muscles). Not changed here.
