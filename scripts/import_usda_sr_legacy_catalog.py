#!/usr/bin/env python3
"""Validate and import the normalized USDA SR Legacy catalogue."""

from __future__ import annotations

import argparse
from pathlib import Path

from import_bls_catalog import import_foods, load_foods
from import_open_food_facts_de_catalog import log


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=Path, default=Path("pb_seeds/usda_sr_legacy_foods.json.gz"))
    parser.add_argument("--base-url", default="http://127.0.0.1:8090")
    parser.add_argument("--database", type=Path, default=Path("pb_data/data.db"))
    parser.add_argument("--max-database-bytes", type=int, default=1_950_000_000)
    parser.add_argument("--batch-size", type=int, default=200)
    args = parser.parse_args()
    foods = load_foods(args.seed, minimum_count=7_000)
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
