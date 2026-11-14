import gzip
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class FnddsCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with gzip.open(ROOT / "pb_seeds" / "fndds_2021_2023_foods.json.gz", "rt", encoding="utf-8") as handle:
            cls.foods = json.load(handle)

    def test_catalog_is_complete_and_deduplicated(self):
        self.assertGreaterEqual(len(self.foods), 5_000)
        self.assertEqual(len(self.foods), len({food["normalized_key"] for food in self.foods}))

    def test_records_are_approved_reference_foods(self):
        for food in self.foods:
            self.assertEqual(food["source"], "usda_fdc")
            self.assertEqual(food["moderation_status"], "approved")
            self.assertEqual(food["reference_amount"], 100.0)
            self.assertEqual(food["reference_unit"], "g")
            self.assertTrue(food["normalized_key"].startswith("usda_fndds|"))
            self.assertTrue(food["name_de"].strip())

    def test_expected_generic_dishes_exist(self):
        names = "\n".join(food["name_de"].lower() for food in self.foods)
        for expected in ("bananenkuchen", "schokoladenkuchen", "rindfleischeintopf", "kartoffelsalat"):
            self.assertIn(expected, names)

    def test_bulk_route_accepts_fndds_identity(self):
        hook = (ROOT / "pb_hooks" / "admin_off_catalog.pb.js").read_text(encoding="utf-8")
        self.assertIn('normalizedKey.startsWith("usda_fndds|")', hook)


if __name__ == "__main__":
    unittest.main()
