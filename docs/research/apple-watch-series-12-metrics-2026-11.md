# Apple Watch Series 12: what it measures, what reaches Tensile (19 November 2026)

Asked by the owner after the app's breathing rate showed nothing while the Health app listed Respiratory Rate. Two questions: why breathing rate is empty, and which Series 12 measures the app misses or should replace.

## Sources

- [A1] Apple Newsroom, "Introducing Apple Watch Series 12, with the all-new Health Sensing System", 9 Sep 2026: heart rate "every five seconds, all day long"; HRV measured up to 24 times more often, reported as "Recovery HRV" (overnight, against a personal baseline) and overall HRV; Readiness 0-10 with four actions (Recover, Pace Yourself, Ready, Go For It) from activity, training load, vitals and sleep score; daytime vitals in the Vitals app; sleep apnoea, hypertension, ECG and heart notifications carried over. Read (regional newsroom copy).
- [A2] The iOS 27.2 SDK's HealthKit headers (`HKTypeIdentifiers.h`, `HealthKit.swiftinterface`), printed by `.github/workflows/sdk-probe.yml` on 19 Nov 2026. Read.
- [A3] `apple-scores-2026-11.md` (Readiness, Sleep score and Health Age have no API) and `daytime-vitals.md` (why the daytime view was removed).
- [A4] Apple, HealthKit documentation, "Protecting user privacy": an app can't tell whether read access was granted; a type that was refused returns no data, like a type with none.

## What the SDK has (A2)

| Type | Since | In the SDK | In Tensile before this change |
|---|---|---|---|
| `heartRateVariabilityRMSSD` (ms) | iOS/watchOS 27.0 | Yes, the only new quantity type | Read by name (`recoveryHRVType`) and used for recovery on nights it has readings |
| `hypertensionEvent` (category) | iOS/watchOS 26.2 | Yes | **Compiled out** behind `TENSILE_HYPERTENSION_EVENT` because the name couldn't be checked; never read |
| `appleSleepingBreathingDisturbances` | iOS 18 | Yes | Read (Biology breathing card) |
| `respiratoryRate` | iOS 8 | Yes, unchanged | Read, one device a night (`nightlyBreathingRate`) |
| `bleedingAfterMenopause`, `menopausalState` | iOS 27.0 | Yes | Not read (not relevant to the owner) |
| Readiness, Sleep score, daytime vitals | none | **No type** | Can't be read; see A3 |

## Why breathing rate can be empty

The pipeline was checked with a test that feeds an Apple Watch night (a reading every 5 minutes from 11 pm to 6:30 am, for 20 nights) through `OneDeviceBaseline.nightlyMeans` and `choose`: last night comes out right (`BreathingRateNightTests`). That leaves two causes:

1. **Read access is off for Respiratory Rate.** Health hides this from the app (A4): the query just returns nothing. iOS shows the permission sheet only once per type, so a switch left off on the first sheet stays off.
2. **The Oura ring carries the baseline and hasn't synced last night**, while the watch has it. The baseline must stay one device (`OneDeviceBaseline`, Dial 2025 vs O'Grady 2024), but Today used the baseline device's night only, so it showed nothing. Now the night shown falls back to the other device (`Choice.night(_:)`); the baseline is unchanged.

Built so the owner can tell which: **Settings › Data sources › Health data check** lists every measure below with its newest reading, days with data in the last 14 and its sources, and for "nothing" names both causes and the switch (Settings › Privacy & Security › Health › Tensile). The empty breathing tile on Today has a "Why?" button to it.

## Series 12 measures against the app

| Measure (Series 12) | HealthKit | Tensile | Decision |
|---|---|---|---|
| Heart rate every 5 s | `heartRate` | Strain, sleeping heart rate, zones | Keep. More samples sharpen sleeping heart rate and strain; multi-day reads already use per-minute averages, so 17,000 samples a day don't slow them |
| HRV, overnight "Recovery HRV" | `heartRateVariabilityRMSSD` (iOS 27) | Recovery uses it when present | Keep. RMSSD is the vagal index recovery research uses (Laborde 2017); SDNN stays the fallback |
| HRV, overall | `heartRateVariabilitySDNN` | Fallback for recovery | Keep |
| Resting heart rate | `restingHeartRate` | Recovery, illness watch | Keep |
| Breathing rate, overnight | `respiratoryRate` | Today tile, illness watch (Natarajan 2020) | Keep; fixed as above |
| Wrist temperature, overnight | `appleSleepingWristTemperature` | Illness watch | Keep |
| Blood oxygen | `oxygenSaturation` | Biology | Keep |
| Breathing disturbances | `appleSleepingBreathingDisturbances` | Biology | Keep |
| Sleep stages | `sleepAnalysis` | Sleep, recovery | Keep |
| Sleep apnoea, high/low heart rate, irregular rhythm notifications | category events | Heart page line | Keep |
| **Hypertension notifications** | `hypertensionEvent` (26.2) | Was compiled out | **Turned on.** The blood-pressure page prompts a week of home readings after one (sensitivity 41%, specificity 92%, figures in `HomeBloodPressure`) |
| Readiness 0-10 | none | Own recovery score | Can't read (A3). Apple publishes no method or validation; Tensile keeps its own, built on published HRV and resting-heart-rate evidence |
| Sleep score | none | Own sleep score | Same |
| Daytime vitals | none | Removed 17 Nov | Stays removed (`daytime-vitals.md`) |
| Steps (new pedometer model) | `stepCount` | Activity | Keep; nothing to change |
| VO₂ max, walking speed, heart rate recovery, daylight | quantity types | Activity, Biology | Keep |
| AFib History | `atrialFibrillationBurden` | Not read | Leave out: only for people already diagnosed with AF |
| Running power, stride, ground contact; cycling power | quantity types | Not read | Leave out: the owner skis, plays squash and lifts; no health decision attached |
| Stand hours | `appleStandTime` | Not read | Leave out: a weak proxy for sitting; Tensile already tracks steps and exercise minutes |
| Workout effort (Apple's estimate) | `estimatedWorkoutEffortScore` | Not read | Leave out: Tensile asks session RPE itself, which is validated (Foster 2001); Apple's estimate has no published validation |

## Code

- `Packages/AppCore/Sources/AppCore/HealthDataCheck.swift` (status and advice, tested in `HealthDataCheckTests`).
- `Packages/AppCore/Sources/AppCore/OneDeviceBaseline.swift` (`Choice.byDevice`, `Choice.night(_:)`; `BreathingRateNightTests`).
- `App/Services/HealthKitClient+DataCheck.swift`, `App/Features/Settings/HealthDataCheckView.swift`.
- `App/Services/HealthKitClient+Hypertension.swift` (flag removed).
