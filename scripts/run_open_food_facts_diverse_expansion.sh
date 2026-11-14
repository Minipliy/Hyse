#!/bin/sh
set -eu

cd /root/Hyse
import_email="hyse-off-diverse-import@localhost.invalid"
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
  --max-new-products 1500000 \
  --variants-per-concept 3 \
  --samples-per-category 9 \
  --batch-size 200
