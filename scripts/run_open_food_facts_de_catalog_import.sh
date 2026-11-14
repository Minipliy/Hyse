#!/bin/sh
set -eu

cd /root/Hyse

import_email="hyse-off-import@localhost.invalid"
import_password="$(openssl rand -hex 32)"

cleanup() {
  docker exec pocketbase /pb/pocketbase admin delete "$import_email" >/dev/null 2>&1 || true
  unset HYSE_PB_ADMIN_EMAIL HYSE_PB_ADMIN_PASSWORD import_password
}
trap cleanup EXIT INT TERM

# Remove only a stale account reserved by this exact one-off importer.
docker exec pocketbase /pb/pocketbase admin delete "$import_email" >/dev/null 2>&1 || true
docker exec pocketbase /pb/pocketbase admin create "$import_email" "$import_password" >/dev/null

export HYSE_PB_ADMIN_EMAIL="$import_email"
export HYSE_PB_ADMIN_PASSWORD="$import_password"

python3 scripts/import_open_food_facts_de_catalog.py \
  --target 100000 \
  --base-url http://127.0.0.1:8090 \
  --pb-data /root/Hyse/pb_data \
  --max-bytes 950000000 \
  --batch-size 200
