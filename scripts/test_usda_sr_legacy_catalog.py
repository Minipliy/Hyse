import gzip
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class UsdaSrLegacyCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with gzip.open(ROOT / "pb_seeds" / "usda_sr_legacy_foods.json.gz", "rt", encoding="utf-8") as handle:
            cls.foods = json.load(handle)

    def test_catalog_is_large_and_deduplicated(self):
        self.assertGreaterEqual(len(self.foods), 7_000)
        self.assertEqual(len(self.foods), len({food["normalized_key"] for food in self.foods}))

    def test_records_keep_stable_usda_identity(self):
        for food in self.foods:
            self.assertTrue(food["normalized_key"].startswith("usda_sr_legacy|"))
            self.assertTrue(food["source_id"].startswith("USDA-FDC-"))
            self.assertEqual(food["moderation_status"], "approved")

    def test_banana_bread_has_usda_macros(self):
        food = next(food for food in self.foods if food["source_id"] == "USDA-FDC-174906")
        self.assertTrue(food["name_de"].startswith("Bananenbrot"))
        self.assertEqual(food["calories"], 326.0)
        self.assertEqual(food["carbs"], 54.6)
        self.assertEqual(food["protein"], 4.3)
        self.assertEqual(food["fat"], 10.5)

    def test_pineapple_cake_is_not_apple_cake(self):
        food = next(food for food in self.foods if food["source_id"] == "USDA-FDC-172703")
        self.assertNotIn("Apfelkuchen", food["name_de"])


if __name__ == "__main__":
    unittest.main()
