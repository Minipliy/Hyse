#!/usr/bin/env python3
"""Disposable production smoke test for authenticated Gemini food text parsing."""

from __future__ import annotations

import os
import secrets

from import_open_food_facts_de_catalog import authenticate, request_json


BASE = os.environ.get("HYSE_BASE_URL", "http://127.0.0.1:8090").rstrip("/")


def normalized_names(result: dict) -> list[str]:
    return [str(item.get("name") or "").lower() for item in result.get("items") or []]


def main() -> int:
    admin = authenticate(BASE)
    suffix = secrets.token_hex(6)
    email = f"hyse-gemini-text-smoke-{suffix}@localhost.invalid"
    password = secrets.token_urlsafe(24) + "A1!"
    user_id = ""
    try:
        user = request_json("POST", f"{BASE}/api/collections/users/records", {
            "email": email, "password": password, "passwordConfirm": password,
            "verified": True, "emailVisibility": False, "name": "Gemini Text Smoke Test",
        }, admin)
        user_id = str(user.get("id") or "")
        auth = request_json("POST", f"{BASE}/api/collections/users/auth-with-password", {
            "identity": email, "password": password,
        })
        token = str(auth.get("token") or "")

        first = request_json("POST", f"{BASE}/api/hyse/ai/food-text", {
            "text": "45g Proteinpulver\n1 Kiwi\n1 Nektarine", "locale": "de",
        }, token, timeout=60)
        names = normalized_names(first)
        assert len(names) == 3, names
        assert any("protein" in name for name in names), names
        assert any("kiwi" in name for name in names), names
        assert any("nektarine" in name for name in names), names
        protein = next(item for item in first["items"] if "protein" in item["name"].lower())
        assert protein["unit"] == "g" and abs(float(protein["amount"]) - 45) < 0.1, protein

        second = request_json("POST", f"{BASE}/api/hyse/ai/food-text", {
            "text": "2 oz chicken\n1 cup cooked rice\none apple", "locale": "en",
        }, token, timeout=60)
        names = normalized_names(second)
        assert len(names) == 3, names
        assert any("chicken" in name for name in names), names
        assert any("rice" in name for name in names), names
        assert any("apple" in name for name in names), names
        chicken = next(item for item in second["items"] if "chicken" in item["name"].lower())
        assert chicken["unit"] == "g" and 56 <= float(chicken["amount"]) <= 57.5, chicken
        assert first.get("free_tier_only") is True and second.get("free_tier_only") is True
        print("Gemini food-text smoke test passed in German and English with exact quantities and separate foods.")
        return 0
    finally:
        if user_id:
            try:
                request_json("DELETE", f"{BASE}/api/collections/users/records/{user_id}", token=admin)
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
