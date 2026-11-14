#!/usr/bin/env python3
"""Read-only verification of the diverse Open Food Facts batch."""

import json
import sqlite3
import sys
from collections import Counter

from expand_open_food_facts_catalog import concept_key, product_brand_key
from import_open_food_facts_de_catalog import gtin_is_valid

SOURCE_NOTE = "Product listed for Germany by Open Food Facts; nutrition per 100 g/ml."
connection = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
try:
    approved = connection.execute(
        "SELECT COUNT(*) FROM global_foods WHERE moderation_status = 'approved'"
    ).fetchone()[0]
    barcoded = connection.execute(
        "SELECT COUNT(DISTINCT barcode_normalized) FROM global_foods "
        "WHERE moderation_status = 'approved' AND barcode_normalized != ''"
    ).fetchone()[0]
    products = connection.execute(
        "SELECT barcode_normalized, name_de, brand, calories, carbs, protein, fat "
        "FROM global_foods WHERE source_note = ? AND moderation_status = 'approved'",
        (SOURCE_NOTE,),
    ).fetchall()
    admin_count = connection.execute(
        "SELECT COUNT(*) FROM _admins WHERE email = ?",
        ("hyse-off-100k-import@localhost.invalid",),
    ).fetchone()[0]
finally:
    connection.close()

barcodes = [str(product[0]) for product in products]
brands = Counter(product_brand_key({"brand": product[2]}) for product in products)
concepts = Counter(concept_key({"name_de": product[1], "brand": product[2]}) for product in products)
result = {
    "approved": approved,
    "barcoded_approved": barcoded,
    "new_batch": len(products),
    "distinct_new_barcodes": len(set(barcodes)),
    "invalid_gtins": sum(not gtin_is_valid(barcode) for barcode in barcodes),
    "brands": len(brands),
    "max_new_per_brand": max(brands.values(), default=0),
    "concepts": len(concepts),
    "max_new_per_concept": max(concepts.values(), default=0),
    "missing_core_nutrition": sum(any(value is None for value in product[3:]) for product in products),
    "temporary_admins": admin_count,
    "sample": [{"barcode": item[0], "name": item[1], "brand": item[2]} for item in products[::max(1, len(products) // 12)][:12]],
}
print(json.dumps(result, ensure_ascii=False, indent=2))
