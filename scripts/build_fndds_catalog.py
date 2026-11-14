#!/usr/bin/env python3
"""Build a compact Hyse seed from USDA FNDDS 2021–2023.

FNDDS contains generic foods and mixed dishes rather than another branded
barcode catalogue.  Names are translated locally with Argos Translate; the
original English description is kept verbatim for search and provenance.
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
import re
from pathlib import Path


NUTRIENT_IDS = {
    "protein": 1003,
    "fat": 1004,
    "carbs": 1005,
    "calories": 1008,
    "fiber": 1079,
    "salt_sodium": 1093,
    "saturated_fat": 1258,
    "sugar": 2000,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--translation-cache", type=Path, default=Path("/tmp/fndds_translations.json"))
    return parser.parse_args()


def translation_input(name: str) -> str:
    replacements = (
        (r"\bNFS\b", "not further specified"),
        (r"\bNS as to\b", "type not specified"),
        (r"\bNS\b", "not specified"),
        (r"\bwith icing\b", "with sugar glaze"),
        (r"\bicing or filling\b", "sugar glaze or filling"),
        (r"\bicing\b", "sugar glaze"),
    )
    value = name
    for pattern, replacement in replacements:
        value = re.sub(pattern, replacement, value, flags=re.IGNORECASE)
    return value


def cleanup_german(value: str) -> str:
    replacements = {
        "Zuckereis": "Zuckerguss",
        "Zuckerglasur": "Zuckerguss",
        "Fleischlaib": "Hackbraten",
        "Macaroni": "Makkaroni",
        "Chicken Curry": "Hähnchencurry",
        "Gluteris": "Klebreis",
        "Glutinöser Reis": "Klebreis",
        "geschmiert": "geschmort",
        "gedüngt": "geschmort",
        "gefressen": "gegessen",
        "Hähnchen-Trommelstiel": "Hähnchen-Unterkeule",
        "Hähnchen-Trommelstock": "Hähnchen-Unterkeule",
        "Trommelstock": "Unterkeule",
        "Carrorts": "Karotten",
        "puertoricanischen Stil": "puertoricanischer Art",
    }
    result = re.sub(r"\s+", " ", value).strip(" ,")
    for old, new in replacements.items():
        result = result.replace(old, new)
    return result


def finalize_german(source_name: str, translated: str) -> str:
    result = cleanup_german(translated)
    source_lower = source_name.lower()
    if "skin not eaten" in source_lower:
        result = re.sub(r"(?:nicht gegessene Haut|Haut nicht gegessen|nicht gegessen)", "ohne Haut", result)
    elif "skin eaten" in source_lower:
        result = re.sub(r"(?:gegessene Haut|Haut gegessen|gegessen)", "mit Haut", result)

    cake_flavors = {
        "chocolate": "Schokoladenkuchen",
        "banana": "Bananenkuchen",
        "apple": "Apfelkuchen",
        "carrot": "Karottenkuchen",
        "lemon": "Zitronenkuchen",
        "black forest": "Schwarzwälder Kirschtorte",
        "german chocolate": "Schokoladenkuchen",
        "pineapple": "Ananaskuchen",
        "strawberry": "Erdbeerkuchen",
        "cheese": "Käsekuchen",
    }
    if source_lower.startswith(("cake or cupcake, ", "cake, ", "snack cake, ")):
        for flavor, alias in cake_flavors.items():
            if re.search(r"\b" + re.escape(flavor) + r"\b", source_lower):
                return f"{alias} · {result}"
    return result


def load_translations(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    value = json.loads(path.read_text(encoding="utf-8"))
    return value if isinstance(value, dict) else {}


def save_translations(path: Path, translations: dict[str, str]) -> None:
    path.write_text(json.dumps(translations, ensure_ascii=False, sort_keys=True), encoding="utf-8")


def translate_names(names: list[str], cache_path: Path) -> dict[str, str]:
    import argostranslate.translate

    translations = {name: cleanup_german(value) for name, value in load_translations(cache_path).items()}
    missing = [name for name in names if name not in translations]
    for index, name in enumerate(missing, start=1):
        translated = argostranslate.translate.translate(translation_input(name), "en", "de")
        translations[name] = cleanup_german(translated)
        if index % 100 == 0:
            save_translations(cache_path, translations)
            print(f"TRANSLATED {index}/{len(missing)}", flush=True)
    save_translations(cache_path, translations)
    return translations


def finite_number(value: object, default: float = 0.0) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return number if math.isfinite(number) else default


def build_record(food: dict[str, object], name_de: str) -> dict[str, object] | None:
    nutrients = {
        int(item.get("nutrient", {}).get("id", -1)): finite_number(item.get("amount"))
        for item in food.get("foodNutrients", [])
        if isinstance(item, dict) and isinstance(item.get("nutrient"), dict)
    }
    if NUTRIENT_IDS["calories"] not in nutrients:
        return None

    values = {field: max(0.0, nutrients.get(nutrient_id, 0.0)) for field, nutrient_id in NUTRIENT_IDS.items()}
    values["salt"] = values.pop("salt_sodium") * 2.5 / 1000.0
    if values["calories"] > 900 or any(values[field] > 100 for field in values if field != "calories"):
        return None

    fdc_id = str(food.get("fdcId") or "").strip()
    source_name = str(food.get("description") or "").strip()
    if not fdc_id or not source_name or not name_de:
        return None
    category = food.get("wweiaFoodCategory") or {}
    category_name = str(category.get("wweiaFoodCategoryDescription") or "") if isinstance(category, dict) else ""
    fruit_text = f"{source_name} {category_name}".lower()
    is_fruit = any(word in fruit_text for word in ("fruit", "apple", "banana", "berry", "berries", "melon", "citrus", "peach", "pear", "pineapple"))
    source_id = f"USDA-FNDDS-{fdc_id}"
    return {
        "name": source_name,
        "source_name_en": source_name,
        "name_de": name_de,
        "brand": "",
        "barcode": "",
        "barcode_raw": "",
        "barcode_normalized": "",
        "unit": "g",
        "serving_size": 100.0,
        "calories": round(values["calories"], 4),
        "carbs": round(values["carbs"], 4),
        "protein": round(values["protein"], 4),
        "fat": round(values["fat"], 4),
        "sugar": round(values["sugar"], 4),
        "fiber": round(values["fiber"], 4),
        "saturated_fat": round(values["saturated_fat"], 4),
        "salt": round(values["salt"], 4),
        "creator": "",
        "source": "usda_fdc",
        "moderation_status": "approved",
        "source_id": source_id,
        "data_source": "USDA FoodData Central, FNDDS 2021–2023",
        "source_note": f"USDA food code {food.get('foodCode', '')}; German name translated locally; nutrients unchanged",
        "data_date": "2024-10-31",
        "reference_amount": 100.0,
        "reference_unit": "g",
        "average_values": True,
        "normalized_key": f"usda_fndds|{fdc_id}",
        "off_de_catalog_rank": 0,
        "off_unique_scans": 0,
        "off_popularity_period": 0,
        "is_fruit": is_fruit,
    }


def main() -> int:
    args = parse_args()
    root = json.loads(args.source.read_text(encoding="utf-8"))
    foods = root.get("SurveyFoods") if isinstance(root, dict) else None
    if not isinstance(foods, list) or len(foods) < 5_000:
        raise SystemExit("Expected at least 5000 FNDDS survey foods")
    names = [str(food.get("description") or "").strip() for food in foods if isinstance(food, dict)]
    translations = translate_names([name for name in names if name], args.translation_cache)
    records = [record for food in foods if isinstance(food, dict)
               if (record := build_record(
                   food,
                   finalize_german(
                       str(food.get("description") or "").strip(),
                       translations.get(str(food.get("description") or "").strip(), ""),
                   ),
               )) is not None]
    if len(records) < 5_000:
        raise SystemExit(f"Only {len(records)} valid FNDDS records")
    if len({record["normalized_key"] for record in records}) != len(records):
        raise SystemExit("Duplicate FNDDS identities")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(args.output, "wt", encoding="utf-8", compresslevel=9) as handle:
        json.dump(records, handle, ensure_ascii=False, separators=(",", ":"))
    print(f"WROTE {len(records)} records to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
