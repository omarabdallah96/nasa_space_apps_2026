# Firesight — mobile data contract

The mobile app reads three JSON documents. The mock files in `assets/mock/`
follow this contract exactly. When the backend (or the web app's Node
pipeline) produces the same shapes, the app switches over with one flag
(`useMockData` in `lib/config.dart`) and no other changes.

Static hosting works: these can be plain files on any CDN.

| Endpoint (suggested)            | Mock file                      |
|---------------------------------|--------------------------------|
| `GET /regions.json`             | `assets/mock/regions.json`     |
| `GET /record/{regionId}.json`   | `assets/mock/record_{id}.json` |
| `GET /hotspots/{regionId}.json` | `assets/mock/hotspots_{id}.json` |

---

## 1. `regions.json`

```json
{
  "regions": [
    {
      "id": "lebanon",
      "name": "Lebanon",
      "nameAr": "لبنان",
      "bbox": [35.10, 33.05, 36.62, 34.69],   // [west, south, east, north]
      "center": [33.85, 35.86]               // [lat, lon]
    }
  ]
}
```

## 2. `record/{regionId}.json` — the harmonized 25-year record

```json
{
  "regionId": "lebanon",
  "generatedAt": "2026-11-14T00:00:00Z",
  "units": "fire cell-days (~1 km cell, counted once per day), VIIRS-equivalent",
  "baseline": { "from": 2003, "to": 2024 },
  "latest":   { "year": 2026, "month": 10 },   // latest COMPLETE month
  "evidence": {
    "method": "Per-region VIIRS/MODIS ratio over overlap years, applied to MODIS-only years",
    "overlapYears": [2012, 2024],
    "ratio": 3.1,                       // VIIRS / MODIS
    "heldOutErrorRaw": 0.62,            // yearly error before fix (fraction)
    "heldOutErrorHarmonized": 0.14      // yearly error after fix (fraction)
  },
  "monthly": [
    { "year": 2011, "month": 9, "sensor": "MODIS", "raw": 57,  "harmonized": 177 },
    { "year": 2012, "month": 9, "sensor": "VIIRS", "raw": 184, "harmonized": 184 }
  ],
  "season": [
    { "month": 1, "p10": 3.2, "median": 7.0, "p90": 14.5 }
  ]
}
```

Rules:
- `monthly` is sorted by year, then month, with no gaps from the first year to `latest`.
- `raw` = the count from the sensor named in `sensor`. `harmonized` = the VIIRS-equivalent count.
  For VIIRS years, `raw == harmonized`.
- `season` has exactly 12 entries (months 1–12), computed over the `baseline` years from `harmonized`.
- The app computes the anomaly ratio, the rank and the one-sentence summary itself
  (`lib/domain/anomaly.dart`), so the backend doesn't need to.

## 3. `hotspots/{regionId}.json` — near-real-time detections

```json
{
  "regionId": "lebanon",
  "hours": 48,
  "hotspots": [
    {
      "lat": 33.91, "lon": 35.72,
      "acquiredAt": "2026-11-13T11:42:00Z",
      "sensor": "VIIRS_NOAA20",          // MODIS | VIIRS_SNPP | VIIRS_NOAA20 | VIIRS_NOAA21
      "confidence": "nominal",           // low | nominal | high
      "frp": 6.3                         // fire radiative power, MW
    }
  ]
}
```

Source: the NASA FIRMS area API. Call it from a small server function so the
FIRMS `MAP_KEY` never ships inside the app.

## 4. Fire danger forecast

The backend computes the Canadian Fire Weather Index (FWI) from Open-Meteo
weather and classes it with EFFIS limits: `very_low` < 5.2 ≤ `low` < 11.2 ≤
`moderate` < 21.3 ≤ `high` < 38 ≤ `very_high` < 50 ≤ `extreme`. Dates are the
local dates of the country, today first. `usual` comes from the harmonized
record: median active-fire cell-days per day on that date, as a share of the
busiest time of year.

`GET /forecast?lat=&lon=&days=7`: the grid point nearest a place (Today card,
burn planner, alerts near the user). 404 outside the four countries.

```json
{
  "country": { "slug": "lebanon", "name": "Lebanon" },
  "point": { "lat": 33.785, "lon": 35.525, "distanceKm": 11.9 },
  "generatedAt": "2026-11-15T09:40:45.720Z",
  "days": [
    {
      "date": "2026-11-15",
      "level": "low",
      "fwi": 8.6,
      "components": { "ffmc": 87.8, "dmc": 13.7, "dc": 440.6, "isi": 4.7, "bui": 25.3 },
      "weather": { "tempC": 23.1, "humidity": 54, "windKmh": 7.9, "rainMm": 0 },
      "usualInCountry": { "cellDaysPerDay": 0.4, "highCellDaysPerDay": 2.2, "shareOfPeak": 0.167, "inPeakSeason": false }
    }
  ]
}
```

`GET /countries/{regionId}/forecast?days=7`: the whole country (map layer,
alerts for watched places). A day's `level` is the class of the 90th
percentile point; `points` gives every grid point's FWI and level per day.

```json
{
  "country": { "slug": "lebanon", "name": "Lebanon" },
  "generatedAt": "2026-11-15T09:40:45.720Z",
  "grid": { "stepDegrees": 0.15, "points": 43 },
  "days": [
    {
      "date": "2026-11-15",
      "level": "high",
      "fwi": { "median": 11.8, "p90": 30.9, "max": 34.7 },
      "areaShare": { "highOrAbove": 0.209, "veryHighOrAbove": 0, "extreme": 0 },
      "usual": { "cellDaysPerDay": 0.4, "highCellDaysPerDay": 2.2, "shareOfPeak": 0.167, "inPeakSeason": false }
    }
  ],
  "points": [ { "lat": 33.125, "lon": 35.225, "fwi": [12.1], "level": ["moderate"] } ]
}
```

Demo mode (`USE_MOCK=true`) generates a forecast in the same shape, so the
week always starts today.

## 5. Accounts (optional)

Signing in is optional; every feature works as a guest. Demo mode has no
accounts. The token is an opaque bearer token, stored in the phone's secure
storage (Keychain / Android Keystore). A session lasts 180 days after it was
last used.

| Request | Body | Answer |
|---|---|---|
| `POST /auth/register` | `{email, password, name?}` | `201 {user, token}`; `409 email_taken`, `400 weak_password` (under 8 characters), `400 bad_email` |
| `POST /auth/login` | `{email, password}` | `{user, token}`; `401 wrong_credentials` |
| `GET /auth/me` | — | `{user}`; `401 signed_out` when the token expired |
| `PATCH /auth/me` | `{name}` | `{user}` |
| `POST /auth/logout` | — | `{signedIn: false}` |
| `DELETE /auth/me` | `{password}` | `{deleted: true}`; required by the app stores |

All but register and login send `Authorization: Bearer <token>`. Sign-in,
sign-up and deletion are limited to 20 attempts per client per 15 minutes
(`429 rate_limited`).

```json
{
  "user": { "id": "4f1c…", "email": "rana@example.com", "name": "Rana", "createdAt": "2026-11-15T10:00:00.000Z" },
  "token": "q9X…"
}
```

## Regenerating mocks

```
python tools/generate_mock.py
```
