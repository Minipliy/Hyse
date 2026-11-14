#!/usr/bin/env python3
"""Import the most popular valid German Open Food Facts products into PocketBase.

The full CSV export is streamed and never stored on disk. Candidates are kept in
a bounded heap, existing barcodes are skipped, and the import stops before the
configured PocketBase storage ceiling is reached. Authentication is supplied
through environment variables so credentials never appear in process arguments.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import heapq
import io
import json
import math
import os
import re
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


EXPORT_URL = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
USER_AGENT = "Hyse/1.0 (hyse@minipliy.net)"
GERMAN_POPULARITY = re.compile(r"(?:^|:)top-(?:\d+|country)-de-scans-\d{4}$")
PRINT_LOCK = threading.Lock()


def log(message: str) -> None:
    with PRINT_LOCK:
        print(message, flush=True)


def finite_number(value: object, default: float | None = None) -> float | None:
    if isinstance(value, bool):
        return default
    try:
        number = float(str(value).replace(",", "."))
    except (TypeError, ValueError):
        return default
    return number if math.isfinite(number) else default


def clean_text(value: object, maximum: int) -> str:
    return " ".join(str(value or "").split())[:maximum]


def gtin_is_valid(code: str) -> bool:
    if len(code) not in (8, 12, 13, 14) or not code.isdigit():
        return False
    total = sum(int(digit) * (3 if index % 2 == 0 else 1)
                for index, digit in enumerate(reversed(code[:-1])))
    return (10 - total % 10) % 10 == int(code[-1])


def nutrient(row: dict[str, str], key: str, default: float | None = None) -> float | None:
    return finite_number(row.get(f"{key}_100g"), default)


def is_german_product(row: dict[str, str]) -> bool:
    countries = {part.strip().lower() for part in str(row.get("countries_tags") or "").split(",")}
    if "en:germany" in countries or "de:deutschland" in countries:
        return True
    return any(GERMAN_POPULARITY.search(part.strip().lower())
               for part in str(row.get("popularity_tags") or "").split(","))


def normalize_product(row: dict[str, str]) -> dict[str, object] | None:
    code = "".join(character for character in str(row.get("code") or "") if character.isdigit())
    if not gtin_is_valid(code):
        return None

    name_de = clean_text(row.get("product_name_de") or row.get("product_name"), 500)
    source_name = clean_text(row.get("product_name") or name_de, 500)
    if not name_de:
        return None

    calories = nutrient(row, "energy-kcal")
    if calories is None:
        energy_kj = nutrient(row, "energy-kj")
        calories = None if energy_kj is None else energy_kj / 4.184
    core = {
        "calories": calories,
        "carbs": nutrient(row, "carbohydrates"),
        "protein": nutrient(row, "proteins"),
        "fat": nutrient(row, "fat"),
    }
    if any(value is None for value in core.values()):
        return None
    assert all(value is not None for value in core.values())
    if not 0 <= float(core["calories"]) <= 900:
        return None
    if any(not 0 <= float(core[key]) <= 100 for key in ("carbs", "protein", "fat")):
        return None
    estimated = 4 * (float(core["carbs"]) + float(core["protein"])) + 9 * float(core["fat"])
    if float(core["calories"]) > 0 and estimated > 0:
        tolerance = max(120, 0.5 * max(float(core["calories"]), estimated))
        if abs(float(core["calories"]) - estimated) > tolerance:
            return None

    serving_text = clean_text(row.get("serving_size"), 80).lower()
    categories = str(row.get("categories_tags") or "").lower()
    unit = "ml" if any(marker in f" {serving_text}" for marker in (" ml", " cl", " l")) or "en:beverages" in categories else "g"
    serving = finite_number(row.get("serving_quantity"), 100) or 100
    if serving <= 0 or serving > 1_000:
        serving = 100

    optional: dict[str, float] = {}
    for output, source in (("sugar", "sugars"), ("fiber", "fiber"),
                           ("saturated_fat", "saturated-fat"), ("salt", "salt")):
        value = nutrient(row, source, 0) or 0
        optional[output] = round(value, 3) if 0 <= value <= 100 else 0

    scans = max(0, int(finite_number(row.get("unique_scans_n"), 0) or 0))
    popularity = max(0, int(finite_number(row.get("popularity_key"), 0) or 0))
    return {
        "source_id": code,
        "source_name_en": source_name,
        "name_de": name_de,
        "brand": clean_text(row.get("brands"), 160),
        "barcode": code,
        "unit": unit,
        "serving_size": round(serving, 3),
        **{key: round(float(value), 3) for key, value in core.items()},
        **optional,
        "unique_scans": scans,
        "popularity": popularity,
    }


def tls_context() -> ssl.SSLContext:
    context = ssl.create_default_context()
    return context


def collect_candidates(url: str, target: int) -> list[dict[str, object]]:
    heap: list[tuple[int, int, str, dict[str, object]]] = []
    seen_barcodes: set[str] = set()
    csv.field_size_limit(16 * 1024 * 1024)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    started = time.monotonic()
    with urllib.request.urlopen(request, timeout=300, context=tls_context()) as response:
        compressed = gzip.GzipFile(fileobj=response)
        text = io.TextIOWrapper(compressed, encoding="utf-8", errors="replace", newline="")
        for row_number, row in enumerate(csv.DictReader(text, delimiter="\t"), start=1):
            if not is_german_product(row):
                if row_number % 250_000 == 0:
                    log(f"SCAN rows={row_number} candidates={len(heap)} elapsed={int(time.monotonic() - started)}s")
                continue
            product = normalize_product(row)
            if product is not None:
                barcode = str(product["barcode"])
                if barcode not in seen_barcodes:
                    seen_barcodes.add(barcode)
                    key = (int(product["unique_scans"]), int(product["popularity"]), barcode, product)
                    if len(heap) < target:
                        heapq.heappush(heap, key)
                    elif key[:3] > heap[0][:3]:
                        removed = heapq.heapreplace(heap, key)
                        seen_barcodes.discard(removed[2])
            if row_number % 250_000 == 0:
                log(f"SCAN rows={row_number} candidates={len(heap)} elapsed={int(time.monotonic() - started)}s")
    selected = [item[3] for item in sorted(heap, reverse=True)]
    log(f"SELECTED count={len(selected)} requested={target}")
    return selected


def request_json(method: str, url: str, body: dict[str, object] | None = None,
                 token: str = "", timeout: int = 60) -> dict[str, object]:
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    headers = {"Accept": "application/json", "User-Agent": USER_AGENT}
    if data is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = token
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = response.read()
    return json.loads(payload) if payload else {}


def authenticate(base_url: str) -> str:
    email = os.environ.get("HYSE_PB_ADMIN_EMAIL", "")
    password = os.environ.get("HYSE_PB_ADMIN_PASSWORD", "")
    if not email or not password:
        raise RuntimeError("HYSE_PB_ADMIN_EMAIL and HYSE_PB_ADMIN_PASSWORD are required")
    result = request_json("POST", f"{base_url}/api/admins/auth-with-password",
                          {"identity": email, "password": password})
    token = str(result.get("token") or "")
    if not token:
        raise RuntimeError("PocketBase admin authentication returned no token")
    return token


def existing_barcodes(base_url: str, token: str) -> set[str]:
    result: set[str] = set()
    page = 1
    while True:
        query = urllib.parse.urlencode({"page": page, "perPage": 500, "fields": "barcode_normalized"})
        payload = request_json("GET", f"{base_url}/api/collections/global_foods/records?{query}", token=token)
        items = payload.get("items") or []
        if not isinstance(items, list):
            raise RuntimeError("PocketBase returned an invalid record list")
        for item in items:
            if isinstance(item, dict):
                barcode = str(item.get("barcode_normalized") or "")
                if barcode:
                    result.add(barcode)
        total_pages = int(payload.get("totalPages") or 0)
        if page >= total_pages:
            break
        page += 1
    log(f"EXISTING count={len(result)}")
    return result


def directory_size(path: Path) -> int:
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            try:
                total += (Path(root) / name).stat().st_size
            except FileNotFoundError:
                pass
    return total


def record_payload(product: dict[str, object], rank: int, data_date: str) -> dict[str, object]:
    barcode = str(product["barcode"])
    unit = str(product["unit"])
    payload: dict[str, object] = {
        "name": product["name_de"],
        "source_name_en": product["source_name_en"],
        "name_de": product["name_de"],
        "brand": product["brand"],
        "barcode": barcode,
        "barcode_raw": barcode,
        "barcode_normalized": barcode,
        "unit": unit,
        "serving_size": product["serving_size"],
        "creator": "",
        "source": "open_food_facts",
        "moderation_status": "approved",
        "source_id": barcode,
        "data_source": "Open Food Facts (ODbL 1.0)",
        "source_note": "Popular product in Germany; nutrition per 100 g/ml. Source: openfoodfacts.org.",
        "data_date": data_date,
        "reference_amount": 100,
        "reference_unit": unit,
        "average_values": False,
        "normalized_key": f"open_food_facts|{barcode}",
        "off_de_catalog_rank": rank,
        "off_unique_scans": product["unique_scans"],
        "off_popularity_period": "Germany latest OFF export",
        "is_fruit": False,
    }
    for name in ("calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt"):
        payload[name] = product[name]
    return payload


def create_batch(base_url: str, token: str, payloads: list[dict[str, object]]) -> tuple[int, int]:
    try:
        result = request_json("POST", f"{base_url}/api/hyse/admin/off-catalog/import", {"items": payloads}, token, timeout=180)
        return int(result.get("created") or 0), int(result.get("skipped") or 0)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:1_000]
        raise RuntimeError(f"PocketBase {error.code}: {detail}") from error


def import_products(products: list[dict[str, object]], base_url: str, pb_data: Path,
                    max_bytes: int, batch_size: int) -> tuple[int, int, int]:
    token = authenticate(base_url)
    existing = existing_barcodes(base_url, token)
    pending = [(rank, product) for rank, product in enumerate(products, start=1)
               if str(product["barcode"]) not in existing]
    log(f"PENDING count={len(pending)} skipped={len(products) - len(pending)}")
    if directory_size(pb_data) >= max_bytes:
        raise RuntimeError(f"PocketBase storage is already at or above the limit ({max_bytes} bytes)")

    created = failed = server_skipped = 0
    data_date = time.strftime("%Y-%m-%d", time.gmtime())
    for offset in range(0, len(pending), batch_size):
        used = directory_size(pb_data)
        if used >= max_bytes:
            log(f"STOP reason=storage-limit storage={used} limit={max_bytes}")
            break
        chunk = pending[offset:offset + batch_size]
        payloads = [record_payload(product, rank, data_date) for rank, product in chunk]
        try:
            added, skipped_now = create_batch(base_url, token, payloads)
            created += added
            server_skipped += skipped_now
        except Exception as error:
            # Retry individual rows only to isolate a malformed source record.
            log(f"BATCH_ERROR offset={offset} count={len(chunk)} detail={error}")
            for payload in payloads:
                try:
                    added, skipped_now = create_batch(base_url, token, [payload])
                    created += added
                    server_skipped += skipped_now
                except Exception as row_error:
                    failed += 1
                    log(f"ERROR barcode={payload['barcode_normalized']} detail={row_error}")
        log(f"IMPORT created={created} failed={failed} skipped={len(products) - len(pending) + server_skipped} processed={min(offset + len(chunk), len(pending))}/{len(pending)} storage={directory_size(pb_data)}")
        if failed >= 25 and failed * 20 > max(1, created):
            log("STOP reason=excessive-errors")
            break
    return created, len(products) - len(pending) + server_skipped, failed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, default=100_000)
    parser.add_argument("--export-url", default=EXPORT_URL)
    parser.add_argument("--base-url", default="http://127.0.0.1:8090")
    parser.add_argument("--pb-data", type=Path, default=Path("pb_data"))
    parser.add_argument("--max-bytes", type=int, default=950_000_000)
    parser.add_argument("--batch-size", type=int, default=200)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 1 <= args.target <= 500_000:
        raise SystemExit("--target must be between 1 and 500000")
    if not 1 <= args.batch_size <= 250:
        raise SystemExit("--batch-size must be between 1 and 250")
    products = collect_candidates(args.export_url, args.target)
    if len(products) < min(args.target, 10_000):
        raise RuntimeError(f"Only {len(products)} valid German products were found")
    created, skipped, failed = import_products(
        products, args.base_url.rstrip("/"), args.pb_data, args.max_bytes, args.batch_size
    )
    used = directory_size(args.pb_data)
    log(f"DONE selected={len(products)} created={created} skipped={skipped} failed={failed} storage={used}")
    return 0 if failed == 0 else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        log("STOP reason=interrupted")
        raise SystemExit(130)
    except Exception as error:
        log(f"FATAL {error}")
        raise SystemExit(1)
