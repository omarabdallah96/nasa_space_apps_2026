"""Generate mock data for the Fire Site mobile app.

Output files follow docs/api_contract.md exactly, so the real backend can
replace them without app changes. The numbers are synthetic but shaped like
the real record: seasonal peaks per country, known extreme years, and a
MODIS -> VIIRS jump at 2012 in the raw series.

Run:  python tools/generate_mock.py
"""

import json
import math
import random
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "mock"
FIRST_YEAR, LAST_YEAR, LAST_MONTH = 2000, 2026, 10  # latest complete month
VIIRS_START = 2012
BASELINE = (2003, 2024)

REGIONS = [
    {
        "id": "lebanon", "name": "Lebanon", "nameAr": "لبنان",
        "bbox": [35.10, 33.05, 36.62, 34.69], "center": [33.85, 35.86],
        "scale": 140, "peak": 9.3, "width": 1.6, "spring": 0.25, "ratio": 3.1,
        "extremes": {(2019, 10): 7.0, (2021, 7): 2.4, (2007, 10): 2.2, (2026, 10): 2.6},
    },
    {
        "id": "portugal", "name": "Portugal", "nameAr": "البرتغال",
        "bbox": [-9.52, 36.96, -6.19, 42.15], "center": [39.6, -8.0],
        "scale": 2400, "peak": 8.0, "width": 1.2, "spring": 0.35, "ratio": 2.6,
        "extremes": {(2003, 8): 3.2, (2005, 8): 2.6, (2017, 6): 3.0, (2017, 10): 6.0, (2025, 8): 2.8},
    },
    {
        "id": "greece", "name": "Greece", "nameAr": "اليونان",
        "bbox": [19.37, 34.80, 29.65, 41.75], "center": [38.6, 22.9],
        "scale": 1100, "peak": 7.8, "width": 1.3, "spring": 0.45, "ratio": 2.8,
        "extremes": {(2007, 8): 4.5, (2021, 8): 4.0, (2023, 7): 3.0, (2023, 8): 3.5},
    },
    {
        "id": "cyprus", "name": "Cyprus", "nameAr": "قبرص",
        "bbox": [32.27, 34.56, 34.60, 35.70], "center": [35.05, 33.3],
        "scale": 60, "peak": 7.3, "width": 1.4, "spring": 0.3, "ratio": 3.4,
        "extremes": {(2021, 7): 4.0, (2016, 6): 2.5, (2007, 8): 2.0},
    },
]


def seasonal(month, r):
    """Fire season shape: summer/autumn peak plus a small spring agri-burn bump."""
    main = math.exp(-((month - r["peak"]) ** 2) / (2 * r["width"] ** 2))
    spring = r["spring"] * math.exp(-((month - 3.5) ** 2) / 1.5)
    return 0.04 + main + spring


def percentile(values, p):
    s = sorted(values)
    k = (len(s) - 1) * p
    lo, hi = math.floor(k), math.ceil(k)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def build_record(r, rng):
    monthly = []
    for year in range(FIRST_YEAR, LAST_YEAR + 1):
        year_factor = rng.lognormvariate(0, 0.25)
        for month in range(1, 13):
            if year == LAST_YEAR and month > LAST_MONTH:
                break
            value = r["scale"] * seasonal(month, r) * year_factor * rng.lognormvariate(0, 0.3)
            value *= r["extremes"].get((year, month), 1.0)
            harmonized = round(value)
            sensor = "VIIRS" if year >= VIIRS_START else "MODIS"
            raw = harmonized if sensor == "VIIRS" else round(harmonized / r["ratio"])
            monthly.append({
                "year": year, "month": month, "sensor": sensor,
                "raw": raw, "harmonized": harmonized,
            })

    season = []
    for month in range(1, 13):
        vals = [m["harmonized"] for m in monthly
                if m["month"] == month and BASELINE[0] <= m["year"] <= BASELINE[1]]
        season.append({
            "month": month,
            "p10": round(percentile(vals, 0.10), 1),
            "median": round(percentile(vals, 0.50), 1),
            "p90": round(percentile(vals, 0.90), 1),
        })

    return {
        "regionId": r["id"],
        "generatedAt": "2026-11-14T00:00:00Z",
        "units": "fire cell-days (~1 km cell, counted once per day), VIIRS-equivalent",
        "baseline": {"from": BASELINE[0], "to": BASELINE[1]},
        "latest": {"year": LAST_YEAR, "month": LAST_MONTH},
        "evidence": {
            "method": "Per-region VIIRS/MODIS ratio over overlap years, applied to MODIS-only years",
            "overlapYears": [VIIRS_START, 2024],
            "ratio": r["ratio"],
            "heldOutErrorRaw": round(rng.uniform(0.34, 0.84), 2),
            "heldOutErrorHarmonized": round(rng.uniform(0.05, 0.27), 2),
        },
        "monthly": monthly,
        "season": season,
    }


def build_hotspots(r, rng, n=40):
    w, s, e, nb = r["bbox"]
    clat, clon = r["center"]
    spots = []
    for i in range(n):
        lat = min(max(rng.gauss(clat, (nb - s) / 5), s), nb)
        lon = min(max(rng.gauss(clon, (e - w) / 5), w), e)
        spots.append({
            "lat": round(lat, 4), "lon": round(lon, 4),
            "acquiredAt": f"2026-11-{13 + (i % 2):02d}T{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:00Z",
            "sensor": rng.choice(["VIIRS_SNPP", "VIIRS_NOAA20", "VIIRS_NOAA21", "MODIS"]),
            "confidence": rng.choice(["nominal", "high", "nominal", "low"]),
            "frp": round(rng.lognormvariate(1.8, 0.9), 1),
        })
    return {"regionId": r["id"], "hours": 48, "hotspots": spots}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(2026)
    index = [{k: r[k] for k in ("id", "name", "nameAr", "bbox", "center")} for r in REGIONS]
    (OUT / "regions.json").write_text(json.dumps({"regions": index}, ensure_ascii=False, indent=2), encoding="utf-8")
    for r in REGIONS:
        (OUT / f"record_{r['id']}.json").write_text(json.dumps(build_record(r, rng)), encoding="utf-8")
        (OUT / f"hotspots_{r['id']}.json").write_text(json.dumps(build_hotspots(r, rng)), encoding="utf-8")
    print(f"Wrote mock data for {len(REGIONS)} regions to {OUT}")


if __name__ == "__main__":
    main()
