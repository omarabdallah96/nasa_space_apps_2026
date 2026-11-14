# Ember Almanac — mobile data contract

The mobile app reads three JSON documents. The mock files in `assets/mock/`
follow this contract exactly. When the backend (or the web app's Node
pipeline) produces the same shapes, the app switches over with one flag
(`useMockData` in `lib/main.dart`) and no other changes.

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

## Regenerating mocks

```
python tools/generate_mock.py
```
