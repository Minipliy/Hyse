#!/usr/bin/env node
const assert = require("node:assert/strict")
const { render, load } = require("../pb_hooks/routine_share_page.js")

const id = "abcdefghijklmno"
global.$app = { dao: () => ({ findRecordById(collection, recordID) {
    assert.equal(collection, "routine_shares")
    if (recordID !== id) throw new Error("Not found")
    const fields = {
        snapshot_json: { string: () => JSON.stringify({
            name: "Kraft <script>alert(1)</script>",
            details: "Ganzkörper & mehr",
            exercises: [{
                englishName: "Bench <img src=x>", germanName: "Bankdrücken",
                type: "weight_reps", notes: "Langsam & kontrolliert",
                restSeconds: 90,
                sets: [{ type: "normal", weightKilograms: 60.5, reps: 8 }]
            }]
        }) },
        image: "routine.jpg"
    }
    return { get: (key) => fields[key] }
} }) }
const context = (recordID) => ({ pathParam: () => recordID, html: (status, body) => ({ status, body }) })

const de = render(context(id), "de")
assert.equal(de.status, 200)
assert.match(de.body, /Bankdrücken/)
assert.match(de.body, /60,5 kg/)
assert.match(de.body, /Langsam &amp; kontrolliert/)
assert.match(de.body, /api\/files\/routine_shares\/abcdefghijklmno\/routine.jpg/)
assert.match(de.body, /hyseapp:\/\/routine\/abcdefghijklmno/)
assert.match(de.body, /name="color-scheme" content="light dark"/)
assert.match(de.body, /prefers-color-scheme:dark/)
assert.match(de.body, /\.exercise\{background:#19231d/)
assert.doesNotMatch(de.body, /<script>alert\(1\)<\/script>/)
const en = render(context(id), "en")
assert.match(en.body, /Bench &lt;img src=x&gt;/)
assert.equal(load("short"), null)
assert.equal(render(context("short"), "de").status, 404)
console.log("Routine share page rendering, escaping and link checks passed.")
