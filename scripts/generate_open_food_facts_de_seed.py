#!/usr/bin/env python3
"""Build an idempotent PocketBase seed from popular German OFF scan groups."""

from __future__ import annotations

import csv
import gzip
import io
import json
import math
import ssl
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "pb_migrations" / "1788093000_open_food_facts_de_top_1000.js"
EXPORT = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
USER_AGENT = "Hyse/1.0 (hyse@minipliy.net)"
PRIMARY_TAG = "top-1000-de-scans-2025"
FALLBACK_TAG = "top-5000-de-scans-2025"
TARGET_COUNT = 1_000
TLS_CONTEXT = ssl.create_default_context(cafile="/etc/ssl/cert.pem")


def gtin_is_valid(code: str) -> bool:
    if len(code) not in (8, 12, 13, 14) or not code.isdigit():
        return False
    total = 0
    reversed_body = list(reversed(code[:-1]))
    for index, digit in enumerate(reversed_body):
        total += int(digit) * (3 if index % 2 == 0 else 1)
    return (10 - total % 10) % 10 == int(code[-1])


def finite_number(value, default=None):
    if isinstance(value, bool):
        return default
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return number if math.isfinite(number) else default


def nutrient(product: dict, key: str, default=None):
    return finite_number(product.get(f"{key}_100g"), default)


def clean_text(value, maximum: int) -> str:
    return " ".join(str(value or "").split())[:maximum]


def normalized_product(product: dict) -> dict | None:
    code = "".join(character for character in str(product.get("code") or "") if character.isdigit())
    if not gtin_is_valid(code):
        return None

    source_name = clean_text(product.get("product_name"), 500)
    if not source_name:
        return None
    name_de = source_name

    calories = nutrient(product, "energy-kcal")
    if calories is None:
        energy_kj = nutrient(product, "energy-kj")
        calories = None if energy_kj is None else energy_kj / 4.184
    core = {
        "calories": calories,
        "carbs": nutrient(product, "carbohydrates"),
        "protein": nutrient(product, "proteins"),
        "fat": nutrient(product, "fat"),
    }
    if any(value is None for value in core.values()):
        return None
    if not (0 <= core["calories"] <= 900):
        return None
    if any(not 0 <= core[key] <= 100 for key in ("carbs", "protein", "fat")):
        return None
    estimated_calories = 4 * (core["carbs"] + core["protein"]) + 9 * core["fat"]
    if core["calories"] > 0 and estimated_calories > 0:
        tolerance = max(120, 0.5 * max(core["calories"], estimated_calories))
        if abs(core["calories"] - estimated_calories) > tolerance:
            return None

    serving_text = clean_text(product.get("serving_size"), 80).lower()
    categories = str(product.get("categories_tags") or "").lower()
    unit = "ml" if any(marker in serving_text for marker in (" ml", " cl", " l")) or "en:beverages" in categories else "g"
    serving = finite_number(str(product.get("serving_quantity") or "").replace(",", "."), 0) or 0
    if serving <= 0 or serving > 1_000:
        serving = 100

    optional = {
        "sugar": nutrient(product, "sugars", 0),
        "fiber": nutrient(product, "fiber", 0),
        "saturated_fat": nutrient(product, "saturated-fat", 0),
        "salt": nutrient(product, "salt", 0),
    }
    for key, value in optional.items():
        optional[key] = round(value, 3) if 0 <= value <= 100 else 0

    return {
        "source_id": code,
        "source_name_en": source_name,
        "name_de": name_de,
        "brand": clean_text(product.get("brands"), 160),
        "barcode": code,
        "unit": unit,
        "serving_size": round(serving, 3),
        **{key: round(value, 3) for key, value in core.items()},
        **optional,
        "scans": int(finite_number(product.get("unique_scans_n"), 0) or 0),
        "unique_scans": int(finite_number(product.get("unique_scans_n"), 0) or 0),
    }


