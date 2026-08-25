# Privacy Policy

HolisticHealth for iOS · Last updated August 25, 2026

> **The short version:** HolisticHealth reads health data from Apple HealthKit to display it back to you. That data never leaves your device — there is no server, no analytics, no advertising, and no account. Nothing is collected, stored, or shared by us, because we never receive it in the first place.

This is the same policy the app itself links to.

## What the app accesses

With your permission (requested through Apple's standard HealthKit authorization screen, and revocable at any time in **Settings → Health → Data Access & Devices**), HolisticHealth reads the following from HealthKit, when present:

- Steps, distance (walking, running, cycling, swimming), active and resting energy, exercise and stand minutes
- Heart rate, resting heart rate, heart rate variability (HRV), heart rate recovery, walking heart rate average, VO₂ max
- Walking speed
- Workouts (type, duration, and associated heart rate/energy/distance data)
- Sleep analysis
- Lean body mass (used only to estimate resting energy expenditure)
- Date of birth (used only to estimate a max-heart-rate formula when no better data is available)

HolisticHealth **never writes to HealthKit**. It only reads data to display it — it does not create, modify, or delete any HealthKit record.

## Where your data goes

Nowhere but your device. HolisticHealth has no networking code, no analytics SDK, no crash reporter, and no third-party libraries of any kind. There is no backend server for this app — we could not see your data even if we wanted to.

A small amount of app-specific preference data — a manually entered max heart rate override, a choice of resting-energy formula, and your daily self-rated check-ins — is stored locally on your device using Apple's standard `UserDefaults` mechanism. Like any app data, this may be included in your device's own iCloud or iTunes backup, which is controlled entirely by your Apple ID and device settings, not by us.

## Sharing with third parties

We don't share, sell, rent, or otherwise disclose your health data or any other information to anyone, for any purpose — including advertising, marketing, or analytics — because the app never transmits it anywhere to begin with.

## Data retention and deletion

HealthKit data itself remains under Apple's control and your own; HolisticHealth simply reads it live each time the app is used and does not retain a separate copy. The small local preferences described above are deleted automatically when you delete the app. You can revoke HealthKit access at any time without deleting the app, via **Settings → Health → Data Access & Devices → HolisticHealth**.

## Children's privacy

HolisticHealth is not directed at children under 13 and does not knowingly collect any information from them — consistent with the rest of this policy, since the app does not collect information from anyone.

## Changes to this policy

If this policy ever changes, an updated version will be posted here with a new "last updated" date. Given the app's design — no networking, no accounts, no data collection — we don't expect that to happen often.

## Contact

Questions about this policy or the app can be sent to [zubenkovic@gmail.com](mailto:zubenkovic@gmail.com), or filed as an [issue on GitHub](https://github.com/zubenkovic/HolisticHealth/issues).
