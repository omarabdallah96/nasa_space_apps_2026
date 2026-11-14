# Ember Almanac — mobile

Team **CedX** · NASA Space Apps Challenge 2026 · *Harmonization of MODIS and VIIRS Hot Spots*

The mobile companion to the Ember Almanac web app. It answers one question
for the places you care about: **"Is this fire season normal?"**

## Screens

| Tab | What it shows |
|---|---|
| **Today** | One-sentence answer, status, Fire Rings, season chart, evidence |
| **Calendar** | Year × month burning calendar + the 2012 seam toggle (raw vs harmonized) |
| **Map** | Hotspots from the last 48 h on NASA GIBS VIIRS imagery |
| **Watchlist** | Saved places and their current status (push alerts come next) |

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
- `ApiFireRepository` is a stub to implement when the backend is live,
  then set `useMockData = false` in `lib/main.dart`.
- Regenerate the mocks: `python tools/generate_mock.py`

## Layout

```
lib/
  data/models/         Region, FireRecord, Hotspot
  data/repositories/   FireRepository (interface), mock, api stub
  domain/anomaly.dart  ratio vs usual, rank, status, the one sentence
  state/               AppState (selected region, watchlist)
  theme/               Ember palette, Fraunces + IBM Plex
  ui/                  shell, screens, custom-painted widgets
```
