# Workout zones: the options (2026-11)

Question from the owner, who wears an Apple Watch Series 12 (watchOS 27) and lifts: "figure out a way to incorporate workout zones and give me options for how."

This replaces the "Not adopted" verdict in `watch-features.md` §6.9. That verdict's worry was two sets of zone minutes for one workout. It is answered below by keeping strain on one scale and letting the zones on screen be a choice.

## What "zones" can and can't tell you

A heart-rate zone is a label for effort. It is not a measurement of what the body is doing.

- The thresholds that matter in physiology (the first and second lactate or ventilatory thresholds) sit at very different heart rates in different people. In 100 adults the first threshold fell anywhere from 60% to 90% of maximum heart rate, so fixed percentages "conform poorly to exercise intensity domains" [1].
- Every scheme below is a fixed percentage of something, except custom limits from a test. They are useful for comparing your own workouts with each other. They are weak for saying "this was below your threshold".
- A maximum heart rate from age is off by about 10 bpm (1 SD) for one person [2]. The app prefers a typed or learned maximum (`ObservedMaxHeartRate`).

The same heart rate is a different zone number in each scheme. For resting 55 and maximum 185:

| | Zone 1 | Zone 2 | Zone 3 | Zone 4 | Zone 5 |
|---|---|---|---|---|---|
| Tensile (50–100% of reserve) | 120–133 | 133–146 | 146–159 | 159–172 | 172+ |
| Percent of max (50–100%) | 93–111 | 111–130 | 130–148 | 148–167 | 167+ |

125 bpm is zone 1 in the first row and zone 2 in the second. "Zone 2" means nothing until you say whose.

## The options

### A. Keep Tensile's zones only (what the app did)

- **Gives:** one scale everywhere. Zones 1–5 are 50, 60, 70, 80 and 90% of heart-rate reserve [3], the scale Banister's TRIMP (day strain) is built on [4]. Reserve tracks oxygen-uptake reserve better than percent of maximum does [5].
- **Costs:** the numbers don't match Apple's Workout app, a Garmin or a gym machine, and a lab test can't be entered.
- **Evidence:** reserve is the better base for a formula [5]. The five 10-point steps are Edwards' zones [6] moved onto reserve, which is the app's choice, not a published scheme.
- **Built:** yes, and it stays the default.

### B. Percent of maximum heart rate

- **Gives:** the zones most watches and gym machines show: five 10-point steps from 50% of maximum [6].
- **Costs:** ignores resting heart rate, so two people with the same maximum and very different fitness get the same zones. Each heart rate lands about a zone higher than in A.
- **Evidence:** the scheme is conventional, not validated against thresholds [1]. The book it comes from was not re-verified; the description is from a review [7], also not re-fetched this round.
- **Built:** yes, as a choice.

### C. Follow Apple Health's zones

- **Gives:** the zones in Apple's Workout and Fitness apps, including any the owner typed in the Watch app (Workout › Heart Rate Zones). iOS and watchOS 27 let an app read them: `HKHealthStore.preferredWorkoutZoneConfiguration(for:)` [8].
- **Costs:** needs iOS 27 on the phone. Apple does not publish its percentages: its user guide says only that the zones are "a percentage of your maximum heart rate and are automatically calculated" [9], while older write-ups say heart-rate reserve [10]. Apple's first zone has no lower limit ("The first zone has no lower bound" [11]), so everything under zone 2 counts as zone 1, and a lifting session shows nearly all its time as zone 1.
- **Evidence:** none specific to Apple's cut-offs, because they aren't public.
- **Built:** yes, as a choice. On iOS 26, or when Health returns nothing, the option says so and Tensile's zones are shown.

### D. Custom limits (lab or threshold test)

