#!/usr/bin/env python3
"""Create a small barcode-free homemade layer from imported OFF products."""

from __future__ import annotations

import argparse
import re
import sqlite3
import time
from pathlib import Path

from import_open_food_facts_de_catalog import authenticate, create_batch

NUTRIENTS = ("calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt")
DEFINITIONS = [
    ("bananenbrot", "Bananenbrot", "Banana bread", r"\b(bananenbrot|banana bread)\b", r"müsli|muesli|cookie|flapjack|gewürz|gewurz|backmischung|butter"),
    ("apfelkuchen", "Apfelkuchen", "Apple cake", r"\b(apfelkuchen|apple cake)\b", r"backmischung|aroma|joghurt|yogurt"),
    ("kaesekuchen", "Käsekuchen", "Cheesecake", r"\b(käsekuchen|kaesekuchen|cheesecake)\b", r"aroma|riegel|bar|joghurt|yogurt"),
    ("marmorkuchen", "Marmorkuchen", "Marble cake", r"\b(marmorkuchen|marble cake)\b", r"backmischung|aroma"),
    ("karottenkuchen", "Karottenkuchen", "Carrot cake", r"\b(karottenkuchen|möhrenkuchen|moehrenkuchen|carrot cake)\b", r"riegel|bar|porridge|müsli|muesli"),
    ("zitronenkuchen", "Zitronenkuchen", "Lemon cake", r"\b(zitronenkuchen|lemon cake)\b", r"backmischung|aroma|riegel|bar"),
    ("brownies", "Brownies", "Brownies", r"\bbrownie(s)?\b", r"protein|riegel|bar|eis|ice cream|backmischung"),
    ("muffins", "Muffins", "Muffins", r"\bmuffin(s)?\b", r"protein|backmischung|aroma"),
    ("pfannkuchen", "Pfannkuchen", "Pancakes", r"\b(pfannkuchen|pancake(s)?)\b", r"mix|mischung|sirup|syrup|protein"),
    ("waffeln", "Waffeln", "Waffles", r"\b(waffel(n)?|waffle(s)?)\b", r"mix|mischung|riegel|bar"),
    ("tomatensosse", "Tomatensoße", "Tomato sauce", r"\b(tomatensoße|tomatensosse|tomato sauce)\b", r"ketchup|pizza"),
    ("bolognese", "Bolognese-Soße", "Bolognese sauce", r"\b(bolognese)\b", r"gewürz|gewurz|fix|chips|pizza"),
    ("lasagne", "Lasagne", "Lasagne", r"\b(lasagne|lasagna)\b", r"chips|suppe|soup"),
    ("chili-con-carne", "Chili con Carne", "Chili con carne", r"\bchili con carne\b", r"gewürz|gewurz|fix|chips"),
    ("kartoffelsalat", "Kartoffelsalat", "Potato salad", r"\b(kartoffelsalat|potato salad)\b", r"gewürz|gewurz"),
    ("nudelsalat", "Nudelsalat", "Pasta salad", r"\b(nudelsalat|pasta salad)\b", r"gewürz|gewurz"),
    ("milchreis", "Milchreis", "Rice pudding", r"\b(milchreis|rice pudding)\b", r"pulver|powder|protein|riegel|bar"),
    ("griessbrei", "Grießbrei", "Semolina pudding", r"\b(grießbrei|griessbrei|semolina pudding)\b", r"pulver|powder"),
]


def robust_average(rows: list[sqlite3.Row]) -> dict[str, float]:
    result = {}
    for field in NUTRIENTS:
        values = sorted(float(row[field]) for row in rows if row[field] is not None and 0 <= float(row[field]) <= (900 if field == "calories" else 100))
        if not values:
            result[field] = 0
            continue
        trim = max(0, len(values) // 10)
        selected = values[trim:len(values) - trim] if trim and len(values) - 2 * trim >= 3 else values
        result[field] = round(sum(selected) / len(selected), 3)
    return result


def build_payloads(database: Path, date: str) -> list[dict[str, object]]:
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    rows = connection.execute(
        "select name,name_de,barcode_normalized," + ",".join(NUTRIENTS) +
        " from global_foods where source='open_food_facts' and barcode_normalized != ''"
    ).fetchall()
    payloads = []
    for slug, name_de, name_en, include, exclude in DEFINITIONS:
        include_re = re.compile(include, re.I)
        exclude_re = re.compile(exclude, re.I)
        matches = []
        seen = set()
        for row in rows:
            text = f"{row['name_de'] or ''} {row['name'] or ''}"
            barcode = str(row["barcode_normalized"] or "")
            if barcode not in seen and include_re.search(text) and not exclude_re.search(text):
                seen.add(barcode)
                matches.append(row)
        if len(matches) < 3:
            continue
        nutrition = robust_average(matches)
        payload = {
            "name": f"Homemade {name_en} (average)", "source_name_en": name_en,
            "name_de": f"{name_de}, selbstgemacht (Durchschnitt)", "brand": "",
            "barcode": "", "barcode_raw": "", "barcode_normalized": "", "unit": "g", "serving_size": 100,
            "creator": "", "source": "open_food_facts", "moderation_status": "approved",
            "source_id": f"off-category:hyse-homemade-{slug}",
            "data_source": "Open Food Facts product aggregate (ODbL 1.0)",
            "source_note": f"Robust average of {len(matches)} matching OFF products; generic homemade entry without barcode.",
            "data_date": date, "reference_amount": 100, "reference_unit": "g", "average_values": True,
            "normalized_key": f"open_food_facts_category|hyse-homemade-{slug}",
            "off_unique_scans": 0, "off_popularity_period": "Germany latest OFF export", "is_fruit": False,
        }
        payload.update(nutrition)
        payloads.append(payload)
    return payloads


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=Path("pb_data/data.db"))
    parser.add_argument("--base-url", default="http://127.0.0.1:8090")
    args = parser.parse_args()
    payloads = build_payloads(args.database, time.strftime("%Y-%m-%d", time.gmtime()))
    token = authenticate(args.base_url)
    created = skipped = 0
    for offset in range(0, len(payloads), 200):
        added, ignored = create_batch(args.base_url, token, payloads[offset:offset + 200])
        created += added
        skipped += ignored
    print(f"DONE homemade_candidates={len(payloads)} created={created} skipped={skipped}")


if __name__ == "__main__":
    main()
