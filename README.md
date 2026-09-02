# Moa

A SwiftUI + HealthKit dashboard that turns the data your iPhone and Apple Watch already collect into a small set of honest, research-grounded numbers — no scores that hide what's actually going on, no manual logging, no accounts.

## Documentation

- [Privacy Policy](PRIVACY.md) — what the app reads, and confirmation that none of it ever leaves your device
- [License](LICENSE.md) — MIT

## Why

Most health apps either flatten everything into a single opaque "score," or bury you in raw charts with no context. Moa tries to sit in between: every number is shown next to what it actually means — its own target, its own recent range, or the research behind it — and nothing is averaged or capped away just to make the headline number look tidier.

A few examples of that philosophy showing up in the code:

- **Activity Index** shows steps, cardio minutes, strength minutes, and sleep duration as four independent numbers against their own targets — not blended into one percentage that hides whether you're 200 steps short or 6,000 steps short.
- **Heart rate zones** are computed with the Karvonen method (using your resting heart rate, not just max HR) and shown for today, this week, and this month, with an in-app explanation of how that differs from Apple's own Fitness app calculation.
- **Sleep Regularity Index** (Phillips et al., 2017) is kept on its native −100…+100 scale instead of being remapped into a 0–100 "score," since remapping a validated published metric would misrepresent what the number actually is.
- **Recovery** is deliberately descriptive only — HRV and resting heart rate trends, no injury-risk score or training go/no-go verdict, because the research behind training-load ratios is genuinely contested and that call should stay yours.
- **VILPA detection** (vigorous intermittent lifestyle physical activity — Stamatakis et al.) surfaces the vigorous effort that happens *outside* logged workouts: a sprint for the train, a fast flight of stairs.

Every metric that cites research does so in an in-app tooltip, not just this README.

## Features

- **Movement** — steps, distance (walking/running, cycling, and swimming, summed), cardio and strength minutes against weekly targets, active calories, and VILPA bursts
- **Rest** — sleep duration, Sleep Regularity Index, bedtime/wake consistency
- **Heart & Vitals** — resting heart rate, HRV, VO₂ max with a trend chart, walking heart rate, heart rate recovery, walking speed, and heart rate zones (today/week/month)
- **Resting energy** — Apple's estimate alongside a Katch-McArdle estimate from your lean body mass, when available
- **Recovery** — HRV and resting-heart-rate trend lines, shown as information, not a verdict
- **Activity Index** — the four-number weekly/monthly summary described above
- A daily self-rated "how's your health today?" check-in, tracked alongside the automatic data
- Every section gracefully degrades based on what data is actually available — phone-only, Watch-only, or nothing yet — rather than assuming a wearable is present

## Privacy

Moa reads HealthKit data and nothing else. There is no networking code in the app, no analytics or crash-reporting SDK, no third-party dependencies, and no accounts. Everything is computed and stored on-device (a couple of small preferences live in `UserDefaults` — a manual max-heart-rate override, a resting-energy formula preference, and your daily check-ins). Nothing you do in this app is ever transmitted anywhere.

Full policy: **[PRIVACY.md](PRIVACY.md)** — this is also what the app itself links to.

## Requirements

- Xcode 26 or later
- iOS 26.5+ (see `IPHONEOS_DEPLOYMENT_TARGET` in the project settings — lower it if you need to target older devices; nothing in the code depends on anything that recent)
- An Apple ID signed into Xcode to run on a device (HealthKit doesn't work in the Simulator with real data, though the app builds and runs there)
- An Apple Watch is not required — the app adapts to whatever data is actually present, but continuous metrics (HRV, heart rate zones, VO₂ max, recovery) need one

## Getting started

```bash
git clone https://github.com/zubenkovic/Moa.git
cd Moa
open Moa.xcodeproj
```

Select the `Moa` scheme, pick your device, and run. On first launch the app asks for HealthKit read permission for the data types listed above.

## Running tests

```bash
xcodebuild -project Moa.xcodeproj -scheme MoaTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Tests cover the pure-logic engines (Activity Index, Sleep Regularity Index) — anything with zero HealthKit imports, by design, so the math is easy to verify independent of how the data was fetched.

## Architecture

- **SwiftUI** throughout, no UIKit except for a couple of font-measurement calls
- **HealthKitManager** is the single point of contact with HealthKit — a small set of generic fetchers (today's total, today's average, a daily history, workouts, sleep) rather than one bespoke query per metric
- Each home-screen section (`MovementSection`, `RestSection`, `HeartSection`, …) owns its own state and fetch cycle independently; `SectionLoadCoordinator` just tracks when all of them have reported in for the first paint
- Computation lives in standalone `*Engine` types with no HealthKit imports, kept unit-testable in isolation from data fetching

## Contributing

Issues and pull requests are welcome. If you're proposing a change to how a metric is computed, a comment linking the research it's based on (or explaining why the existing approach is wrong) makes review much faster.

## Support

If Moa is useful to you, you can support its development via [GitHub Sponsors](https://github.com/sponsors/zubenkovic).

## License

MIT — see [LICENSE.md](LICENSE.md).

This app is not a medical device and does not provide medical advice. It's a way to look at data you already have; talk to a clinician about what it means for you.
