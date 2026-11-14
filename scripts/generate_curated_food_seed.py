#!/usr/bin/env python3
"""Generate Hyse's reviewed staple-food seed from official source exports.

Inputs are never downloaded by this script and no API key is stored. Obtain:
- USDA FoodData Central SR Legacy JSON, release 2018-04 (CC0)
- Health Canada Canadian Nutrient File CSV files, release 2026

The generated JSON is human-reviewable. The generated PocketBase migration is
idempotent through stable source IDs and never overwrites user-created foods.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED_PATH = ROOT / "pb_seeds" / "curated_staple_foods.json"
MIGRATION_PATH = ROOT / "pb_migrations" / "1787750000_curated_staple_foods.js"
DATA_MIGRATION_PATH = ROOT / "pb_migrations" / "1787750030_curated_staple_food_data.js"
INDEX_MIGRATION_PATH = ROOT / "pb_migrations" / "1787750060_curated_source_id_index.js"
DEFAULT_PORTION_MIGRATION_PATH = ROOT / "pb_migrations" / "1787750090_curated_default_portions.js"

# fdc_id: (German name, category, preparation, documented portions)
# Portion tuple: (translation key, grams, default)
USDA = {
    168877: ("Reis, weiß, ungekocht", "grains", "dry", [("cup", 185, True)]),
    168878: ("Reis, weiß, gekocht", "grains", "cooked", [("cup", 158, True)]),
    173904: ("Haferflocken, trocken", "grains", "dry", [("serving", 27, True), ("cup", 81, False)]),
    169736: ("Nudeln, trocken", "grains", "dry", [("serving", 57, True)]),
    169737: ("Nudeln, gekocht, ungesalzen", "grains", "cooked", [("cup", 124, True)]),
    170026: ("Kartoffeln, roh, mit Schale", "grains", "raw", [("small", 170, False), ("medium", 213, True), ("large", 369, False)]),
    170438: ("Kartoffeln, gekocht, ungesalzen", "grains", "cooked", [("serving", 136, True)]),
    174924: ("Weißbrot", "grains", "prepared", [("slice", 29, True)]),
    172688: ("Vollkornbrot", "grains", "prepared", [("slice", 32, True)]),
    169700: ("Couscous, gekocht", "grains", "cooked", [("cup", 157, True)]),
    168482: ("Süßkartoffel, roh", "grains", "raw", [("serving", 130, True)]),
    168917: ("Quinoa, gekocht", "grains", "cooked", [("cup", 185, True)]),
    171077: ("Hähnchenbrust, roh, ohne Haut", "protein", "raw", [("serving", 113, True)]),
    174515: ("Putenbrust, roh, ohne Haut", "protein", "raw", [("serving", 113, True)]),
    174030: ("Rinderhack, 90 % mager, roh", "protein", "raw", [("serving", 113, True)]),
    175167: ("Lachs, Atlantik, Zucht, roh", "protein", "raw", [("serving", 85, True)]),
    171986: ("Thunfisch, in Wasser, abgetropft, ungesalzen", "protein", "prepared", [("serving", 85, True)]),
    171287: ("Ei, ganz, roh", "protein", "raw", [("small", 38, False), ("medium", 44, False), ("large", 50, True)]),
    172448: ("Tofu, fest", "protein", "prepared", [("serving", 126, True)]),
    172421: ("Linsen, gekocht, ungesalzen", "protein", "cooked", [("cup", 198, True)]),
    173757: ("Kichererbsen, gekocht, ungesalzen", "protein", "cooked", [("cup", 164, True)]),
    173740: ("Kidneybohnen, gekocht, ungesalzen", "protein", "cooked", [("cup", 177, True)]),
    171265: ("Vollmilch, 3,25 % Fett", "dairy", "prepared", [("cup", 244, True)]),
    171284: ("Naturjoghurt, Vollmilch", "dairy", "prepared", [("serving", 170, True), ("cup", 245, False)]),
    173417: ("Hüttenkäse, 1 % Fett", "dairy", "prepared", [("cup", 226, True)]),
    173414: ("Cheddar", "dairy", "prepared", [("slice", 28, True)]),
    175215: ("Sojadrink, ungesüßt, angereichert", "dairy", "prepared", [("cup", 243, True)]),
    171688: ("Apfel, roh, mit Schale", "fruit", "raw", [("small", 149, False), ("medium", 182, True), ("large", 223, False)]),
    173944: ("Banane, roh", "fruit", "raw", [("small", 101, False), ("medium", 118, True), ("large", 136, False)]),
    169097: ("Orange, roh", "fruit", "raw", [("small", 96, False), ("medium", 131, True), ("large", 184, False)]),
    167762: ("Erdbeeren, roh", "fruit", "raw", [("serving", 147, True), ("cup", 144, False)]),
    171711: ("Heidelbeeren, roh", "fruit", "raw", [("cup", 148, True)]),
    174683: ("Weintrauben, rot oder grün, roh", "fruit", "raw", [("serving", 126, True), ("cup", 151, False)]),
    171705: ("Avocado, roh", "fruit", "raw", [("serving", 50, True)]),
    170379: ("Brokkoli, roh", "vegetables", "raw", [("cup", 91, True)]),
    170393: ("Karotte, roh", "vegetables", "raw", [("small", 50, False), ("medium", 61, True), ("large", 72, False)]),
    170457: ("Tomate, rot, roh", "vegetables", "raw", [("small", 91, False), ("medium", 123, True), ("large", 182, False)]),
    168409: ("Gurke, roh, mit Schale", "vegetables", "raw", [("serving", 301, True)]),
    170108: ("Paprika, rot, roh", "vegetables", "raw", [("small", 74, False), ("medium", 119, True), ("large", 164, False)]),
    168462: ("Spinat, roh", "vegetables", "raw", [("cup", 30, True)]),
    169291: ("Zucchini, roh, mit Schale", "vegetables", "raw", [("small", 118, False), ("medium", 196, True), ("large", 323, False)]),
    170000: ("Zwiebel, roh", "vegetables", "raw", [("small", 70, False), ("medium", 110, True), ("large", 150, False)]),
    171413: ("Olivenöl", "fats", "prepared", [("tablespoon", 13.5, True)]),
    173410: ("Butter, gesalzen", "fats", "prepared", [("tablespoon", 14.2, True)]),
    174294: ("Erdnussbutter, cremig", "nuts", "prepared", [("serving", 32, True)]),
    170567: ("Mandeln", "nuts", "raw", [("serving", 28.35, True)]),
    170187: ("Walnüsse", "nuts", "raw", [("serving", 28.35, True)]),
    169640: ("Honig", "sweeteners", "prepared", [("tablespoon", 21, True)]),
}

CANADA = {
    6979: ("Skyr-Alternative, griechischer Joghurt, fettfrei, natur", "dairy", "prepared"),
    6995: ("Magerquark, natur, ungesalzen", "dairy", "prepared"),
}

USDA_NUTRIENTS = {"protein": 1003, "fat": 1004, "carbs": 1005, "calories": 1008,
                  "fiber": 1079, "sugar": 2000, "saturated_fat": 1258, "sodium": 1093}
CNF_NUTRIENTS = {"protein": 203, "fat": 204, "carbs": 205, "calories": 208,
                 "sugar": 269, "fiber": 291, "sodium": 307, "saturated_fat": 606}


def rounded(value: float) -> float:
    return round(float(value) + 1e-10, 2)


def nutrient_values(pairs: dict[int, float], ids: dict[str, int]) -> dict[str, float]:
    missing = [name for name, nutrient_id in ids.items() if nutrient_id not in pairs]
    if missing:
        raise ValueError(f"Missing required nutrients: {', '.join(missing)}")
    values = {name: rounded(pairs[nutrient_id]) for name, nutrient_id in ids.items()}
    values["salt"] = rounded(values.pop("sodium") * 2.5 / 1000)
    return values


def usda_foods(path: Path) -> list[dict]:
    source = json.loads(path.read_text(encoding="utf-8"))["SRLegacyFoods"]
    by_id = {int(food["fdcId"]): food for food in source}
    output = []
    for fdc_id, (name_de, category, preparation, portions) in USDA.items():
        food = by_id[fdc_id]
        nutrients = {int(item["nutrient"]["id"]): item["amount"] for item in food["foodNutrients"] if item.get("amount") is not None}
        output.append({
            "source_id": f"USDA-FDC-{fdc_id}", "source": "usda_fdc",
            "source_name_en": food["description"], "name_de": name_de,
            "category": category, "preparation": preparation,
            "reference_amount": 100, "reference_unit": "g", **nutrient_values(nutrients, USDA_NUTRIENTS),
            "data_source": "USDA FoodData Central, SR Legacy 2018-04 (CC0 1.0)",
            "source_note": f"Average values per 100 g edible portion; FDC ID {fdc_id}; salt calculated from documented sodium using sodium × 2.5.",
            "data_date": food.get("publicationDate", "2019-04-01"), "average_values": True,
            "portions": [{"name_key": key, "amount": grams, "unit": "g", "gram_equivalent": grams, "is_default": default}
                         for key, grams, default in portions],
        })
    return output


def cnf_foods(directory: Path) -> list[dict]:
    with (directory / "Food_Name.csv").open(encoding="utf-8-sig", newline="") as handle:
        names = {int(row["Food_Code"]): row for row in csv.DictReader(handle)}
    values: dict[int, dict[int, float]] = {}
    with (directory / "Nutrient_Amount.csv").open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            food_id = int(row["Food_Code"])
            if food_id in CANADA:
                values.setdefault(food_id, {})[int(row["Nutrient_Code"])] = float(row["Nutrient_Amount"])
    output = []
    for food_id, (name_de, category, preparation) in CANADA.items():
        row = names[food_id]
        output.append({
            "source_id": f"CNF-{food_id}", "source": "health_canada",
            "source_name_en": row["Food_Description_EN"], "name_de": name_de,
            "category": category, "preparation": preparation,
            "reference_amount": 100, "reference_unit": "g", **nutrient_values(values[food_id], CNF_NUTRIENTS),
            "data_source": "Health Canada, Canadian Nutrient File 2026 (Open Government Licence – Canada)",
            "source_note": f"Average values per 100 g; CNF food code {food_id}; salt calculated from documented sodium using sodium × 2.5.",
            "data_date": row["Food_Last_Updated_Date"], "average_values": True,
            # The source's documented 100 g reference is the conservative default;
            # no consumer-container weight is inferred.
            "portions": [{"name_key": "serving", "amount": 100, "unit": "g", "gram_equivalent": 100, "is_default": True}],
        })
    return output


def schema_migration() -> str:
    return """/// Curated staple-food metadata schema. Generated by scripts/generate_curated_food_seed.py.
