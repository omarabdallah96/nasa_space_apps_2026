# Firesight — Progress

Team **CedX** · NASA Space Apps Challenge 2026 · *Harmonization of MODIS and VIIRS Hot Spots*
Last updated: 2026-11-15

Firesight answers one question for fire-prone Mediterranean countries (Portugal, Greece,
Lebanon, Cyprus): **"Is this fire season normal?"** It has two parts that share one backend:

| Part | Repo | Status |
|---|---|---|
| Web app + API backend | `D:\2027\my_server\CedX-Nasa` (GitHub `omarabdallah96/CedX-Nasa`) | Live at <https://cedx.coding-now.online> |
| Mobile app (Flutter, Android + iOS) | this repo | Built, runs against the live API; no test builds published yet |

---

## Web app + backend (CedX-Nasa)

Stack: React + Vite + MapLibre + GSAP on the front end, Hono + SQLite on the server,
TypeScript pipeline on Node 24. Deployed with Dokploy from `main` (Docker), with a storage
volume for reports and photos.

### Timeline

| Date | Commit | What was done |
|---|---|---|
| 2026-11-13 | `4797c5d` | First version ("Ember Almanac"): harmonized MODIS + VIIRS record, globe intro, verdict, Fire Rings, burning calendar, exports |
| 2026-11-13 | `24f5fbe` | Home page rebuilt as a scroll story where the rings grow; area inputs fixed |
| 2026-11-14 | `2361b65` | Record extended to yesterday; read-only JSON API; date ranges; last-7-days card; records; more downloads |
| 2026-11-14 | `e460ded` | Renamed to **Firesight**; full Arabic version with right-to-left layout |
| 2026-11-14 | `ae0138f` | Live FIRMS near-real-time hotspots, shared ground reports, rate limiting (for the phone app) |
| 2026-11-14 | `1f1adb6` | `/admin` moderation page with password sign-in |

### Done

- **Data pipeline**: FIRMS yearly archive + area API, clipped to Natural Earth borders, packed
  for the browser. Server refreshes the newest days every 6 hours (needs `FIRMS_MAP_KEY`, set in prod).
- **Harmonization**: 0.01° cell-days, per-month VIIRS/MODIS factors fitted per country,
  Terra-only factor before July 2002, outage filling, NOAA-20 handover after Suomi-NPP stopped
  (2 Nov 2026), leave-one-year-out validation (e.g. Greece yearly error 61% → 6%).
- **Website**: one-sentence verdict, last 7 days, any date range, Fire Rings, burning calendar,
  raw vs harmonized "2012 seam" toggle, season profile, evidence panel, CSV/PNG exports,
  English + Arabic.
- **API** (`/api/v1`): countries, now, verdict, calendar, season, range, records, hotspots
  (JSON/CSV), method, live hotspots (1–72 h, cached 10 min), data files.
- **Ground reports**: `POST/GET/DELETE /reports` with photo upload (JPEG/PNG/WebP ≤ 5 MB),
  idempotent retries, per-report delete token, 90-day retention.
- **Abuse protection**: per-client rate limits (1200 req / 10 min, 30 reports / hour).
- **Moderation**: `/admin` — hide a report, hide all reports from a phone, delete; HttpOnly
  session cookie, 10 password tries / 15 min.
- **Tests**: 61 backend tests (harmonization, API, phone endpoints, admin, i18n), passing as of 2026-11-14.

---

## Mobile app (this repo)

Stack: Flutter. Talks only to `FireRepository`; the default build uses the live API
(`https://cedx.coding-now.online/api/v1`), `--dart-define=USE_MOCK=true` uses bundled demo data.

### Timeline (all 2026-11-14)

| Commit | What was done |
|---|---|
| `7630447` | App scaffolded with mock data and core screens |
| `3b1f4cb` | Alerts system, local notifications, emergency services UI |
| `7e1df79`, `da7dab1` | App structure, branding, screens, services |
| `c592cf6` | Smoke triangulation + app smoke tests |
| `f26cac5` | Alerts screen, home screen, settings, navigation shell |
| `094731f` | `ApiFireRepository` + config for backend data |
| `210a5ed` | Field reports shared through the backend; live FIRMS hotspots on the map |
| `28da80c` | Renamed to **Firesight** (app name, manifests, strings) |
| `965a5ef` | UX pass on every screen, theme and localization updates, UX flow tests |

### Done

- **Four tabs**: Today (near me, verdict sentence, share card, Fire Rings, season chart,
  fire weather, evidence), Calendar (year × month + 2012 seam toggle), Map (48 h hotspots on
  NASA GIBS, my location, field reports), Alerts (alerts, watched places, emergency).
- **Near me**: region by GPS, distance and direction to the nearest hotspot.
- **Alerts**: above-normal activity, "critical period starts in N days", hotspots nearby;
  local notifications without repeats; Android background check every 3 hours (WorkManager).
- **Field verification**: photo + GPS + label, linked to the nearest satellite hotspot, shared
  with other phones through the backend.
- **Smoke triangulation**: compass bearing on smoke reports; two or more reports crossed on the
  map to estimate the fire location with an uncertainty circle.
- **Fire weather + 7-day burn planner**: Open-Meteo wind/humidity combined with the critical
  period → safe / caution / do not burn, and the best burn day this week.
- **Share card**: PNG of the sentence + Fire Rings for WhatsApp etc.
- **Emergency**: one tap to call Civil Defence (125) or SMS your location.
- **Offline**: every API response and map tile cached on disk.
- **Arabic + RTL**, Levantine month names.
- **Brand**: logo drawn in code, app icons, native + animated splash, 4-page onboarding.
- **Tests**: 39 app tests (smoke, features, report sync, UX flows), passing as of 2026-11-14.

---

## Next

- [ ] Publish test builds (Android APK / TestFlight).
- [ ] Finish the app rebrand (listed as the next step in the 2026-11-14 progress report).
- [ ] Update the mobile `README.md`: its "Data: mock now, backend later" section is out of date
      — the app now uses the live API by default.
- [ ] Re-run both test suites before submission.
- [ ] Demo script / video and the Space Apps submission page.
