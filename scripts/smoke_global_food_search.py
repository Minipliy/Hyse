#!/usr/bin/env python3
"""Authenticated production smoke test for the bounded global food search."""

import os
import secrets
import time
import urllib.parse

from import_open_food_facts_de_catalog import authenticate, request_json

BASE = os.environ.get("HYSE_BASE_URL", "http://127.0.0.1:8090").rstrip("/")
admin = authenticate(BASE)
suffix = secrets.token_hex(6)
email = f"hyse-search-smoke-{suffix}@localhost.invalid"
password = secrets.token_urlsafe(24) + "A1!"
user_id = ""
try:
    user = request_json("POST", f"{BASE}/api/collections/users/records", {
        "email": email, "password": password, "passwordConfirm": password,
        "verified": True, "emailVisibility": False,
    }, admin)
    user_id = str(user.get("id") or "")
    auth = request_json("POST", f"{BASE}/api/collections/users/auth-with-password", {
        "identity": email, "password": password,
    })
    token = str(auth.get("token") or "")
    for query, expected in (("Bananenbrot", "bananenbrot"), ("Game Meat", "game meat")):
        started = time.monotonic()
        result = request_json("GET", f"{BASE}/api/hyse/global-foods/search?{urllib.parse.urlencode({'q': query})}", token=token)
        elapsed = time.monotonic() - started
        items = result.get("items") or []
        assert 1 <= len(items) <= 80
        assert any(expected in f"{item.get('name', '')} {item.get('name_de', '')}".lower() for item in items)
        assert elapsed < 4, f"Search for {query!r} was too slow: {elapsed:.2f}s"
        first = items[0]
        assert isinstance(first.get("is_fruit"), bool), f"is_fruit must be JSON boolean, got {type(first.get('is_fruit')).__name__}"
        print(f"Global food search for {query!r} passed ({len(items)} results, {elapsed:.2f}s).")
finally:
    if user_id:
        try:
            request_json("DELETE", f"{BASE}/api/collections/users/records/{user_id}", token=admin)
        except Exception:
            pass
