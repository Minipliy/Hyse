#!/usr/bin/env node
const assert = require("node:assert/strict")
const { render, load } = require("../pb_hooks/recipe_share_page.js")

const shareID = "abcdefghijklmno"
const globalID = "pqrstuvwxyzabcd"
const records = {
  recipe_shares: {
    [shareID]: {
      snapshot_json: { string: () => JSON.stringify({
        name: "Pasta <script>alert(1)</script>", description: "Schnell & lecker",
        servings: 2, minutes: 15, kcal: 420, protein: 24, carbs: 53, fat: 12,
        ingredients: [{ name: "Tomaten <img src=x>", amount: 200.5, unit: "g" }],
        steps: ["Alles kochen & servieren."]
      }) }, image: "recipe_photo.jpg"
    }
  },
  global_recipes: {
    [globalID]: {
      moderation_status: "approved", snapshot_json: { string: () => JSON.stringify({
        name: "Globales Rezept", recipeDescription: "Einfach", servings: 2,
        ingredients: [{ food: { name: "Hafer" }, grams: 100, unit: "g" }],
        preparationSteps: ["Verrühren"], preparationMinutes: 5
      }) }, calories: 500, protein: 20, carbs: 60, fat: 10
    },
    "zzzzzzzzzzzzzzz": { moderation_status: "superseded", snapshot_json: { name: "Hidden" } }
  }
}
global.$app = { dao: () => ({ findRecordById(collection, id) {
  const fields = records[collection]?.[id]
  if (!fields) throw new Error("not found")
  return { get: (key) => fields[key] }
} }) }
const context = (id) => ({ pathParam: () => id, html: (status, body) => ({ status, body }) })

const page = render(context(shareID), "de")
assert.equal(page.status, 200)
assert.match(page.body, /Zutaten/)
assert.match(page.body, /Alles kochen &amp; servieren/)
assert.match(page.body, /200,5 g/)
assert.match(page.body, /Hyse kostenlos laden/)
assert.match(page.body, /api\/files\/recipe_shares\/abcdefghijklmno\/recipe_photo.jpg/)
assert.doesNotMatch(page.body, /<script>alert\(1\)<\/script>/)
assert.doesNotMatch(page.body, /<img src=x>/)
assert.match(page.body, /hyseapp:\/\/recipe\/abcdefghijklmno/)
assert.match(page.body, /name="color-scheme" content="light dark"/)
assert.match(page.body, /prefers-color-scheme:dark/)
assert.match(page.body, /\.panel\{background:#19231d/)
assert.match(page.body, /\.nutrition span\{background:#1e3427/)

const globalPage = render(context(globalID), "en")
assert.equal(globalPage.status, 200)
assert.match(globalPage.body, /Globales Rezept/)
assert.match(globalPage.body, /250 kcal/)
assert.match(globalPage.body, /name="color-scheme" content="light dark"/)
assert.equal(load("zzzzzzzzzzzzzzz"), null)
assert.equal(render(context("short"), "de").status, 404)
console.log("Recipe share page rendering, escaping and approval checks passed.")
