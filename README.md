# Ember Almanac — mobile

<img src="assets/brand/logo.png" width="120" alt="Ember Almanac logo">

Team **CedX** · NASA Space Apps Challenge 2026 · *Harmonization of MODIS and VIIRS Hot Spots*

The mobile companion to the Ember Almanac web app. It answers one question
for the places you care about: **"Is this fire season normal?"**

## Screens

| Tab | What it shows |
|---|---|
| **Today** | Near me (GPS), the one-sentence answer, share card, Fire Rings, season chart, fire weather + burn advice, evidence |
| **Calendar** | Year × month burning calendar + the 2012 seam toggle (raw vs harmonized) |
| **Map** | Hotspots from the last 48 h on NASA GIBS imagery, my location, field reports |
| **Alerts** | Early-warning alerts, watched places, emergency call / SMS to Civil Defence (125) |

## Mobile-only features (not in the web app)

- **Near me** — finds your region by GPS, plus distance and direction to the nearest hotspot.
- **Alerts** — above-normal activity, *critical period starts in N days* (from the harmonized
  calendar), and hotspots near you. Sent as local notifications for now, and checked on launch
  without repeating alerts you've already seen.
- **Field verification** — photo + GPS + label (wildfire / agricultural burn / industrial /
  false alarm), linked to the satellite hotspot. This builds ground truth.
- **Share card** — a PNG of the sentence + Fire Rings, shared to WhatsApp or anywhere else.
- **Fire weather + burn advice** — Open-Meteo wind and humidity, the critical period and the
  current anomaly combined into *safe / caution / do not burn*.
- **Arabic + RTL** — full right-to-left layout, with Levantine month names (تشرين الأول…).
- **Offline** — `ApiFireRepository` caches every response on disk and falls back to it when
  there is no signal. Map tiles are cached too.
- **Emergency** — one tap to call 125, or SMS your location.

## Brand: logo, splash, onboarding

- The logo is drawn in code, in `lib/ui/brand/ember_logo.dart`: Fire Rings (one ring per year,
  glowing in fire season) around a flame. Every icon is rendered from it:
  ```
  flutter test tool/brand/render_brand_test.dart   # writes assets/brand/*.png
  dart run flutter_launcher_icons                  # app icons
  dart run flutter_native_splash:create            # native splash
  ```
- Launch order: native splash → animated splash (the rings draw in) → 4-page intro on first
  launch (language and permissions on the last page) → app. Replay the intro with the
  **?** button on the Today tab.

## Run

```
flutter pub get
flutter run
```

## Data: mock now, backend later

The app runs on **mock data** in `assets/mock/`, which follows the exact JSON
contract in [`docs/api_contract.md`](docs/api_contract.md).

- Screens only talk to `FireRepository` (`lib/data/repositories/`).
- `MockFireRepository` reads the bundled JSON.
- `ApiFireRepository` is ready: set `apiBaseUrl` and `useMockData = false` in `lib/config.dart`.
- Regenerate the mocks: `python tools/generate_mock.py`

## Layout

```
lib/
  data/models/         Region, FireRecord, Hotspot
  data/repositories/   FireRepository (interface), mock, api (+ offline cache)
  domain/anomaly.dart  ratio vs usual, rank, status, the one sentence
  services/            location, alert engine, notifications, weather, reports
  l10n/strings.dart    English + Arabic
  state/               AppState (region, watchlist, alerts, reports, language)
  theme/               Ember palette, Fraunces + IBM Plex
  ui/                  shell, screens, custom-painted widgets
```
