#!/usr/bin/env python3
"""Explain why a current Open Food Facts export yields few new barcode foods."""

from __future__ import annotations

import csv
import gzip
import io
import json
import sqlite3
import ssl
import urllib.request
from collections import Counter
from pathlib import Path

from expand_open_food_facts_catalog import concept_key
from import_open_food_facts_de_catalog import (
    EXPORT_URL, USER_AGENT, is_german_product, normalize_product,
)


def audit(database: Path, export_url: str) -> dict[str, object]:
    db = sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        barcodes = {str(row[0]) for row in db.execute(
            "SELECT barcode_normalized FROM global_foods WHERE barcode_normalized != ''"
        )}
        concepts: Counter[str] = Counter()
        for name, name_de, brand in db.execute("SELECT name, name_de, brand FROM global_foods"):
            key = concept_key({"source_name_en": name, "name_de": name_de, "brand": brand})
            if key:
                concepts[key] += 1
    finally:
        db.close()

    counts: Counter[str] = Counter()
    examples: dict[str, list[dict[str, str]]] = {}
    observed: set[str] = set()
    request = urllib.request.Request(export_url, headers={"User-Agent": USER_AGENT})
    csv.field_size_limit(16 * 1024 * 1024)
    with urllib.request.urlopen(request, timeout=300, context=ssl.create_default_context()) as response:
        stream = io.TextIOWrapper(gzip.GzipFile(fileobj=response), encoding="utf-8", errors="replace", newline="")
        for row in csv.DictReader(stream, delimiter="\t"):
            counts["rows"] += 1
            if not is_german_product(row):
                continue
            counts["german_rows"] += 1
            product = normalize_product(row)
            if product is None:
                continue
            counts["valid_rows"] += 1
            barcode = str(product["barcode"])
            if barcode in observed:
                counts["duplicate_export_barcode"] += 1
                continue
            observed.add(barcode)
            if barcode in barcodes:
                counts["existing_barcode"] += 1
                continue
            counts["new_valid_barcode"] += 1
            key = concept_key(product)
            reason = "eligible" if key and concepts[key] < 3 else "concept_limit"
            counts[reason] += 1
            if len(examples.setdefault(reason, [])) < 8:
                examples[reason].append({
                    "barcode": barcode,
                    "name": str(product["name_de"]),
                    "brand": str(product["brand"]),
                    "concept": key,
                    "existing_variants": str(concepts[key]),
                })
            if counts["rows"] % 250000 == 0:
                print(json.dumps({"progress": counts["rows"], "counts": counts}), flush=True)
    return {"counts": dict(counts), "examples": examples}


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--export-url", default=EXPORT_URL)
    args = parser.parse_args()
    print(json.dumps(audit(args.database, args.export_url), ensure_ascii=False, indent=2), flush=True)
