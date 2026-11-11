# Oura Ring: direct link and sleep source (2026-11)

## What Oura shares where

- **Apple Health (Oura app › Settings › Data Sharing › Apple Health):** sleep (times, stages, breathing rate), 1-minute heart rate, steps, energy, workouts, mindful minutes, height and weight. Third-party guides agree that HRV, skin temperature, SpO2 and Oura's scores are *not* written to Apple Health on iPhone (they are on Android's Health Connect). Oura's own current list couldn't be checked from the build sandbox, so treat this as likely, not certain.
- **Oura API v2 (the direct link):** sleep periods with a 5-minute hypnogram, average overnight HRV (RMSSD), lowest and average heart rate, readiness score and contributors, temperature deviation, daily sleep score. OAuth 2 only: Oura stopped issuing personal access tokens in December 2025. Refresh tokens are single use. API access on current rings needs an Oura membership.

Sources: Oura blog, *Data sharing and partner integrations*; Oura blog, *Connect Oura & Apple Health*; Sonar Health and UltraFit360 sync guides (2025-26); `hedgertronic/oura-ring` README (OAuth notes only, no code used).

## Sleep: which device first

The setting `SleepSourcePreference` (default: Oura ring first) takes one device's whole night instead of merging two, so the stages come from one scorer.

Evidence for the ring as the default: Robbins et al., *Sensors* 2024;24(20):6532. 35 healthy adults, one lab night against polysomnography. Oura Gen3, Apple Watch Series 8 and Fitbit Sense 2 all detected sleep vs wake well (≥95% sensitivity) and got total sleep about right. Oura's stage sensitivity was the most consistent (about 76-80%) versus Apple Watch (about 50-86%), and Apple Watch under-counted deep sleep and over-counted light sleep. Limits: small sample, one night, older models, and the lead author advises Oura (declared). So the evidence is modest; the setting is mainly the user's choice.

## HRV

Oura's `average_hrv` is RMSSD averaged over the sleep. With the ring first it fills the app's overnight RMSSD series (typed values still win), which keeps recovery's HRV on nights the watch isn't worn. It is never mixed with Apple's SDNN (Shaffer & Ginsberg, *Front Public Health* 2017: the two measures aren't interchangeable). Oura's whole-night average and the watch's minute-long recordings can differ a little; nights switch source only where Oura has no value.

## Not used for scoring

Oura's readiness and sleep scores and temperature deviation are shown on the Health tab as Oura reports them. Tensile's recovery and sleep scores keep their own published methods.
