#!/usr/bin/env python3
import importlib.util
import sqlite3
import sys
import tempfile
from pathlib import Path

path = Path(__file__).with_name("add_off_homemade_aggregates.py")
sys.path.insert(0, str(path.parent))
spec = importlib.util.spec_from_file_location("homemade", path)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.NamedTemporaryFile(suffix=".db") as value:
    db = sqlite3.connect(value.name)
    fields = ",".join(f"{name} real" for name in module.NUTRIENTS)
    db.execute(f"create table global_foods(name text,name_de text,barcode_normalized text,source text,{fields})")
    for index, kcal in enumerate((270, 300, 330, 900)):
        nutrients = (kcal, 45, 5, 10, 20, 2, 4, 0.5)
        db.execute("insert into global_foods values(?,?,?,?," + ",".join("?" for _ in nutrients) + ")",
                   ("Banana bread", "Bananenbrot", str(index), "open_food_facts", *nutrients))
    db.commit()
    payloads = module.build_payloads(Path(value.name), "2026-09-01")

banana = next(item for item in payloads if "bananenbrot" in item["normalized_key"])
assert banana["barcode_normalized"] == ""
assert banana["name_de"].startswith("Bananenbrot, selbstgemacht")
assert banana["average_values"] is True
assert banana["calories"] < 500
print("Homemade OFF aggregate checks passed.")
