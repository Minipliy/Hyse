#!/usr/bin/env python3
"""Contract tests for the automatic global food catalogue workflow."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
HOOK = (ROOT / "pb_hooks/global_food_submissions.pb.js").read_text(encoding="utf-8")
HELPERS = (ROOT / "pb_hooks/global_food_submission_helpers.js").read_text(encoding="utf-8")
MIGRATION = (ROOT / "pb_migrations/1787751100_submission_only_global_foods.js").read_text(encoding="utf-8")
INDEX_MIGRATION = (ROOT / "pb_migrations/1787751250_food_submission_indexes.js").read_text(encoding="utf-8")
RESOLVER = (ROOT / "pb_hooks/global_food_resolver.pb.js").read_text(encoding="utf-8")
FOOD_STORE = (ROOT / "CalorieTrackerApp/FoodStore.swift").read_text(encoding="utf-8")
CREATE_FOOD = (ROOT / "CalorieTrackerApp/CreateFoodView.swift").read_text(encoding="utf-8")


def route_body(path: str, following_path: str) -> str:
    start = HOOK.index(f'routerAdd("POST", "{path}"')
    end = HOOK.index(f'routerAdd("POST", "{following_path}"', start)
    return HOOK[start:end]


class SubmissionOnlyFlowTests(unittest.TestCase):
    def test_new_food_is_published_and_linked_immediately(self):
        body = route_body("/api/hyse/global-foods/submit-new", "/api/hyse/global-foods/submit-change")
        self.assertIn('new Record(dao.findCollectionByNameOrId("global_foods"))', body)
        self.assertIn('submission.set("status", "approved")', body)
        self.assertIn('personal.set("global_food", target.id)', body)
        self.assertIn('global_food: target.id', body)

    def test_obsolete_resolver_is_fail_closed(self):
        self.assertIn("never create a global catalogue row directly", RESOLVER)
        self.assertNotIn("saveRecord", RESOLVER)

    def test_legacy_review_remains_admin_only(self):
        self.assertIn("$apis.requireAdminAuth()", HOOK)
        self.assertIn('action === "reject" && !reason', HOOK)
        self.assertIn('action === "approve" ? "approved" : "rejected"', HOOK)

    def test_approval_deduplicates_before_creating(self):
        self.assertIn("barcode_normalized = {:barcode}", HOOK)
        self.assertIn("normalized_key = {:key}", HOOK)
        self.assertIn("duplicate = !!target", HOOK)
        self.assertIn('if (!target) target = new Record(txDao.findCollectionByNameOrId("global_foods"))', HOOK)

    def test_catalogue_rules_hide_unapproved_user_records(self):
        rule = 'moderation_status = "approved" || (moderation_status = "" && creator = "")'
        self.assertGreaterEqual(MIGRATION.count(rule), 1)
        self.assertIn("globals.createRule = null", MIGRATION)

    def test_legacy_migration_is_repeat_safe_and_audited(self):
        self.assertIn("if (existingAudit) continue", MIGRATION)
        self.assertIn("migration_origin = {:origin}", MIGRATION)
        self.assertIn("global_food_migration_audit", MIGRATION)
        self.assertIn("Original global record retained unchanged", MIGRATION)
        self.assertNotRegex(MIGRATION.split("}, (db) =>", 1)[0], r"deleteRecord\(global\)")

    def test_pending_creation_uniqueness_is_scoped_to_personal_food(self):
        self.assertIn("idx_global_submission_pending_create", INDEX_MIGRATION)
        self.assertIn("personal_food_client_id", INDEX_MIGRATION)
        self.assertIn("idx_global_submission_pending_update", INDEX_MIGRATION)

    def test_new_user_foods_are_always_queued_for_catalogue_submission(self):
        self.assertIn("saved.globalSubmissionPending = authManager?.isLoggedIn == true", FOOD_STORE)
        self.assertIn("addFoodResolvingGlobal(item)", CREATE_FOOD)
        self.assertNotIn("submitGlobally", CREATE_FOOD)

    def test_changes_publish_fruit_classification_immediately(self):
        body = route_body("/api/hyse/global-foods/submit-change", "/api/hyse/global-foods/submissions/:id/review")
        self.assertIn('source.set("moderation_status", "approved")', body)
        self.assertIn('global_food: source.id', body)
        self.assertIn('"is_fruit"', HELPERS)
        self.assertNotIn("Only the creator can submit a change", body)

    def test_each_route_loads_helpers_inside_its_isolated_callback(self):
        self.assertEqual(HOOK.count('require(`${__hooks}/global_food_submission_helpers.js`)'), 3)
        self.assertNotRegex(HOOK, r"const hyseRevision|function hyseRevision")

    def test_global_food_client_decodes_fruit_flag(self):
        service = (ROOT / "CalorieTrackerApp/GlobalFoodService.swift").read_text(encoding="utf-8")
        self.assertIn('case isFruit = "is_fruit"', service)
        self.assertIn('isFruit: remote.isFruit ?? false', service)

    def test_legacy_user_foods_are_repaired_after_account_activation(self):
        self.assertIn("queuedLegacySubmission", FOOD_STORE)
        self.assertIn("!Self.bundledDefaultFingerprints.contains", FOOD_STORE)
        self.assertIn("retryPendingGlobalSubmissions()", FOOD_STORE)


if __name__ == "__main__":
    unittest.main()
