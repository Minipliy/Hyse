#!/usr/bin/env python3
"""Disposable live PocketBase recipe isolation/idempotency smoke test."""
import json
import os
import secrets
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = os.environ.get("HYSE_TEST_BASE", "https://hyse.minipliy.net")
ACCOUNT_FILE = "/tmp/hyse_recipe_e2e_accounts.json"


def request(method, path, body=None, token=None, expected=range(200, 300)):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            raw = response.read()
            if response.status not in expected:
                raise AssertionError(f"{method} {path}: unexpected status {response.status}")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        if error.code in expected:
            raw = error.read()
            return error.code, json.loads(raw) if raw else None
        raise AssertionError(f"{method} {path}: status {error.code}") from error


def register_account(label):
    suffix = uuid.uuid4().hex
    email = f"codex-recipe-{label}-{suffix}@minipliy.net"
    password = secrets.token_urlsafe(20) + "A1!"
    _, user = request("POST", "/api/collections/users/records", {
        "username": f"recipe_{label}_{suffix[:12]}", "email": email,
        "password": password, "passwordConfirm": password, "has_local_password": True,
    })
    return {"id": user["id"], "email": email, "password": password}


def authenticate(account):
    _, auth = request("POST", "/api/collections/users/auth-with-password", {
        "identity": account["email"], "password": account["password"],
    })
    return account["id"], auth["token"]


def cleanup(token):
    try:
        request("DELETE", "/api/hyse/account", token=token, expected=range(200, 300))
    except Exception:
        pass


def main():
    user1 = token1 = user2 = token2 = None
    try:
        if os.environ.get("HYSE_TEST_PREPARE") == "1":
            accounts = [register_account("owner"), register_account("other")]
            with open(ACCOUNT_FILE, "w", encoding="utf-8") as handle:
                json.dump(accounts, handle)
            os.chmod(ACCOUNT_FILE, 0o600)
            print("Prepared two disposable recipe test accounts.")
            return
        if os.path.exists(ACCOUNT_FILE):
            with open(ACCOUNT_FILE, encoding="utf-8") as handle:
                accounts = json.load(handle)
            user1, token1 = authenticate(accounts[0])
            user2, token2 = authenticate(accounts[1])
        else:
            user1, token1 = authenticate(register_account("owner"))
        client_id = str(uuid.uuid4())
        food_id = str(uuid.uuid4())
        snapshot = {
            "id": client_id, "name": "PocketBase E2E Bowl", "recipeDescription": "Test snapshot",
            "ingredients": [{
                "id": str(uuid.uuid4()), "grams": 200, "unit": "g",
                "food": {"id": food_id, "name": "E2E Ingredient", "kcalPer100g": 50,
                         "carbsPer100g": 8, "proteinPer100g": 2, "fatPer100g": 1,
                         "sugarPer100g": 1, "fiberPer100g": 2, "saturatedFatPer100g": 0.2,
                         "saltPer100g": 0.1, "isFavorite": False, "unit": "g", "isFruit": False},
            }],
            "servings": 2, "isFavorite": False, "filters": [], "createdAt": 0, "updatedAt": 0,
            "syncStatus": "pending_sync", "origin": "personal", "preparationSteps": [], "tags": [],
        }
        payload = {
            "user": "invalid-owner", "client_id": client_id, "name": snapshot["name"],
            "description": "Test snapshot", "ingredients": [], "servings": 2,
            "total_weight_grams": 200, "preparation_steps": [], "preparation_minutes": 5,
            "tags": ["e2e"], "filters": [], "is_favorite": False,
            "calories": 100, "carbs": 16, "protein": 4, "fat": 2, "sugar": 2,
            "fiber": 4, "saturated_fat": 0.4, "salt": 0.2,
            "created_at_local": "2026-08-24T20:00:00Z", "updated_at_local": "2026-08-24T20:00:00Z",
            "snapshot_json": snapshot,
        }
        _, recipe = request("POST", "/api/collections/user_recipes/records", payload, token1)
        assert recipe["user"] == user1, "server did not enforce recipe owner"
        recipe_id = recipe["id"]

        payload["description"] = "Idempotent update"
        request("PATCH", f"/api/collections/user_recipes/records/{recipe_id}", payload, token1)
        _, page = request("GET", "/api/collections/user_recipes/records?perPage=100", token=token1)
        assert len(page["items"]) == 1, "idempotent update created a duplicate"

        meal_client_id = str(uuid.uuid4())
        _, meal = request("POST", "/api/collections/user_foods/records", {
            "user": user1, "record_type": "entry", "client_id": meal_client_id,
            "recipe_client_id": client_id, "name": snapshot["name"], "amount": 100,
            "eaten_at": "2026-08-24T20:00:00Z", "meal": "Lunch", "meal_key": "lunch",
            "local_day": "2026-08-24", "timezone_offset": 0, "category_id": str(uuid.uuid4()),
            "unit": "g", "calories": 50, "carbs": 8, "protein": 2, "fat": 1,
            "sugar": 1, "fiber": 2, "saturated_fat": 0.2, "salt": 0.1,
            "kcal_per_100g": 50, "carbs_per_100g": 8, "protein_per_100g": 2,
            "fat_per_100g": 1, "added_sugar_per_100g": 1, "fruit_sugar_per_100g": 0,
            "fiber_per_100g": 2, "saturated_fat_per_100g": 0.2, "salt_per_100g": 0.1,
        }, token1)
        assert meal.get("user_recipe") == recipe_id, "meal recipe relation was not resolved"

        _, submission = request("POST", "/api/hyse/global-recipes/submit", {
            "client_id": client_id, "snapshot_json": snapshot,
        }, token1)
        assert submission["status"] in ("pending", "approved")

        if not token2:
            user2, token2 = authenticate(register_account("other"))
        _, private_page = request("GET", "/api/collections/user_recipes/records?perPage=100", token=token2)
        assert private_page["items"] == [], "another user could list private recipes"
        request("GET", f"/api/collections/user_recipes/records/{recipe_id}", token=token2, expected={400, 403, 404})
        _, submissions = request("GET", "/api/collections/global_recipe_submissions/records?perPage=100", token=token2)
        assert submissions["items"] == [], "another user could list private submissions"
        print("Recipe PocketBase E2E passed: owner enforcement, idempotency, meal relation, submission and isolation.")
    finally:
        if token2:
            cleanup(token2)
        if token1:
            cleanup(token1)
        if os.path.exists(ACCOUNT_FILE):
            os.unlink(ACCOUNT_FILE)


if __name__ == "__main__":
    main()
