#!/usr/bin/env python3
"""End-to-end check against an isolated PocketBase clone (never production)."""
import json
import secrets
import sqlite3
import sys
import urllib.error
import urllib.request


base, photo_path, isolated_db = sys.argv[1:4]
base = base.rstrip("/")
if not (base.startswith("http://127.0.0.1:") or base.startswith("http://localhost:")) or "validation" not in isolated_db:
    raise SystemExit("This test only runs against an isolated local PocketBase clone.")


def request(method, path, payload=None, token=None, content_type="application/json"):
    data = None if payload is None else (json.dumps(payload).encode() if content_type == "application/json" else payload)
    headers = {"Content-Type": content_type}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        with urllib.request.urlopen(urllib.request.Request(base + path, data=data, headers=headers, method=method), timeout=15) as response:
            return response.status, response.read(), response.headers
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.headers


password = "HyseTest-" + secrets.token_urlsafe(18)
email = f"routine-share-{secrets.token_hex(8)}@example.invalid"
status, body, _ = request("POST", "/api/collections/users/records", {
    "email": email, "password": password, "passwordConfirm": password
})
assert status == 200, ("create test account", status, body[:300])
owner = json.loads(body)["id"]
# The copied server requires email verification. Mark only this temporary
# account verified in the isolated database so the API can authenticate it.
with sqlite3.connect(isolated_db) as db:
    db.execute("UPDATE users SET verified = 1 WHERE id = ?", (owner,))
status, body, _ = request("POST", "/api/collections/users/auth-with-password", {"identity": email, "password": password})
assert status == 200, ("authenticate", status, body[:300])
token = json.loads(body)["token"]

snapshot = {"name": "Test Routine", "details": "Plan for two sets", "exercises": [{
    "nameKey": "barbell_bench_press", "englishName": "Bench Press", "germanName": "Bankdrücken",
    "type": "weight_reps", "equipment": "barbell", "primaryMuscles": ["chest"], "secondaryMuscles": ["triceps"],
    "notes": "Controlled", "restSeconds": 90,
    "sets": [{"type": "normal", "weightKilograms": 60, "reps": 8, "durationSeconds": 0,
              "distanceMeters": 0, "assistedKilograms": 0},
             {"type": "warmup", "weightKilograms": 30, "reps": 12, "durationSeconds": 0,
              "distanceMeters": 0, "assistedKilograms": 0}]
}]}
status, body, _ = request("POST", "/api/collections/routine_shares/records", {"owner": owner, "snapshot_json": snapshot})
assert status in (400, 401, 403), ("anonymous publishing", status, body[:300])
status, body, _ = request("POST", "/api/collections/routine_shares/records", {"owner": owner, "snapshot_json": snapshot}, token)
assert status == 200, ("publish routine", status, body[:300])
record_id = json.loads(body)["id"]

status, body, _ = request("GET", f"/api/hyse/public-routines/{record_id}")
assert status == 200 and json.loads(body)["snapshot_json"] == snapshot, ("public snapshot", status)
status, body, _ = request("GET", f"/de/routine/{record_id}")
assert status == 200 and b"Bankdr" in body and b"hyseapp://routine/" in body, ("German page", status)
status, body, _ = request("GET", f"/en/routine/{record_id}")
assert status == 200 and b"Bench Press" in body, ("English page", status)
snapshot["details"] = "Updated plan"
status, body, _ = request("PATCH", f"/api/collections/routine_shares/records/{record_id}", {"snapshot_json": snapshot}, token)
assert status == 200, ("update shared routine", status, body[:300])
status, body, _ = request("GET", f"/api/hyse/public-routines/{record_id}")
assert status == 200 and json.loads(body)["snapshot_json"]["details"] == "Updated plan", ("updated public snapshot", status)

with open(photo_path, "rb") as photo:
    image = photo.read()
boundary = "HyseRoutineTest" + secrets.token_hex(8)
multipart = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"routine.jpg\"\r\n"
             "Content-Type: image/jpeg\r\n\r\n").encode() + image + f"\r\n--{boundary}--\r\n".encode()
status, body, _ = request("PATCH", f"/api/collections/routine_shares/records/{record_id}", multipart, token, f"multipart/form-data; boundary={boundary}")
assert status == 200, ("upload photo", status, body[:300])
filename = json.loads(body)["image"]
assert filename
status, _, _ = request("GET", f"/api/files/routine_shares/{record_id}/{filename}")
assert status == 200, ("public photo", status)
status, body, _ = request("GET", f"/de/routine/{record_id}")
assert status == 200 and b"og:image" in body and filename.encode() in body, ("photo preview", status)
status, body, _ = request("PATCH", f"/api/collections/routine_shares/records/{record_id}", {"image": ""}, token)
assert status == 200 and json.loads(body)["image"] == "", ("remove photo", status, body[:300])
status, body, _ = request("GET", f"/de/routine/{record_id}")
assert status == 200 and b"og:image" not in body, ("removed photo preview", status)

status, _, _ = request("DELETE", f"/api/collections/routine_shares/records/{record_id}", token=token)
assert status == 204, ("revoke", status)
status, _, _ = request("GET", f"/api/hyse/public-routines/{record_id}")
assert status == 404, ("revoked link", status)
print("Routine share: authenticated publish/update, public DE/EN pages, photo upload/removal, revoke passed.")
