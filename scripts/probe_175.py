#!/usr/bin/env python3
"""Global probe: for each app, query all 175 storefronts via two free public sources.

1) iTunes Lookup API       https://itunes.apple.com/lookup?id=<id>&country=<cc>          (app price + availability)
2) apps.apple.com catalog  https://apps.apple.com/api/apps/v1/catalog/<cc>/apps/<id>?platform=web&views=top-in-app-purchasables
                                                                                        (IAP products with local prices)

Outputs a JSON snapshot per app + a console summary. This is the reference
implementation of the iOS app's data engine (same logic, runs without a Mac).
"""
import json
import os
import time
import urllib.request
import urllib.error
import concurrent.futures as cf
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
DB = os.path.join(ROOT, "data", "storefronts.json")
OUTDIR = os.path.join(ROOT, "data") + os.sep
SFS = json.load(open(DB, encoding="utf-8"))
APPS = {"ChatGPT": 6448311069, "Spotify": 324684580, "Notion": 868278324, "WeChat": 414478124}


def get(url, headers=None, timeout=15, retries=2):
    h = {"User-Agent": UA, "Accept": "application/json"}
    if headers:
        h.update(headers)
    last = None
    for attempt in range(retries + 1):
        req = urllib.request.Request(url, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, json.loads(r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            try:
                body = e.read().decode("utf-8", "replace")[:160]
            except Exception:
                body = ""
            return e.code, {"error": body}
        except Exception as e:
            last = e
            time.sleep(1.5 * (attempt + 1))
    return 0, {"error": str(last)}


def parse_iap(pid, a):
    o = (a.get("offers") or [{}])[0]
    return {
        "id": pid,
        "name": a.get("name"),
        "offerName": a.get("offerName"),
        "family": a.get("subscriptionFamilyName"),
        "familyRank": a.get("subscriptionFamilyRank"),
        "isSubscription": a.get("isSubscription", False),
        "period": o.get("recurringSubscriptionPeriod"),
        "price": o.get("price"),
        "currency": o.get("currencyCode"),
        "formatted": o.get("priceFormatted"),
    }


def probe(sf, appid):
    cc = sf["storefront"]
    out = {"storefront": cc}
    st, d = get(f"https://itunes.apple.com/lookup?id={appid}&country={cc}&entity=software")
    out["lookup_http"] = st
    if st == 200 and d.get("resultCount"):
        r = d["results"][0]
        out["app"] = {"name": r.get("trackName"), "seller": r.get("sellerName"),
                      "price": r.get("price"), "currency": r.get("currency"),
                      "formatted": r.get("formattedPrice")}
    st2, d2 = get(
        f"https://apps.apple.com/api/apps/v1/catalog/{cc}/apps/{appid}"
        f"?platform=web&views=top-in-app-purchasables&l=en-us",
        headers={"Authorization": "Bearer",
                 "Referer": f"https://apps.apple.com/{cc}/app/id{appid}"})
    out["iap_http"] = st2
    if st2 == 200 and isinstance(d2, dict) and d2.get("data"):
        try:
            iaps = d2["data"][0].get("views", {}).get("top-in-app-purchasables", {}).get("data", [])
            out["iaps"] = [parse_iap(x.get("id"), x.get("attributes", {})) for x in iaps]
        except Exception as e:
            out["iaps"] = []
            out["parse_error"] = str(e)
    return out


def status_of(r):
    if r.get("iaps"):
        return "ok_with_iap"
    if r.get("app"):
        return "app_available_no_iap"
    if r.get("lookup_http") == 200:
        return "lookup_empty"
    return "unavailable"


def main():
    for appname, appid in APPS.items():
        t0 = time.time()
        with cf.ThreadPoolExecutor(max_workers=5) as ex:
            results = list(ex.map(lambda sf: probe(sf, appid), SFS))
        cnt = Counter(status_of(r) for r in results)
        withiap = [r for r in results if r.get("iaps")]
        sku = {}
        for r in withiap:
            for i in r["iaps"]:
                sku.setdefault(i["id"], []).append((r["storefront"], i["formatted"]))
        top = max((len(v) for v in sku.values()), default=0)
        print(f"\n== {appname} (id {appid}) — {time.time() - t0:.0f}s")
        print(f"   status: {dict(cnt)}")
        print(f"   distinct SKUs: {len(sku)} | best SKU coverage: {top} storefronts")
        for pid, lst in sorted(sku.items(), key=lambda kv: -len(kv[1]))[:3]:
            print(f"   sku {pid}: {len(lst)} sfs | {lst[:4]}")
        json.dump({"app": appname, "appId": appid,
                   "probedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                   "statusCounts": dict(cnt), "results": results},
                  open(OUTDIR + f"probe_{appid}.json", "w", encoding="utf-8"),
                  ensure_ascii=False)
    print("\ndone")


if __name__ == "__main__":
    main()