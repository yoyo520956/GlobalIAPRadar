#!/usr/bin/env python3
"""Build the Apple storefront DB from the PPP repo's official 175-country list.

Sources:
- appstore-ppp-pricing-agent-skill/appstore_ppp_prices/countries.csv (MIT, 175 App Store countries, alpha-3)
- mledoze/countries (CC0 dataset): alpha-3 -> alpha-2, English/Chinese names, ISO currency codes
Currency shown here is a *starting hint* only; the app overwrites it with the
empirical currency returned by the iTunes lookup API per storefront.
"""
import csv
import json
import os
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "data", "countries.csv")
OUT = os.path.join(ROOT, "data", "storefronts.json")
DATASET = "https://cdn.jsdelivr.net/gh/mledoze/countries@master/countries.json"

req = urllib.request.Request(DATASET, headers={"User-Agent": "Mozilla/5.0"})
data = json.loads(urllib.request.urlopen(req, timeout=60).read())

by_cca3 = {}
zh = {}
for c in data:
    a3 = (c.get("cca3") or "").upper()
    if a3:
        by_cca3[a3] = c
        t = (c.get("translations") or {}).get("zho") or {}
        zh[a3] = t.get("common") or (c.get("name") or {}).get("common")

rows = list(csv.DictReader(open(CSV, encoding="utf-8")))
print("csv data rows:", len(rows))
print("codes:", " ".join(r["country_code"] for r in rows[:20]), "...")

out, missing, dup = [], [], set()
seen = set()
for r in rows:
    a3 = r["country_code"].strip().upper()
    c = by_cca3.get(a3)
    if not c or not (c.get("cca2") or "").strip():
        missing.append(a3)
        continue
    sf = c["cca2"].lower()
    if sf in seen:
        dup.append(sf)
    seen.add(sf)
    cur = ",".join((c.get("currencies") or {}).keys())
    out.append({
        "storefront": sf,
        "alpha3": a3,
        "nameEn": (c.get("name") or {}).get("common") or a3,
        "nameZh": zh.get(a3) or (c.get("name") or {}).get("common") or a3,
        "currency": None,  # filled empirically from iTunes lookup per storefront
        "isoCurrency": cur or None,
        "pppCategory": r.get("category"),
    })

# Apple storefronts missing from the ISO dataset — Apple uses its own codes
MANUAL = [{"storefront": "xk", "alpha3": "XKS", "nameEn": "Kosovo", "nameZh": "科索沃",
           "currency": "EUR", "isoCurrency": "EUR", "pppCategory": "unknown",
           "note": "Apple storefront code, not ISO 3166"}]
out = sorted(out + [m for m in MANUAL if m["storefront"] not in {x["storefront"] for x in out}],
             key=lambda x: x["storefront"])
json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("mapped:", len(out), "| unmapped:", missing, "| dup storefronts:", dup)
print("zh sample:", [(x["storefront"], x["nameEn"], x["nameZh"]) for x in out[:6]])