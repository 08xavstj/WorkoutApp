# Apple Watch app redesign (2026-11)

The owner wears an Apple Watch Series 12 on watchOS 27.2.1. He says the current Watch app "is very basic and hard to use on the watch" and wants a revamped Watch app with all the new features. This document maps the current app and its usability problems, collects what the best watch workout apps and Apple's guidance do, and specifies a new Watch app with a build plan in chunks. No app code was written for it.

**How this was researched (18 Nov 2026).** Every file in `Watch/`, `WatchWidgets/`, `Shared/WatchSession.swift`, `Shared/WatchFaceData.swift`, `SharedCardio/` and `App/Services/WatchSync.swift` was read, plus the AppCore files the Watch compiles (`CardioZoneTracker.swift`, `CardioRoute.swift`, `IntervalSession.swift`) and `project.yml`. Apple's Human Interface Guidelines were read from the JSON behind each HIG page (Workouts, Accessibility, Layout, Buttons, Typography, Digital Crown, Always On, Gestures, Color, Materials, Charts, Widgets, Controls, Pickers, Tab views, Designing for watchOS) [H1]–[H16]. WWDC transcripts were read for "What's new in watchOS 26" [W1], "Deliver workout insights with HealthKit workout zones" (WWDC26) [W2], "Build a workout app for Apple Watch" [W3], "Build a multi-device workout app" [W4] and "Design and build apps for watchOS 10" [W5]. WWDC26 has no "What's new in watchOS 27" session (the session list was checked); Apple's watchOS 27 support page was used instead [A1]. API facts were checked against Apple's documentation JSON [D1]–[D9]. Third-party apps were checked through their App Store pages, developer pages and reviews [T1]–[T12]; none was installed or run, so their interaction details are as reviewers describe them. Two HCI papers were read in full from the authors' PDFs [E1][E2].

**Labels.** Every number below either cites its source or says **app's choice**. Usability numbers rest on Apple's guidance and HCI studies, not on health outcomes; where nothing better exists the spec says so. Health claims (rest times, effort ratings, zones) reuse the citations already in AppCore.

---

## 0. Summary

**Top problems** (details in §2):

1. The set you are about to lift can be off-screen. The live page is one scrolling column: clock, vitals, record banner, rest card and the "Reps left?" grid all sit above the exercise, so during rest the target weight is pushed below the fold.
2. The hierarchy is upside down. The elapsed time is the biggest text (Title 2, 30 pt on a 46 mm watch) and the weight × reps is Title 3 (20 pt), allowed to shrink to 70 %.
3. Changing the weight or reps takes about 7 taps through an "Edit" button at the mini size (28 pt, the HIG floor), then a sheet with +/− buttons.
4. Double tap presses Complete inside a scroll view inside vertical pages, which the HIG says to avoid, and there is no undo: a stray double tap logs a set that can only be fixed on the phone.
5. The Digital Crown scrolls the live page and spills over into other pages. It never adjusts the weight on the main page.
6. There is no Always On handling at all: no use of `isLuminanceReduced` anywhere in `Watch/`.
7. Without the phone, the Watch can't log a single set ("Start empty" records heart rate only).
8. Cardio has one live page with average pace only. It has no current pace, laps, splits, live elevation or auto-pause, and the pages can't be customised.
9. White labels on the tinted buttons measure 1.8–2.7 : 1 contrast (the green Complete button is 1.8 : 1). The HIG asks for at least 4.5 : 1.
10. End screens are plain text rows with no charts. Neither the start screen nor any workout page shows recovery, strain or today's plan, even though the Watch already stores them.

**The new structure in brief:**

- **Home** (one crown-scrolled column). At the top, a recovery and strain glance. Below it, today's plan card (Start), quick-start tiles for Lift and your last cardio, "More activities", and the last activity.
- **Lifting**: a horizontal pager, Controls | **Set** | Rest | Heart | Exercises.
  - The Set page is non-scrolling. It shows big weight × reps; the crown turns the weight through loads your gym can make; tapping reps moves the crown to the reps; one tap or a double tap logs the set; Undo is offered for 4 s.
  - Logging a set moves to the Rest page. It has a ring countdown, −15/+15 s, a tap at 10 s left, a buzz at the end, the next-set preview and the optional 0–4+ "reps left" chips.
  - It runs the phone's live session as now, a plan sent ahead of time, or a quick lift logged with the phone out of reach.
- **Cardio and sports**: a horizontal pager, Controls | **Metrics** | Now Playing, as in Apple's Workout app. Metrics is a crown-driven vertical stack of pages you choose per activity: Main, Heart zones, Pace, Elevation, Splits, Target and Interval. It adds a lap button, auto-laps with a tap at each split, auto-pause for runs, Water Lock for runs and snow, and dimmed Always On views. Sports get heart and zone pages with no target.
- **Summary**: one scrolling page with a zones bar, a heart-rate mini chart, splits or sets, records, and a Handoff "Open on iPhone" row.

**Build plan** (each chunk compiles on its own; §7):

| Chunk | Contents |
|---|---|
| C0 | Shared palette and design components |
| C1 | AppCore logic with tests (load stepper, laps and pace, rest cues, heart-rate series) |
| C2 | Lifting pager (Set, Rest, Heart, Exercises, Controls) with undo and Always On |
| C3 | Cardio pager and metric pages, laps, auto-pause, Water Lock |
| C4 | End summaries with charts |
| C5 | Home and start flows |
| C6 | Contract: plan ahead and lifting without the phone (Watch and iPhone) |
| C7 | Interval sessions on the wrist |
| C8 | Controls, Smart Stack relevance, complication tidy-up |
| C9 | Accessibility and Always On audit, docs |

---

## 1. The current Watch app, screen by screen

### 1.1 Entry points and routing

| Entry | Where | What it does |
|---|---|---|
| App launch | `TensileWatchApp` → `WatchRootView` | Routes by state. A cardio workout that is running or paused shows `WatchCardioPagesView`, and an ended one shows `WatchCardioEndView`. Otherwise it routes on `WatchWorkoutModel.phase`: idle or starting shows `WatchStartView`, running or paused shows the lifting pages, ended shows `WatchEndView`. |
| Complication tap | `tensile://start` (`onOpenURL`) | Clears ended states. Lands on the start screen. |
| iPhone "Start on Apple Watch" | `WatchAppDelegate.handle(_ workoutConfiguration:)` | Strength types start lifting and wait for the phone's snapshot. Other types are mapped to a `CardioActivity` and start at once, with the stored target. |
| Phone request over WatchConnectivity | `WatchWorkoutModel.handle(_ request:)` | `startRecording` (ignored once older than 10 min), `stopRecording` and `discardRecording`. |
| Siri / Shortcuts | `WatchShortcuts.swift` | "Start a workout in Tensile" starts the phone's waiting session, or an empty recording. "Start cardio" opens the cardio list. |
| Complications | `WatchWidgets/` | Recovery & strain (circular, corner, rectangular) and Today's plan (rectangular, corner, circular, inline). Smart Stack relevance comes from date windows only. |

### 1.2 Lifting

```
WatchStartView (ScrollView)
  ├─ phone session waiting: name, "6 exercises · 18 sets", [Start] (double tap)
  ├─ none: "No workout on your iPhone", [Start empty] (double tap; heart rate only)
  ├─ [Cardio] → sheet WatchCardioStartView
  └─ status lines (Starting…, problem, "Scores from your iPhone: 07:12")

Lifting pages: TabView(.verticalPage), the crown pages between them
  ├─ WatchControlsView   Pause/Resume · Skip exercise · Finish → effort sheet · Discard → confirm · phone status
  ├─ WatchLiveView       (default) ScrollView:
  │     elapsed time (title2, orange) / "Paused"
  │     ♥ bpm · kcal (footnote)
  │     record banner (6 s)
  │     rest card: "Rest  1:23", linear bar, [+15s] [Skip] (small)
  │     "Reps left?" 0 1 2 / 3 4+ grid, [Skip] (mini)
  │     warm-up overview/step  OR  exercise block:
  │        name (headline) + A1 chip, machine note
  │        "Set 2 of 4" (footnote)
  │        "8 × 60 kg" (title3, scale ≥ 0.7)  [Edit] (mini)
  │        "Goal 8 reps · Last 60 kg × 8 · 2 left" (caption2, scale ≥ 0.8), phone note
  │        rep counter card (squat/deadlift, beta): [Start set] (small), dots, "Slowing"
  │        "then <partner>"
  │     pinned bottom: [✓ Complete] (36 pt min height; double tap)
  └─ WatchExerciseListView  List of exercises (done tick / "Up next · 4 sets"), tap → live page
Edit → sheet WatchSetEditSheet: reps −/+, weight −/+ (crown on the weight row), [Done]
Finish → sheet WatchSessionEffortSheet: 1–10 grid (3 per row), [End without rating] (small)
End → WatchEndView: Duration, Sets, Avg HR, Max HR, Calories rows, [Done]
```

Set flow today: Complete ticks the set and starts the rest (`WatchWorkoutModel.completeSet`, `.success` haptic). For a working set it then asks "Reps left?" above the rest bar, and a tap sends `rateSet`. Rest ends with one `.notification` tap (`restEnded`). Supersets skip the rest between halves, and drop and rest-pause stages use the phone's `restBeforeSeconds`.

### 1.3 Cardio and sports

```
WatchCardioStartView (sheet, NavigationStack, ScrollView)
  [Start <last activity>] (double tap) · Target ▸ (No target / Easy / Zone 1–5 list)
  Cardio (11) · Sports (12) · Snow (4) as full-width rows · zone source caption
Cardio pages: TabView(.verticalPage)
  ├─ WatchCardioControlsView   Pause/Resume · End → confirm · Discard → confirm
  ├─ WatchCardioLiveView      (default) ScrollView:
  │     clock (title3, orange) + activity glyph / "Paused"
  │     heart rate 46 pt, zone colour, "Zone 3" badge
  │     "Easy 107–133 · In range / Ease off / Pick it up" (caption)
  │     distance · average pace or speed (footnote), kcal (footnote)
  │     pinned bottom: [Pause/Resume] (30 pt min height; double tap)
  └─ WatchCardioZonesView      ScrollView: "Time in zones", 5 rows (Z, bpm range, mm:ss, bar), under Z1, in target
End → WatchCardioEndView: rows (time, distance, pace or speed, climb, top speed, HR, kcal), zone rows, "Map … on your iPhone", [Done] (double tap)
```

Haptics come from the zone tracker: `.notification` when heart rate stays above the band, `.directionUp` when it stays below, `.success` when it comes back in (`WatchCardioModel.play`). A GPS route is recorded outdoors (`WatchRouteRecorder`). The class comment at `WatchCardioModel.swift:18-20` still says "No GPS route is recorded" (stale).

### 1.4 Data the Watch already has

- `WatchSession` snapshots of the phone's live session. Each carries exercises, sets with the last-time ghost, the goal, the target RIR, the set-by-set note, kind and stage rest; achievable loads; superset labels; warm-up steps; the rest end; the unit; and records.
- `WatchFaceData` in the App Group: recovery, band, calibrating, strain, strain target, easy day, plan slots, bed-by window, week count. Only the complications show it.
- `HeartRateZoneScheme` from the phone (`WatchZoneStore`). Without one, Apple Health's zones are used on watchOS 27, else age-estimated zones.
- The WatchConnectivity contract (`Shared/WatchSession.swift`). Phone to Watch: `snapshot`, `request`, `faceData`, `zones`. Watch to phone: `command` (completeSet, rateSet, skipRest, adjustRest, pause, resume, finish, recordingStarted, recordingStopped, warm-up steps) and `summary`.