def collect() -> list[dict]:
    primary: dict[str, dict] = {}
    fallback: dict[str, dict] = {}
    csv.field_size_limit(16 * 1024 * 1024)
    request = urllib.request.Request(EXPORT, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=180, context=TLS_CONTEXT) as response:
        compressed = gzip.GzipFile(fileobj=response)
        text = io.TextIOWrapper(compressed, encoding="utf-8", errors="replace", newline="")
        for row_number, raw in enumerate(csv.DictReader(text, delimiter="\t"), start=1):
            tags = {value.removeprefix("en:") for value in str(raw.get("popularity_tags") or "").split(",")}
            target = primary if PRIMARY_TAG in tags else fallback if FALLBACK_TAG in tags else None
            if target is not None:
                item = normalized_product(raw)
                if item is not None:
                    target[item["barcode"]] = item
            if row_number % 250_000 == 0:
                print(f"Scanned {row_number:,} rows; {len(primary)} primary and {len(fallback)} fallback candidates", flush=True)

    ranked_primary = sorted(primary.values(), key=lambda item: (-item["unique_scans"], item["barcode"]))
    ranked_fallback = sorted(fallback.values(), key=lambda item: (-item["unique_scans"], item["barcode"]))
    selected = ranked_primary[:]
    seen = {item["barcode"] for item in selected}
    selected.extend(item for item in ranked_fallback if item["barcode"] not in seen)
    if len(selected) < TARGET_COUNT:
        raise RuntimeError(f"Only {len(selected)} valid products were available")
    return selected[:TARGET_COUNT]


def migration_source(foods: list[dict]) -> str:
    # PocketBase 0.22 scans JavaScript migrations line by line. Keep the
    # generated product catalogue below its per-line parser limit instead of
    # emitting the entire 1,000-item array as one very long line.
    data = json.dumps(foods, ensure_ascii=False, indent=2)
    return f'''/// Generated by scripts/generate_open_food_facts_de_seed.py on 2026-08-30.
/// Source: Open Food Facts German 2025 popularity tags (ODbL 1.0).
migrate((db) => {{
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  const add = (field) => {{
    if (!globals.schema.getFieldByName(field.name)) globals.schema.addField(new SchemaField(field))
  }}
  add({{ name: "off_de_catalog_rank", type: "number", options: {{ min: 1, max: null, noDecimal: true }} }})
  add({{ name: "off_unique_scans", type: "number", options: {{ min: 0, max: null, noDecimal: true }} }})
  add({{ name: "off_popularity_period", type: "text", options: {{ min: null, max: 40, pattern: "" }} }})
  dao.saveCollection(globals)

  const foods = {data}
  for (let index = 0; index < foods.length; index++) {{
    const food = foods[index]
    let record = null
    try {{ record = dao.findFirstRecordByFilter(globals.id, "barcode_normalized = {{:barcode}}", {{ barcode: food.barcode }}) }} catch (_) {{}}
    if (record && String(record.get("source") || "") !== "open_food_facts") continue
    if (!record) record = new Record(globals)
    record.set("name", food.source_name_en); record.set("source_name_en", food.source_name_en); record.set("name_de", food.name_de)
    record.set("brand", food.brand); record.set("barcode", food.barcode); record.set("barcode_raw", food.barcode); record.set("barcode_normalized", food.barcode)
    record.set("unit", food.unit); record.set("serving_size", food.serving_size)
    for (const name of ["calories","carbs","protein","fat","sugar","fiber","saturated_fat","salt"]) record.set(name, food[name])
    record.set("creator", ""); record.set("source", "open_food_facts"); record.set("moderation_status", "approved")
    record.set("source_id", food.source_id); record.set("data_source", "Open Food Facts (ODbL 1.0)")
    record.set("source_note", "Popular product in Germany; nutrition per 100 g/ml. Source: openfoodfacts.org, retrieved 2026-08-30.")
    record.set("data_date", "2026-08-30"); record.set("reference_amount", 100); record.set("reference_unit", food.unit); record.set("average_values", false)
    record.set("normalized_key", "open_food_facts|" + food.barcode)
    record.set("off_de_catalog_rank", index + 1); record.set("off_unique_scans", food.unique_scans); record.set("off_popularity_period", "Germany 2025")
    record.set("is_fruit", false)
    dao.saveRecord(record)
  }}
}}, (db) => {{
  // Retain imported foods because meal history may reference them.
}})
'''


def main() -> None:
    foods = collect()
    OUTPUT.write_text(migration_source(foods), encoding="utf-8")
    print(f"Wrote {len(foods)} products to {OUTPUT}")


if __name__ == "__main__":
    main()
