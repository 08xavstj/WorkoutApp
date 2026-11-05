# Tensile

![Tensile](docs/brand/logo.png)

An iPhone app in the style of Bevel: **Strain, Recovery and Sleep** scores from Apple Health, an **AI coach** you can chat with, plus a full **gym workout tracker** whose sessions count toward strain.

> The app is called **Tensile** (the repo and Xcode project keep the name WorkoutApp). The logo is a "T" made from a loaded barbell whose bar flexes under the weight; regenerate the icons with `python3 docs/brand/make_logo.py`. Before shipping, run a proper trademark search on the name. Don't use Bevel's or Whoop's name, logo or artwork.

## What's in v0.1

Five tabs: **Today**, **Fitness**, **Coach**, **Health** and **Log**. Settings open from the profile button at the top right of any tab.

| Area | What it does |
|---|---|
| **Today** | Strain, Recovery and Sleep rings with a coaching line and one suggested next step; tap the Strain ring for today's range and the workouts that would reach it, or Recovery and Sleep for what drove them. **Up next** lists what's due (morning check-in, doses, bedtime window, habits); **Nutrition** shows energy balance (Cronometer intake vs. estimated calories burned), macros and water; a weather row appears when the weather affects training or sleep (tap it for the full forecast); four health tiles (RHR, HRV, breathing rate, sleep) link to Health |
| **Fitness** | A week strip of daily strain, then **This week**: the weekly plan with today's session and Start, consistency and the weekly Review. Below it, today's strain gauge with today's range, activities (logged lifts plus Garmin/other workouts) and heart-rate zones; cardio and muscular **training load** (7-day vs 28-day); Progress (muscles and hard sets, cardio fitness, strength); and Workouts (**Saved workouts** and **History**) |
| **Trainer** | **Start workout** (Log tab, or Start on Fitness › This week) builds a session from your **gym equipment** (bar weights, plate pairs, dumbbell/kettlebell sets and machine/cable increments; set up in Settings, or from the builder's toolbar). It picks exercises you can do there, sets reps and effort from your recovery, and suggests weights from your lift history **rounded to what you can actually load**, progressing by your gym's smallest jump. Swap any exercise; see plate loading per side. **Empty workout** and **Saved workouts** sit under Start workout on the Log tab |
| **Live workout** | Timer, live strain added, rest pill (−15s/+15s/Skip), previous sets, "New PR" badges, plate-loading hints, finished and upcoming exercises collapsed. While it runs, a bar above the tabs shows it so you can go back in |
| **Coach** | Chat that knows your scores, food, calories, gym and lifts; training questions come back with a ready-to-start workout card. Runs on the iPhone with Apple Intelligence; nothing leaves the device |
| **Health** | 90-day HRV baseline chart, key measures (including body age) and every stat Apple Health has, grouped by category under All measures: resting, sleeping and walking heart rate, heart-rate recovery (measured after workouts), a heart-rate stress estimate, VO₂ max, blood oxygen, respiration, temperature, mindful minutes, steps, distance, floors, intensity minutes, active/resting energy, weight, body fat, BMI, lean mass, blood pressure, water and protein. **Records** (lab results, blood pressure, body measurements, progress photos, medications) and **Patterns** (what affects you, alcohol and your sleep, vitamins and minerals) |
| **Log** | Start workout at the top, with Empty workout and Saved workouts under it; then overnight HRV, drinks, blood pressure, progress photos, waist and grip, and lab results (typed in) |
| **Progress photos** | Front and side photos (Log › Progress photo; history in Health › Records) kept only inside the app (encrypted, never in the Photos library), a before/after slider and timeline. They never leave the iPhone |

### Calories burned (`EnergyCalculator`)

Resting energy uses **Mifflin-St Jeor** (height, weight, age, sex), or **Katch-McArdle** (lean mass) only when the body-fat % comes from a DXA or clinic measurement; smart-scale readings are off by about 5–8 points, so they don't switch the equation. Exercise uses the **Keytel et al. (2005)** heart-rate equation for minutes when your heart rate is clearly raised, with a MET-based floor for logged lifting sessions (heart rate swings during lifting). Everyday movement comes from steps outside workouts (ACSM walking equation, about 0.00042 kcal per step per kg), and digestion is worked out from your macros when they're logged (about 25% of protein calories, 7.5% of carbs, 2% of fat; Westerterp 2004), otherwise ~10% of what you ate. HRV isn't part of any validated energy equation, so it isn't used. Expect about ±15–25% error, more on training days: no wrist device managed under 20% in Shcherbina et al. (2017), so treat the number as a guide.

### How the scores work (`Packages/AppCore`)

- **Strain (0-100%)**: cardio load from heart rate (Banister TRIMP), plus **lifting load** = session RPE x minutes (Foster sRPE). A gym session counts as whichever is higher, its heart-rate load or its RPE load, so lifting isn't undercounted and nothing is counted twice. Load maps onto 0-100% with a curve that flattens near the top.
- **Recovery (0-100%)**: last night's HRV and resting heart rate (your sleeping heart rate when there are enough nights, otherwise Apple Health's resting heart rate) compared with your own 30-day baseline (z-scores), plus sleep against your own last 30 sleep scores. The 7-day HRV trend sets the band, as in HRV-guided training trials: below your normal range (mean − 0.5 SD) the score is capped at 33 ("Easy day"), inside it the score stays 34–66, and above it the score reaches 67+ only when resting heart rate and sleep aren't also off. Needs 14 nights of data to calibrate.
- **Sleep (0-100)**: time asleep vs. need, efficiency (full marks from 85%, none at 70%), deep + REM share (target scaled by age), interruptions (0–1 full marks, 2–3 half, 4+ none) and, when known, sleep regularity (SRI 85+ full marks, 50 none). Overlapping iPhone/Watch records are merged.

