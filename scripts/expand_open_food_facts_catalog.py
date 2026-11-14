#!/usr/bin/env python3
"""Stream a diverse German OFF catalogue into PocketBase within a hard DB cap.

Packaged products retain their GTIN. Specific OFF leaf categories additionally
become barcode-free average foods so searches such as homemade chocolate cake
or banana bread have a useful generic result. No image or ingredient blobs are
stored, keeping the catalogue compact.
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
import sqlite3
import ssl
import time
import unicodedata
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

from import_open_food_facts_de_catalog import (
    EXPORT_URL, USER_AGENT, authenticate, create_batch, directory_size,
    is_german_product, normalize_product, request_json,
)

TAXONOMY_URL = "https://static.openfoodfacts.org/data/taxonomies/categories.json"
NUTRIENTS = ("calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt")
NOISE = {
    "bio", "organic", "original", "classic", "klassik", "neu", "new", "pack", "beutel", "dose",
    "glas", "flasche", "stück", "stueck", "x", "g", "kg", "ml", "cl", "l", "gramm", "liter",
    "der", "die", "das", "ein", "eine", "the", "and", "und", "mit", "von", "aus",
}


def log(message: str) -> None:
    print(message, flush=True)


def folded(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value or "")).encode("ascii", "ignore").decode("ascii").lower()
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


def concept_key(product: dict[str, object]) -> str:
    brand_tokens = set(folded(product.get("brand")).split())
    tokens = []
    for token in folded(product.get("name_de") or product.get("source_name_en")).split():
        if token in NOISE or token in brand_tokens or token.isdigit() or re.fullmatch(r"\d+(?:g|kg|ml|cl|l)", token):
            continue
        tokens.append(token)
    return " ".join(tokens[:12])


def existing_catalogue(base_url: str, token: str, include_keys: bool = True) -> tuple[set[str], set[str], Counter[str]]:
    barcodes: set[str] = set()
    keys: set[str] = set()
    concepts: Counter[str] = Counter()
    page = 1
    while True:
        query = urllib.parse.urlencode({
            "page": page, "perPage": 500,
            "fields": "barcode_normalized,normalized_key,name,name_de,brand" if include_keys else "barcode_normalized,name,name_de,brand",
        })
        payload = request_json("GET", f"{base_url}/api/collections/global_foods/records?{query}", token=token)
        items = payload.get("items") or []
        for item in items:
            if not isinstance(item, dict):
                continue
            barcode = str(item.get("barcode_normalized") or "")
            key = str(item.get("normalized_key") or "")
            if barcode:
                barcodes.add(barcode)
            if include_keys and key:
                keys.add(key)
            signature = concept_key({
                "name_de": item.get("name_de"), "source_name_en": item.get("name"), "brand": item.get("brand")
            })
            if signature:
                concepts[signature] += 1
        if page >= int(payload.get("totalPages") or 0):
            break
        page += 1
    log(f"EXISTING records={sum(concepts.values())} barcodes={len(barcodes)} concepts={len(concepts)}")
    return barcodes, keys, concepts


def existing_catalogue_sqlite(database: Path, include_keys: bool = True) -> tuple[set[str], set[str], Counter[str]]:
    """Read the colocated catalogue without hundreds of paginated API calls."""
    barcodes: set[str] = set()
    keys: set[str] = set()
    concepts: Counter[str] = Counter()
    total = 0
    connection = sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        for barcode, key, name, name_de, brand in connection.execute(
            "SELECT barcode_normalized, normalized_key, name, name_de, brand FROM global_foods"
        ):
            total += 1
            if barcode:
                barcodes.add(str(barcode))
            if include_keys and key:
                keys.add(str(key))
            signature = concept_key({"name_de": name_de, "source_name_en": name, "brand": brand})
            if signature:
                concepts[signature] += 1
    finally:
        connection.close()
    log(f"EXISTING records={total} barcodes={len(barcodes)} concepts={len(concepts)}")
    return barcodes, keys, concepts


def load_taxonomy(url: str) -> dict[str, dict[str, object]]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120, context=ssl.create_default_context()) as response:
        value = json.load(response)
    if not isinstance(value, dict):
        raise RuntimeError("OFF category taxonomy is invalid")
    return value


def taxonomy_label(taxonomy: dict[str, dict[str, object]], tag: str, language: str) -> str:
    entry = taxonomy.get(tag) or {}
    names = entry.get("name") or {}
    if not isinstance(names, dict):
        return ""
    return " ".join(str(names.get(language) or names.get("en") or "").split())[:460]


def ancestors(taxonomy: dict[str, dict[str, object]], tag: str) -> set[str]:
    seen: set[str] = set()
    pending = [tag]
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.add(current)
        entry = taxonomy.get(current) or {}
        parents = entry.get("parents") or []
        if isinstance(parents, list):
            pending.extend(str(value) for value in parents)
    return seen


def category_tags(row: dict[str, str]) -> list[str]:
    return [part.strip().lower() for part in str(row.get("categories_tags") or "").split(",")
            if part.strip().lower().startswith("en:")]


def product_category_key(row: dict[str, str]) -> str:
    tags = category_tags(row)
    return tags[-1] if tags else "uncategorized"


def product_brand_key(product: dict[str, object]) -> str:
    first_brand = str(product.get("brand") or "").split(",", 1)[0]
    return folded(first_brand) or "unbranded"


def concept_has_room(signature: str, existing: Counter[str], incoming: Counter[str],
                     existing_limit: int, incoming_limit: int) -> bool:
    if not signature:
        return False
    return (incoming[signature] < incoming_limit if incoming_limit else existing[signature] < existing_limit)


def packaged_payload(product: dict[str, object], rank: int, date: str) -> dict[str, object]:
    barcode = str(product["barcode"])
    unit = str(product["unit"])
    payload: dict[str, object] = {
        "name": product["name_de"], "source_name_en": product["source_name_en"], "name_de": product["name_de"],
        "brand": product["brand"], "barcode": barcode, "barcode_raw": barcode, "barcode_normalized": barcode,
        "unit": unit, "serving_size": product["serving_size"], "creator": "", "source": "open_food_facts",
        "moderation_status": "approved", "source_id": barcode, "data_source": "Open Food Facts (ODbL 1.0)",
        "source_note": "Product listed for Germany by Open Food Facts; nutrition per 100 g/ml.", "data_date": date,
        "reference_amount": 100, "reference_unit": unit, "average_values": False,
        "normalized_key": f"open_food_facts|{barcode}", "off_de_catalog_rank": rank,
        "off_unique_scans": product["unique_scans"], "off_popularity_period": "Germany latest OFF export", "is_fruit": False,
    }
    payload.update({name: product[name] for name in NUTRIENTS})
    return payload


def aggregate_payload(tag: str, samples: list[tuple[int, tuple[float, ...]]], taxonomy: dict[str, dict[str, object]], date: str) -> dict[str, object] | None:
    if len(samples) < 5:
        return None
    name_de = taxonomy_label(taxonomy, tag, "de")
    name_en = taxonomy_label(taxonomy, tag, "en")
    if not name_de or not name_en:
        return None
    values = list(zip(*(sample[1] for sample in samples)))
    nutrition: dict[str, float] = {}
    for nutrient_name, column in zip(NUTRIENTS, values):
        ordered = sorted(column)
        trimmed = ordered[1:-1] if len(ordered) >= 7 else ordered
        nutrition[nutrient_name] = round(sum(trimmed) / len(trimmed), 3)
    family = ancestors(taxonomy, tag)
    volume = bool(family.intersection({"en:beverages", "en:drinks", "en:plant-based-beverages", "en:milks"}))
    fruit = bool(family.intersection({"en:fruits", "en:fresh-fruits", "en:dried-fruits"}))
    source_suffix = tag.removeprefix("en:")
    source_id = f"off-category:{source_suffix}"
    if len(source_id) > 120:
        import hashlib
        source_id = f"off-category:{hashlib.sha256(tag.encode()).hexdigest()[:32]}"
    unit = "ml" if volume else "g"
    payload: dict[str, object] = {
        "name": f"{name_en} (average)", "source_name_en": name_en, "name_de": f"{name_de} (Durchschnitt)",
        "brand": "", "barcode": "", "barcode_raw": "", "barcode_normalized": "", "unit": unit,
        "serving_size": 100, "creator": "", "source": "open_food_facts", "moderation_status": "approved",
        "source_id": source_id, "data_source": "Open Food Facts category aggregate (ODbL 1.0)",
        "source_note": f"Robust average of {len(samples)} German-language OFF products in category {tag}; no barcode.",
        "data_date": date, "reference_amount": 100, "reference_unit": unit, "average_values": True,
        "normalized_key": f"open_food_facts_category|{tag}", "off_unique_scans": sum(item[0] for item in samples),
        "off_popularity_period": "Germany latest OFF export", "is_fruit": fruit,
    }
    payload.update(nutrition)
    return payload


def db_bytes(path: Path) -> int:
    return sum((path.parent / name).stat().st_size for name in (path.name, f"{path.name}-wal", f"{path.name}-shm")
               if (path.parent / name).exists())


def run(args: argparse.Namespace) -> None:
    token = authenticate(args.base_url)
    if args.database.is_file():
        existing_barcodes, existing_keys, concepts = existing_catalogue_sqlite(args.database, include_keys=not args.packaged_only)
    else:
        existing_barcodes, existing_keys, concepts = existing_catalogue(args.base_url, token, include_keys=not args.packaged_only)
    taxonomy = {} if args.packaged_only else load_taxonomy(args.taxonomy_url)
    category_samples: dict[str, list[tuple[int, tuple[float, ...]]]] = defaultdict(list)
    new_categories: Counter[str] = Counter()
    new_brands: Counter[str] = Counter()
    new_concepts: Counter[str] = Counter()
    new_brand_concepts: Counter[tuple[str, str]] = Counter()
    pending: list[dict[str, object]] = []
    created = skipped = scanned = valid = 0
    date = time.strftime("%Y-%m-%d", time.gmtime())
    request = urllib.request.Request(args.export_url, headers={"User-Agent": USER_AGENT})

    def flush() -> None:
        nonlocal created, skipped, pending
        if not pending:
            return
        added, ignored = create_batch(args.base_url, token, pending)
        created += added
        skipped += ignored
        pending = []

    csv.field_size_limit(16 * 1024 * 1024)
    with urllib.request.urlopen(request, timeout=300, context=ssl.create_default_context()) as response:
        stream = io.TextIOWrapper(gzip.GzipFile(fileobj=response), encoding="utf-8", errors="replace", newline="")
        for row in csv.DictReader(stream, delimiter="\t"):
            scanned += 1
            if args.packaged_only and created >= args.max_new_products:
                break
            if scanned % 250_000 == 0:
                log(f"STREAM rows={scanned} valid={valid} created={created} concepts={len(concepts)} db={db_bytes(args.database)}")
            # The current compact OFF CSV no longer exposes product_name_de or
            # lang. Country membership is therefore the stable export-level
            # German filter; generic category names still come from the German
            # taxonomy translation.
            if not is_german_product(row):
                continue
            product = normalize_product(row)
            if product is None:
                continue
            valid += 1
            tags = category_tags(row)
            if tags and not args.packaged_only:
                leaf = tags[-1]
                if leaf in taxonomy and taxonomy_label(taxonomy, leaf, "de"):
                    score = int(product["unique_scans"])
                    sample = (score, tuple(float(product[name]) for name in NUTRIENTS))
                    heap = category_samples[leaf]
                    if len(heap) < args.samples_per_category:
                        heapq.heappush(heap, sample)
                    elif sample[0] > heap[0][0]:
                        heapq.heapreplace(heap, sample)

            barcode = str(product["barcode"])
            signature = concept_key(product)
            if barcode in existing_barcodes or not concept_has_room(
                signature, concepts, new_concepts, args.variants_per_concept, args.new_variants_per_concept
            ):
                continue
            category = product_category_key(row)
            brand = product_brand_key(product)
            brand_concept = (brand, signature)
            if args.max_per_brand_concept and new_brand_concepts[brand_concept] >= args.max_per_brand_concept:
                continue
            if args.max_per_category and new_categories[category] >= args.max_per_category:
                continue
            if args.max_per_brand and new_brands[brand] >= args.max_per_brand:
                continue
            if created + len(pending) >= args.max_new_products or db_bytes(args.database) >= args.packaged_stop_bytes:
                continue
            concepts[signature] += 1
            new_concepts[signature] += 1
            new_brand_concepts[brand_concept] += 1
            new_categories[category] += 1
            new_brands[brand] += 1
            existing_barcodes.add(barcode)
            pending.append(packaged_payload(product, len(existing_barcodes), date))
            if len(pending) >= args.batch_size:
                flush()
    flush()

    if args.packaged_only:
        log(f"DONE rows={scanned} valid={valid} created={created} skipped={skipped} categories={len(new_categories)} brands={len(new_brands)} db={db_bytes(args.database)}")
        if created < args.max_new_products:
            raise RuntimeError(f"SHORTFALL requested={args.max_new_products} created={created}; source has no more eligible barcode products")
        return

    generic: list[dict[str, object]] = []
    for tag, samples in sorted(category_samples.items()):
        key = f"open_food_facts_category|{tag}"
        if key in existing_keys:
            continue
        payload = aggregate_payload(tag, samples, taxonomy, date)
        if payload is not None:
            generic.append(payload)
    for offset in range(0, len(generic), args.batch_size):
        if db_bytes(args.database) >= args.max_database_bytes:
            break
        added, ignored = create_batch(args.base_url, token, generic[offset:offset + args.batch_size])
        created += added
        skipped += ignored
    log(f"DONE rows={scanned} valid={valid} created={created} skipped={skipped} generic_candidates={len(generic)} db={db_bytes(args.database)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--export-url", default=EXPORT_URL)
    parser.add_argument("--taxonomy-url", default=TAXONOMY_URL)
    parser.add_argument("--base-url", default="http://127.0.0.1:8090")
    parser.add_argument("--database", type=Path, default=Path("pb_data/data.db"))
    parser.add_argument("--max-database-bytes", type=int, default=1_800_000_000)
    parser.add_argument("--packaged-stop-bytes", type=int, default=1_650_000_000)
    parser.add_argument("--max-new-products", type=int, default=1_500_000)
    parser.add_argument("--variants-per-concept", type=int, default=3)
    parser.add_argument("--new-variants-per-concept", type=int, default=0,
                        help="If set, cap only the new batch per product concept, regardless of existing products")
    parser.add_argument("--max-per-brand-concept", type=int, default=0,
                        help="Maximum newly imported records for the same brand and product concept")
    parser.add_argument("--samples-per-category", type=int, default=9)
    parser.add_argument("--batch-size", type=int, default=200)
    parser.add_argument("--packaged-only", action="store_true", help="Import barcode products only, without category averages")
    parser.add_argument("--max-per-category", type=int, default=0, help="Maximum newly imported products per leaf category (0 disables)")
    parser.add_argument("--max-per-brand", type=int, default=0, help="Maximum newly imported products per normalized first brand (0 disables)")
    args = parser.parse_args()
    if not 1 <= args.batch_size <= 250:
        parser.error("--batch-size must be between 1 and 250")
    if not 1 <= args.variants_per_concept <= 10:
        parser.error("--variants-per-concept must be between 1 and 10")
    if args.new_variants_per_concept < 0 or args.max_per_brand_concept < 0:
        parser.error("new concept and brand-concept limits must not be negative")
    if args.max_per_category < 0 or args.max_per_brand < 0:
        parser.error("category and brand limits must not be negative")
    if args.packaged_stop_bytes >= args.max_database_bytes or args.max_database_bytes > 2_000_000_000:
        parser.error("database limits must reserve space and remain at or below 2 GB")
    return args


if __name__ == "__main__":
    run(parse_args())
