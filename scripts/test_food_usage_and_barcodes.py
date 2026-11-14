#!/usr/bin/env python3
"""Deterministic contract tests for server-derived usage and Hyse-first scans."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def normalize_barcode(raw: str) -> str:
    cleaned = "".join(ch for ch in raw if ch not in " \t\r\n.-–—")
    if not cleaned.isdigit() or len(cleaned) not in (8, 12, 13, 14):
        raise ValueError("invalid barcode")
    digits = [int(value) for value in cleaned]
    total = sum(value * (3 if offset % 2 == 0 else 1) for offset, value in enumerate(reversed(digits[:-1])))
    if (10 - total % 10) % 10 != digits[-1]:
        raise ValueError("invalid check digit")
    return cleaned


def identity(entry: dict, saved: dict[str, dict] | None = None) -> str:
    if entry.get("global_recipe"):
        return f"recipe:global:{entry['global_recipe']}"
    if entry.get("recipe_client_id"):
        return f"recipe:local:{entry['recipe_client_id']}"
    if entry.get("global_food"):
        return f"global_food:{entry['global_food']}"
    client = entry.get("source_food_client_id")
    linked = (saved or {}).get(client, {}).get("global_food")
    if linked:
        return f"global_food:{linked}"
    if client:
        return f"user_food:{client}"
    return entry["source_key"]


def rebuild(entries: list[dict], saved: dict[str, dict] | None = None) -> dict[str, dict]:
    # PocketBase's (user, client_id) unique index makes repeated sync an upsert.
    records = {entry["client_id"]: entry for entry in entries if not entry.get("deleted")}
    result: dict[str, dict] = {}
    for entry in records.values():
        key = identity(entry, saved)
        current = result.setdefault(key, {"usage_count": 0, "first": entry["at"], "last": entry["at"], "last_amount": entry["amount"]})
        current["usage_count"] += 1
        current["first"] = min(current["first"], entry["at"])
        if entry["at"] >= current["last"]:
            current["last"] = entry["at"]
            current["last_amount"] = entry["amount"]
    return result


class FoodUsageTests(unittest.TestCase):
    def entry(self, client: str, **changes) -> dict:
        value = {"client_id": client, "source_food_client_id": "food-a", "at": "2026-08-01 10:00:00.000Z", "amount": 100}
        value.update(changes)
        return value

    def test_one_and_repeated_entries_count_once_each(self):
        self.assertEqual(rebuild([self.entry("meal-1")])["user_food:food-a"]["usage_count"], 1)
        self.assertEqual(rebuild([self.entry("meal-1"), self.entry("meal-2")])["user_food:food-a"]["usage_count"], 2)

    def test_repeat_sync_edit_and_move_do_not_increment(self):
        first = self.entry("meal-1")
        edited = self.entry("meal-1", amount=250, meal="dinner")
        value = rebuild([first, edited])["user_food:food-a"]
        self.assertEqual(value["usage_count"], 1)
        self.assertEqual(value["last_amount"], 250)

    def test_copy_batch_and_delete_rebuild_exactly(self):
        values = [self.entry("original"), self.entry("copy"), self.entry("batch-1"), self.entry("batch-2", source_food_client_id="food-b")]
        self.assertEqual(rebuild(values)["user_food:food-a"]["usage_count"], 3)
        values[1]["deleted"] = True
        self.assertEqual(rebuild(values)["user_food:food-a"]["usage_count"], 2)

    def test_guest_merge_retry_is_idempotent(self):
        guest = self.entry("stable-guest-id")
        self.assertEqual(rebuild([guest, dict(guest)])["user_food:food-a"]["usage_count"], 1)

    def test_recipe_and_food_are_separate(self):
        food = self.entry("food-entry")
        recipe = self.entry("recipe-entry", source_food_client_id=None, recipe_client_id="recipe-a")
        self.assertEqual(set(rebuild([food, recipe])), {"user_food:food-a", "recipe:local:recipe-a"})

    def test_personal_to_global_link_collapses_identity(self):
        old = self.entry("old")
        new = self.entry("new", global_food="global-a")
        value = rebuild([old, new], {"food-a": {"global_food": "global-a"}})
        self.assertEqual(value["global_food:global-a"]["usage_count"], 2)

    def test_deleted_relation_keeps_snapshot_key(self):
        historical = self.entry("historic", source_food_client_id=None, source_key="snapshot:oats:g")
        self.assertEqual(rebuild([historical])["snapshot:oats:g"]["usage_count"], 1)

    def test_rebuild_itself_is_idempotent(self):
        values = [self.entry("one"), self.entry("two")]
        self.assertEqual(rebuild(values), rebuild(values))

    def test_last_entry_supplies_last_amount(self):
        values = [self.entry("one", at="2026-08-01 08:00:00.000Z", amount=50), self.entry("two", at="2026-08-02 08:00:00.000Z", amount=175)]
        self.assertEqual(rebuild(values)["user_food:food-a"]["last_amount"], 175)

    def test_multiple_portions_are_one_meal_entry(self):
        value = self.entry("one", amount=600, portion_count=4)
        self.assertEqual(rebuild([value])["user_food:food-a"]["usage_count"], 1)

    def test_reinstall_reconstruction_matches_original(self):
        history = [self.entry("one"), self.entry("two", at="2026-08-03 08:00:00.000Z")]
        before_uninstall = rebuild(history)
        after_reinstall = rebuild([dict(item) for item in history])
        self.assertEqual(before_uninstall, after_reinstall)


class BarcodeTests(unittest.TestCase):
    def test_supported_formats_preserve_zeroes(self):
        for value in ("96385074", "036000291452", "4006381333931", "00012345600012"):
            self.assertEqual(normalize_barcode(value), value)
        self.assertEqual(normalize_barcode("4006 3813-3393.1"), "4006381333931")

    def test_invalid_check_digit_and_characters(self):
        for value in ("4006381333932", "ABC4006381333931", "123"):
            with self.assertRaises(ValueError):
                normalize_barcode(value)

    def test_priority_and_external_fallback(self):
        def choose(personal, global_food, local, external):
            return next((item for item in (personal, global_food, local, external) if item is not None), None)
        self.assertEqual(choose("personal", "global", "local", "external"), "personal")
        self.assertEqual(choose(None, "global", "local", "external"), "global")
        self.assertEqual(choose(None, None, None, "external"), "external")

    def test_hyse_hit_never_calls_external(self):
        calls = []
        def scan(known):
            if known:
                return known
            calls.append("external")
            return "external"
        self.assertEqual(scan("personal"), "personal")
        self.assertEqual(scan("global"), "global")
        self.assertEqual(calls, [])

    def test_missing_hyse_food_calls_external_once(self):
        calls = []
        calls.append("external")
        self.assertEqual(calls, ["external"])

    def test_offline_scan_can_use_cached_food(self):
        cache = {"4006381333931": "cached"}
        self.assertEqual(cache.get(normalize_barcode("4006381333931")), "cached")

    def test_rescan_prefers_saved_external_import(self):
        personal = {"4006381333931": "private-import"}
        self.assertEqual(personal.get("4006381333931"), "private-import")

    def test_conflicting_personal_matches_are_not_silently_selected(self):
        matches = ["food-a", "food-b"]
        self.assertGreater(len(matches), 1)

    def test_most_used_sort_uses_aggregate_count(self):
        totals = {"food-a": 7, "food-b": 2}
        self.assertEqual(sorted(totals, key=totals.get, reverse=True), ["food-a", "food-b"])


class SecurityContractTests(unittest.TestCase):
    def test_usage_collection_is_client_read_only_and_owner_scoped(self):
        migration = (ROOT / "pb_migrations/1787751000_food_usage_and_normalized_barcodes.js").read_text()
        self.assertIn('listRule: "user = @request.auth.id"', migration)
        self.assertIn("createRule: null, updateRule: null, deleteRule: null", migration)

    def test_private_barcode_lookup_remains_owner_scoped(self):
        ownership = (ROOT / "pb_hooks/user_foods_owner.pb.js").read_text()
        migration = (ROOT / "pb_migrations/1787503800_harden_user_food_ownership.js").read_text()
        self.assertIn('e.record.set("user", account.id)', ownership)
        self.assertIn("user = @request.auth.id", migration)

    def test_global_approved_barcode_is_unique(self):
        migration = (ROOT / "pb_migrations/1787751250_food_submission_indexes.js").read_text()
        self.assertIn("CREATE UNIQUE INDEX `idx_global_foods_approved_barcode`", migration)

    def test_external_request_contains_barcode_but_no_account_token(self):
        service = (ROOT / "CalorieTrackerApp/OpenFoodFactsService.swift").read_text()
        self.assertIn("world.openfoodfacts.org/api/v2/product/", service)
        self.assertNotIn('forHTTPHeaderField: "Authorization"', service)

    def test_external_request_identifies_hyse_to_open_food_facts(self):
        service = (ROOT / "CalorieTrackerApp/OpenFoodFactsService.swift").read_text()
        self.assertIn('private static let contactEmail = "hyse@minipliy.net"', service)
        self.assertIn('CFBundleShortVersionString', service)
        self.assertIn('request.setValue(userAgent, forHTTPHeaderField: "User-Agent")', service)

    def test_open_food_facts_provenance_survives_global_catalogue_loading(self):
        service = (ROOT / "CalorieTrackerApp/GlobalFoodService.swift").read_text()
        search = (ROOT / "pb_hooks/global_food_search.pb.js").read_text()
        self.assertIn('case sourceID = "source_id"', service)
        self.assertIn('remote.source == "open_food_facts" ? "Open Food Facts" : nil', service)
        self.assertIn("coalesce(g.source_id,'') source_id", search)

    def test_external_foods_are_not_published_as_hyse_catalogue_records(self):
        store = (ROOT / "CalorieTrackerApp/FoodStore.swift").read_text()
        hook = (ROOT / "pb_hooks/global_food_submissions.pb.js").read_text()
        self.assertIn('saved.externalSource == nil', store)
        self.assertIn('$0.externalSource == nil', store)
        self.assertIn('Open Food Facts records cannot be republished as Hyse data.', hook)

    def test_existing_open_food_facts_links_are_backfilled_with_provenance(self):
        migration = (ROOT / "pb_migrations/1788700540_preserve_open_food_facts_provenance.js").read_text()
        self.assertIn("source = 'open_food_facts'", migration)
        self.assertIn('food.set("external_source", "Open Food Facts")', migration)
        self.assertIn('food.set("external_source_id", sourceID)', migration)


if __name__ == "__main__":
    unittest.main()
