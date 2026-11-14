#!/usr/bin/env python3
"""Disposable live PocketBase test for the four independent food workflows.

Requires HYSE_E2E_ADMIN_EMAIL and HYSE_E2E_ADMIN_PASSWORD. It creates one
verified temporary user, authenticates as that user, exercises saved food,
meal entry, global brand/catalogue submission, portions, favorite and consent,
then deletes the account through Hyse's account-deletion route.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = os.environ.get("HYSE_TEST_BASE", "https://hyse.minipliy.net").rstrip("/")
ADMIN_EMAIL = os.environ["HYSE_E2E_ADMIN_EMAIL"]
ADMIN_PASSWORD = os.environ["HYSE_E2E_ADMIN_PASSWORD"]
RUN = uuid.uuid4().hex[:10]
USER_EMAIL = f"hyse-e2e-{RUN}@example.invalid"
USER_PASSWORD = f"HyseE2E{RUN}Password"


def request(method, path, payload=None, token=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        body = error.read().decode(errors="replace")
        raise RuntimeError(f"{method} {path} failed with {error.code}: {body[:500]}") from error


def main():
    _, admin = request("POST", "/api/admins/auth-with-password", {"identity": ADMIN_EMAIL, "password": ADMIN_PASSWORD})
    admin_token = admin["token"]
    _, user = request("POST", "/api/collections/users/records", {
        "email": USER_EMAIL, "emailVisibility": False, "verified": True,
        "password": USER_PASSWORD, "passwordConfirm": USER_PASSWORD,
        "name": "Hyse E2E"
    }, admin_token)
    try:
        _, auth = request("POST", "/api/collections/users/auth-with-password", {"identity": USER_EMAIL, "password": USER_PASSWORD})
        token = auth["token"]
        user_id = auth["record"]["id"]
        client_food = str(uuid.uuid4())
        client_entry = str(uuid.uuid4())
        client_portion = str(uuid.uuid4())

        _, brand = request("POST", "/api/hyse/brands", {"name": f"Hyse E2E Brand {RUN}"}, token)
        saved_payload = {
            "user": user_id, "record_type": "saved", "client_id": client_food,
            "name": f"E2E Food {RUN}", "brand": brand["name"], "brand_relation": brand["id"],
            "calories": 123, "carbs": 12, "protein": 8, "fat": 4, "sugar": 1,
            "fiber": 2, "saturated_fat": 0.5, "salt": 0.1, "barcode": "",
            "unit": "g", "serving_size": 75, "is_favorite": False, "is_fruit": False
        }
        _, saved = request("POST", "/api/collections/user_foods/records", saved_payload, token)
        _, portion = request("POST", "/api/collections/food_portions/records", {
            "owner": user_id, "user_food": saved["id"], "client_id": client_portion,
            "custom_name": "Test bowl", "amount": 75, "unit": "g", "sort_order": 0,
            "is_default": True, "status": "private"
        }, token)
        _, updated_portion = request("PATCH", f"/api/collections/food_portions/records/{portion['id']}", {
            "amount": 80, "custom_name": "Updated test bowl"
        }, token)
        _, submission = request("POST", "/api/hyse/global-foods/submit-new", {
            "client_id": client_food,
            "name": saved_payload["name"], "brand": brand["name"], "brand_id": brand["id"],
            "barcode": "", "unit": "g", "serving_size": 75, "calories": 123,
            "carbs": 12, "protein": 8, "fat": 4, "sugar": 1, "fiber": 2,
            "saturated_fat": 0.5, "salt": 0.1, "is_fruit": False
        }, token)
        global_food_id = submission["global_food"]
        request("PATCH", f"/api/collections/user_foods/records/{saved['id']}", {"global_food": global_food_id}, token)
        request("POST", "/api/collections/user_favorites/records", {"user": user_id, "global_food": global_food_id}, token)
        request("POST", "/api/collections/user_foods/records", {
            "user": user_id, "record_type": "entry", "client_id": client_entry,
            "name": saved_payload["name"], "calories": 92.25, "carbs": 9, "protein": 6,
            "fat": 3, "sugar": 0.75, "fiber": 1.5, "saturated_fat": 0.375,
            "salt": 0.075, "amount": 75, "eaten_at": "2026-08-26T05:00:00.000Z",
            "meal": "breakfast", "meal_key": "breakfast", "local_day": "2026-08-26",
            "timezone_offset": 120, "category_id": str(uuid.uuid4()), "unit": "g",
            "kcal_per_100g": 123, "carbs_per_100g": 12, "protein_per_100g": 8,
            "fat_per_100g": 4, "added_sugar_per_100g": 1, "fruit_sugar_per_100g": 0,
            "fiber_per_100g": 2, "saturated_fat_per_100g": 0.5, "salt_per_100g": 0.1,
            "global_food": global_food_id, "portion_name": "Test bowl", "portion_count": 1
        }, token)
        request("POST", "/api/hyse/consents", {
            "installation_id": str(uuid.uuid4()), "language": "en", "source": "e2e_test",
            "receipts": [
                {"category": "terms", "granted": True, "document_version": "terms-2026-09-1"},
                {"category": "privacy_notice", "granted": True, "document_version": "privacy-2026-09-1"},
                {"category": "marketing_email", "granted": False, "document_version": "privacy-2026-09-1"}
            ]
        }, token)
        query = urllib.parse.quote('record_type = "saved" || record_type = "entry"')
        _, page = request("GET", f"/api/collections/user_foods/records?perPage=100&filter={query}", token=token)
        assert len(page["items"]) == 2
        assert portion["owner"] == user_id and portion["user_food"] == saved["id"]
        assert updated_portion["amount"] == 80 and updated_portion["owner"] == user_id
        assert submission["status"] == "approved" and global_food_id
        print("Food sync E2E passed: saved food, meal entry, automatic global publication, portion create/update, favorite and consent")
    finally:
        # This route also removes pending brand submissions and cascades all
        # account-owned records, validating account isolation/cleanup.
        try:
            if "token" in locals():
                request("DELETE", "/api/hyse/account", token=token)
            else:
                request("DELETE", f"/api/collections/users/records/{user['id']}", token=admin_token)
        except Exception as cleanup_error:
            print(f"Cleanup warning: {cleanup_error}", file=sys.stderr)
        try:
            if "global_food_id" in locals():
                request("DELETE", f"/api/collections/global_foods/records/{global_food_id}", token=admin_token)
        except Exception as cleanup_error:
            print(f"Global food cleanup warning: {cleanup_error}", file=sys.stderr)


if __name__ == "__main__":
    main()