These are our own formulas from published sports-science methods, not Whoop's or Bevel's (theirs aren't public). Tune the constants in `StrainCalculator`, `RecoveryCalculator` and `SleepCalculator`; the tests in `Packages/AppCore/Tests` show the expected ranges.

## Run it on your iPhone (Mac + Xcode)

You need Xcode 26 or later, an iPhone on iOS 26+, and your Apple Developer account.

```bash
git clone https://github.com/08xavstj/WorkoutApp.git
cd WorkoutApp
brew install xcodegen
xcodegen generate
open WorkoutApp.xcodeproj
```

Before opening Xcode, set your signing once (HealthKit needs your own team and a unique bundle ID):

```bash
scripts/set-signing.sh <TEAM_ID> com.yourname.workoutapp
```

Your Team ID is the 10-character code at [developer.apple.com/account](https://developer.apple.com/account) → **Membership details**. It's saved in `Config/Signing.local.xcconfig` (not committed), so it survives `xcodegen generate` and `git pull`. Don't set the team in Xcode's Signing tab: regenerating the project resets it.

Then in Xcode:
1. Plug in your iPhone (or use Wi-Fi debugging), pick it as the run destination, press **Run**.
2. If Xcode shows a signing error, open **Signing & Capabilities**, check that *Automatically manage signing* is on and the team is your paid membership (not "Personal Team"), and click **Try Again**.
3. On the phone: allow Apple Health access when asked. Wear your watch to bed for a few nights so recovery can build a baseline.

The `.xcodeproj` is generated, so it isn't committed. Re-run `xcodegen generate` after pulling changes that add files.

Run the score tests any time: `swift test --package-path Packages/AppCore`.

## Apple Watch

Tensile has a Watch app for lifting days. It shows the session running on your iPhone (exercise, set x of y, target reps and weight, superset partner as A1/A2), ticks sets off with a quick "how hard?" step (effort 6–10 as reps left, plus reps and weight you can adjust by your gym's real plate jumps), runs the rest timer with a tap at the end, and records heart rate and calories with its own workout session. Pause, resume, skip the exercise, and finish (with a 1–10 rating for the whole session) all work from the wrist; the iPhone's finish sheet opens pre-filled.

The Watch's workout is the single record. Tap **Start on Apple Watch** from the workout's menu on the phone (or start the session from the Watch) and the Watch saves the one `HKWorkout` for that session with its heart rate and calories; the phone then doesn't save a second one. AirPods heart rate still streams into Apple Health as before and is merged with the watch's. If the Watch starts a workout with no session on the phone, the phone creates one ("Watch workout, N min") when the summary arrives, and if the phone is out of reach the Watch keeps recording and queues what you did until it reconnects.

Watch face complications: long-press the watch face → **Edit** → swipe to **Complications** → tap a slot → **Tensile**. "Recovery & strain" fits a round subdial (on Wayfinder, the bottom right): recovery in the middle, coloured by band (blue easy day, amber normal, green recovered), with today's strain filling the orange ring and today's target marked as a thin arc outside it; it also fits a corner or the rectangular slot. "Next session" fits a corner ("Push 6 PM", "Rest day", or the next one, like "Tue Pull", once today's is done), a round slot or the inline line. The iPhone sends the numbers whenever it refreshes your scores (they show "--" until it has today's), and the next session moves on by itself. Signing: the complications are a widget extension (`<your app id>.watchkitapp.widgets`) that shares data with the Watch app through the App Group `group.com.lontraindustries.workoutapp`. Automatic signing adds it; if Xcode shows an App Group error, open Signing & Capabilities for **TensileWatch** and **TensileWatchWidgets**, add App Groups if it's missing, and tick `group.com.lontraindustries.workoutapp`.

Installing: the Watch app ships inside the iPhone app, so it installs with it when "Automatic app install" is on in the Watch app on your iPhone; otherwise open the Watch app → **Available Apps** → Tensile. Signing: it uses the same team and the bundle ID `<your app id>.watchkitapp` (set by `scripts/set-signing.sh`; if you set signing before the Watch app existed, run the script again so `COMPANION_APP_BUNDLE_IDENTIFIER` is written). Xcode's automatic signing creates the Watch provisioning profile the first time you run on a device.

## Connect a Garmin watch

The app reads everything through Apple Health, so it works with Garmin watches (like the Instinct 2) as well as Apple Watch.

1. In the **Garmin Connect** app: **More → Settings → Connected Apps → Apple Health**, and turn on every category.
2. On your iPhone: **Settings → Health → Data Access & Devices → Garmin Connect**, and allow all categories.
3. Open Garmin Connect once a day (or leave it running in the background) so it syncs to Health.

What comes through: heart rate, resting heart rate, sleep and stages, and workouts. That covers strain and sleep.

What doesn't: **HRV**. Garmin keeps HRV Status in its own app. Without it, recovery is based on resting heart rate and sleep only. To include HRV, open the **Log** tab each morning, tap **Overnight HRV** and type last night's average from Garmin Connect (HRV Status). Health HRV is used instead whenever it exists.

Gym sessions: log them in this app. If you also start a Strength activity on the watch, turn off **Save to Apple Health** when you finish, so Health doesn't get the workout twice. Garmin's in-workout heart rate sometimes reaches Health only as a summary, which is why lifting strain is driven by your effort rating.

## Connect Cronometer

Cronometer has no public API (it only gives API access to selected partners), but it can write your food log to Apple Health, and this app reads it from there.

1. In the Cronometer app, open its settings, find **Apple Health** under connected apps/devices, and turn on **exporting nutrition** to Health.
2. On your iPhone, open **Settings → Health → Data Access & Devices → Cronometer** and check that it's allowed to *write* Energy Consumed, Protein, Carbohydrates, Fat, Fiber and Water.
3. In Tensile, allow it to *read* those same types (asked on first launch, or the profile button → **Settings** → **Data sources** → **Ask for Apple Health access**).

Food you log shows up in the Nutrition card on Today and the coach uses it. For example, it can tell you that you ate too little protein after a high-strain day. If Cronometer doesn't send a nutrient (some users report carbs or fiber dropping out), that field shows "--".

## The coach

The coach runs on Apple's on-device model (Apple Intelligence) and needs no setup or account. It works on iPhones that support Apple Intelligence, with it turned on in the Settings app; the app has no cloud AI, and nothing you type leaves the phone.

## Project layout

```
project.yml                 XcodeGen spec (targets, entitlements, Info.plist)
App/                        iPhone app (SwiftUI + SwiftData)
  Design/                   Theme colors, score rings, cards
  Models/                   SwiftData models: WorkoutSession, ExerciseLog, SetLog
  Services/                 HealthKit, daily scores, exercise library, settings
  Services/Coach/           On-device coach (Foundation Models)
  Features/                 Today, Fitness, Coach, Health, Log, Workout, Trainer, Settings screens
  Resources/exercises.json  Exercise library (free-exercise-db, public domain)
Watch/                      Apple Watch app (SwiftUI + HealthKit + WatchConnectivity)
WatchWidgets/               Apple Watch complications (WidgetKit)
Shared/                     Code the app, widget and Watch share (WatchSession is the wrist's session model)
Packages/AppCore/           Strain/recovery/sleep math + tests (no UI, no HealthKit)
.claude/skills/             Claude Code skills for this project
.github/workflows/ios.yml   CI: runs tests and builds the app on macOS
```

## Roadmap

1. **Automatic HRV for Garmin**: Garmin's Health API (requires approved business access), or a 1-minute morning reading with a Bluetooth chest strap or the iPhone camera.
2. Widgets and Live Activity for the rest timer and today's rings.
3. Templates/routines, PRs and progress charts per exercise (Swift Charts).
4. Stress score (daytime HRV), nutrition trends and calorie balance (intake vs. burn), and trends (7/30-day charts).
5. Coach upgrades: weekly review, auto-generated plans saved as templates, App Intents so Siri can answer "what's my recovery?".
6. Sign in with Apple + per-user rate limits on the coach function.

See [docs/REFERENCES.md](docs/REFERENCES.md) for the open-source projects and skills this builds on.