- **Gives:** the only option that can match the owner's physiology, if the numbers come from a test.
- **Costs:** needs a test and five numbers typed in. Limits typed from a formula are no better than A or B.
- **Evidence:** thresholds differ too much between people for a percentage to find them [1], which is the case for a measured value.
- **Built:** yes: five fields, "Zone N starts at", checked to rise in order. Not built: a helper that fills the limits from one threshold heart rate (for example Friel's percentages of lactate-threshold heart rate, which are coaching practice, not a study).

### E. Show Apple's recorded time-in-zone for Apple-recorded workouts

- **Gives:** for a run recorded in Apple's Workout app, exactly the split Apple's Fitness app shows (`HKWorkout.zoneGroup(for:)` [12]).
- **Costs:** iOS 27 only. Those minutes would be in Apple's zones even when another scheme is chosen, and the app has no detail page for workouts from other apps to put them on.
- **Built:** no. Option C gets nearly the same numbers by counting the workout's heart rate in Apple's zones. Worth doing if a detail page for Apple-recorded workouts is added.

### F. Zone-guided cardio on the Watch

- **Gives:** a cardio workout recorded by Tensile's Watch app, with heart rate large, the zone by number and color, time in each zone, and an optional target with a wrist tap on leaving and re-entering it.
- **Costs:** another workout recorder next to Apple's. No GPS route (see "Not built").
- **Evidence:** for the display, none needed. For the target, see the next section.
- **Built:** yes (`WatchCardioModel`, `CardioZoneTracker`).

## The "Easy" target and what the evidence says

The Watch's Easy target is 40–60% of heart-rate reserve: the ACSM's moderate intensity, 40–59% of reserve, with vigorous from 60% [13]. It is the same band the weekly plan's easy cardio uses (`EasyCardio`). With no resting heart rate (a Watch that has heard nothing from the phone) it is 64–76% of maximum, the same position stand's moderate band on that scale; that column was not re-verified against the paper.

Where that sits in each scheme, for resting 55 and maximum 185 (107–133 bpm):

- Tensile's zones: zone 1 and just under it. Not zone 2.
- Percent of max: zone 2 (111–130), with a few beats either side.

So "easy" is roughly "zone 2" only on a percent-of-max watch. The target is defined in bpm from reserve and stays the same whichever zones are shown. Any single zone can be the target instead.

What it does not claim:

- **That easy cardio is the best cardio.** Mostly-easy-plus-some-hard ("polarised") training raised VO₂peak slightly more than other mixes (SMD 0.24, 95% CI 0.01–0.48), only in interventions under 12 weeks and in highly trained athletes, with no difference in time-trial performance (SMD −0.01) [14]. In 30 recreational runners, polarised and between-thresholds training both improved 10 km time (5.0% against 3.6%); the difference was not significant [15].
- **That "zone 2" is special for health.** A 2025 narrative review found little direct evidence for zone 2 as the best intensity for mitochondrial or fitness gains in the general population, and argued that higher intensities matter more when training time is short [16]. Read from the abstract and secondary summaries, not the full text.
- **That the band finds your threshold.** It can't [1]. The Watch and the settings page both say: if you can't talk in full sentences, slow down, whatever the number says. The talk test tracks the ventilatory and lactate thresholds across walking, jogging, cycling and other modes [17].

Easy cardio earns its place in this app for a different reason: it adds little strain on a rest day and counts toward weekly moderate minutes (`CardioPlanner`).

The tap timings are the app's choice. No study sets them: 20 s outside the band before a tap, 10 s inside before the "back in range" tap, a repeat every 2 minutes only while above, and a restart of the count after 30 s without readings. Being under the band taps once and never repeats, because recoveries between intervals are under it on purpose.

## What was built

1. **A choice of scheme** (Settings › Training › Heart-rate zones): Tensile, Percent of max, Apple Health, Custom. One sentence each, with the bpm ranges in use and the Easy band.
2. **Strain is untouched.** Day strain and the Fitness tab's daily zone minutes stay on heart-rate reserve whatever is chosen, and the settings page says so. Changing the scale would change every past score, and TRIMP is defined on reserve [4].
3. **Workout screens follow the choice** (workout detail and summary), naming the scheme when it isn't Tensile's. With Tensile's scheme the minutes are identical to before (tested against `StrainCalculator`).
4. **Cardio on the Watch** with the chosen zones. They travel by WatchConnectivity, are kept on the Watch, and fall back to Health's own zones on watchOS 27 and then to percent of an age-estimated maximum [2].
5. On watchOS 27 the saved workout carries the zones the wrist showed (`HKWorkoutBuilder.setCustomZoneConfiguration(_:for:)` [18]), so Apple's Fitness app splits the time the same way. Apple's zone 1 has no floor, so time under Tensile's zone 1 shows as zone 1 there.

## Recommendation

Leave the default on Tensile's zones: it is the scale strain is computed on, so the zone bars and the strain number tell one story. Switch to Apple Health's only if matching Apple's Fitness app matters more than that. Use Custom only with numbers from a test. For easy days use the Easy target on the Watch rather than "zone 2".

## Not built, and why

- **GPS routes.** They need location permission strings, a location manager and `HKWorkoutRouteBuilder`, none of which could be compiled or tested here. Distance still comes from the Watch's workout data.
- **Daily zone minutes in the chosen scheme.** They come out of the strain sum, which must stay on reserve.
- **Option E** and the threshold helper in D, as above.
- **Live zone updates from HealthKit** (`HKLiveWorkoutBuilderDelegate.workoutBuilder(_:didUpdateWorkoutZone:)` [19]). The Watch counts zone time itself so it works on watchOS 26 and with any scheme.

## To confirm on a real Watch

- That Health returns five heart-rate zones and whether zone 1 has a minimum.
- That the custom zones appear in Apple's Fitness app for a Tensile cardio workout.
- That distance arrives for outdoor runs, walks and rides without location permission.
- That the three taps (above, below, back in range) feel different enough while running.
- Which source Apple Health files the Watch app's workouts under. The phone keeps a Tensile cardio workout either way (it checks the workout's metadata as well as its source).

