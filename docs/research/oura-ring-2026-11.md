# Oura Ring 5 in Tensile: every metric, where it comes from, and which device to trust (2026-11)

Checked 18 November 2026 for an owner with an Oura Ring 5 and an Apple Watch Series 12 (iOS 27). Supersedes the "what Oura shares" part of `oura-integration.md`, which could not reach Oura's pages from the build sandbox; that file's sleep and HRV reasoning still stands and is extended here.

**How this was checked.** Oura's API documentation was read from the machine-readable OpenAPI spec that the live docs page loads (`openapi-1.43.json`) [R4], plus Oura's authentication page [R5] and support articles. Apple's HealthKit pages were read from Apple's documentation JSON [R35–R38]. Study numbers marked ✓ were read in the paper (PMC full text or the PDF); numbers marked (abstract) or (secondary) come from an abstract or a write-up and should be re-checked before they go into a code comment. No app code was changed.

---

## 0. Short answer

- The ring is the **Oura Ring 5**, launched 28 May 2026 and shipping since 4 June [R1]. The API reports it as hardware type `or5` [R4].
- **Oura writes only raw basics to Apple Health:** sleep times and stages, 1-minute heart rate, a nightly respiratory rate, steps, active energy, workouts (and routes), mindful minutes, height and weight [R6][R7]. It writes **no HRV, no resting heart rate, no temperature, no SpO2, no VO2max and none of its scores** [R6][R7][R8].
- **Everything else needs the Oura API v2**, which needs OAuth 2 (personal access tokens ended December 2025), an active Oura membership, and a client secret even when PKCE is used [R4][R5].
- **Where Oura is the better-evidenced device:** overnight HRV (RMSSD) and overnight heart rate. An independent ECG study found Oura Gen 4 agreed with ECG at CCC 0.99 for HRV and 0.98 for resting HR [R25 ✓]. Apple Watch morning HRV (SDNN) was off by a mean 29% against a chest strap [R28 ✓]. **This is the integration with the clearest health payoff.**
- **Where neither device is clearly better:** sleep staging (Oura Gen3 κ 0.65 vs an older Apple algorithm κ 0.60 in one Oura-funded head-to-head [R18 ✓]; Apple's own 2025 algorithm reports κ 0.68 [R22 ✓]; no study has tested the Ring 5 or watchOS 26/27 against PSG). Sleep *duration* is good on both.
- **Where the Watch wins:** steps, daytime and exercise heart rate, workouts, VO2max (the only one with a published validation [R31 ✓]), SpO2 (independent studies exist [R32]) and breathing disturbances (FDA-cleared feature [R39]).
- **Leave out:** Oura's Readiness, Sleep and Activity scores, Daytime Stress, Resilience, Cumulative Stress, Cardiovascular Age, Cardio Capacity, Breathing Disturbance Index, Chronotype and the Health Radar features. None has published validation of the number itself, and several aren't in the API anyway. This matches the 17 November removal of Apple's unpublished scores (`apple-scores-2026-11.md`).

---

## 1. What the Oura Ring 5 and app provide (November 2026)

"In API" means a v2 endpoint returns it [R4]. "In Health" means Oura writes it to Apple Health [R6][R7]. Membership: Ring Gen3 and later need an active membership (USD 5.99/month) for the app's insights, Apple Health sharing and API access [R1][R6][R4].

| Feature | What it is | In API | In Health | Source |
|---|---|---|---|---|
| Sleep periods and stages | Bedtime, wake, total/deep/light/REM/awake time, efficiency, latency, 30-s and 5-min hypnograms, restless periods, movement | Yes (`sleep`) | Duration, times, stages | [R4][R6] |
| Sleep score | 0–100 composite of 7 contributors (total, efficiency, restfulness, REM, deep, latency, timing) | Yes (`daily_sleep`) | No | [R4][R8] |
| Readiness score | 0–100 composite of 9 contributors (HRV balance, RHR, body temperature, recovery index, sleep balance, sleep regularity, previous night, previous-day activity, activity balance) | Yes (`daily_readiness`) | No | [R4][R8] |
| Activity score, steps, calories, MET minutes | Activity score (6 contributors), steps, active/total kcal, 5-min activity class, MET series, inactivity alerts | Yes (`daily_activity`) | Steps, active energy | [R4][R6] |
| Overnight HRV | RMSSD in 5-min windows, night average and max | Yes (`sleep.average_hrv`, `sleep.hrv` series) | **No** | [R17][R4][R8] |
| Overnight heart rate | Average and lowest, 5-min series | Yes (`sleep`) | 1-min HR only (no RHR type) | [R4][R6] |
| Daytime heart rate | Time series (API: 5-min increments; tagged awake/rest/sleep/workout/live/session) | Yes (`heartrate`) | 1-min intervals | [R4][R6] |
| Temperature deviation and trend | °C from the personal baseline (no absolute value) | Yes (`daily_readiness`) | **No** | [R4][R7] |
| Respiratory rate | Night average (derived from heart-rate changes) | Yes (`sleep.average_breath`) | Night average | [R4][R6][R41] |
| Blood oxygen (SpO2) | Night average % | Yes (`daily_spo2`) | **No** | [R4][R7] |
| Breathing Disturbance Index / breathing regularity | 0–100 index from SpO2 drops | Yes (`daily_spo2.breathing_disturbance_index`) | No | [R4] |
| Daytime Stress | Seconds in "high stress" / "high recovery", day summary restored/normal/stressful | Yes (`daily_stress`) | No | [R4][R13] |
| Resilience | 14-day level (limited…exceptional) from sleep recovery, daytime recovery, stress | Yes (`daily_resilience`) | No | [R4][R12] |
| Cumulative Stress | ~Month-long load, weekly, 5 contributors (Oct 2025) | No | No | [R11] |
| Cardiovascular Age | Predicted vascular age 18–100 and pulse wave velocity (m/s) | Yes (`daily_cardiovascular_age`) | No | [R4][R16] |
| Cardio Capacity (VO2max) | Submaximal estimate, optional 6-min walk test | Yes (`vO2_max`) | No | [R4][R15] |
| Workouts and auto-detection | Activity, kcal, distance, intensity, source (manual/auto/live); Live Activity Tracking since 4 June 2026, 40+ auto-detected activities | Yes (`workout`) | Workouts and routes | [R4][R2][R6] |
| Sessions / Moments | Meditation, breathing, nap, rest with HR, HRV, motion, mood | Yes (`session`) | Mindful minutes | [R4][R6] |
| Tags / Enhanced Tags | User-entered habits, symptoms, events | Yes (`enhanced_tag`; `tag` deprecated) | No | [R4] |
| Rest Mode | Periods the user marked as rest/illness | Yes (`rest_mode_period`) | No | [R4] |
| Optimal bedtime | Recommended bedtime window and status | Yes (`sleep_time`) | No | [R4] |
| Chronotype | Early/late type from ≤90 days of sleep, activity, temperature; dynamic since March 2026 | No | No | [R14] |
| Symptom Radar | No/minor/major signs from temperature, respiratory rate, RHR, HRV; needs 7 nights in 14 | No | No | [R3] |
| Health Radar: Blood Pressure Signals | 30-day pattern in night PPG; no mmHg values; manual cuff log; wellness only, "cannot diagnose or rule out" | No | No | [R3][R2] |
| Health Radar: Nighttime Breathing | 30-day view, Steady…Highly varied | No | No | [R3] |
| Cycle Insights, fertile window, pregnancy, perimenopause/menopause, hormonal birth control | Temperature-based cycle features (May 2026 additions) | No | No | [R9][R10][R2] |
| Meals and glucose | Meal logging; Dexcom Stelo glucose in select regions | No | No | [R10] |
| GLP-1 Insights | Medication, side effects, weight with ring data (June 2026) | No | No | [R2] |
| Lab uploads | PDF blood results read into the app (30 June 2026) | No | No | [R2] |
| Oura Advisor, Counsel Health (Labs) | Chat assistant; AI + physicians (US, paid add-on) | No | No | [R2][R1] |
| Ring configuration, battery | Model (`or5`), size, colour, firmware; battery level series | Yes (`ring_configuration`, `ring_battery_level`) | No | [R4] |
| Personal info | Age, weight, height, sex, email | Yes (`personal_info`) | Height, weight | [R4][R6] |

Sleep apnea: Oura has no cleared sleep-apnea feature. Nighttime Breathing and the BDI are wellness views; a PSG study of Oura apnea/hypopnea detection is registered but has no results [R3][R42]. Blood pressure: Oura announced it was pursuing FDA clearance for a hypertension feature in 2025 [R48]; what shipped as Blood Pressure Signals is labelled wellness-only and shows no values [R3].

---

## 2. What Oura writes to Apple Health

Oura's support article is the primary source [R6]; its blog adds detail [R7]. Oura doesn't name HealthKit identifiers, so the right-hand column is the HealthKit type each item has to be (Apple's catalogue has one type per item).

| Oura → Health (Oura's words) | HealthKit type | Notes | Source |
|---|---|---|---|
| Sleep (duration, start, end, stages) | `HKCategoryType(.sleepAnalysis)` (stage values `asleepCore/Deep/REM`, `awake`, possibly `inBed`) | Oura warns the stages "may appear differently" in Health. Which category values it writes isn't documented: check on the phone. Tensile already detects these by bundle prefix `com.ouraring`. | [R6] |
| Heart rate, 1-minute intervals | `heartRate` | Day and night. The API itself only gives 5-min values, so Health is the finer source. | [R6][R4] |
| Respiratory rate, "average nighttime" | `respiratoryRate` | One value per night (the Watch writes many per night). | [R6][R8] |
| Steps | `stepCount` | | [R6] |
| Active energy | `activeEnergyBurned` | The blog says "Active/Resting energy"; the support article lists only Active. Unconfirmed whether `basalEnergyBurned` is written. | [R6][R7] |
| Workouts, workout routes | `HKWorkout`, `HKWorkoutRoute` | With kcal, distance, type, duration. Counts toward Apple's rings. | [R6][R7][R8] |
| Mindful minutes | `mindfulSession` | From Oura sessions. | [R6] |
| Height, weight | `height`, `bodyMass` | | [R6] |

**Not written to Apple Health** (on iPhone): HRV of any kind (neither `heartRateVariabilitySDNN` nor the new iOS 27 `heartRateVariabilityRMSSD` [R36]), resting heart rate (`restingHeartRate`), temperature (`bodyTemperature`; `appleSleepingWristTemperature` is the Watch's own type [R35]), SpO2 (`oxygenSaturation`), VO2max, breathing disturbances, and all scores, stress, resilience and age features [R6][R7][R8]. On Android, Health Connect does get HRV and night RHR from Oura [R7]; that difference is Oura's choice, not an Apple limit.

Requirements: iOS only; Gen3 and later need an active membership [R6].

---

## 3. Oura API v2 (spec version 1.43)

### 3.1 Access, membership, limits

- **Only v2 exists**; v1 is sunset [R4].
- **Membership:** a 403 means a missing scope *or* "the user's Oura subscription has expired"; the fix is to renew [R4].
- **App user cap:** an API application is limited to **10 users** until Oura approves it [R4]. Tensile's model (each owner registers their own free developer app) stays inside this.
- **Rate limits:** per-token and per-application layers; 429 responses carry `Retry-After`, `X-RateLimit-Limit/-Window/-Reset/-Tier`. The FAQ gives **5,000 requests per 5 minutes** [R4]. Tensile's few requests per sync are far below this.
- **User-Agent:** "Every request must include a `User-Agent` header… Not every HTTP library sends a default value, so set it explicitly" [R4].
- **Webhooks** are "strongly recommended", arrive about 30 s after the phone syncs, but need a public HTTPS server that answers a verification challenge [R4]. Tensile has no server and keeps data on the phone, so it should keep polling (a sync when the app opens is fine for these limits).
- **Freshness:** sleep data reaches the cloud only after the user opens the Oura app; activity, stress and heart rate may sync in the background [R4].
- **Sandbox:** `/v2/sandbox/usercollection/*` returns fake data for every type, without an Oura account; useful for tests [R4].

### 3.2 OAuth 2

| Item | Value | Source |
|---|---|---|
| Authorize | `https://cloud.ouraring.com/oauth/authorize` (new clients may use `https://developer.ouraring.com/authorize`) | [R5] |
| Token | `https://api.ouraring.com/oauth/token` | [R5] |
| Revoke | `https://api.ouraring.com/oauth/revoke?access_token=…` | [R5] |
| Flow | Authorization code (`response_type=code`); also a client-side flow (`response_type=token`) with **no refresh token** and a 30-day token | [R5] |
| PKCE | Supported: `code_challenge` "Recommended", `code_challenge_method` must be `S256`; `code_verifier` required at the token step if a challenge was sent | [R5] |
| Client secret | **Still required** at the token and refresh steps (in the body or HTTP Basic). PKCE doesn't replace it | [R5] |
| Refresh | Single use: each refresh returns a new refresh token | [R5] |
| Access-token life | Use `expires_in`. The docs disagree ("typically 30 days" in the FAQ, "typically 24 hours" in troubleshooting) | [R4][R5] |
| Auth code life | 10 minutes, single use | [R4] |
| Redirect URIs | A whitelist registered on the app; the token request must repeat the same `redirect_uri` | [R5] |
| Personal access tokens | Deprecated December 2025, "no longer available for use" | [R4] |
| Mobile note | "On supported mobile devices with the Oura app installed, this link can open the OAuth consent page within the app" | [R5] |

**Scopes** (spec 1.43): `email`, `personal`, `daily`, `heartrate`, `workout`, `tag`, `session`, `spo2`, and a new **`heart_health`** ("Heart health data") [R4]. The authentication page still lists only the first eight [R5]. The spec does **not** map scopes to endpoints; from the scope descriptions and tag pages: `daily` covers sleep, readiness, activity (and very likely `sleep`, `daily_stress`, `daily_resilience`, `sleep_time`, `rest_mode_period`); `spo2` covers `daily_spo2`; `heartrate` covers `heartrate`; `workout`, `session`, `tag` (for `tag` and `enhanced_tag`) as named; `personal_info` returns the id with no scope and the rest with `personal`/`email`. `heart_health` most likely gates `daily_cardiovascular_age` and `vO2_max`, but that is **an inference**; verify with a 403 test before relying on it [R4].

**A native iOS app** uses `ASWebAuthenticationSession` with the authorize URL and a callback scheme, exchanges the code for tokens with `URLSession`, and keeps tokens in the Keychain. Oura's docs don't forbid custom-scheme redirect URIs; they're a per-app whitelist [R5]. Because the token endpoint needs the client secret, a public app can't keep a shared secret safe without a server. Tensile's existing answer (each owner registers a free Oura developer app and types its ID and secret, stored in the Keychain) is the right one for an app with no backend, and it also stays under the 10-user cap. The client-side `token` flow avoids the secret but forces re-sign-in every 30 days, so it's worse for the owner.

### 3.3 Endpoints and fields

All `GET /v2/usercollection/<name>` with `start_date`/`end_date` (or `start_datetime`/`end_datetime` for time series), `next_token`, and a `fields` filter; single documents at `/<name>/{document_id}` [R4].

| Endpoint | Fields (spec 1.43) | Likely scope |
|---|---|---|
| `sleep` | `id, day, type` (long_sleep/sleep/late_nap/rest/deleted), `bedtime_start, bedtime_end, time_in_bed, total_sleep_duration, deep/light/rem_sleep_duration, awake_time, efficiency, latency, restless_periods, average_heart_rate, lowest_heart_rate, average_hrv, average_breath, heart_rate` (5-min sample), `hrv` (5-min sample), `sleep_phase_5_min, sleep_phase_30_sec, app_sleep_phase_5_min` (deprecated, matches app), `movement_30_sec, readiness{score, contributors, temperature_deviation, temperature_trend_deviation}, readiness_score_delta, sleep_score_delta, low_battery_alert, period, sleep_algorithm_version` (v1/v2), `sleep_analysis_reason, ring_id` (null) | daily |
| `daily_sleep` | `id, day, score, contributors{deep_sleep, efficiency, latency, rem_sleep, restfulness, timing, total_sleep}, timestamp` | daily |
| `daily_readiness` | `id, day, score, temperature_deviation, temperature_trend_deviation, contributors{activity_balance, body_temperature, hrv_balance, previous_day_activity, previous_night, recovery_index, resting_heart_rate, sleep_balance, sleep_regularity}, timestamp` | daily |
| `daily_activity` | `score, contributors{…6}, steps, active_calories, total_calories, target_calories, target_meters, meters_to_target, equivalent_walking_distance, average_met_minutes, met` (sample), `class_5_min, high/medium/low_activity_time` and `…_met_minutes, sedentary_time, sedentary_met_minutes, resting_time, non_wear_time, inactivity_alerts, timestamp` | daily |
| `daily_spo2` | `day, spo2_percentage{average}, breathing_disturbance_index` | spo2 |
| `daily_stress` | `day, stress_high` (s), `recovery_high` (s), `day_summary` (restored/normal/stressful) | daily (inferred) |
| `daily_resilience` | `day, level` (limited…exceptional), `contributors{sleep_recovery, daytime_recovery, stress}` | daily (inferred) |
| `daily_cardiovascular_age` | `day, vascular_age, pulse_wave_velocity` | heart_health (inferred) |
| `vO2_max` | `day, timestamp, vo2_max` | heart_health (inferred) |
| `heartrate` | rows of `timestamp, bpm, source` (awake/rest/sleep/workout/live/session); 5-min increments | heartrate |
| `workout` | `activity, calories, distance, intensity, label, source` (manual/autodetected/confirmed/workout_heart_rate/live_*), `start/end_datetime, day` | workout |
| `session` | `type` (breathing/meditation/nap/relaxation/rest/body_status), `start/end_datetime, heart_rate, heart_rate_variability, motion_count` (samples), `mood` | session |
| `enhanced_tag` | `tag_type_code, start/end_time, start/end_day, comment, custom_name` | tag |
| `rest_mode_period` | `start/end_day, start/end_time, episodes[{tags, timestamp}]` | not stated |
| `sleep_time` | `day, optimal_bedtime{day_tz, start_offset, end_offset}, recommendation, status` | not stated |
| `ring_configuration` | `color, design, firmware_version, hardware_type` (… gen4, **or5**), `set_up_at, size` | not stated |
| `ring_battery_level` | `timestamp, level, charging, in_charger` | not stated |
| `personal_info` | `id, age, weight, height, biological_sex, email` | personal / email |
| `tag` | deprecated, use `enhanced_tag` | tag |

Spec notes worth keeping: `average_heart_rate` and `lowest_heart_rate` in `sleep` are computed from 30-second samples and differ from what the Oura app shows (the app uses 5-minute aggregates) [R4]. `app_sleep_phase_5_min` matches the app's hypnogram and "will be removed in the future"; `sleep_phase_5_min` and `sleep_phase_30_sec` are the lasting fields [R4]. SpO2 needs Gen3 or later [R4].

---

## 4. Already integrated vs missing

### 4.1 What Tensile fetches today (API)

From `Packages/AppCore/Sources/AppCore/Oura.swift`, `App/Services/Oura/OuraLink.swift`, `OuraCache.swift`, `App/Features/Health/OuraCard.swift`. Scopes requested: `personal daily heartrate`. Sync: 90 days first, then 7; at most every 30 min; cache keeps 120 days.

| Endpoint | Fields decoded | Used for |
|---|---|---|
| `sleep` | `id, day, type, bedtime_start, bedtime_end, sleep_phase_5_min, total_sleep_duration, deep/light/rem_sleep_duration, awake_time, efficiency, average_hrv, average_heart_rate, lowest_heart_rate, average_breath` | Sleep samples for nights missing from Health when the ring is first (`HealthKitClient.sleepSamples`); overnight RMSSD for recovery when the ring is first (`DailyMetricsModel.ouraRMSSD`); HRV on `OuraCard` |
| `daily_readiness` | `day, score, temperature_deviation` | `OuraCard` (readiness, temperature) |
| `daily_sleep` | `day, score` | `OuraCard` (sleep score) |

Decoded but not used anywhere: `average_heart_rate`, `lowest_heart_rate`, `average_breath`, the stage durations and `efficiency` (the hypnogram is used instead).

Requested but never called: the `heartrate` scope (no `/heartrate` request) and the `personal` scope (no `/personal_info` request).

### 4.2 Missing endpoints and fields

| Missing | Scope needed | Recommended? (section 6) |
|---|---|---|
| `sleep.lowest_heart_rate` / `average_heart_rate` into the recovery RHR baseline | daily (already granted, already decoded) | **Yes**: highest value for the least work |
| `sleep.hrv` and `sleep.heart_rate` 5-min samples | daily | Optional (in-sleep detail; the night average is what the studies validated) |
| `sleep.latency, time_in_bed, restless_periods, low_battery_alert, sleep_algorithm_version, sleep_phase_30_sec` | daily | `low_battery_alert` and `time_in_bed` yes (data quality); the rest optional |
| `daily_readiness.temperature_trend_deviation` | daily | Optional, labelled |
| `daily_spo2` | **spo2** (not granted) | Optional, labelled; the Watch wins |
| `rest_mode_period` | not stated (likely daily) | Optional: could switch on Tensile's rest mode |
| `ring_configuration` | not stated | Optional: show "Oura Ring 5" and firmware in Settings |
| `daily_activity` | daily | No (Watch wins for steps and energy; Activity score is a composite) |
| `workout`, `session` | workout, session | No (already in Health as workouts and mindful minutes) |
| `heartrate` | heartrate (granted) | No (Health has the same data at 1-min, finer than the API's 5-min) |
| `daily_stress`, `daily_resilience` | daily | No (proprietary, unvalidated) |
| `daily_cardiovascular_age`, `vO2_max` | heart_health (inferred) | No (see section 5) |
| `enhanced_tag`, `sleep_time`, `personal_info`, `ring_battery_level`, `daily_readiness.contributors`, `daily_sleep.contributors` | tag / daily / personal | No |
| Cumulative Stress, Chronotype, Symptom Radar, Health Radar, Cycle, Meals/Glucose, GLP-1, Labs | **not in the API** | Can't be integrated |

### 4.3 The HealthKit side today

| Oura writes | How Tensile reads it now | Status |
|---|---|---|
| Sleep stages | `SleepSource.tracker` marks samples from bundle `com.ouraring*` (or a name containing "oura") as `.ring`; `SleepSourcePreference` takes one device's whole night; with ring-first, nights Oura didn't write come from `OuraCache` | **Handled** |
| 1-min heart rate | `heartRatePerMinuteBySource` / `heartRateBySource` split by source for workouts (`HeartRateMerge`). `heartRatePerMinute` (used for sleeping HR in `SleepingHeartRateHistory`) averages **all sources** per minute | Workouts handled; sleeping HR **mixes ring and watch** minutes in one baseline |
| Nightly respiratory rate | `overnightRespiratoryRate` averages every `respiratoryRate` sample in the window, **all sources**. Oura's one nightly value is averaged with the Watch's many samples | **Mixes devices**; neither algorithm is validated against PSG (section 5) |
| Steps, active energy | Statistics queries (`dailySum`, `.cumulativeSum`) | HealthKit de-duplicates overlapping sources by the user's Data Sources priority in the Health app; correct only if the Watch is above Oura there |
| Workouts | `externalWorkouts` returns every workout not from Tensile; `WorkoutLinker` links by overlap; workout kcal are summed per day | An Oura auto-detected workout that overlaps a Watch workout is **counted twice** in the per-day workout energy and can be picked for linking. No source filter |
| Mindful minutes | Not read | Nothing to do |
| HRV, RHR, temperature, SpO2 | Oura doesn't write them; Tensile's reads of these types return Watch data only | No conflict |

### 4.4 Small issues in the existing link (no code changed)

1. **No explicit `User-Agent`.** `URLSession` sends a default one, so requests work today, but Oura asks native apps to set it explicitly and says requests without one "may be rejected" [R4].
2. **No PKCE.** Oura marks `code_challenge` (S256) "Recommended" [R5]. It's cheap to add and protects the code on a custom-scheme redirect, which other apps could also register.
3. **Unused scopes.** `heartrate` and `personal` are requested but never used. Requesting only what is used is the data-minimisation default; changing scopes means the owner signs in again.
4. **HRV from Oura only when the ring is first for sleep.** `ouraRMSSD()` returns empty unless `SleepSourceSetting == .ring`. The HRV evidence (section 5) favours the ring regardless of which device stages sleep, so the HRV choice shouldn't depend on the sleep setting.
5. **Oura's scores on `OuraCard`.** Readiness and sleep score are shown "as Oura reports them". Apple's equivalent scores were removed on 17 Nov 2026 for having no published method or validation (`apple-scores-2026-11.md`); Oura's composites are in the same position (section 5).

---

## 5. Validation evidence, metric by metric

Gold standards: PSG for sleep, ECG for heart rate and HRV, indirect calorimetry for energy and VO2max, arterial blood gas or a reference oximeter for SpO2, PSG apnea–hypopnea index for breathing. Most Oura studies have Oura-employed authors or Oura funding; that is flagged per row. **No published study has tested the Oura Ring 5 or the Apple Watch Series 12 for any metric**, so every row is about earlier hardware or algorithms.

| Metric | Oura evidence | Apple Watch evidence | Verdict |
|---|---|---|---|
| **Sleep vs wake, total sleep** | Gen3, 35 healthy adults, 1 night PSG: sleep sensitivity ≥95%, TST bias about −9 min (Oura-funded; lead author on Oura's advisory board) [R18 ✓]. Gen3, 96 adults, multi-night PSG: sensitivity 94.4%, specificity ~74%, accuracy ~92% (partly Oura-funded) [R19 (abstract)]. Clinical sleep-lab population (sleep disorders): TST difference <12 min at group level, but large individual errors [R21 (abstract)] | S8 in the same study: sensitivity ≥95%, TST bias about +8 min [R18 ✓]. Apple's validation (166 people, 299 nights PSG): sleep sensitivity 97.9%, specificity 75%; 2025 algorithm 96.8% / 78.9% (Apple-run) [R22 ✓]. S8 in 62 adults (independent): κ 0.53 overall [R23 (secondary)] | **Both good for duration and timing; no winner.** Specificity (catching wake) is the weak spot for both |
| **Sleep stages** | Gen3 four-stage κ 0.65; sensitivity light 78%, deep 80%, REM 76%; no significant bias in any stage (Oura-funded) [R18 ✓]. Algorithm paper: 79% four-stage accuracy, 106 people, 440 nights (Oura authors) [R20 ✓]. Gen3, Tokyo: stage accuracy 75.5% (light) to 90.6% (REM), REM under by 4–6 min [R19 (abstract)]. **Clinical population: 53% four-stage accuracy** (independent, Sci Rep 2025) [R21 (abstract)]. A US class action (filed 20 Aug 2026) disputes Oura's stage-accuracy claims [R47 (secondary)] | S8 (2022 algorithm): κ 0.60; deep sensitivity 50.5%; **deep under by 43 min, light over by 45 min** [R18 ✓]. Apple's own: κ 0.63, and **0.68 for the iOS 26 / watchOS 26 algorithm**; clinical PSG population κ 0.55 [R22 ✓]. Lee 2023 (11 trackers, PSG) included Oura 3 and Apple Watch 8; per-device F1 not confirmed here [R24 (abstract)] | **Weak and mixed.** The one head-to-head favoured Oura (smaller deep/light bias), but it was Oura-funded and used Apple's old algorithm; Apple's current algorithm reports a higher κ in its own data. Stages should inform, not drive, scores |
| **Overnight HRV (RMSSD)** | **Independent** (Air Force Research Lab funding, no conflicts), 13 adults, 536 nights vs Polar H10 ECG: Gen4 CCC 0.99, MAPE 6.0%, bias −1.0 ms (LoA −11.8 to 9.9); Gen3 CCC 0.97, MAPE 7.2%. WHOOP 0.94, Garmin 0.87, Polar 0.82 [R25 ✓]. 35 adults vs ECG: RMSSD accurate per 5-min and per night (independent, UC Irvine) [R26 (abstract)]. 49 adults vs ECG: night-average r² 0.98 (Oura authors) [R27 (secondary)]. Accuracy improves with ≥30-min aggregation [R54 (abstract)] | Series 9 / Ultra 2, 39 adults, 316 morning 5-min supine readings vs Polar H10: **SDNN bias −8.3 ms, LoA −53.8 to 37.2, MAPE 28.9%**; not equivalent within ±10 ms [R28 ✓]. iOS 27's new `heartRateVariabilityRMSSD` type (Series 12) has **no published validation** yet [R36] | **Oura wins clearly.** Never mix Oura RMSSD with Apple SDNN [R50]; mixing with Apple RMSSD needs the per-person scaling Tensile already does |
| **Resting / sleeping heart rate** | Independent ECG study: Gen4 CCC 0.98, bias −0.9 bpm, MAPE 1.9%; Gen3 CCC 0.97 [R25 ✓]. Night average r² 0.996 (Oura authors) [R27 (secondary)] | Series 9 / Ultra 2 morning RHR: MAE 3.7 bpm, MAPE 5.9% [R28 ✓]. Apple's `restingHeartRate` is computed from daytime stillness, a different quantity (`evidence-audit-2026-11.md` §1.2) | **Oura wins for the night value.** Use Oura's lowest/average sleeping HR for the recovery baseline when the ring was worn |
| **Daytime and exercise HR** | Night-validated; no published daytime/exercise validation found. API values are 5-min [R4] | Apple Watch among the most accurate brands for HR in the systematic review [R30 (abstract)]; Series 12 samples every 5 s (Apple claim) [R46] | **Watch wins** in the day and during exercise |
| **Temperature deviation** | Oura in-house: ring vs iButton on the same finger, 16 people, r² 0.92; bath test r² >0.99 (company blog, not peer-reviewed) [R33]. Deviation drives ovulation detection: 96.4% of ovulations, MAE 1.26 days vs LH tests (Oura authors) [R34 ✓ abstract]. Finger temperature preceded reported fever in TemPredict (n=50, Sci Rep 2020) [R44 (secondary)] | Wrist temperature during sleep, environment-corrected, one value a night [R35]. Ovulation estimate MAE 1.22 days (Apple-funded preprint) [R55 (secondary)] | **No independent validation of either sensor.** Both work as a personal baseline signal. Prefer one device per baseline; Oura's is what the illness research used |
| **Respiratory rate** | vs ECG-derived rate, 43 adults: mean error 0.71 breaths/min (company blog) [R41]. No PSG study found | No peer-reviewed validation found | **Weak for both.** Use only as a change-from-baseline flag, one source |
| **SpO2** | No independent study found. Oura claims Ring 4 is 30% more accurate than Gen3 (within 2 points of reference, company study, 60 people) [R42] | Systematic review: no strong systematic bias vs medical oximeters, outliers up to 15 points; healthy people often read below 95% [R32 (abstract)] | **Watch wins** (independent evidence exists). A nightly average has little use in a healthy adult |
| **Breathing disturbances / apnea** | BDI: compared only with "human-annotated SpO2 desaturation events" (company) [R42]; no AHI validation published; PSG study registered, no results [R42]. Nighttime Breathing is wellness-only [R3] | Breathing Disturbances (`appleSleepingBreathingDisturbances`, iOS 18 [R38]) feed an **FDA-cleared** moderate-to-severe sleep-apnea notification (Sept 2024) [R39] | **Watch wins.** Tensile already reads Apple's type |
| **Steps** | Free-living vs reference monitors: r ≥0.76, group-level bias; step count at hip/wrist reference within 10% MAPE (independent, adults 20–40) [R29 (abstract)] | Steps accurate in lab settings [R30 (abstract)]; Series 12 adds a new step algorithm (Apple claim) [R46] | **Watch wins** |
| **Energy expenditure** | vs indirect calorimetry r 0.93 but underestimates more as intensity rises [R29 (abstract)] | No brand accurate for energy expenditure; devices tend to underestimate [R30 (abstract)] | **Neither is accurate.** Watch first for consistency; never add the two |
| **Workouts** | Auto-detection for 40+ activities; live tracking since June 2026 (company) [R2] | Watch workouts are recorded, not guessed | **Watch wins**; Oura workouts only where no Watch workout overlaps |
| **VO2max / Cardio Capacity** | Submaximal estimate; Oura says it is "not as accurate as a laboratory maximal test"; **no published validation** found [R15] | Lambe 2025, 30 adults vs treadmill test: **underestimates by 6.1 mL/kg/min, MAPE 13.3%**, LoA −6.1 to 18.3 [R31 ✓ abstract] | **Watch**, the only one with published accuracy (and it's modest). Tensile's own fitness checks are better still |
| **Cardiovascular Age / PWV** | Night PPG from the ring predicted chronological age with MAE ~6–7 years, same as a clinical fingertip oximeter, 160 adults (PLOS Digit Health 2026) [R43 (abstract)]. Not compared with a reference PWV device, and no link to outcomes shown | n/a | **Unvalidated as a health measure.** Leave out |
| **Readiness, Sleep, Activity scores** | Proprietary composites; inputs partly validated, **the composite weighting is unpublished and no study validates the score** against an outcome [R49]. Small athlete studies found subjective ratings more sensitive to load than ring measures [R49 (secondary)] | Apple's Readiness and Sleep score: same situation (`apple-scores-2026-11.md`) | **Leave out** |
| **Daytime Stress, Resilience, Cumulative Stress** | "Validated by internal studies… compared to other well-established industry solutions" plus surveys; no methods published [R13]. Resilience: three contributors, weights unpublished [R12]. Cumulative Stress checked against the Perceived Stress Scale and a burnout inventory (company claim) [R11] | n/a | **Leave out** |
| **Symptom Radar, Health Radar** | No independent validation; Blood Pressure Signals "cannot diagnose or rule out any condition" [R3]. Not in the API | Apple's hypertension notification is FDA-cleared: sensitivity 41%, specificity 92% [R40 (secondary)] | **Can't integrate; leave out** |
| **Chronotype, Optimal bedtime** | Company method only [R14] | n/a | **Leave out** (Tensile's sleep window follows its own research, `sleep-window-2026-11.md`) |
| **Cycle features** | Ovulation detection as above [R34] | Apple Cycle Tracking with wrist temperature [R35] | Not relevant to this owner; not in the API |

---

## 6. Recommendation per metric

Columns: **Path** (how Tensile gets it), **Winner** (when both devices have the night or day), **Use** (feeds Tensile's own scores / shown as-is labelled "from Oura" / left out).

| Metric | Path | Winner when both | Use | Why |
|---|---|---|---|---|
| Overnight HRV (RMSSD, night average) | API `sleep.average_hrv` (not in Health) | **Oura** | **Feed recovery** (HRV baseline), whatever the sleep-source setting; keep the existing per-person scaling when nights switch device | Strongest independent evidence of any metric here [R25][R26]; Watch SDNN error ~29% [R28] |
| Sleeping / lowest HR | API `sleep.lowest_heart_rate`, `average_heart_rate` (already decoded) | **Oura** | **Feed recovery** RHR baseline and the illness watch; one source per baseline, Watch per-minute HR only on nights without the ring | CCC 0.97–0.98 vs ECG [R25] |
| Sleep duration, timing, regularity | Health (`sleepAnalysis` from Oura) with the API as fallback (as now) | Either; keep the owner's setting, default ring | **Feed sleep score** | Both ≥95% sleep sensitivity [R18][R22] |
| Sleep stages | Same, one device per night (as now) | Default ring; evidence doesn't separate them | **Show**, light weight only in scores; label stage minutes as estimates | κ 0.55–0.68 on both; 53% in a clinical group [R18][R21][R22] |
| Temperature deviation | API `daily_readiness.temperature_deviation` (+ `temperature_trend_deviation`) | Oura when the ring was worn, else Watch wrist temperature; never mix in one baseline | **Show labelled "from Oura"**, and use only as one flag in the illness watch, marked weak evidence | No independent sensor validation [R33]; personal-baseline use has some support [R34][R44] |
| Respiratory rate | Health (Oura writes one nightly value), split by source | Oura night value when worn, else Watch | **Illness-watch flag only**, one source per baseline | Weak evidence both sides [R41] |
| SpO2 (night average) | Health (Watch). Oura via API `daily_spo2` (needs `spo2` scope) | **Watch** | Show the Watch's; Oura's optional in the vitals list, labelled, not in scores | Independent evidence only for the Watch [R32] |
| Breathing disturbances | Health (Watch, already read) | **Watch** | Keep Apple's; leave Oura BDI out | FDA-cleared Watch feature [R39]; BDI unvalidated [R42] |
| Daytime and workout HR | Health, per minute, split by source (as now) | **Watch** | Feeds strain/zones (as now) | [R30][R46] |
| Steps, active energy | Health statistics | **Watch** (owner sets Watch above Oura in Health › Data Sources) | Feed as now; never add Oura and Watch values | [R29][R30] |
| Workouts | Health | **Watch**; drop an Oura workout that overlaps a Watch workout | Feed as now, after de-duplicating | Avoids double-counted kcal |
| VO2max | Health (Watch) and Tensile's own tests | **Watch** / Tensile test | Leave Oura's out | Only the Watch has a published validation [R31]; none for Oura [R15] |
| Readiness, Sleep, Activity scores | — | — | **Leave out** (remove from `OuraCard`) | Proprietary composites, no published validation [R49]; same rule as Apple's scores |
| Daytime Stress, Resilience, Cumulative Stress | — | — | **Leave out** | Internal validation only [R11][R12][R13] |
| Cardiovascular Age, PWV | — | — | **Leave out** | Predicts calendar age, not health outcomes [R43] |
| BDI, Nighttime Breathing, Blood Pressure Signals, Symptom Radar | — | — | **Leave out** (most aren't in the API) | Wellness-only, unvalidated [R3] |
| Chronotype, optimal bedtime | — | — | **Leave out** | Company method only [R14] |
| Rest Mode | API `rest_mode_period` | — | Optional: turn on Tensile's rest mode when Oura's is on | A user-entered state, not a measurement |
| Ring model, battery | API `ring_configuration`, `sleep.low_battery_alert` | — | Optional: data-quality note ("ring battery ran out, night incomplete") | Prevents a short night being scored as real |
| Tags, sessions, cycle, meals, GLP-1, labs | — | — | **Leave out** | Not measurements, or not in the API, or not relevant |

---

## 7. Integration plan, in order of health value per effort

1. **HRV from Oura whenever it has the night** (small). Decouple `ouraRMSSD()` from the sleep-source setting; keep the per-person scaling that puts Oura and Apple RMSSD on one scale; never mix with SDNN. Biggest evidence-backed gain.
2. **Sleeping HR from Oura for the recovery baseline** (medium). The values are already decoded. One source per baseline, Watch per-minute HR only on nights without the ring; tests in AppCore.
3. **Remove Oura's Readiness and Sleep scores from `OuraCard`** (small). Keep HRV, sleeping HR and temperature deviation, labelled "from Oura". Consistent with the 17 Nov removal of Apple's scores; tell the owner why with [R49].
4. **Fix the HealthKit multi-source spots** (medium): respiratory rate per source (one device a night); de-duplicate overlapping Oura and Watch workouts before linking and summing kcal; in Settings, tell the owner to put Apple Watch above Oura for Steps and Active Energy in Health › Data Sources so HealthKit's own de-duplication favours the Watch.
5. **Auth hygiene** (small): explicit `User-Agent: Tensile/<version>`; PKCE S256; scopes trimmed to what's used (`daily`, plus `spo2` only if Oura SpO2 is shown); prompt the owner to reconnect once.
6. **Optional, data quality** (small): `low_battery_alert`, `time_in_bed` and ring model for a "night incomplete" note; `rest_mode_period` to switch on rest mode.
7. **Don't add**: scores, stress, resilience, cardiovascular age, VO2max, BDI, chronotype, Health Radar.

Re-check this file when an independent PSG or ECG study of the Ring 5 or the Series 12 appears, or when Oura starts writing HRV or RHR to Apple Health.

---

## References

- [R1] TechCrunch, "Oura unveils its Ring 5 with a thinner, lighter design starting at $399", 28 May 2026. https://techcrunch.com/2026/05/28/oura-unveils-its-ring-5-with-a-thinner-lighter-design-starting-at-399/
- [R2] Oura blog, "New software features" (Ring 5 launch). https://ouraring.com/blog/new-software-features/
- [R3] Oura Member Care, "Health Radar" (updated 29 Oct 2026). https://support.ouraring.com/en-us/articles/52627030482707-Health-Radar
- [R4] Oura API v2 documentation, OpenAPI spec 1.43 (loaded by https://cloud.ouraring.com/v2/docs). https://cloud.ouraring.com/v2/static/json/openapi-1.43.json
- [R5] Oura API, "Authentication". https://cloud.ouraring.com/docs/authentication
- [R6] Oura support, "Apple Health integration". https://support.ouraring.com/hc/en-us/articles/360025438734
- [R7] Oura blog, "Data sharing and partner integrations". https://ouraring.com/blog/data-sharing-partner-integrations/
- [R8] Sonar Health, "Sync Oura to Apple Health" (27 May 2026). https://www.sonarhealth.co/blog/sync-oura-to-apple-health/
- [R9] Oura blog, "The value of Oura membership". https://ouraring.com/blog/the-value-of-oura-membership/
- [R10] Oura partner support, "Oura Ring overview". https://partnersupport.ouraring.com/hc/en-us/articles/47837676430739-Oura-Ring-Overview
- [R11] TechCrunch, "Oura launches redesigned app and Cumulative Stress feature", 20 Oct 2025. https://techcrunch.com/2025/10/20/oura-launches-redesigned-app-and-cumulative-stress-feature
- [R12] Oura support, "Resilience". https://support.ouraring.com/hc/articles/25358829055251
- [R13] Oura support, "Daytime Stress". https://support.ouraring.com/hc/lv/articles/21205822135315
- [R14] Oura blog, "What is your chronotype?". https://ouraring.com/blog/what-is-your-chronotype/
- [R15] Oura support, "Cardio Capacity (VO2 max)". https://support.ouraring.com/hc/en-us/articles/28336620578835-Cardio-Capacity-VO2-Max ; Oura blog, "Cardio Capacity". https://ouraring.com/blog/it/cardio-capacity/
- [R16] Oura support, "Cardiovascular Age". https://support.ouraring.com/hc/en-us/articles/28451491040019-Cardiovascular-Age ; https://ouraring.com/blog/cardiovascular-age/
- [R17] Oura support, "Heart rate variability". https://support.ouraring.com/hc/en-us/articles/360025441974
- [R18] Robbins R, et al. Accuracy of three commercial wearable devices for sleep tracking in healthy adults. *Sensors* 2024;24(20):6532. Funded by Oura. https://pmc.ncbi.nlm.nih.gov/articles/PMC11511193/
- [R19] Svensson T, et al. Validity and reliability of the Oura Ring Generation 3 with Oura sleep staging algorithm 2.0. *Sleep Med* 2024;115. https://www.pubmed.gov/38382312/
- [R20] Altini M, Kinnunen H. The promise of sleep: a multi-sensor approach for accurate sleep stage detection using the Oura ring. *Sensors* 2021;21(13):4302. https://pmc.ncbi.nlm.nih.gov/articles/PMC8271886/
- [R21] Consumer sleep-tracking rings vs PSG in a clinical sleep-lab population (Oura, SleepOn, Circul). *Sci Rep* 2025;15:9461. https://www.nature.com/articles/s41598-025-93774-z
- [R22] Apple, "Estimating Sleep Stages from Apple Watch" (updated October 2025). https://www.apple.com/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf
- [R23] Schyvens A-M, et al. A performance validation of six commercial wrist-worn wearable sleep-tracking devices. *Sleep Adv* 2025;6(2):zpaf021. https://academic.oup.com/sleepadvances/article/6/2/zpaf021/8090472
- [R24] Lee T, et al. Accuracy of 11 wearable, nearable, and airable consumer sleep trackers. *JMIR mHealth uHealth* 2023;11:e50983. https://mhealth.jmir.org/2023/1/e50983
- [R25] Dial MB, et al. Validation of nocturnal resting heart rate and heart rate variability in consumer wearables. *Physiol Rep* 2025;13(16):e70527. https://pmc.ncbi.nlm.nih.gov/articles/PMC12367097/
- [R26] Cao R, et al. Accuracy assessment of Oura ring nocturnal heart rate and heart rate variability in comparison with electrocardiography. *J Med Internet Res* 2022;24(1):e27487. https://www.jmir.org/2022/1/e27487/
- [R27] Kinnunen H, et al. Feasible assessment of recovery and cardiovascular health: accuracy of nocturnal HR and HRV assessed via ring PPG in comparison to medical grade ECG. *Physiol Meas* 2020;41(4):04NT01. https://pubmed.ncbi.nlm.nih.gov/32217820/ ; figures from https://ouraring.com/blog/how-accurate-is-oura/
- [R28] O'Grady B, et al. Apple Watch HRV (SDNN) and resting HR vs Polar H10. *Sensors* 2024. https://pmc.ncbi.nlm.nih.gov/articles/PMC11478500/
- [R29] Validation of Oura ring energy expenditure and steps in laboratory and free-living. *BMC Med Res Methodol* 2023. https://pmc.ncbi.nlm.nih.gov/articles/PMC9950693/
- [R30] Fuller D, et al. Reliability and validity of commercially available wearable devices for measuring steps, energy expenditure, and heart rate: systematic review. *JMIR mHealth uHealth* 2020;8(9):e18694. https://mhealth.jmir.org/2020/9/e18694
- [R31] Lambe R, et al. Investigating the accuracy of Apple Watch VO2 max measurements: a validation study. *PLoS One* 2025;20(5):e0323741. https://pmc.ncbi.nlm.nih.gov/articles/PMC12080799/
- [R32] Windisch P, et al. Accuracy of the Apple Watch oxygen saturation measurement in adults: a systematic review. *Cureus* 2023. https://pmc.ncbi.nlm.nih.gov/articles/PMC10039641/
- [R33] Oura blog, "Oura's temperature sensor is validated and accurate". https://ouraring.com/blog/temperature-validated-accurate/
- [R34] Oura Ring as a tool for ovulation detection: validation analysis. *J Med Internet Res* 2025 (Oura authors). https://pmc.ncbi.nlm.nih.gov/articles/PMC11829181/
- [R35] Apple Developer, `appleSleepingWristTemperature`. https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applesleepingwristtemperature
- [R36] Apple Developer, `heartRateVariabilityRMSSD` (iOS 27.0+). https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilityrmssd
- [R37] Apple Developer, `heartRateVariabilitySDNN`. https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn
- [R38] Apple Developer, `appleSleepingBreathingDisturbances` (iOS 18.0+). https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applesleepingbreathingdisturbances
- [R39] AASM, "Apple Watch Series 10 features sleep apnea notifications" (FDA clearance Sept 2024). https://aasm.org/apple-watch-series-10-features-sleep-apnea-notifications
- [R40] FDA 510(k) K250507, Apple Hypertension Notification Feature (third-party transcription; check the FDA PDF). https://510k.innolitics.com/device/K250507
- [R41] Oura blog, "How accurate is Oura's respiratory rate?". https://ouraring.com/blog/nl/how-accurate-is-ouras-respiratory-rate/
- [R42] Oura blog, "Development of the blood oxygen sensing (SpO2) feature". https://ouraring.com/blog/de/development-of-the-blood-oxygen-sensing-spo2-feature/ ; ClinicalTrials.gov NCT07908199 (Oura PSG apnea/hypopnea validation, no results). https://clinicaltrials.gov/study/NCT07908199
- [R43] Vascular age estimation using a consumer wearable sleep tracker. *PLOS Digit Health* 2026. https://ideas.repec.org/a/plo/pdig00/0001329.html
- [R44] Oura blog on TemPredict (Smarr/Mason, *Sci Rep* 2020). https://ouraring.com/blog/tempredict_covid19_research/
- [R46] Apple Newsroom, "Introducing Apple Watch Series 12 with the all-new Health Sensing System", Sept 2026. https://www.apple.com/ee/newsroom/2026/09/introducing-apple-watch-series-12-with-the-all-new-health-sensing-system/
- [R47] the5krunner, "Oura's sleep stage accuracy: lawsuit", 23 Aug 2026 (secondary). https://the5krunner.com/2026/08/23/oura-sleep-accuracy-lawsuit/
- [R48] MedTech Dive, "Oura pursues FDA clearance for smart ring blood pressure feature". https://www.medtechdive.com/news/oura-fda-clearance-smart-ring-blood-pressure/803181/
- [R49] BioSource Software, "Wearable composite health scores require validation" (commentary). https://www.biosourcesoftware.com/post/5-second-science-wearable-composite-health-scores-require-validation
- [R50] Shaffer F, Ginsberg JP. An overview of heart rate variability metrics and norms. *Front Public Health* 2017;5:258. https://www.frontiersin.org/articles/10.3389/fpubh.2017.00258/full
- [R54] Liang et al. Deriving accurate nocturnal heart rate, rMSSD and frequency HRV from the Oura ring. *Sensors* 2024;24(23):7475. https://mdpi.com/1424-8220/24/23/7475
- [R55] Wang Y, et al. Apple Watch wrist-temperature ovulation estimates (Apple-funded preprint, NCT05852951). https://preprints.jmir.org/preprint/50821


## Owner's decision, 18 Nov 2026

The owner asked to see Oura's Readiness and Sleep scores, Daytime Stress, Resilience, Cardiovascular Age, Cardio Capacity (VO₂ max) and the Breathing Disturbance Index despite the findings above. They are shown in a separate "Oura's own numbers" card (`OuraOwnNumbersCard`, `OuraOwnNumbers` in AppCore), each row with its evidence note, and are display-only: no Tensile score, baseline, coach answer or recommendation reads them. Chronotype and Health Radar stay out because the API doesn't provide them. The panel asks for the `spo2` and `heart_health` scopes; if Oura refuses `heart_health` at sign-in, the app retries without it.