---

## 2. Usability problems found

Sizes are for the 46 mm Series 12: 416 × 496 px at 326 ppi [A2], so 208 × 248 pt at @2x, and 1 pt ≈ 0.156 mm (derived). Its default text size is xLarge, which the HIG lists for 44/45/49 mm. The 46 mm is assumed to be the same, to verify on the wrist. At xLarge: Title 2 is 30 pt, Title 3 20 pt, Headline and Body 17 pt, Caption 1 16 pt, Caption 2 15 pt, Footnote 1 14 pt and Footnote 2 13 pt [H7].

| # | Problem | Where | Why it matters |
|---|---|---|---|
| P1 | **The set to lift scrolls away.** Clock, vitals, record banner, rest card (about 90 pt) and the reps-left grid (two rows of 44 pt plus a header) stack above the exercise block in one `ScrollView`. During rest, "8 × 60 kg" sits below the fold. | `WatchLiveView.swift:77-104` | The one thing a lifter checks between sets needs a scroll. The HIG asks for "large font sizes" with "the most important information … easy to read" in a workout [H1]. Larger content that adds scrolling cancels out its benefit while moving [E2]. |
| P2 | **Inverted hierarchy.** Elapsed time is `.title2.bold` in orange (30 pt). The weight × reps is `.title3` (20 pt) with `minimumScaleFactor(0.7)`, so it can drop to 14 pt. | `WatchLiveView.swift:184, 292-294` | The least actionable number is the largest. |
| P3 | **Editing a set is slow and tiny.** "Edit" is `.controlSize(.mini)` (28 pt, the HIG's minimum; 44 pt is the default [H2]). It opens a sheet with reps −/+, weight −/+ and Done. Weight +1 step and reps −2 take Edit, +, −, −, Done, Complete and a rating: **7 taps**. The crown works only on the focusable weight row inside a scrolling sheet, with no visible focus. | `WatchLiveView.swift:297-299`, `WatchEffortSheets.swift:5-141` | Tap count and target size both work against you mid-set with chalky hands. The HIG asks for visible feedback when the crown changes a value [H6]. |
| P4 | **Double tap with no undo.** `handGestureShortcut(.primaryAction)` sits on Complete inside a `ScrollView` inside `.verticalPage` tabs. The HIG says "Avoid setting a primary action in views with lists, scroll views, or vertical tabs" [H12]. A misfire logs a set, and nothing on the wrist un-ticks it (no such command exists). The same pattern is on the start screen, the cardio Pause button and the cardio Done button. | `WatchLiveView.swift:421`, `WatchStartView.swift:28,44`, `WatchCardioLiveView.swift:198,208,367` | Double tap is ambiguous: scroll, page, or act. A wrong log feeds the phone's set-by-set autoregulation (`LiveSetCoach.autoregulate`). |
| P5 | **The crown is spent on navigation where it should adjust.** On the lifting pages it scrolls the live column and then flips to Controls or Exercises. The warm-up step page binds it to next/back, so a long cue can't be scrolled. | `WatchRootView.swift:44-51`, `WatchWarmUpView.swift:105-117` | The HIG suggests using the crown "to inspect data in contexts where navigation isn't necessary" and backing every crown action with touch [H6]. The most frequent adjustment, weight, never gets it. |
| P6 | **Under-sized controls on workout pages:** +15s/Skip (`.small`, 32 pt), RIR Skip (`.mini`), Start set (`.small`), warm-up Back and Skip (`.small`), "End without rating" (`.small`), and the cardio Pause bar (30 pt min). | `WatchLiveView.swift:224,395`, `WatchRepCounterView.swift:51`, `WatchWarmUpView.swift:58,145,148`, `WatchEffortSheets.swift:257`, `WatchCardioLiveView.swift:206,214` | 44 pt ≈ 6.9 mm. In a 24-person study, 7 mm targets were missed 2.87 % of the time standing and **9.67 % walking** [E1]. Targets 20–40 % larger compensate for walking [E2]. |
| P7 | **No Always On design.** There is no use of `isLuminanceReduced`. Bright filled buttons and tinted cards stay lit. The rest and warm-up countdowns use `TimelineView(.periodic(by: 1))`, which the system throttles in the background. Apple's guidance is to pause animation, drop sub-second updates and dim non-essential content, and to use `Text` timer styles, which the system keeps updating in Always On [D5][H5]. | `WatchLiveView.swift:206`, `WatchWarmUpView.swift:162` | With the wrist down, the countdown can freeze or jump, and the screen stays bright. |
| P8 | **Rest is minimal.** A thin linear bar, +15 s but no −15 s, one buzz at the end and no warning. There is no next-set preview inside the rest card; it is in the block below, which may be off-screen (P1). | `WatchLiveView.swift:200-230` | Lifters plan the next set during rest. Hevy, Strong and SmartGym all centre the watch on an automatic rest timer with a haptic [T1][T2][T4]. |
| P9 | **No lifting without the phone.** "Start empty" records heart rate only. The live page then says "No sets to log", and the Exercises page says "your iPhone has no workout running". | `WatchStartView.swift:31-44`, `WatchLiveView.swift:119-124` | Hevy, Strong and SmartGym log sets with the phone in the locker [T1][T2][T4]. A gym with poor Bluetooth range loses the whole log. |
| P10 | **The start screen is bare.** It has no recovery, strain or plan glance, though the Watch stores all three for the complications. Cardio is a sheet with 27 activities in one list. A caption2 status line takes the last row. | `WatchStartView.swift` | The HIG asks for "quick, glanceable, single-screen interactions" and anticipating needs [H16]. |
| P11 | **Cardio has one live page.** It shows only average pace over the whole workout (`CardioSummary.pace(seconds:meters:)`), no current or lap pace, no laps or splits, no live elevation, and no choice of pages. Time in zones is a list rather than Apple's single zone page. | `WatchCardioLiveView.swift:213-244` | Average pace can't steer a run. Apple's Workout app has Metrics, Heart Rate Zones, Segments, Splits, Elevation and Power views, chosen per workout [A3]. |
| P12 | **No lap or segment marking, auto-pause, split alerts or Water Lock.** `workoutSession(_:didGenerate:)` isn't implemented, so `motionPaused` events are dropped. | `WatchCardioModel.swift:430-444` | These are standard on Garmin (lap key, Auto Lap, lap alerts) [T9] and in Apple's Workout app. |
| P13 | **Text-only end screens.** Footnote rows; lifting shows 5 numbers and no sets, records or zones. The cardio zones are 5 progress bars. Done uses double tap inside a ScrollView (P4). | `WatchEndView.swift`, `WatchCardioLiveView.swift:478-559` | The HIG asks for a summary that "confirms that a workout is finished and displays the recorded information" [H1], with glanceable charts and details on the phone [H11]. |
| P14 | **Contrast fails on tinted buttons.** `.borderedProminent` puts white labels on the score colours: white on recovery green #3EDB84 is **1.8 : 1**, on strain orange #FF8E3C 2.3 : 1, on lifting pink #FF6B97 2.7 : 1 (measured here with the WCAG formula). The HIG cites WCAG AA: 4.5 : 1 up to 17 pt, 3 : 1 at 18 pt or bold [H2]. Black on the same colours is 7.8–11.7 : 1. | Complete, Start, Done, Pause buttons | The most used button is the least legible. |
| P15 | **Text shrinks below the HIG minimum.** `minimumScaleFactor(0.6–0.8)` on caption2 lines reaches 9–12 pt; the RPE labels at 0.6 reach about 9 pt. The HIG minimum on watchOS is 12 pt [H2]. The warm-up "why" uses `.tertiary` on black. | `WatchEffortSheets.swift:229`, `WatchLiveView.swift:352,359`, `WatchWarmUpView.swift:120` | Unreadable at arm's length in motion. |
| P16 | **Unclear state.** "Paused" is a caption2 word. iPhone reachability shows only on the Controls page. "Recording" with no session doesn't say what is being recorded. Errors are caption2 red lines. | various | The HIG asks for "clear feedback that indicates when a session starts or stops" and a distinct look for an active workout [H1]. |
| P17 | **Silent logging.** A tick changes the text and plays `.success`, with no visual confirmation of which set was logged and no "rest over" state beyond the bar vanishing. | `WatchWorkoutModel.completeSet` | Haptics can be missed while moving. Activity raises the vibration detection threshold [E4], so a visual must pair with the tap. |
| P18 | **VoiceOver gaps.** The elapsed line, rest card and exercise block have no combined labels. Weight and reps aren't adjustable by swipe (no `accessibilityAdjustableAction`). Zone colour is paired with text (good). | `WatchLiveView.swift` | VoiceOver users can't change a set without the sheet. |
| P19 | **Smart Stack and controls.** There are no watchOS 26 controls [W1]. Relevance uses dates only; the gym location (`location(category:)`) [D9] is unused. | `WatchWidgets/` | The plan card could surface at the gym. |

What already works and is kept: the stable-id commands and queued delivery, the phone as owner of the session, the rep counter (beta) gating, supersets and drop or rest-pause stages, the record banner, the warm-up protocol, the zone tracker with its 20 s leave delay, the route recorder, the custom zone configuration on watchOS 27, and the complications' freshness rules.

---

## 3. What the best watch workout apps do (research)

### 3.1 Apple's guidance

- **Workouts (HIG)** [H1]:
  - Show the data people care about "as time passes between wrist raises", with relevant controls "like lap or interval markers".
  - Don't show unrelated parts of the app during a workout.
  - Use "a distinct visual appearance to indicate an active workout".
  - Make workout controls "easy to find and tap" with clear start and stop feedback.
  - Provide a summary.
  - "Discard extremely brief workout sessions".
  - "Use large font sizes, high-contrast colors" for in-motion legibility.
  - The common arrangement is controls on the left, metrics in the middle and media on the right; WWDC21's sample builds exactly that as a `TabView` with Controls, Metrics and Now Playing [W3].
- **Digital Crown** [H6]:
  - Since watchOS 10 the crown is "the primary input for navigation".
  - It can also "inspect data in contexts where navigation isn't necessary".
  - Back every crown action with touch.
  - Give visual feedback and match the update speed to the turn.
  - Apps can't respond to crown presses.
- **Double tap** [H12]:
  - Since watchOS 11 it scrolls lists and advances vertical tabs.
  - A primary action is for "a nonscrolling view", on the button people use most.
  - "Avoid setting a primary action in views with lists, scroll views, or vertical tabs."
- **Always On** [H5][D5]:
  - A workout session keeps the app on screen with the wrist down, at a lower update rate.
  - Pause animation, remove sub-second updates and dim non-essential content.
  - Keep the layout consistent (show controls as unavailable rather than removing them).
  - `Text` date styles (`.timer`, relative) update automatically in Always On.
  - Hide sensitive data. Pace and heart rate in a workout are the HIG's own example of information to keep glanceable.
- **Layout and buttons** [H3][H4]:
  - No more than three glyph buttons or two text buttons in a row.
  - Full-width buttons for primary actions.
  - Toolbar corner buttons get Liquid Glass automatically on watchOS 26.
  - Inline buttons are capsules.
  - Hit regions of at least 44 × 44 pt.
- **Accessibility** [H2]:
  - watchOS controls: 44 × 44 pt default and 28 × 28 pt minimum.
  - Text: 16 pt default and 12 pt minimum.
  - Support enlarging text "by at least … 140 percent in watchOS apps".
  - Contrast to WCAG AA.
  - Convey state with more than colour.
- **Color** [H13]: "Avoid using full-screen background color in views that are likely to remain onscreen for long periods of time, such as in a workout."
- **Charts** [H11]: on the watch, show what can be read "at a glance", keep interactions simple and leave detail to the iPhone.
- **watchOS 26** [W1]:
  - The new design system (Liquid Glass) is applied automatically to toolbars and controls for apps built for watchOS 10 and later.
  - Controls come to Apple Watch (Control Center, Smart Stack, Ultra's Action button) and are built with WidgetKit.
  - HealthKit workout apps can be suggested in the Smart Stack "based on a person's routine" if they set the correct `HKWorkoutActivityType`, accurate start and end times, and an `HKWorkoutRouteBuilder`.
  - RelevanceKit adds date, sleep, fitness and location contexts, including point-of-interest categories.
- **watchOS 27** [A1][W2]:
  - Workout Buddy adds progress insights and runs without the iPhone.
  - Extended and Max Extended workout modes.
  - Better treadmill distance.
  - The Smart Stack gets single-tap selection.
  - HealthKit gains workout zones: live `didUpdateWorkoutZone` updates, `zoneGroupsByType` on the saved workout, and custom configurations set before `beginCollection`.
  - There is no Workout Buddy API for third parties.

### 3.2 Apple's Workout app

- **Metric views** [A3][T12]:
  - Metrics and Metrics 2 have editable fields.
  - Heart Rate Zones shows "your Heart Rate Zone, heart rate, time in the current zone, and your average heart rate".
  - Segments, Splits, Elevation, Power and Activity rings are fixed views you can turn on, off or reorder.
  - The crown moves between views.
- **watchOS 26 layout** [T5]: four corner buttons give quick access to workout views, custom workouts, Pacer and Race Route; reviewers also mention alerts and Workout Buddy.
- **Custom workouts** [A3]: warm-up, work and recovery intervals, cool-down, alerts; they can be built on the iPhone since iOS 26 [T5].
- **watchOS 27 layout** [A1]: quicker access to goals, music, views and alerts.

### 3.3 Third-party apps

| App | What reviewers and listings report | Take for Tensile |
|---|---|---|
| **Hevy** [T1] | Tracks workouts from the watch with the phone in the locker. Routines sync. Heart rate, timers for timed exercises, set types. Some users report errors when ending. | Log lifts without the phone, from a plan sent ahead (P9). Make ending robust. |
| **Strong** [T2] | A full standalone logger. "3-tap logging". Auto rest timer with haptics. Supersets and drop sets on the wrist. | Fewest taps per set, auto rest. |
| **SmartGym** [T4] | "Double Tap predicts your next move. Log a set, start a rest timer, advance to the next exercise." One-tap default logging with an "Advanced Logging" edit. Colour-coded zone bar at the top. Smart Stack widgets "right before your usual training time". Fully standalone. | Context-dependent double tap (Done on Set, Next on Rest). A zone strip. Smart Stack timing. |
| **RepCount, Gravitus, Jefit** [T3] | One-tap set logging, haptic rest alerts, offline with sync. | Same pattern; nothing new. |
| **WorkOutDoors** [T6] | Configurable screens with 4 layouts and 3 text sizes. Hundreds of fields. Manual or automatic laps with current- and previous-lap versions of each metric. Maps. One-time purchase. | Per-activity metric pages, lap metrics. Skip the map on the wrist (reviewers call it "of limited utility" on the small screen). |
| **Garmin** [T9] | Per-activity data screens with a chosen field count. A lap key that can be turned off. Auto Lap by distance. A lap alert with one or two chosen fields. | Lap button plus Auto Lap (1 km or 1 mi) with a short alert showing split time and pace. |
| **Runna** [T7] | Interval steps advance by themselves and "buzz at every change". A pace-target screen shows ahead or behind for the rep. "Double Tap to End Lap" ends a step. Customisable screens. No phone needed outdoors. | Interval runner with a buzz at each step and a target page. Double tap is not used on scrolling or vertical pages, so step skip is a button. |
| **Strava** [T8] | The 2025 redesign: "clearer, more glanceable in-workout stats" (pace, distance, heart rate). Some reviewers still prefer Apple's Workout app mid-run. | Glanceability over feature count. |
| **Gentler Streak** [T10] | Real-time heart rate zones with interpretation ("ease off or push"). Activity tailored to recovery. | Tie Home and the zone page to today's recovery and easy-day guidance. |
| **Athlytic** [T11] | Colour-coded zone chart, current zone, in-workout effort score. A live route map swiped to between stats and Now Playing, zoomed with the crown. Zone-coloured route in the summary. | Zones bar plus summary; the map stays on the iPhone. |
| **Slopes** [T13] | Lift versus run detection without manual pausing. "Easy to handle even with your gloves on." | Snow: big targets, Water Lock against glove and sleeve taps. Run counting is out of scope: no API, and own detection is unreliable per reviewers. |

**What makes set logging fast on a wrist** (common to Strong, SmartGym, Hevy and the HIG):

1. The planned set is pre-filled, so "as planned" is one tap.
2. The most likely change, weight, is on the crown with detents, stepping only through loads the gym can make.
3. One primary button (Done) answers double tap on a non-scrolling page.
4. The rest timer starts by itself, with a haptic at the end and the next set visible.
5. Effort is optional and one tap.
6. Undo is quick.
7. It works without the phone.

### 3.4 Evidence behind the interaction numbers

- **Targets while moving.** Dobbelstein, Haas and Rukzio (ISWC 2017, n = 24) used 7 mm round targets. Walking raised the miss rate from 2.87 % to 9.67 %. Swipes stayed under 0.6 % errors in every condition [E1]. Schildbach and Rukzio (MobileHCI 2010, n = 16) found that walking raised target-selection errors 23 %; targets 20 % larger helped significantly and 40 % larger "almost completely compensated". Larger text did **not** help reading while walking, because it added scrolling [E2]. So on the Watch, primary in-workout buttons go above 44 pt, and pages don't scroll.
- **Glance length.** Most watch interactions are short. In the in-vivo Apple Watch study, glances at the face or a notification were under about 3 s [E3]. This comes from a follow-on chapter, not checked against the CHI paper, so it is weak. It supports one number per region and no reading tasks mid-set.
- **Vibration while active.** Voluntary movement raises the vibration detection threshold [E4]. Another study found no standing-versus-running effect on recognising patterns [E5]. The evidence is mixed. Pair every alert haptic with a visual state change, and keep distinct patterns for distinct events.
- **Effort ratings.** The reps-in-reserve scale (Zourdos 2016; Helms 2016) and an error of about one rep (Halperin 2022) are already cited in AppCore (`SetFeedback`, `VolumeProgression`). Whole-rep chips 0–4+ match that resolution.
- **Rest lengths.** These come from the phone (`RestTimer`, `TrainingTools.swift`: Singer 2024, Schoenfeld 2016, Grgic 2018, ACSM 2009). The Watch never invents one except the standalone default in §4.4.8.
- **Wrist heart rate while lifting.** The Apple Watch was accurate in squats, deadlifts and rows but worse in overhead and burpee-type movements (`watch-features.md` [B19]). So heart rate is a secondary page in lifting, not the set page's headline.

---

## 4. The redesign

### 4.1 Principles

1. **One page, one job, no scrolling** during a workout. Scrolling is only for lists (Exercises, the activity list, summaries).
2. **The crown adjusts on the Set page and navigates elsewhere.** Lifting pages page horizontally by swipe (Apple's Controls | Metrics | Media arrangement [H1][W3]), so the crown is free for weight and reps. Cardio metric pages are vertical and crown-driven, as in Apple's Workout app.
3. **Double tap does the obvious next thing**, on non-scrolling pages only: Set → Done, Rest → Next set, session preview → Start. It isn't used on Home, lists, summaries or the cardio vertical pages, where the system scrolls or pages instead [H12].
4. **Every logged action can be undone for 4 s**, then the edit belongs to the phone.
5. **Haptic plus visual** for every alert.
6. **Always On dims and freezes**, with layouts unchanged [H5].
7. **Phone or no phone, the same screens.**

### 4.2 Information architecture

```
Home (NavigationStack root, crown scrolls)
 ├─ Glance header: recovery ring + band word, strain bar vs target     (tap → Today detail sheet)
 ├─ Today's plan card: "Push · 6:00 pm · 55 min" [Start]               (→ Session preview)
 │     or "Rest day" / "Easy day: keep it easy" / "Bed by 10:30" (PlanGlance wording)
 ├─ Quick start: [Lift] [Outdoor run ↺]                                (last cardio)
 ├─ Hard cardio this week: "4 × 4 min · Bike" [Start]                  (when sent, §4.6)
 ├─ More activities ▸  (Cardio · Sports · Snow, grouped list)
 ├─ Last activity: "Pull · Tue · 52 min · 16 sets" ▸ (summary)
 └─ Footer: "Scores from iPhone 07:12" · Settings ▸ (pages per activity, units, haptics)

Session preview (non-scrolling): name, exercises · sets · minutes, phone status, [Start] (double tap)
Lifting  : Controls | Set* | Rest | Heart | Exercises      (horizontal pager)
Cardio   : Controls | Metrics* (vertical pages) | Now Playing
Summary  : one scrolling page → [Done] (no double tap; Done also in the toolbar)
```

How the flows differ:

| | Lifting | Steady cardio | Sports (court, field) | Snow |
|---|---|---|---|---|
| Start | Plan card, phone session, or Quick lift | Last-activity tile or list; target picker | List; no target (`CardioActivity.takesTarget`) | List; no target |
| Main page | Set (weight × reps) | Main metrics (time, heart rate + zone, pace or speed, distance) | Heart rate + zone, time, kcal | Speed, distance, time, heart rate |
| Default pages | Set, Rest, Heart, Exercises | Main, Heart zones, Pace (on foot) or Speed, Splits, Elevation (outdoor), Target (if set) | Main, Heart zones | Main, Heart zones, Elevation |
| Laps | — | Lap button + Auto Lap | Lap button (periods, sets) | — |
| Auto-pause | — | Runs (§4.5.5) | — | — |
| Water Lock | — | Offered | — | Offered |
| Double tap | Done / Next set | Pages (system) | Pages (system) | Pages (system) |

### 4.3 Home

- **Glance header.** Recovery in a 10-segment ring with the number and band word ("Recovered", "Normal", "Easy day", "Calibrating"); strain as a bar with the target range outlined. It reuses `SegmentedRing` and `StrainBar` (moved to Shared, C0) and the complications' freshness rules (`scoresAreCurrent`, `GlanceFreshness.strainIsCurrent` from `Glances.swift`, which the Watch app starts compiling in C5), so Home and the face never disagree. A stale reading shows "--" with "Open Tensile on iPhone".
- **Today's plan card.** It uses `PlanGlance.lines(for:at:onWatch:)` wording, so it matches the complication.
  - When a phone session is live, the card reads "On your iPhone: Push · 3 of 18 sets" with [Join].
  - When a plan was sent ahead (C6), it reads [Start] and runs on the wrist alone.
  - On an HRV-guided easy day (`WatchFaceData.easyDay`), the card adds "Easy day: keep the plan light". The guidance is the phone's own, not new advice.
- **Quick start.** Two 64 pt tiles (app's choice; ≥ 44 pt [H2]): Lift (opens Quick lift or the plan) and the last cardio activity (one tap starts it with its stored target).
- **No TopGlow wash on workout pages** [H13]. Home and the summary may carry a faint wash of the lifting or recovery colour at the top (app's choice; the iPhone app's `TopGlow` look).

### 4.4 Lifting in-workout

#### 4.4.1 Pager

`TabView(.page)`, horizontal: **Controls | Set | Rest | Heart | Exercises**. It opens on Set.

- Done animates to Rest. Rest ending, Skip or Next set animates back to Set. With Reduce Motion, these jumps cross-fade without sliding.
- If the user has swiped to Heart or Exercises, the pager does not yank them away. The rest end still buzzes, and the toolbar's rest chip flashes.

Every page has the same toolbar:

- leading: elapsed time, 15 pt monospaced, plus a pause glyph when paused;
- trailing: heart rate in the zone colour;
- centre: a rest chip "1:42" while rest runs on another page.

Toolbar items are system glass on watchOS 26 [H4][W1]. The clock in the top right stays where the system puts it.

#### 4.4.2 Set page (non-scrolling)

```
┌────────────────────────────┐
│ 12:34   ⏱1:42?      ♥ 128  │  toolbar (15 pt)
│ Bench press           A1   │  Headline 17 pt, 1 line, middle-truncated
│ Set 3 of 4 · Goal 8        │  Footnote 14 pt secondary  ("Drop 1 of 2" in lifting pink)
│                            │
│  ⟨ 82.5 ⟩ kg               │  48 pt rounded bold numerals; crown focus ring
│   ×  8   reps              │  34 pt; tap → crown moves here
│ Last 80 × 8 · 2 left       │  Footnote 14 pt (ghost) or the phone's note
│ ┌────────────────────────┐ │
│ │       ✓  Done          │ │  60 pt, full width, black label on recovery green
│ └────────────────────────┘ │
└────────────────────────────┘
```

- **Crown.** By default the crown steps the weight through `ExerciseSnapshot.achievableLoadsKg` (the gym's plates, dumbbells and stacks, as CLAUDE.md requires of the trainer), else by `WatchSession.step`. Each step has a detent and a `.click` [H6]. Tapping the reps moves the focus (and the ring) to reps, 0–50 by 1. Tapping the weight moves it back. For a hold (`isHold`) the crown sets seconds in 5 s steps (existing app's choice in `WatchHoldAdjuster`) and the weight is hidden. The logic moves to AppCore `LoadStepper` with tests (C1).
- **Done.** 60 pt full width (app's choice: 44 pt × 1.36, inside the 20–40 % walking margin [E2]). Double tap presses it (`handGestureShortcut(.primaryAction)`; the page doesn't scroll [H12]).
  - On Done: a `.success` tap, a 0.6 s "✓ Set 3 logged" tick-over (cross-fade under Reduce Motion), then the move to Rest.
  - The command is held for the undo window (§4.4.7).
- **Warm-up sets** read "Warm-up 1 of 2" and skip the RIR question (as now).
- **Supersets.** An "A1 → A2" chip. After A1 the pager stays on Set and shows A2 (no rest, as now).
- **Drop and rest-pause stages.** A stage shows "Drop 1 of 2" and uses the phone's `restBeforeSeconds`; a drop has no rest page (as now).
- **Rep counter (beta, squat and deadlift).**
  - It is not a card. The reps line shows a small "Count" glyph button (44 pt hit area) that starts counting.
  - While counting, the reps value fills in live, the dots sit under it, and "Slowing" appears as a strain-orange word.
  - Rules are unchanged (Hickmott 2022 via `RepDetection`).
- **Machine note** ("Seat 4 · Pin 7") replaces the ghost line; tap the line to swap between them.
- **Fit.** Content height ≈ 22 + 18 + 52 + 38 + 18 + 8 + 60 ≈ 216 pt in 248 pt, with toolbar space reserved. On the 42 mm Series 12 (374 × 446 px [A2], about 187 × 223 pt) and at large Dynamic Type sizes, a `ViewThatFits` fallback first drops the ghost line to an info button, then shrinks the numerals to the scaled-metric floor. It never goes below Footnote 2 (13 pt).

**Taps per set** (P3):

| Task | Now | New |
|---|---|---|
| Log as planned | 1 (+1 optional rating) | 1 tap or double tap (+1 optional rating) |
| +1 weight step, −2 reps | 7 (Edit, +, −, −, Done, Complete, rating) | 3 taps + 2 crown turns (turn, tap reps, turn, Done, rating) |
| Undo a mistaken log | not possible on the wrist | 1 (Undo within 4 s) |

#### 4.4.3 Rest page (non-scrolling)

Two states.

- **(a) Just logged, working set** (not a warm-up, hold or stage, as now):

```
│ Reps left?          ◔ 1:58 │  Headline 17; 44 pt mini ring with Text(timerInterval:)
│ [ 0 ] [ 1 ] [ 2 ]          │  3 + 2 chips, 52 pt tall (app's choice), lifting tint outline
│ [ 3 ] [ 4+]   [Skip]       │  Skip is a 44 pt text chip
```

  A tap logs RPE = 10 − reps left through the existing `rateSet` (Zourdos 2016, as now), shows "2 left ✓" and collapses to (b). With no answer, it collapses after 15 s (app's choice: long enough to answer on a wrist raise, short enough to clear before the next set).

- **(b) Resting:**

```
│ Rest                Skip › │  Skip: 44 pt
│        ╭───────╮           │
│        │ 1:42  │           │  ring 120 pt, track + arc (nonisolated Shape), digits 40 pt
│        ╰───────╯           │  Text(timerInterval: now...end, countsDown: true)
│  [ −15 ]        [ +15 ]    │  48 pt circles (app's choice)
│ Next: Bench 82.5 × 8   ✎   │  Footnote 14; tap → Set page
```

- **Next set** (double tap). The primary action starts the next set early: skip rest, go to Set. That is the next move, as SmartGym does [T4].
- **±15 s.** Steps stay at 15 s (existing app's choice); the timer never goes below 0. −15 needs no contract change: `WatchCommand.adjustRest(seconds:)` already carries a signed value. The phone side (`RestTimerStore.adjust(by:)`) must clamp at 0, to check in C2.
- **Haptics.**
  - 10 s left: one `.click` (app's choice, the watch-features.md §2.4 idea trimmed to one warning; no evidence either way).
  - End: `.notification` (as now; off when the phone's rest-alert setting says so, `restBuzz`).
  - The end also flips the page to "Go" for 3 s with the next set in Title 2. In Always On, the "Go" state stays until the wrist is raised.
- **Rest length.** From the phone (`restSeconds`, `restLengthSeconds`) as now; standalone in §4.4.8.

#### 4.4.4 Heart page

- Heart rate at 46 pt in the zone colour.
- A 5-segment zone bar with the current segment raised and its number printed ("Z3"), plus time in the current zone. This is the layout of Apple's Heart Rate Zones view [T12].
- A 10-minute heart-rate sparkline (a `Path` in a `nonisolated` Shape; no Canvas), average and maximum.
- The zone scheme is the phone's (`WatchZoneStore`), and zone time comes from `CardioZoneTracker`, which the lifting model starts using too (C2). The same rules apply as in cardio and on the phone (`HeartRateZoneScheme.zoneMinutes`).
- A caption, once per workout: "Wrist heart rate reads less well in overhead lifts" (watch-features.md [B19]).

#### 4.4.5 Exercises page

- `List` (crown scrolls; no primary action).
- Each row has a 28 pt progress ring (done / total working sets), the name in Headline, and "3 of 4 · next 82.5 × 8" in Footnote. The A/B superset label sits in the ring.
- Tap a row to select it and jump to Set (as now, `selectedExercise`).
- Swipe a row for "Skip" (the existing `skipExercise` semantics).
- In standalone sessions only: "Add exercise" at the end, from the library (§4.4.8).

#### 4.4.6 Controls page

- A 2 × 2 grid of 64 pt circular glass buttons (`.buttonStyle(.glass)`; app's choice for size; at most 2 per row [H3]): **Pause/Resume** (yellow glyph), **Finish** (flag, lifting pink), **Skip exercise**, **Discard** (red, confirmation).
- Below the grid, one status line in Footnote 14: "iPhone connected" or "iPhone out of reach · sets saved on Watch".
- Finish leads to the session-effort sheet (Foster's CR-10 as now) with 48 pt chips and a 44 pt "Skip".
- Paused state: the Set page dims and shows a full-width "Paused · Resume" button (60 pt; double tap resumes). This is a distinct paused look [H1].

#### 4.4.7 Undo

- After Done, a toolbar chip "Undo" (44 pt) shows for **4 s** (app's choice: long enough for a wrist raise, short enough not to delay the phone much). The `completeSet` command is held on the Watch for that window.
  - Undo inside the window un-ticks the set locally and nothing reaches the phone.
  - After the window, the command goes with `sentAt` set to the tap time, so the phone's rest and `completedAt` use the real moment (`LiveWorkoutRules.remainingRest`, `completedAt`).
- This avoids a new "uncomplete" command, which would have to undo the phone's set-by-set autoregulation.
- After the window, a logged set is changed on the phone (stated in the Exercises row's swipe hint).
- The rest timer and the RIR question start at once on the Watch; Undo cancels both.

#### 4.4.8 Phone-synced and standalone sessions

| Case | How it starts | Who owns the log | What the phone gets |
|---|---|---|---|
| **Phone session running** (today's path) | Phone "Start on Watch", or the Home card [Join] | Phone; the Watch sends commands (queued when out of reach, as now) | Commands + `WatchWorkoutSummary` (unchanged) |
| **Plan sent ahead** (new, C6) | Home plan card [Start] with the phone anywhere | Watch, a local `WatchSession` built from the plan snapshot | `WatchWorkoutSummary.loggedExercises`. The phone creates the `WorkoutSession` and its sets when the summary arrives. If the phone starts the same plan meanwhile, it shows "Running on Apple Watch" and doesn't start a second one. |
| **Quick lift** (new, C6) | Home [Lift] → pick from recent exercises (library sent ahead) or "Heart rate only" | Watch | As above, named "Watch workout" |

- **Rest in standalone sessions.** The plan snapshot carries the phone's per-exercise rest (`restSeconds`), so the evidence-based defaults (`RestTimer`) still apply. A quick lift with no plan uses **120 s**: the app's choice between the ≥ 90 s that suffices for growth (Singer 2024) and the 2–3 min that heavy compound lifts want (Schoenfeld 2016; Grgic 2018). It is adjustable with ±15.
- **Loads in standalone sessions.** The library carries each exercise's achievable-load window (`achievableLoadsKg`), so the crown only offers makeable loads, as on the phone.

### 4.5 Cardio and sports in-workout

#### 4.5.1 Pager

`TabView(.page)`: **Controls | Metrics | Now Playing** (`NowPlayingView`, system; app's choice to include it, as Apple's arrangement [H1]). Metrics is `TabView(.verticalPage)`: the crown and the system's double tap move between metric pages [H12]. There are no primary actions inside Metrics.

#### 4.5.2 Metric page catalogue

Each page is non-scrolling, with at most four values. The primary value is 40–48 pt and secondary values are 20–30 pt (Title 3 to Title 2), rounded monospaced numerals (sizes are app's choice following "use large font sizes" [H1] and the HIG type scale [H7]).

| Page | Content | Activities |
|---|---|---|
| **Main** | Time (Title 2), heart rate 48 pt in zone colour with the zone number, current pace or speed, distance | All (sports: time, heart rate, kcal) |
| **Heart zones** | Apple's layout [T12]: 5-segment bar, current zone number and its bpm range, heart rate, time in the current zone, average heart rate | All |
| **Pace** | Current pace (20 s rolling, the same window as `CardioRoute.speedWindowSeconds`, app's choice), lap pace, average pace | On foot |
| **Speed** | Current, lap and average speed; maximum | Cycling, snow |
| **Elevation** | Current altitude, gain so far, 30-minute profile sparkline (Apple's Elevation view shows the last 30 minutes [A3]) | Outdoor with GPS |
| **Splits** | The last 3 splits as bars (time per km or mi) with numbers; current split progress; a big **Lap** button (60 pt) | Distance activities |
| **Target** | The band as a vertical gauge with heart rate as a moving marker; "In range / Ease off / Pick it up" in words; time in band. With an interval session (§4.6): step name, step time left ring, the step's band and effort cue. | When a target or interval is set |

- **Customisation.** Choose and reorder pages per activity in Home → Settings → "Pages for Outdoor run" (`List` with `onMove` and toggles), stored per `CardioActivity.rawValue` in UserDefaults. The defaults are in §4.2. This mirrors Apple's per-workout views [A3] and WorkOutDoors' per-activity screens [T6], without a field editor (app's choice: page choice covers most needs with far less UI).
- **Indoor cycle and machines** get no pace or speed page unless the workout reports distance (as now, `CardioActivity.movement`).

#### 4.5.3 Laps, segments and split alerts

- **Manual lap.** The Splits page's Lap button and the Controls page's Lap button add an `HKWorkoutEvent(.segment)` to the builder over the lap's interval, and start a new lap in `LapTracker`. `.lap` is meant for equal-distance laps such as a track or pool, and `.segment` for periods of interest [D2][D3].
- **Auto Lap.** Every 1 km, or 1 mi where `watchUsesMiles()`. That is the app's choice, following the Garmin Auto Lap convention [T9] and Apple's splits [A3]. It adds `.lap` events with a start and end [D3].
- **Split alert.** One `.navigationGenericManeuver` tap ("a new navigation step" [D7]; app's choice of pattern). A 3 s banner over any page shows "Km 3 · 5:12 /km". In Always On it stays until the next wrist raise.
- **Sports.** The Lap button doubles as "period" (halves, games); there are no auto laps.
- `LapTracker` is pure AppCore with tests (C1), fed `(time, cumulative distance)` from the builder's distance statistics. Pace for the Pace page uses the same samples.

#### 4.5.4 Haptics during cardio

| Event | Pattern | Source |
|---|---|---|
| Heart rate above the band for 20 s | `.notification` | Existing tracker (`CardioZoneTracker.leaveSeconds`, app's choice documented there) |
| Below the band for 20 s | `.directionUp` | Existing |
| Back in the band | `.success` | Existing |
| Split or lap | `.navigationGenericManeuver` | §4.5.3 |
| Interval step change | `.start` (work) / `.stop` (recovery) | `WKHapticType` meanings [D7]; app's choice |
| Auto-paused / resumed | `.stop` / `.start` | Same as manual pause, as now |

Every haptic pairs with a visual state change (§3.4).

#### 4.5.5 Auto-pause: feasible for runs

- **Runs.** HealthKit generates `.motionPaused` and `.motionResumed` events "during running workout sessions" when the user has the system Settings › Workout › Autopause switch on [D1]. Apple's engineer advises not pausing the session for these. Instead, add pause and resume events to the live builder, so elapsed time and metrics leave the stop out [F1].
  - Spec: implement `workoutSession(_:didGenerate:)` in `WatchCardioModel`. On `.motionPaused`, add a `.pause` event to the builder and pause the zone tracker, the route points (`route.isPaused`) and `LapTracker`. Show "Auto-paused" (Title 3, strain orange) with a `.stop` tap. Reverse all of it on `.motionResumed`.
  - The clock uses the builder's elapsed time.
  - The toggle is the system's, so the Controls page shows "Auto-pause: on in Watch Settings" when the first event arrives.
- **Cycling, walking and others.** No system events [D1]. An own detector (GPS speed under a threshold for a few seconds) is possible but its thresholds would be the app's untested choice. **Deferred**; not in this plan.

#### 4.5.6 Water Lock

- A "Lock" control on the Controls page calls `WKInterfaceDevice.current().enableWaterLock()` [D4]. Unlocking is by turning the crown (system); the app can't unlock it.
- Allowed only in the foreground during an active workout on a WR50 device; the Series 12 qualifies.
- Offered for outdoor runs (rain and sweat) and snow (gloves and sleeves, which Slopes users mention [T13]). That is the app's choice; Apple turns it on automatically only for swims.
- There is no swim activity in `CardioActivity`, so no automatic lock.

#### 4.5.7 Always On (cardio and lifting)

| Element | Active | Reduced luminance (`isLuminanceReduced`) |
|---|---|---|
| Primary numbers | Full colour | White at 85 % (app's choice); zone colour kept as a 4 pt underline only |
| Filled buttons (Done, Lap, Resume) | Filled | Stroked outline, label 70 % (HIG's "stroked outlines and dimmed interiors" [D5]); still tappable (taps wake the app [D5]) |
| Rings and bars | Filled arc | Arc kept, track hidden, 60 % opacity |
| Timers | `Text(timerInterval:)` / `.timer` | Same view: the system updates it [D5]; no sub-second digits [D5] |
| Heart-rate sparkline, banners, chips | Shown | Sparkline hidden; banners stay; RIR chips outlined |
| Animations (tick-over, page slides, pulsing heart) | On | Off; finish the motion to a rest state [H5] |
| Toolbar | As active | As active (consistent layout [H5]) |

No content is hidden for privacy; pace and heart rate are the HIG's example of what to keep visible [H5]. Users can turn Always On off per app.

### 4.6 Interval sessions on the wrist (hard cardio)

- `IntervalSession` was built to run on the Watch: Foundation-only, Codable, one file plus `+Zones` (its header says so). The phone already plans one hard session a week (`HardCardio`; Helgerud 2007, Wen 2019, cited in `IntervalSession.swift`).
- New: the phone sends this week's session (contract §5). Home shows "4 × 4 min · Bike" and starts it in cardio mode with `modality.watchActivity`.
- **The Target page becomes the Interval page:** step title ("Hard 2 of 4"), the step's time left as a ring, the step's band (`Band.heartRateBand(in:)`) as the target, and the effort cue ("Effort 8–9 of 10 · talk in short words").
- **Step change:** a `.start` (work) or `.stop` (recovery) tap plus a 3 s banner (Runna's "buzz at every change" [T7]).
- **Skip step** is a 44 pt button on the Interval page; there is no double tap, because Metrics are vertical pages [H12].
- `CardioZoneTracker` gets a `retarget(_:at:)` so the band can change mid-workout without losing zone time (AppCore, with tests, C7).

### 4.7 End summary

One `ScrollView` (crown; no primary action), sections in order. The detail lives on the iPhone [H11].

**Lifting:**

1. Header: "Push · saved", time, sets done, "3 records".
2. Records (if any): the record lines from the phone's note (`WatchRecordNote`), or "Checked on iPhone" if the phone was away.
3. Sets list, compact: "Bench 4 × 8 · 82.5 kg" per exercise.
4. Heart: average and maximum, and a zones bar (one 12 pt stacked bar with the 5 zone colours, widths by time, numbers under it).
5. Heart-rate mini chart for the whole session (≤ 60 points, one per minute or coarser; app's choice matching the phone's per-minute convention).
6. Session effort if given.
7. "Open on iPhone" (below).
8. Done (60 pt) and a toolbar ✓.

**Cardio:**

1. Header.
2. Big time, distance, average pace or speed.
3. Zones bar.
4. Heart-rate mini chart.
5. Splits bars (up to 10, fastest highlighted).
6. Elevation gain.
7. In-target share.
8. Laps count.
9. "Open on iPhone".
10. Done.

**"Open on iPhone".** The summary advertises a Handoff `NSUserActivity` ("com.lontraindustries.workoutapp.viewWorkout", with the workout UUID), and the row reads "Map, splits and coach notes on your iPhone". Handoff from watchOS to iOS needs to be checked on the devices in C4. If it doesn't surface, the row stays as text and the phone shows the summary when it next opens (lifting already opens its finish sheet through the `finish` command).

**Brief workouts.** If a workout ends under 60 s after it started, the Watch asks "Save this 0:42 workout?" before saving. The HIG asks to discard or ask [H1]; the 60 s is the app's choice. The existing 10-minute cut-off for the complication's "done" stays.

Charts are `Shape`s declared `nonisolated` (zones bar, sparkline, split bars). No Canvas, no Swift Charts animation, and no interaction beyond scrolling [H11].

### 4.8 Visual system

#### 4.8.1 Type (46 mm, default size xLarge [H7])

| Role | Size | Style |
|---|---|---|
| Primary numeral (weight, heart rate on Main, rest digits) | 48 pt (rest digits 40 pt) | `.system(size:weight:.bold, design:.rounded)` via `@ScaledMetric(relativeTo: .title)`, monospaced digits. App's choice above Title 1 (38 pt), following "large font sizes" [H1] |
| Secondary numeral (reps, pace, distance) | 30–34 pt | Rounded semibold, `@ScaledMetric(relativeTo: .title2)` |
| Page title / exercise name | 17 pt | Headline |
| Supporting line | 14 pt | Footnote (Footnote 1) |
| Smallest allowed in a workout | 13 pt | Footnote 2. App's choice above the HIG 12 pt minimum [H2]; no `minimumScaleFactor` that crosses it |
| Toolbar values | 15 pt | Caption 2, monospaced |

- Weights use `.semibold` and `.bold`, never light [H7].
- Dynamic Type up to AX3 must work: the HIG asks for 140 % on watchOS [H2]. `ViewThatFits` drops secondary lines first.

#### 4.8.2 Colour

- One shared palette, `Shared/WatchPalette.swift`, compiled by the Watch app and its widgets. It merges `WatchTheme` and `FacePalette` (the same hexes, the dark variants of `App/Design/Theme.swift`):
  - scores: lifting #FF6B97, strain #FF8E3C, recovery #3EDB84, heart #FF6E86;
  - zones 1–5: #7DBBFF, #3ADBA6, #FFD24D, #FF9A4D, #FF5C7A;
  - plan and recovery bands: sleep #9692FF, easy #5C9DFF, normal #FFC53D;
  - track: white at 18 %.
- Each score has its two-colour gradient pair, as on the phone (`Theme.strainColors` etc.), used only for rings and bars.
- **Labels on filled tints are black** (7.1–14.6 : 1, measured), never white (1.4–3.0 : 1). On black, every palette colour passes 7 : 1 (measured), so coloured numbers on black are fine.
- State is never colour alone: zones print their number, the band state prints words, and records print a trophy glyph [H2].
- The background is black on workout pages [H13]; any wash is limited to Home and the summary.
- Colour providers and Shapes are `nonisolated` (CLAUDE.md).

#### 4.8.3 Tap targets and spacing

| Element | Size | Source |
|---|---|---|
| Any control | ≥ 44 × 44 pt | HIG default [H2] |
| Primary in-workout (Done, Lap, Resume, Next set) | 60 pt tall, full width | App's choice: ≈ +36 % over 44 pt, within the 20–40 % that offsets walking [E2]; 44 pt ≈ 7 mm, missed 9.7 % walking [E1] |
| Secondary circles (±15, controls grid) | 48 pt / 64 pt | App's choice (≥ 44 pt) |
| Chips (RIR, effort) | 52 pt / 48 pt tall | App's choice |
| Buttons per row | ≤ 3 glyph or 2 text | HIG [H3] |
| Gap between adjacent targets | ≥ 8 pt | App's choice (the HIG's ~12 pt [H2] doesn't fit a 208 pt screen with two 48 pt circles plus the ring) |

#### 4.8.4 Liquid Glass (watchOS 26)

- System toolbars, sheets and buttons pick up the new look automatically [W1][H4].
- Glass is for controls only: the toolbar items, the Controls grid (`.buttonStyle(.glass)`), and the Done button (`.glassProminent` tinted recovery, with a black label, contrast to verify on device).
- Metrics, rings, the set card and the summary are content: no glass, no material.
- No glass on glass. On glass, text is `.primary`, with hierarchy from size and weight.
- Reduce Transparency is handled by the system.
- watchOS 26 is the deployment target, so the glass styles need no `#available` gate. watchOS 27-only APIs do (§6).

### 4.9 Smart Stack, controls and Siri

- **Relevance.** Add a `.location(category: .fitnessCenter)` relevance attribute to "Today's plan" on training days, so the card rises at the gym [D9]. To verify: that `fitnessCenter` is a supported category (the call returns nil otherwise [W1]) and that no location permission is needed. Keep the date windows.
- **Workout suggestions.** The Watch already sets the right `HKWorkoutActivityType` and uses a route builder outdoors, which is what watchOS 26 needs to suggest Tensile workouts in the Smart Stack [W1]. Keep recording the real start: the lifting model's 15-minute back-dating to the phone's start is still "accurate start" for that session.
- **Controls (watchOS 26)** [W1]. Two `ControlWidgetButton`s in the widget extension:
  - "Start lifting": opens the app on the Session preview, or Quick lift.
  - "Start <last cardio>": opens the app and starts the activity, as `StartCardioIntent` does plus starting.
  - Both run `openAppWhenRun` intents shared with the app (the intents move to `Shared/WatchIntents.swift`).
  - They can live in Control Center and the Smart Stack.
- **Siri.** The existing App Shortcuts stay. Add "Log my set in Tensile" only if double tap and the crown prove insufficient (not planned).
- **Phone Live Activity on the Watch.** It already shows in the Smart Stack via `.supplementalActivityFamilies([.small])` when the phone runs a workout. When the Watch app records the same workout it is redundant but harmless; no change.

### 4.10 Accessibility

- **VoiceOver.**
  - Set page:
    - the weight is one element, "Weight, 82.5 kilograms", with `accessibilityAdjustableAction` stepping through the same loads as the crown;
    - reps, the same;
    - Done reads "Log set 3 of 4, 82.5 kilograms, 8 reps";
    - the ghost line reads "Last time 80 kilograms, 8 reps, 2 in reserve".
  - Rest: "Rest, 1 minute 42 seconds left" (`.updatesFrequently`). At the end, an `AccessibilityNotification.Announcement("Rest over. Next: bench press, 82.5 kilograms, 8 reps")`.
  - Zones bar: "Zone 3 of 5, 146 to 159 beats per minute, 12 minutes in zone".
  - Charts: a summary label ("Heart rate from 92 to 171, average 138") rather than per-point elements.
  - Toolbar values: combined labels.
- **Voice Control.** Visible button text equals the label ("Done", "Skip", "Lap").
- **Dynamic Type.** All text uses styles or `@ScaledMetric`. Test at AX3. `ViewThatFits` fallbacks keep pages non-scrolling down to the minimum, and switch to a scroll view only at AX sizes. There, double tap is disabled on that page (`isEnabled:` false) to respect the HIG rule [H12].
- **Reduce Motion.** No page slide on auto-advance (cross-fade), no ring sweep (jump to value), no tick-over scale, no pulsing heart. Haptics are unchanged.
- **Colour.** Numbers and words always accompany colour (§4.8.2). Increase Contrast thickens strokes and drops the 85 % dimming in Always On.
- **Motor.** Every crown action has a touch alternative (tap to focus, then the −/+ glyph buttons, 44 pt, that appear when the weight is focused and VoiceOver or Switch Control is on) [H6][H2].

### 4.11 Number register

| Number | Value | Evidence or app's choice |
|---|---|---|
| Control default / minimum | 44 / 28 pt | HIG Accessibility [H2] |
| Primary in-workout button height | 60 pt | App's choice informed by [E1][E2] |
| Secondary circles; controls grid | 48 / 64 pt | App's choice (≥ [H2]) |
| Chips | 52 / 48 pt | App's choice |
| Gap between targets | ≥ 8 pt | App's choice |
| Text minimum on workout pages | 13 pt | App's choice above HIG 12 pt [H2] |
| Primary numerals | 40–48 pt | App's choice following [H1][H7] |
| Dynamic Type support | ≥ 140 % (to AX3) | HIG [H2] |
| Contrast | ≥ 4.5 : 1 (≥ 3 : 1 at 18 pt / bold) | WCAG AA via HIG [H2] |
| Buttons per row | ≤ 3 glyph / 2 text | HIG [H3] |
| Undo window | 4 s | App's choice |
| RIR chips | 0, 1, 2, 3, 4+ | Zourdos 2016; Helms 2016; ~1-rep error, Halperin 2022 (already in AppCore) |
| RIR prompt auto-collapse | 15 s | App's choice |
| Rest steps | ±15 s | Existing app's choice |
| Rest warning | 10 s before the end | App's choice (watch-features.md §2.4; usability only) |
| Standalone rest default | 120 s | App's choice within Singer 2024 / Schoenfeld 2016 / Grgic 2018 |
| Zone leave delay | 20 s | Existing (`CardioZoneTracker.leaveSeconds`) |
| Rolling pace window | 20 s | Existing app's choice (`CardioRoute.speedWindowSeconds`) |
| Auto Lap | 1 km / 1 mi | Convention (Garmin [T9], Apple splits [A3]); app's choice |
| Split banner | 3 s (Always On: until raise) | App's choice |
| Elevation profile span | 30 min | Apple's Elevation view [A3] |
| Heart page sparkline | 10 min | App's choice |
| Summary heart-rate points | ≤ 60, ≥ 1 min each | App's choice (phone's per-minute convention) |
| Brief-workout prompt | < 60 s | HIG asks [H1]; threshold app's choice |
| Record banner | 6 s | Existing app's choice |
| "Done for the day" cut-off | 10 min | Existing app's choice |
| Always On primary dimming | 85 % white | App's choice |
| Rep counter "slowing" | ~20 % speed loss | Existing (Hickmott 2022, `RepDetection`) |
| Screen | 208 × 248 pt (46 mm), 187 × 223 pt (42 mm) | Derived from Apple's specs [A2] |
| Smart Stack widget, 46 mm | 194 × 80.5 pt | HIG Widgets [H14] |

---

## 5. WatchConnectivity contract: exact changes

Everything is additive and optional, so older apps on either side still decode (synthesized `Codable` reads a missing optional as nil). No existing key, case or field changes meaning.

| Change | Type | Direction | Why |
|---|---|---|---|
| `WatchSession.ExerciseSnapshot.catalogID: String?` | field | phone → Watch | The phone recreates a standalone log's exercises by catalog id (`ExerciseLog.exerciseID`). |
| `WatchSession.plannedFor: Date?` | field | phone → Watch | Marks a snapshot as a plan sent ahead, not a running session. The Watch never sends commands for it. |
| `WatchMessage.plan = "plan"` → `WatchSession` | new key (application context) | phone → Watch | Today's (or the next) planned lifting session, built with the same planner call the iPhone's Start uses, with loads, rest and targets. Sent with the face data when the plan changes. |
| `WatchMessage.library = "library"` → `WatchExerciseLibrary { exercises: [ExerciseSnapshot] }` | new key + struct (application context) | phone → Watch | Up to 40 recent exercises (app's choice) with their last sets and achievable loads, for Quick lift. |
| `WatchMessage.intervals = "intervals"` → `IntervalSession` | new key (application context) | phone → Watch | This week's hard cardio session (§4.6). The Watch adds `IntervalSession.swift` and `IntervalSession+Zones.swift` to its sources. |
| `WatchWorkoutSummary.loggedExercises: [WatchSession.ExerciseSnapshot]?` | field | Watch → phone | Sets done in a standalone session (only completed sets, with RPE). Nil for phone-owned sessions, so nothing changes for them. |
| `WatchWorkoutSummary.name: String?` | field | Watch → phone | "Push" or "Watch workout". |
| `WatchCommandMessage.sentAt` = tap time for held commands | behaviour (Watch) | Watch → phone | The undo window (§4.4.7) delays sending, not the logged time. |
| `adjustRest(seconds:)` with negative values | behaviour | Watch → phone | −15 s. Already a signed `Int`. The phone must clamp at 0 (check `RestTimerStore.adjust`). |

Not changed:

- `completeSet`, `rateSet`, `finish`, `pause` and `resume`.
- The request kinds and the summary's existing fields.
- Cardio still saves to Apple Health and the phone reads it from there (`HealthKitClient.externalWorkouts`). Laps and segments ride along as workout events.

**Phone side** (`App/Services/WatchSync.swift`):

- `updatePlan()` and `updateLibrary()` are called next to `updateFace`, and each sends only on change. `updateIntervals()` is called when `HardCardio` changes.
- `apply(_ summary:)`: with `loggedExercises` and no matching session (`matchingSession`), it creates the `WorkoutSession` with exercises and completed sets (weights in kg, the order kept) through the same insertion path `WorkoutLauncher.start` uses (`insertLog`). It marks `watchWorkoutUUID`, then runs records and autoregulation for the next session as a finished session would.
- **Pure parts** (which sets count, how a logged exercise maps to targets, de-duplicating against an overlapping phone session with `WorkoutLinking`) go in AppCore `WatchLogMerge.swift` with tests.

---

## 6. Model and platform constraints

- **Keep `WatchWorkoutModel` and `WatchCardioModel`.** Changes:

  `WatchWorkoutModel`:
  - `localSession` mode (a `WatchSession` it owns) for plan and Quick lift, with `completeSet` and `rateSet` applied locally instead of sent, persisted to a file after each set (`SafeJSONFile` style; app's choice) so a crash keeps the log;
  - a held-command queue with `undoLastSet()`;
  - `adjustRest(by:)` signed;
  - the rest-warning task;
  - `CardioZoneTracker` for the Heart page;
  - a heart-rate series buffer for the chart;
  - `loggedSets` for the summary;
  - `send(_:sentAt:)`.

  `WatchCardioModel`:
  - a `LapTracker` and split alerts;
  - a rolling pace;
  - live elevation from route altitudes;
  - the heart-rate series;
  - `workoutSession(_:didGenerate:)` for `motionPaused` and `motionResumed` (builder pause and resume events);
  - `enableWaterLock()`;
  - lap and segment events on the builder;
  - an `IntervalSession` runner (C7);
  - a fix for the stale "No GPS route" comment.
- **watchOS 26 target, 27 gated.** watchOS 27-only calls stay behind `#if compiler(>=6.4)` plus `if #available(watchOS 27, *)`, as `WatchCardioModel.healthZones` does: Health's preferred zones, `setCustomZoneConfiguration`, and optionally `didUpdateWorkoutZone`. Everything else in this spec exists on watchOS 26: `handGestureShortcut` (watchOS 11 [D6]), glass styles, controls, RelevanceKit, `enableWaterLock` (watchOS 6.1 [D4]) and motion events (watchOS 3 [D1]).
- **Swift 6, default MainActor.**
  - New Codable and shared types are `nonisolated` (as `WatchSession`).
  - HealthKit and CoreLocation delegates stay `nonisolated` and hop to the main actor (existing pattern).
  - `LapTracker`, `LoadStepper`, `RestCues` and `HeartRateSeries` are `nonisolated` value types in AppCore.
- **No Canvas. Shapes and colour providers `nonisolated`.** The ring arc, zones bar, sparkline and split bars are `nonisolated struct …: Shape`. Palette colours are static `Color` constants built in a `nonisolated` function (as `WatchTheme.color`).
- **Watch sources.** The Watch target compiles only listed AppCore files. Add to `TensileWatch: sources` in `project.yml`:
  - `Glances.swift` (Home glance, C5);
  - `IntervalSession.swift` and `IntervalSession+Zones.swift` (C7);
  - the new `LoadStepper.swift`, `LapTracker.swift`, `RestCues.swift` and `HeartRateSeries.swift` (C1);
  - `Shared/WatchPalette.swift`, `Shared/WatchGauges.swift` and `Shared/WatchIntents.swift` (C0, C8; the widgets target too).

  Each new AppCore file must need only Foundation and the files already listed (state it in its header, as `CardioZoneTracker.swift` does).

---

## 7. Build plan

Each chunk compiles and runs on its own, in this order. "Done when" lists what to check in CI and on the wrist. AppCore tests run with `swift test --package-path Packages/AppCore`. A Linux sandbox can't build the Watch target, so check CI after each push, including the `build-xcode-27` job (`[xcode27]` in the commit message).

### C0. Palette and components (no behaviour change)

- **Create:**
  - `Shared/WatchPalette.swift`: merged colours, gradient pairs, black-on-tint label colour, `nonisolated`.
  - `Shared/WatchGauges.swift`: move `SegmentedRing`, `StrainRing` and `StrainBar` from `RecoveryStrainComplication.swift`.
  - `Watch/Design/WatchType.swift`: the scaled-metric numeral styles of §4.8.1.
  - `Watch/Design/WatchComponents.swift`: `PrimaryWideButton` (60 pt), `CircleButton` (48/64 pt), `ChipGrid`, `MetricBlock`, `ToolbarStatus`.
  - `Watch/Design/WatchShapes.swift`: `RingArc`, `ZoneBar`, `Sparkline` and `SplitBars`, all `nonisolated Shape`.
  - `Watch/Design/AlwaysOn.swift`: a `dimmedWhenLuminanceReduced()` modifier and stroke-versus-fill helpers.
- **Change:**
  - `Watch/WatchTheme.swift` becomes forwarding constants to `WatchPalette` (deleted in C9).
  - `WatchWidgets/TensileComplications.swift`: `FacePalette` forwards to `WatchPalette`.
  - `RecoveryStrainComplication.swift`: imports the moved gauges.
  - `project.yml`: add both Shared files to TensileWatch and TensileWatchWidgets.
- **Done when:** both watch targets build; the complications look identical.

### C1. AppCore logic with tests

- **Create:**
  - `LoadStepper.swift`: nearest index, step ±n, clamping; reps and hold steps; the logic now in `WatchSetAdjuster` and `WatchHoldAdjuster`.
  - `LapTracker.swift`: manual laps, auto laps by distance, split times, lap pace, a 20 s rolling pace from `(date, meters)` samples, pausing.
  - `RestCues.swift`: cue times (warning at 10 s, end) for a rest that can be moved ±15 and can't go below 0.
  - `HeartRateSeries.swift`: per-minute downsampling to ≤ N points, zone-coloured runs.
  - Tests for each in `Packages/AppCore/Tests/AppCoreTests/`, written with the `swift-testing-pro` skill.
- **Change:** `project.yml` adds the four files to TensileWatch sources (unused until C2/C3, so it compiles).
- **Done when:** `swift test` passes.

### C2. Lifting pager

- **Create:**
  - `Watch/Lifting/LiftPagesView.swift`: the horizontal pager, auto-advance and toolbar.
  - `LiftSetPage.swift`: crown focus, Done, hold, warm-up step slot, rep counter inline.
  - `LiftRestPage.swift`: states (a) and (b), ring, ±15, next set, haptics, Always On.
  - `LiftHeartPage.swift`.
  - `LiftExercisesPage.swift`, from `WatchExerciseListView`.
  - `LiftControlsPage.swift`, from `WatchControlsView`.
  - `PendingSet.swift`: `PendingSet`, `SetEdit` and `watchFormat`, moved out of `WatchLiveView.swift`.
- **Change:**
  - `WatchWorkoutModel.swift` (§6, without the local session).
  - `WatchRootView.swift` routes to `LiftPagesView`.
  - `WatchWarmUpView.swift`: non-scrolling step card in the Set slot, crown binding removed, cue behind an info button, 60 pt Done.
  - `WatchRepCounterView.swift`: inline count control.
  - `WatchEffortSheets.swift`: drop `WatchSetEditSheet`, `WatchSetAdjuster` and `WatchHoldAdjuster` (replaced by `LoadStepper` on the Set page); 48 pt chips; 44 pt Skip.
  - Check that the phone's `RestTimerStore.adjust` clamps negative values (`App/Features/Workout/…`).
- **Delete:** `WatchLiveView.swift`, `WatchControlsView.swift`, `WatchExerciseListView.swift`.
- **Done when:** a phone session runs end to end on the wrist with the taps in the §4.4.2 table. Undo works within 4 s and nothing reaches the phone. Always On shows the dimmed layout (Simulator Always On toggle [D5]). VoiceOver adjusts the weight.

### C3. Cardio pager and metric pages

- **Create:**
  - `Watch/Cardio/CardioPagesView.swift`: Controls | Metrics | `NowPlayingView`.
  - `CardioMetricPages.swift`: Main, Heart zones, Pace, Speed, Elevation, Splits, Target.
  - `CardioPageSettings.swift`: per-activity page list and editor.
  - `CardioControlsPage.swift`: Pause, End, Lap, Lock, Discard.
- **Change:** `WatchCardioModel.swift` (§6, without the interval runner); `WatchRootView.swift`.
- **Delete:** `WatchCardioLiveView.swift`. Its end view moves in C4; until then keep `WatchCardioEndView` in a new `Watch/Cardio/CardioEndViewLegacy.swift`.
- **Done when:**
  - an outdoor run shows current pace, auto laps every km with a tap and banner, and manual laps;
  - with Watch Settings' Autopause on, a stop pauses the clock without pausing the session;
  - laps appear as workout events in Health;
  - Water Lock engages;
  - sports show only Main and Zones.

### C4. End summaries

- **Create:** `Watch/Summary/LiftSummaryView.swift`, `CardioSummaryView.swift`, `SummarySections.swift` (zones bar, heart-rate chart, splits and sets lists, Open on iPhone with `.userActivity`).
- **Change:** both models keep the series and lists the summaries need; the brief-workout prompt.
- **Delete:** `WatchEndView.swift`, `CardioEndViewLegacy.swift`.
- **Done when:** both summaries render at AX3 without clipping; VoiceOver reads the chart summaries; Handoff is checked on the devices (keep the text row if it doesn't appear).

### C5. Home and start flows

- **Create:**
  - `Watch/Home/HomeView.swift`: glance, plan card, quick start, hard cardio slot (hidden until C7), last activity, footer.
  - `SessionPreviewView.swift`.
  - `ActivityPickerView.swift`: grouped list plus target, replacing the sheet.
  - `WatchSettingsView.swift`: pages per activity, haptic toggles.
  - `WatchHistoryStore.swift`: the last activity summary, local.
- **Change:**
  - `WatchRootView.swift`;
  - `TensileWatchApp.swift`: `tensile://start` opens Home;
  - `WatchShortcuts.swift`: `StartCardioIntent` opens the picker;
  - `project.yml`: add `Glances.swift` to TensileWatch.
- **Delete:** `WatchStartView.swift`, `WatchCardioStartView.swift`.
- **Done when:** Home matches the complications' numbers and wording at the same moment, and "--" shows when stale.

### C6. Plan ahead and lifting without the phone

- **Change:**
  - `Shared/WatchSession.swift`: the §5 fields, keys and `WatchExerciseLibrary`.
  - `WatchWorkoutModel.swift`: local session mode, persistence, summary with `loggedExercises`, receiving `plan` and `library`.
  - `App/Services/WatchSync.swift`: `updatePlan`, `updateLibrary`, summary import.
  - The phone's plan source: the planner call the Today screen's Start uses (find it with `WorkoutBuilderView` / `GymStore.start(_ plan:)`).
- **Create:**
  - `Watch/Lifting/QuickLiftView.swift`: library picker, "Heart rate only".
  - AppCore `WatchLogMerge.swift` with tests.
- **Done when:** with the iPhone in flight mode, a planned session and a quick lift are logged on the wrist and appear on the phone, with sets, once it reconnects. A phone session that overlaps is joined, not duplicated.

### C7. Interval sessions on the wrist

- **Change:**
  - `project.yml`: add `IntervalSession.swift` and `IntervalSession+Zones.swift`.
  - `CardioZoneTracker.swift`: `retarget(_:at:)`, with tests.
  - `WatchCardioModel.swift`: the step runner.
  - `CardioMetricPages.swift`: the Interval page.
  - `HomeView.swift`: the hard-cardio slot.
  - `WatchSync.swift`: `updateIntervals`.
- **Create:** AppCore `IntervalSession+Progress.swift` (step at elapsed time, time left, next step), with tests.
- **Done when:** a 4 × 4 session runs on the wrist with a tap at each step and the band switching per step.

### C8. Controls, Smart Stack, complications

- **Create:**
  - `Shared/WatchIntents.swift`: `StartWorkoutIntent` and `StartCardioIntent` moved, plus `StartLastCardioIntent`.
  - `WatchWidgets/StartControls.swift`: two `ControlWidgetButton`s.
- **Change:**
  - `WatchWidgets/TensileComplications.swift`: register the controls; the `fitnessCenter` relevance for Today's plan.
  - `Watch/WatchShortcuts.swift`: keep only the `AppShortcutsProvider`.
  - `project.yml`: share the intents file and add `AppIntents` to the widgets target.
- **Done when:** both controls appear in the watch's Control Center and Smart Stack and start the right flow.

### C9. Accessibility and Always On audit, clean-up, docs

- **Change:** every new view gets VoiceOver labels and values, Dynamic Type to AX3, Reduce Motion paths and Increase Contrast strokes. Walk §4.10 and the §4.5.7 table on the device.
- **Delete:** `Watch/WatchTheme.swift` and `FacePalette`, once nothing uses the forwarders.
- **Update:**
  - `README.md` (Watch features);
  - `docs/research/watch-features.md` (point 2.4 done, 6.8 updated);
  - this file's "Still to verify" list.

---

## 8. Still to verify on the wrist

**Built (18 Nov 2026), chunks C0-C9.** Not checked on a device or in a simulator (the sandbox can't build watchOS); CI builds it. Changes from the plan above:

- The lifting toolbar puts Undo, else the rest left (on another page), else the elapsed time in the leading corner, and heart rate in the trailing one; there's no centre item, because the system clock takes the centre when both corners are used.
- A superset's first half with a "Reps left?" question moves to the Rest page for the question (no rest runs), then back to the Set page with the partner; without a question it stays on Set, as planned.
- The Done button is a custom filled button with a black label (contrast measured), not `.glassProminent`, so its contrast doesn't depend on the system's glass tint.
- The warm-up step card keeps Back and Skip behind its info button, with the cue, so the card never scrolls.
- Handoff from the summary is advertised (`NSUserActivity` "com.lontraindustries.workoutapp.viewWorkout" with the workout UUID); the iPhone doesn't handle it yet (left out to keep the phone-side changes small), so the row reads as text.
- The iPhone's "Running on Apple Watch" note for a plan started on the Watch is not built: a phone session started meanwhile is joined when the Watch's log arrives (`WatchLogMerge`), not blocked.
- Cardio pages at the accessibility text sizes don't switch to a scroll view (a scroll view inside the crown-paged stack would fight the crown); check them at AX3.

To check on the Series 12:

- That the 46 mm Series 12 defaults to the xLarge text size, and the Set page fits at the default and largest sizes on 42 mm.
- The label colour `.glassProminent` uses on a light tint, and that black labels can be forced.
- Crown detents with `achievableLoadsKg` windows of 40 loads (the phone sends ±20 around the plan); that is too few for a big change. Consider asking the phone for a wider window in C6.
- That `motionPaused` arrives for third-party running sessions on watchOS 27 with Autopause on [D1][F1].
- That Handoff from the Watch summary appears on the iPhone.
- That `RelevantContext.location(category: .fitnessCenter)` returns non-nil and works without location permission.
- That double tap on the horizontal pager's Set page fires Done and not a page change.
- (next-features W4, 18 Nov) That the "Intervals" card rises in the Smart Stack on the hard session's planned day (from 06:00) and not once it's done or the app says it waits; and that "Today's plan" still rises in the hour before bed-by.
- (next-features W1, 18 Nov) That a session added from Fitness › This week appears in Apple's Workout app under Tensile on its day, that the hard steps alert at Tensile's band (and rest steps stay quiet), and that the finished workout ticks the plan once Health has it.

---

## References

**Apple Human Interface Guidelines** (read 18 Nov 2026 from developer.apple.com/tutorials/data/design/human-interface-guidelines/…json)

- [H1] Workouts. https://developer.apple.com/design/human-interface-guidelines/workouts
- [H2] Accessibility (control sizes, text sizes, 140 % on watchOS, contrast). https://developer.apple.com/design/human-interface-guidelines/accessibility
- [H3] Layout, watchOS (button counts per row). https://developer.apple.com/design/human-interface-guidelines/layout
- [H4] Buttons, watchOS (44 pt hit region, capsules, toolbar corners, Liquid Glass). https://developer.apple.com/design/human-interface-guidelines/buttons
- [H5] Always On. https://developer.apple.com/design/human-interface-guidelines/always-on
- [H6] Digital Crown. https://developer.apple.com/design/human-interface-guidelines/digital-crown
- [H7] Typography, watchOS Dynamic Type sizes (xLarge, default 44/45/49 mm: Large Title 40, Title 1 38, Title 2 30, Title 3 20, Headline 17, Body 17, Caption 1 16, Caption 2 15, Footnote 1 14, Footnote 2 13). https://developer.apple.com/design/human-interface-guidelines/typography
- [H8] Materials, watchOS. https://developer.apple.com/design/human-interface-guidelines/materials
- [H9] Pickers, watchOS. https://developer.apple.com/design/human-interface-guidelines/pickers
- [H10] Tab views, watchOS. https://developer.apple.com/design/human-interface-guidelines/tab-views
- [H11] Charts, watchOS. https://developer.apple.com/design/human-interface-guidelines/charts
- [H12] Gestures, Double tap. https://developer.apple.com/design/human-interface-guidelines/gestures
- [H13] Color, watchOS. https://developer.apple.com/design/human-interface-guidelines/color
- [H14] Widgets, watchOS (Smart Stack sizes, relevance). https://developer.apple.com/design/human-interface-guidelines/widgets
- [H15] Controls (the HIG page still says "Not supported in watchOS"; WWDC25 [W1] supersedes it). https://developer.apple.com/design/human-interface-guidelines/controls
- [H16] Designing for watchOS. https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos

**WWDC** (transcripts read 18 Nov 2026)

- [W1] What's new in watchOS 26 (WWDC25 334). https://developer.apple.com/videos/play/wwdc2025/334/
- [W2] Deliver workout insights with HealthKit workout zones (WWDC26 207). https://developer.apple.com/videos/play/wwdc2026/207/
- [W3] Build a workout app for Apple Watch (WWDC21 10009). https://developer.apple.com/videos/play/wwdc2021/10009/
- [W4] Build a multi-device workout app (WWDC23 10023). https://developer.apple.com/videos/play/wwdc2023/10023/
- [W5] Design and build apps for watchOS 10 (WWDC23 10138). https://developer.apple.com/videos/play/wwdc2023/10138/

**Apple documentation and support**

- [D1] HKWorkoutEventType.motionPaused ("During running workout sessions… Settings > General > Workout > Autopause"). https://developer.apple.com/documentation/healthkit/hkworkouteventtype/motionpaused
- [D2] HKWorkoutEventType.segment. https://developer.apple.com/documentation/healthkit/hkworkouteventtype/segment
- [D3] HKWorkoutEventType.lap. https://developer.apple.com/documentation/healthkit/hkworkouteventtype/lap
- [D4] WKInterfaceDevice.enableWaterLock() (watchOS 6.1; foreground, active workout, WR50). https://developer.apple.com/documentation/watchkit/wkinterfacedevice/enablewaterlock()
- [D5] Designing your app for the Always On state; `isLuminanceReduced`. https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state ; https://developer.apple.com/documentation/swiftui/environmentvalues/isluminancereduced
- [D6] handGestureShortcut(_:isEnabled:) (watchOS 11). https://developer.apple.com/documentation/swiftui/view/handgestureshortcut(_:isenabled:)
- [D7] WKHapticType (meanings of click, directionUp/Down, success, failure, retry, start, stop, notification, navigation…). https://developer.apple.com/documentation/watchkit/wkhaptictype
- [D8] HKWorkoutSession.startMirroringToCompanionDevice (watchOS 10; not adopted here, the WatchConnectivity contract stays). https://developer.apple.com/documentation/healthkit/hkworkoutsession/startmirroringtocompaniondevice(completion:)
- [D9] RelevanceKit RelevantContext (date, fitness(.workoutActive / .activityRingsIncomplete), location(category:), sleep). https://developer.apple.com/documentation/relevancekit/relevantcontext
- [F1] Apple Developer Forums, "Problem with auto pause in workouts and duration" (Apple engineer: add pause/resume events to the builder; don't pause the session). https://developer.apple.com/forums/thread/649276
- [A1] Apple Support, "What's new in watchOS 27". https://support.apple.com/guide/watch/whats-new-in-watchos-27-apdb93ea3872/watchos
- [A2] Apple, Apple Watch Series 12 Technical Specifications (46 mm 416 × 496 px, 42 mm 374 × 446 px, 326 ppi). https://www.apple.com/nz/apple-watch-series-12/specs/
- [A3] Apple Support, "Run with Apple Watch" and Apple Watch User Guide, Workout views (Metrics, Heart Rate Zones, Segment, Split, Elevation, Power; custom workouts; Elevation view last 30 minutes). https://support.apple.com/guide/watch/apd73a43493f/watchos ; https://support.apple.com/guide/watch/apd1f24d4d35/watchos

**Third-party apps** (listings and reviews; not run)

- [T1] Hevy, App Store listing and hevyapp.com. https://apps.apple.com/app/id1458862350 ; https://www.hevyapp.com/
- [T2] Strong, reviews (via Jefit's comparison, a competitor, and lifting-apps review). https://www.jefit.com/blog/best-apps-to-log-sets-and-reps-on-smartwatch-in-2026-top-7-tested
- [T3] Same comparison for RepCount, Gravitus, Jefit, Setgraph, StrengthLog (tap counts are the publisher's estimates).
- [T4] SmartGym Apple Watch page. https://smartgymapp.com/watch
- [T5] Apple Newsroom, "watchOS 26 delivers more personalized ways to stay active and connected" (Workout app layout, Workout Buddy), June 2025; MacStories watchOS 26 review (custom workouts on iPhone). https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/ ; https://www.macstories.net/stories/watchos-26-the-macstories-review/
- [T6] WorkOutDoors, App Store listing; MacRumors forum thread; mushing.com review. https://apps.apple.com/app/workoutdoors/id1241909999 ; https://forums.macrumors.com/threads/workoutdoors-new-workout-features.2134687/ ; https://mushing.com/gear/workoutdoors-review/
- [T7] the5krunner, "Runna on Apple Watch – its own app beats Apple Workouts", 12 Nov 2026; Tom's Guide Runna review. https://the5krunner.com/2026/11/12/runna-apple-watch/ ; https://www.tomsguide.com/reviews/runna-app
- [T8] Strava Apple Watch redesign (Wareable, the5krunner, Sept 2025). https://www.wareable.com/apple/strava-live-segments-apple-watch-redesigned-app ; https://the5krunner.com/2025/09/04/strava-updates-apple-watch-app-with-new-interface-plus-live-segments/
- [T9] Garmin Forerunner manuals: data screens, Lap Key, Auto Lap, Lap Alert. https://www8.garmin.com/manuals/webhelp/forerunner735/EN-US/GUID-B14728B2-11F8-4E73-AB37-10AACD034A8A.html ; https://manualslib.com/manual/2159041/Garmin-Forerunner-55.html?page=45
- [T10] Gentler Streak, 9to5Mac coverage and App Store listing. https://9to5mac.com/2022/08/16/gentler-streak-apple-watch-workout-views-watchos-9/ ; https://apps.apple.com/app/id1576857102
- [T11] Athlytic, App Store listing. https://apps.apple.com/app/id1543571755
- [T12] Apple Watch Ultra User Guide, Heart Rate Zones view ("your Heart Rate Zone, heart rate, time in the current zone, and your average heart rate"), via search; 9to5Mac watchOS 9 workout views. https://support.apple.com/guide/watch-ultra/apd30fa26bb4/watchos ; https://9to5mac.com/2022/09/06/apple-watch-cycling-metrics-watchos-9/
- [T13] Slopes, App Store listing and reviews (lift detection, use with gloves). https://apps.apple.com/app/slopes/id643351983

**HCI evidence**

- [E1] Dobbelstein D, Haas G, Rukzio E. The Effects of Mobility, Encumbrance, and (Non-)Dominant Hand on Interaction with Smartwatches. ISWC '17, 90–93. doi:10.1145/3123021.3123033. Read in full: n = 24, 7 mm targets, miss rate 2.87 % standing vs 9.67 % walking; swipe errors < 0.6 % in all conditions.
- [E2] Schildbach B, Rukzio E. Investigating Selection and Reading Performance on a Mobile Phone while Walking. MobileHCI '10, 93–102. Read (abstract and introduction): n = 16; walking +23 % selection errors; +20 % target size helps, +40 % almost fully compensates; larger text didn't help reading because of scrolling.
- [E3] Pizza S, Brown B, McMillan D, Lampinen A. Smartwatch in vivo. CHI 2016 (1,009 recorded interactions); "under 3 s" glance figure from a related Springer chapter, not checked against the paper. https://dsv.su.se/en/about/news/mobile-life-centre-s-study-reveals-that-most-apple-watch-owners-use-it-as-a-watch-1.258656
- [E4] Karuei I, MacLean KE, et al. Detecting vibrations across the body in mobile contexts. CHI 2011 (movement raises detection thresholds). https://www.cs.ubc.ca/labs/spin/sites/default/files/local_pdfs/2011_DetectingVibrationsAcrosstheBody.pdf
- [E5] AVI 2018 study of vibration recognition at the wrist, standing vs running (no activity effect on recognition). https://simonperrault.github.io/files/AVI2018-Cindy.pdf

**Training evidence reused from AppCore** (already cited in code): Zourdos 2016, Helms 2016, Halperin 2022 (`SetFeedback.swift`, `RPEGuideView.swift`); Singer 2024, Schoenfeld 2016, Grgic 2018, ACSM 2009 (`TrainingTools.swift` `RestTimer`); Helgerud 2007, Wen 2019 (`IntervalSession.swift`); Foster 2001 (session RPE); Hickmott 2022 (`RepDetection`); Apple Watch heart rate in resistance exercise, J Sports Sci 2023 (`watch-features.md` [B19]).