## Sources

1. Iannetta D, Inglis EC, Mattu AT, et al. A critical evaluation of current methods for exercise prescription in women and men. Med Sci Sports Exerc 2020;52(2):466-473. https://pubmed.ncbi.nlm.nih.gov/31479001/ (abstract checked 17 Nov 2026)
2. Tanaka H, Monahan KD, Seals DR. Age-predicted maximal heart rate revisited. J Am Coll Cardiol 2001;37:153-156. (Already in the code; not re-fetched.)
3. Karvonen MJ, Kentala E, Mustala O. The effects of training on heart rate: a longitudinal study. Ann Med Exp Biol Fenn 1957;35:307-315. (Already in the code; not re-fetched.)
4. Banister EW. Modeling elite athletic performance. In: Physiological Testing of Elite Athletes. Human Kinetics, 1991. See `strain-science.md`. (Not re-fetched.)
5. Swain DP, Leutholtz BC. Heart rate reserve is equivalent to %VO2 reserve, not to %VO2max. Med Sci Sports Exerc 1997;29:410-414. (Already in the code; not re-fetched.)
6. Edwards S. The Heart Rate Monitor Book. Polar Electro, 1993. (Not re-verified.)
7. Borresen J, Lambert MI. The quantification of training load, the training response and the effect on performance. Sports Med 2009;39(9):779-795. (Section "Summated heart rate zone score"; text not retrieved this round.)
8. Apple, `preferredWorkoutZoneConfiguration(for:)`, iOS/watchOS 27. https://developer.apple.com/documentation/healthkit/hkhealthstore/preferredworkoutzoneconfiguration(for:) (read 17 Nov 2026)
9. Apple Watch User Guide, "View Heart Rate Zones" (watchOS 27). https://support.apple.com/guide/watch/view-heart-rate-zones-apd897dccddf/watchos (read 17 Nov 2026)
10. 9to5Mac, "Heart Rate Zones on Apple Watch and iPhone", 23 May 2024 (secondary; says heart-rate reserve). https://9to5mac.com/2024/05/23/heart-rate-zones-apple-watch-iphone
11. Apple, `HKWorkoutZoneConfiguration.init(quantityType:zoneBoundaries:)`. https://developer.apple.com/documentation/healthkit/hkworkoutzoneconfiguration/init(quantitytype:zoneboundaries:) (read 17 Nov 2026)
12. Apple, `HKWorkout` ("Accessing zone data": `zoneGroup(for:)`, `zoneGroupsByType`) and `HKWorkoutZoneGroup`. https://developer.apple.com/documentation/healthkit/hkworkout (read 17 Nov 2026)
13. Garber CE, Blissmer B, Deschenes MR, et al. ACSM position stand: quantity and quality of exercise for developing and maintaining cardiorespiratory, musculoskeletal, and neuromotor fitness in apparently healthy adults. Med Sci Sports Exerc 2011;43(7):1334-1359. (The 40–59% and 60–89% reserve bands were confirmed from papers quoting the stand; the original table was not opened.)
14. Oliveira PS, Boppre G, Fonseca H. Comparison of polarized versus other types of endurance training intensity distribution on athletes' endurance performance: a systematic review with meta-analysis. Sports Med 2024;54(8):2071-2095. https://pmc.ncbi.nlm.nih.gov/articles/PMC11329428/ (abstract checked 17 Nov 2026; page range from memory)
15. Muñoz I, Seiler S, Bautista J, España J, Larumbe E, Esteve-Lanao J. Does polarized training improve performance in recreational runners? Int J Sports Physiol Perform 2014;9(2):265-272. https://pubmed.ncbi.nlm.nih.gov/23752040/ (abstract checked 17 Nov 2026)
16. Storoschuk KL, Moran-MacDonald A, Gibala MJ, Gurd BJ. Much ado about zone 2: a narrative review assessing the efficacy of zone 2 training for improving mitochondrial capacity and cardiorespiratory fitness in the general population. Sports Med 2025;55(7):1611-1624. https://pubmed.ncbi.nlm.nih.gov/40560504/ (abstract and secondary summaries)
17. Reed JL, Pipe AL. The talk test: a useful tool for prescribing and monitoring exercise intensity. Curr Opin Cardiol 2014;29(5):475-480. https://pubmed.ncbi.nlm.nih.gov/25010379/ (abstract checked 17 Nov 2026)
18. Apple, `HKWorkoutBuilder.setCustomZoneConfiguration(_:for:)`. https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/setcustomzoneconfiguration(_:for:) (read 17 Nov 2026)
19. Apple, `HKLiveWorkoutBuilderDelegate`. https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilderdelegate (read 17 Nov 2026)
