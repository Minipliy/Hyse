#!/usr/bin/env python3
"""Build a German-searchable Hyse seed from USDA SR Legacy."""

from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path

from build_fndds_catalog import build_record, finalize_german, translate_names


GERMAN_ALIASES = {
    "bread, banana": "Bananenbrot",
    "bread, garlic": "Knoblauchbrot",
    "bread, corn": "Maisbrot",
    "bread, pumpkin": "Kürbisbrot",
    "bread, zucchini": "Zucchinibrot",
    "pie, apple": "Apfelkuchen",
    "pie, blueberry": "Blaubeerkuchen",
    "pie, cherry": "Kirschkuchen",
    "pie, peach": "Pfirsichkuchen",
    "pie, pumpkin": "Kürbiskuchen",
    "rice pudding": "Milchreis",
    "beef stew": "Rindfleischeintopf",
    "chicken soup": "Hühnersuppe",
    "potato soup": "Kartoffelsuppe",
    "tomato soup": "Tomatensuppe",
    "vegetable soup": "Gemüsesuppe",
}


def preferred_german_name(source_name: str, translated: str) -> str:
    lower = source_name.lower()
    for source_prefix, german in GERMAN_ALIASES.items():
        if lower.startswith(source_prefix):
            return f"{german} · {translated}"
    return finalize_german(source_name, translated)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--translation-cache", type=Path, default=Path("/tmp/usda_sr_legacy_translations.json"))
    parser.add_argument("--curated-seed", type=Path, default=Path("pb_seeds/curated_staple_foods.json"))
    args = parser.parse_args()

    root = json.loads(args.source.read_text(encoding="utf-8"))
    foods = root.get("SRLegacyFoods") if isinstance(root, dict) else None
    if not isinstance(foods, list) or len(foods) < 7_500:
        raise SystemExit("Expected at least 7500 USDA SR Legacy foods")

    curated_ids: set[str] = set()
    if args.curated_seed.exists():
        curated = json.loads(args.curated_seed.read_text(encoding="utf-8"))
        curated_ids = {str(item.get("source_id") or "") for item in curated if isinstance(item, dict)}

    selected = [food for food in foods if f"USDA-FDC-{food.get('fdcId', '')}" not in curated_ids]
    names = [str(food.get("description") or "").strip() for food in selected]
    translations = translate_names([name for name in names if name], args.translation_cache)
    records: list[dict[str, object]] = []
    for food in selected:
        source_name = str(food.get("description") or "").strip()
        name_de = preferred_german_name(source_name, translations.get(source_name, ""))
        record = build_record(food, name_de)
        if record is None:
            continue
        fdc_id = str(food.get("fdcId") or "").strip()
        record.update({
            "source_id": f"USDA-FDC-{fdc_id}",
            "normalized_key": f"usda_sr_legacy|{fdc_id}",
            "data_source": "USDA FoodData Central, SR Legacy April 2018",
            "source_note": f"USDA NDB {food.get('ndbNumber', '')}; German name translated locally; nutrients unchanged",
            "data_date": "2018-04-01",
        })
        records.append(record)

    if len(records) < 7_000:
        raise SystemExit(f"Only {len(records)} valid USDA SR Legacy records")
    if len({record["normalized_key"] for record in records}) != len(records):
        raise SystemExit("Duplicate USDA SR Legacy identities")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(args.output, "wt", encoding="utf-8", compresslevel=9) as handle:
        json.dump(records, handle, ensure_ascii=False, separators=(",", ":"))
    print(f"WROTE {len(records)} records to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
