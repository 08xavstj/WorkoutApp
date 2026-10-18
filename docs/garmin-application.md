# Garmin Connect Developer Program: application draft

Ready-to-paste answers for Garmin's Health API access request. Garmin
approves companies and organisations, not personal projects, so apply as
Lontra Industries. Edit anything in [brackets].

## Before you apply

- A registered business name: Lontra Industries [registration number / country].
- A website with a page about the app, e.g. lontraindustries.com/workoutapp.
- A privacy policy URL (see the draft at the bottom). Garmin checks this.
- A business email address on your own domain. Garmin may ignore Gmail addresses.

## Company

- **Company name:** Lontra Industries
- **Website:** [https://…]
- **Contact:** Xavier St-Jacques, [title], [business email]
- **Country:** [Canada]

## Product

- **Product name:** WorkoutApp
- **Platform:** iOS app (iPhone), with a Supabase backend.
- **Description:** WorkoutApp is a training and recovery app for people who
  lift weights. It turns wearable data into daily strain, recovery and sleep
  scores. It also has a gym tracker whose sessions count toward strain, and an
  AI coach that plans workouts around the user's recovery and the equipment in
  their gym.
- **Why Garmin data:** Many of our users train with Garmin watches. Apple
  Health receives heart rate, sleep and steps from Garmin Connect, but not
  HRV, stress, Body Battery or respiration. Recovery scoring depends on
  overnight HRV and resting heart rate, so we need the Health API to give
  Garmin users accurate recovery scores.
- **Stage / users:** [In development, private beta; expected users in year 1: …]
- **Commercial model:** [Free beta / subscription planned]

## Data requested

Health API summaries:

| Summary | Used for |
| --- | --- |
| HRV (overnight) | Recovery score baseline and trend |
| Dailies (resting HR, steps, calories, intensity minutes) | Strain, energy balance |
| Sleep (stages, duration) | Sleep score |
| Stress details and Body Battery | Daily readiness context |
| Respiration and Pulse Ox | Health monitor trends |
| Activities (summary + heart rate) | Strain from workouts |
| User metrics (VO2 max, fitness age) | Biology tab trends |

Read only; we don't write data to Garmin Connect.

## Data handling

- **Auth:** Garmin OAuth. Tokens are stored server-side only (Supabase,
  encrypted at rest), never on the device.
- **Delivery:** Garmin push or ping notifications to a Supabase Edge Function
  over HTTPS.
- **Storage:** Per-user rows in Postgres with row-level security. Each user can
  only read their own data.
- **Retention and deletion:** Data is deleted when a user disconnects Garmin or
  deletes their account. Garmin deregistration notifications are honoured.
- **Sharing:** Garmin data is never sold or shared with third parties. Summaries
  sent to the AI coach contain only the derived numbers needed to answer, with
  no identifiers.
- **Attribution:** Garmin data is labelled "Garmin" in the app, following
  Garmin's brand guidelines.

## Privacy policy (outline for your website)

1. What we collect: health and fitness data you connect (Apple Health,
   Garmin Connect), workouts you log, and food data from Apple Health.
2. Why: to compute strain, recovery and sleep scores, and to coach you.
3. Where it's stored: on your iPhone, and for Garmin data in our Supabase
   database (encrypted).
4. Who sees it: only you. We don't sell or share it. The AI coach gets
   anonymous summary numbers.
5. Your controls: disconnect Garmin or delete your account at any time.
   Data is deleted within [30] days.
6. Contact: [email].
