#!/bin/sh
set -eu

cd /root/Hyse
python3 - <<'PY'
import sqlite3

database = sqlite3.connect("file:/root/Hyse/pb_data/data.db?mode=ro", uri=True)
try:
    count = database.execute(
        "SELECT COUNT(*) FROM global_foods WHERE source_note = ?",
        ("Product listed for Germany by Open Food Facts; nutrition per 100 g/ml.",),
    ).fetchone()[0]
finally:
    database.close()
if count:
    raise SystemExit(f"This one-time OFF import already contains {count} products; stopping before duplicate variants are added.")
PY

import_email="hyse-off-100k-import@localhost.invalid"
import_password="$(openssl rand -hex 32)"

cleanup() {
  docker exec pocketbase /pb/pocketbase admin delete "$import_email" >/dev/null 2>&1 || true
  unset HYSE_PB_ADMIN_EMAIL HYSE_PB_ADMIN_PASSWORD import_password
}
trap cleanup EXIT INT TERM

docker exec pocketbase /pb/pocketbase admin delete "$import_email" >/dev/null 2>&1 || true
docker exec pocketbase /pb/pocketbase admin create "$import_email" "$import_password" >/dev/null
export HYSE_PB_ADMIN_EMAIL="$import_email"
export HYSE_PB_ADMIN_PASSWORD="$import_password"

python3 scripts/expand_open_food_facts_catalog.py \
  --base-url http://127.0.0.1:8090 \
  --database /root/Hyse/pb_data/data.db \
  --max-database-bytes 1800000000 \
  --packaged-stop-bytes 1650000000 \
  --max-new-products 100000 \
  --variants-per-concept 3 \
  --new-variants-per-concept 3 \
  --max-per-brand-concept 1 \
  --max-per-category 2000 \
  --max-per-brand 600 \
  --packaged-only \
  --batch-size 200
