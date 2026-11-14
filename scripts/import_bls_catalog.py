#!/usr/bin/env python3
"""Import the official BLS 4.0 catalogue and documented gap foods.

The normalized, compressed seed is committed with the project so production
doesn't depend on spreadsheet libraries or a third-party download being
available during deployment. Re-running this importer is safe: PocketBase
deduplicates records by their stable ``normalized_key``.
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
from pathlib import Path

from import_open_food_facts_de_catalog import authenticate, create_batch, log


NUTRIENTS = ("calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt")


def load_foods(path: Path, minimum_count: int = 7_000) -> list[dict[str, object]]:
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, list) or len(value) < minimum_count:
        raise RuntimeError(f"Expected at least {minimum_count} reference foods, found {len(value) if isinstance(value, list) else 0}")

    identities: set[str] = set()
    for index, food in enumerate(value, start=1):
        if not isinstance(food, dict):
            raise RuntimeError(f"Food {index} is not an object")
        identity = str(food.get("normalized_key") or "")
        if not identity or identity in identities:
            raise RuntimeError(f"Missing or duplicate identity at food {index}: {identity!r}")
        identities.add(identity)
        if not str(food.get("name_de") or "").strip():
            raise RuntimeError(f"Missing German name at food {index}")
        for nutrient in NUTRIENTS:
            raw = food.get(nutrient)
            if isinstance(raw, bool) or not isinstance(raw, (int, float)) or not math.isfinite(float(raw)):
                raise RuntimeError(f"Invalid {nutrient} at food {index}")
            maximum = 900 if nutrient == "calories" else 100
            if not 0 <= float(raw) <= maximum:
                raise RuntimeError(f"Out-of-range {nutrient} at food {index}: {raw}")
    return value


def import_foods(foods: list[dict[str, object]], base_url: str, database: Path,
                 max_database_bytes: int, batch_size: int) -> tuple[int, int, int]:
    token = authenticate(base_url)
    created = skipped = failed = 0
    for offset in range(0, len(foods), batch_size):
        if database.exists() and database.stat().st_size >= max_database_bytes:
            log(f"STOP reason=storage-limit database={database.stat().st_size} limit={max_database_bytes}")
            break
        chunk = foods[offset:offset + batch_size]
        try:
            added, skipped_now = create_batch(base_url, token, chunk)
            created += added
            skipped += skipped_now
        except Exception as batch_error:
            log(f"BATCH_ERROR offset={offset} count={len(chunk)} detail={batch_error}")
            for food in chunk:
                try:
                    added, skipped_now = create_batch(base_url, token, [food])
                    created += added
                    skipped += skipped_now
                except Exception as row_error:
                    failed += 1
                    log(f"ERROR key={food.get('normalized_key')} detail={row_error}")
        log(f"IMPORT created={created} skipped={skipped} failed={failed} processed={min(offset + len(chunk), len(foods))}/{len(foods)}")
        if failed >= 25 and failed * 20 > max(1, created):
            log("STOP reason=excessive-errors")
            break
    return created, skipped, failed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=Path, default=Path("pb_seeds/bls_4_0_foods.json.gz"))
    parser.add_argument("--base-url", default="http://127.0.0.1:8090")
    parser.add_argument("--database", type=Path, default=Path("pb_data/data.db"))
    parser.add_argument("--max-database-bytes", type=int, default=1_950_000_000)
    parser.add_argument("--batch-size", type=int, default=200)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 1 <= args.batch_size <= 250:
        raise SystemExit("--batch-size must be between 1 and 250")
    foods = load_foods(args.seed)
    log(f"VALIDATED count={len(foods)}")
    created, skipped, failed = import_foods(
        foods, args.base_url.rstrip("/"), args.database, args.max_database_bytes, args.batch_size
    )
    database_size = args.database.stat().st_size if args.database.exists() else 0
    log(f"DONE selected={len(foods)} created={created} skipped={skipped} failed={failed} database={database_size}")
    return 0 if failed == 0 and created + skipped == len(foods) else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        log("STOP reason=interrupted")
        raise SystemExit(130)
    except Exception as error:
        log(f"FATAL {error}")
        raise SystemExit(1)
