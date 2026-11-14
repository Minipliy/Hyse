#!/usr/bin/env python3
import importlib.util
import sqlite3
import sys
import tempfile
from collections import Counter
from pathlib import Path

path = Path(__file__).with_name("expand_open_food_facts_catalog.py")
sys.path.insert(0, str(path.parent))
spec = importlib.util.spec_from_file_location("off_diverse", path)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

banana_a = {"name_de": "Bio Banane 500 g", "source_name_en": "Banana", "brand": "Testmarke"}
banana_b = {"name_de": "Banane 1kg", "source_name_en": "Banana", "brand": "Andere Marke"}
assert module.concept_key(banana_a) == module.concept_key(banana_b) == "banane"
assert module.product_category_key({"categories_tags": "en:foods,en:snacks,en:biscuits"}) == "en:biscuits"
assert module.product_category_key({}) == "uncategorized"
assert module.product_brand_key({"brand": "KoRo, KoRo Handels GmbH"}) == "koro"
assert module.product_brand_key({"brand": ""}) == "unbranded"
assert not module.concept_has_room("", Counter(), Counter(), 3, 3)
assert not module.concept_has_room("banane", Counter({"banane": 4}), Counter(), 3, 0)
assert module.concept_has_room("banane", Counter({"banane": 4}), Counter(), 3, 3)
assert not module.concept_has_room("banane", Counter({"banane": 4}), Counter({"banane": 3}), 3, 3)

with tempfile.TemporaryDirectory() as directory:
    database = Path(directory) / "foods.db"
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE global_foods (barcode_normalized TEXT, normalized_key TEXT, name TEXT, name_de TEXT, brand TEXT)")
        connection.executemany("INSERT INTO global_foods VALUES (?, ?, ?, ?, ?)", [
            ("4008400404127", "off|1", "Banana", "Bio Banane 500 g", "Testmarke"),
            ("4008400404128", "off|2", "Banana", "Banane 1kg", "Andere Marke"),
        ])
    barcodes, keys, concepts = module.existing_catalogue_sqlite(database, include_keys=False)
    assert len(barcodes) == 2 and not keys and concepts["banane"] == 2

taxonomy = {
    "en:cakes": {"name": {"de": "Kuchen", "en": "Cakes"}, "parents": ["en:desserts"]},
    "en:chocolate-cakes": {"name": {"de": "Schokoladenkuchen", "en": "Chocolate cakes"}, "parents": ["en:cakes"]},
    "en:desserts": {"name": {"de": "Desserts", "en": "Desserts"}},
}
sample = (300, 40, 5, 14, 25, 2, 7, 0.5)
payload = module.aggregate_payload("en:chocolate-cakes", [(10 + index, sample) for index in range(7)], taxonomy, "2026-08-31")
assert payload
assert payload["barcode_normalized"] == ""
assert payload["name_de"] == "Schokoladenkuchen (Durchschnitt)"
assert payload["normalized_key"] == "open_food_facts_category|en:chocolate-cakes"
assert payload["average_values"] is True
assert payload["calories"] == 300

hook = (path.parents[1] / "pb_hooks" / "admin_off_catalog.pb.js").read_text()
assert "open_food_facts_category|" in hook
assert "dao.findFirstRecordByFilter" in hook
print("Diverse OFF expansion checks passed.")