migrate((db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId(\"global_foods\")
  const text = (name, max) => new SchemaField({ name, type: \"text\", options: { min: null, max, pattern: \"\" } })
  const number = (name) => new SchemaField({ name, type: \"number\", options: { min: 0, max: null, noDecimal: false } })
  for (const field of [
    text(\"source_name_en\", 500), text(\"name_de\", 500), text(\"source_id\", 120),
    text(\"data_source\", 500), text(\"source_note\", 1200), text(\"data_date\", 40),
    new SchemaField({ name: \"category\", type: \"select\", options: { maxSelect: 1, values: [\"grains\",\"protein\",\"dairy\",\"fruit\",\"vegetables\",\"fats\",\"nuts\",\"sweeteners\"] } }),
    new SchemaField({ name: \"preparation\", type: \"select\", options: { maxSelect: 1, values: [\"raw\",\"dry\",\"cooked\",\"prepared\"] } }),
    number(\"reference_amount\"), new SchemaField({ name: \"reference_unit\", type: \"select\", options: { maxSelect: 1, values: [\"g\",\"ml\"] } }),
    new SchemaField({ name: \"average_values\", type: \"bool\" })
  ]) globals.schema.addField(field)
  const sourceField = globals.schema.getFieldByName(\"source\")
  sourceField.options.values = [\"seed\",\"user\",\"open_food_facts\",\"usda_fdc\",\"health_canada\"]
  dao.saveCollection(globals)
}, (db) => {
  // Keep metadata fields during rollback because existing records may use them.
})
"""


def data_migration(food_json: str) -> str:
    return """/// Curated staple-food records. Generated by scripts/generate_curated_food_seed.py.
migrate((db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId(\"global_foods\")
  const portions = dao.findCollectionByNameOrId(\"food_portions\")

  const foods = __FOODS__
  const key = (food) => [food.source_name_en.toLowerCase(), \"\", \"g\", food.portions.find((p) => p.is_default)?.amount || 0, food.calories, food.carbs, food.protein, food.fat, food.sugar, food.fiber, food.saturated_fat, food.salt].join(\"|\")
  for (const food of foods) {
    let record = null
    try { record = dao.findFirstRecordByFilter(globals.id, \"source_id = {:source}\", { source: food.source_id }) } catch (_) {}
    if (!record) {
      // Only enrich legacy Hyse seed rows. User-created and moderated rows are never overwritten.
      try { record = dao.findFirstRecordByFilter(globals.id, \"name = {:name} && source = 'seed'\", { name: food.name_de }) } catch (_) {}
    }
    if (!record) record = new Record(globals)
    record.set(\"name\", food.source_name_en); record.set(\"source_name_en\", food.source_name_en); record.set(\"name_de\", food.name_de)
    for (const name of [\"category\",\"preparation\",\"reference_amount\",\"reference_unit\",\"calories\",\"carbs\",\"protein\",\"fat\",\"fiber\",\"sugar\",\"saturated_fat\",\"salt\",\"data_source\",\"source_note\",\"data_date\",\"average_values\",\"source_id\",\"source\"]) record.set(name, food[name])
    record.set(\"unit\", \"g\"); record.set(\"serving_size\", food.portions.find((p) => p.is_default)?.amount || 0)
    record.set(\"brand\", \"\"); record.set(\"barcode\", \"\"); record.set(\"creator\", \"\"); record.set(\"moderation_status\", \"approved\"); record.set(\"normalized_key\", key(food))
    dao.saveRecord(record)
    for (let index = 0; index < food.portions.length; index++) {
      const value = food.portions[index]
      let portion = null
      try { portion = dao.findFirstRecordByFilter(portions.id, \"global_food = {:food} && name_key = {:name} && owner = ''\", { food: record.id, name: value.name_key }) } catch (_) {}
      if (!portion) portion = new Record(portions)
      portion.set(\"owner\", \"\"); portion.set(\"user_food\", \"\"); portion.set(\"global_food\", record.id)
      portion.set(\"client_id\", (\"seed_\" + food.source_id + \"_\" + value.name_key).slice(0, 36)); portion.set(\"name_key\", value.name_key); portion.set(\"custom_name\", \"\")
      portion.set(\"amount\", value.amount); portion.set(\"unit\", value.unit); portion.set(\"gram_equivalent\", value.gram_equivalent); portion.set(\"sort_order\", index); portion.set(\"is_default\", value.is_default); portion.set(\"status\", \"approved\")
      dao.saveRecord(portion)
    }
  }
}, (db) => {
  // Intentionally retain curated records on down migration to avoid deleting
  // foods referenced by user meals. Schema cleanup can be handled separately.
})
""".replace("__FOODS__", food_json)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_curated_food_seed.py USDA_JSON CNF_DIRECTORY")
    foods = usda_foods(Path(sys.argv[1])) + cnf_foods(Path(sys.argv[2]))
    if len(foods) != 50 or len({food["source_id"] for food in foods}) != 50:
        raise ValueError("The curated seed must contain exactly 50 unique source IDs")
    SEED_PATH.parent.mkdir(exist_ok=True)
    payload = json.dumps(foods, ensure_ascii=False, indent=2)
    SEED_PATH.write_text(payload + "\n", encoding="utf-8")
    compact = json.dumps(foods, ensure_ascii=False, separators=(",", ":"))
    MIGRATION_PATH.write_text(schema_migration() + "\n", encoding="utf-8")
    DATA_MIGRATION_PATH.write_text(data_migration(compact) + "\n", encoding="utf-8")
    INDEX_MIGRATION_PATH.write_text('''/// Enforce stable curated source IDs after the schema-and-seed transaction commits.
migrate((db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  globals.indexes.push("CREATE UNIQUE INDEX `idx_global_foods_source_id` ON `global_foods` (`source_id`) WHERE `source_id` != ''")
  dao.saveCollection(globals)
}, (db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  globals.indexes = globals.indexes.filter((value) => !value.includes("idx_global_foods_source_id"))
  dao.saveCollection(globals)
})
''', encoding="utf-8")
    DEFAULT_PORTION_MIGRATION_PATH.write_text('''/// Ensure every curated food has a documented default portion.
migrate((db) => {
  const dao = new Dao(db)
  const portions = dao.findCollectionByNameOrId("food_portions")
  for (const sourceID of ["CNF-6979", "CNF-6995"]) {
    const food = dao.findFirstRecordByFilter("global_foods", "source_id = {:source}", { source: sourceID })
    let portion = null
    try { portion = dao.findFirstRecordByFilter(portions.id, "global_food = {:food} && name_key = 'serving' && owner = ''", { food: food.id }) } catch (_) {}
    if (!portion) portion = new Record(portions)
    portion.set("owner", ""); portion.set("user_food", ""); portion.set("global_food", food.id)
    portion.set("client_id", ("seed_" + sourceID + "_serving").slice(0, 36)); portion.set("name_key", "serving"); portion.set("custom_name", "")
    portion.set("amount", 100); portion.set("unit", "g"); portion.set("gram_equivalent", 100); portion.set("sort_order", 0); portion.set("is_default", true); portion.set("status", "approved")
    dao.saveRecord(portion)
  }
}, (db) => {
  // Retain portions referenced by historical meal entries.
})
''', encoding="utf-8")
    print(f"Generated {len(foods)} reviewed foods: {SEED_PATH}, {MIGRATION_PATH}, {DATA_MIGRATION_PATH}, {INDEX_MIGRATION_PATH} and {DEFAULT_PORTION_MIGRATION_PATH}")


if __name__ == "__main__":
    main()
