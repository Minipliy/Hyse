#!/usr/bin/env python3
"""Small deterministic tests for the scalable OFF catalogue importer."""

import importlib.util
from pathlib import Path


SCRIPT = Path(__file__).with_name("import_open_food_facts_de_catalog.py")
ROOT = SCRIPT.parents[1]
SPEC = importlib.util.spec_from_file_location("off_import", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def valid_row(**updates):
    row = {
        "code": "4008400404127",
        "countries_tags": "en:germany,en:austria",
        "product_name": "Test food",
        "product_name_de": "Testlebensmittel",
        "brands": "Testmarke",
        "energy-kcal_100g": "250",
        "carbohydrates_100g": "30",
        "proteins_100g": "10",
        "fat_100g": "10",
        "sugars_100g": "5",
        "fiber_100g": "3",
        "saturated-fat_100g": "2",
        "salt_100g": "1",
        "serving_size": "25 g",
        "serving_quantity": "25",
        "unique_scans_n": "123",
        "popularity_key": "456",
    }
    row.update(updates)
    return row


assert MODULE.gtin_is_valid("4008400404127")
assert not MODULE.gtin_is_valid("4008400404128")
assert MODULE.is_german_product(valid_row())
assert MODULE.is_german_product(valid_row(countries_tags="", popularity_tags="en:top-100000-de-scans-2025"))
assert not MODULE.is_german_product(valid_row(countries_tags="en:france", popularity_tags=""))
product = MODULE.normalize_product(valid_row())
assert product and product["name_de"] == "Testlebensmittel"
assert product["serving_size"] == 25
assert MODULE.normalize_product(valid_row(**{"proteins_100g": ""})) is None
payload = MODULE.record_payload(product, 42, "2026-08-31")
assert payload["barcode_normalized"] == "4008400404127"
assert payload["off_de_catalog_rank"] == 42
assert payload["moderation_status"] == "approved"
hook = (ROOT / "pb_hooks" / "admin_off_catalog.pb.js").read_text(encoding="utf-8")
migration = (ROOT / "pb_migrations" / "1788111000_global_food_barcode_lookup_index.js").read_text(encoding="utf-8")
assert '$apis.requireAdminAuth()' in hook
assert 'items.length > 250' in hook
assert 'barcode_normalized`, `moderation_status' in migration
print("Open Food Facts catalogue importer tests passed.")
