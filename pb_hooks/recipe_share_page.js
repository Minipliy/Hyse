const STORE = "https://apps.apple.com/de/app/hyse/id6811359623"
const adaptiveStyles = `:root{color-scheme:light dark}@media(prefers-color-scheme:dark){body{background:#0b100e;color:#edf4ef}.top{background:#111a16;border-color:#2b3a31}.top .download{color:#8bd5a2}.panel{background:#19231d;border-color:#35463a}.ingredients li{border-color:#35463a}.ingredients strong{color:#a2edb7}.step-number{background:#254531;color:#a2edb7}.nutrition span{background:#1e3427;color:#bfd0c1}.nutrition strong{color:#b7efc8}.cta{background:#1a3022}.cta p{color:#bfd0c1}.button.secondary{background:#243a2b;color:#b7efc8;border-color:#597b61}.footer,.footer a{color:#a9bbad}.mobile-cta{background:#111a16;border-color:#35463a}}`

const escape = (value) => String(value == null ? "" : value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
})[char])
const amount = (value, language) => {
    const number = Number(value)
    if (!Number.isFinite(number) || number < 0) return "0"
    const rounded = String(Math.round(number * 10) / 10)
    return language === "de" ? rounded.replace(".", ",") : rounded
}
const text = (value, max = 4000) => String(value == null ? "" : value).trim().slice(0, max)
const snapshot = (value) => {
    try {
        if (value && typeof value.string === "function") value = value.string()
        if (typeof value === "string") value = JSON.parse(value)
    } catch (_) { return {} }
    return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function load(id) {
    if (!/^[a-zA-Z0-9]{15}$/.test(id)) return null
    try {
        const record = $app.dao().findRecordById("recipe_shares", id)
        return { id, snapshot_json: snapshot(record.get("snapshot_json")), image: text(record.get("image"), 200), collection: "recipe_shares" }
    } catch (_) {}
    try {
        const record = $app.dao().findRecordById("global_recipes", id)
        if (String(record.get("moderation_status")) !== "approved") return null
        const recipe = snapshot(record.get("snapshot_json"))
        const servings = Number(recipe.servings) > 0 ? Number(recipe.servings) : 1
        const steps = Array.isArray(recipe.preparationSteps) ? recipe.preparationSteps : []
        const originalDescription = text(recipe.recipeDescription, 8000)
        const description = originalDescription === steps.join("\n").trim() ? "" : originalDescription
        const ingredients = Array.isArray(recipe.ingredients) ? recipe.ingredients.map((item) => ({
            name: item && item.food ? item.food.name : "", amount: item && item.grams, unit: item && item.unit
        })) : []
        return { id, image: "", collection: "global_recipes", snapshot_json: {
            name: text(recipe.name, 180), description,
            ingredients, steps,
            servings, minutes: recipe.preparationMinutes || null,
            kcal: Number(record.get("calories") || 0) / servings,
            protein: Number(record.get("protein") || 0) / servings,
            carbs: Number(record.get("carbs") || 0) / servings,
            fat: Number(record.get("fat") || 0) / servings
        } }
    } catch (_) { return null }
}

function render(c, language) {
    const de = language === "de"
    const formatAmount = (value) => amount(value, language)
    const id = String(c.pathParam("id") || "")
    const loaded = load(id)
    if (!loaded) return c.html(404, "Recipe not found")
    const recipe = loaded.snapshot_json
    const name = text(recipe.name, 180)
    if (!name) return c.html(404, "Recipe not found")
    const description = text(recipe.description, 8000)
    const ingredients = Array.isArray(recipe.ingredients) ? recipe.ingredients.slice(0, 100) : []
    const steps = Array.isArray(recipe.steps) ? recipe.steps.slice(0, 100).map((step) => text(step, 2000)).filter(Boolean) : []
    const imageFile = loaded.image
    const imageURL = /^[a-zA-Z0-9_.-]+$/.test(imageFile) && imageFile
        ? `${String((typeof $os !== "undefined" && $os.getenv("HYSE_PUBLIC_URL")) || "http://localhost:8090").replace(/\/+$/, "")}/api/files/recipe_shares/${id}/${encodeURIComponent(imageFile)}?thumb=1200x1200`
        : ""
    const webURL = `${String((typeof $os !== "undefined" && $os.getenv("HYSE_PUBLIC_URL")) || "http://localhost:8090").replace(/\/+$/, "")}/${de ? "de/rezept" : "en/recipe"}/${id}`
    const appURL = `hyseapp://recipe/${id}`
    const title = `${name} · Hyse`
    const summary = description.split(/\n/)[0].slice(0, 180) || (de ? "Zutaten und Zubereitung dieses Hyse-Rezepts ansehen." : "See the ingredients and method for this Hyse recipe.")
    const ingredientRows = ingredients.map((item) => {
        const food = text(item && item.name, 180)
        if (!food) return ""
        return `<li><span>${escape(food)}</span><strong>${escape(formatAmount(item.amount))} ${escape(text(item.unit, 12))}</strong></li>`
    }).join("")
    const stepRows = steps.map((step, index) => `<li><span class="step-number">${index + 1}</span><p>${escape(step).replace(/\n/g, "<br>")}</p></li>`).join("")
    const imageMarkup = imageURL
        ? `<img class="hero-image" src="${escape(imageURL)}" alt="${escape(name)}" loading="eager">`
        : `<div class="hero-placeholder" aria-hidden="true"><span>✦</span><span class="plate">◯</span><span>✦</span></div>`
    const schema = {
        "@context": "https://schema.org", "@type": "Recipe", name,
        description: description || summary, recipeYield: `${formatAmount(recipe.servings)} ${de ? "Portionen" : "servings"}`,
        recipeIngredient: ingredients.map((item) => `${formatAmount(item.amount)} ${text(item.unit, 12)} ${text(item.name, 180)}`),
        recipeInstructions: steps.map((step) => ({ "@type": "HowToStep", text: step })),
        url: webURL
    }
    if (imageURL) schema.image = imageURL
    if (Number(recipe.minutes) > 0) schema.totalTime = `PT${Math.round(Number(recipe.minutes))}M`
    const ld = JSON.stringify(schema).replace(/</g, "\\u003c")
    const html = `<!doctype html><html lang="${language}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,follow"><meta name="color-scheme" content="light dark"><meta name="theme-color" media="(prefers-color-scheme:light)" content="#f7f7f2"><meta name="theme-color" media="(prefers-color-scheme:dark)" content="#0b100e"><meta name="apple-itunes-app" content="app-id=6811359623"><title>${escape(title)}</title><meta name="description" content="${escape(summary)}"><link rel="canonical" href="${webURL}"><meta property="og:type" content="article"><meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(summary)}"><meta property="og:url" content="${webURL}">${imageURL ? `<meta property="og:image" content="${escape(imageURL)}">` : ""}<meta name="twitter:card" content="${imageURL ? "summary_large_image" : "summary"}"><script type="application/ld+json">${ld}</script><style>
*{box-sizing:border-box}body{margin:0;background:#f7f7f2;color:#17231d;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;line-height:1.55}a{color:inherit}.top{height:74px;display:flex;align-items:center;justify-content:space-between;gap:16px;padding:0 max(24px,calc((100vw - 1120px)/2));background:#fff;border-bottom:1px solid #e4e9e0}.brand{display:flex;align-items:center;gap:10px;text-decoration:none;font-size:22px;font-weight:800;letter-spacing:-.04em}.brand img{border-radius:11px}.top .download{font-size:14px;font-weight:700;text-decoration:none;color:#246447}.shell{max-width:1120px;margin:auto;padding:32px 24px 110px}.hero{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);border-radius:30px;overflow:hidden;background:#172d23;color:#fff;min-height:410px}.hero-media{min-height:360px}.hero-image{width:100%;height:100%;object-fit:cover;display:block}.hero-placeholder{height:100%;min-height:360px;background:radial-gradient(circle at 50% 48%,#d8d8a3 0 19%,#a4b780 19% 29%,#627b56 29% 30%,#2d513a 30% 100%);display:flex;align-items:center;justify-content:space-around;font-size:38px;color:#f4ddb6}.hero-placeholder .plate{font-size:250px;line-height:1;color:#f5f1d9}.hero-content{padding:clamp(28px,5vw,64px);display:flex;flex-direction:column;justify-content:center}.eyebrow{margin:0 0 18px;color:#b8d4aa;font-size:12px;font-weight:800;letter-spacing:.16em;text-transform:uppercase}h1{font-size:clamp(34px,4.5vw,60px);letter-spacing:-.055em;line-height:1.08;margin:0 0 22px;overflow-wrap:anywhere}.hero-description{font-size:17px;color:#e0e9df;white-space:pre-line;margin:0 0 24px}.facts{display:flex;flex-wrap:wrap;gap:8px}.facts span{border:1px solid #ffffff44;border-radius:99px;padding:7px 12px;font-size:13px;font-weight:600}.grid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.2fr);gap:24px;margin-top:24px}.panel{background:#fff;border:1px solid #e2e9dd;border-radius:26px;padding:clamp(22px,4vw,40px)}h2{margin:0 0 20px;font-size:27px;letter-spacing:-.035em}.ingredients{list-style:none;margin:0;padding:0}.ingredients li{display:flex;justify-content:space-between;gap:16px;padding:13px 0;border-bottom:1px solid #edf0ea}.ingredients li:last-child{border:0}.ingredients strong{white-space:nowrap;color:#2b6047}.steps{list-style:none;margin:0;padding:0}.steps li{display:flex;gap:16px;margin-bottom:22px}.steps li:last-child{margin:0}.step-number{flex:none;width:32px;height:32px;display:grid;place-items:center;background:#e2eee3;border-radius:50%;color:#22603f;font-size:14px;font-weight:800}.steps p{margin:2px 0;white-space:normal;overflow-wrap:anywhere}.nutrition{margin-top:24px;display:flex;flex-wrap:wrap;gap:8px}.nutrition span{background:#edf4ed;border-radius:12px;padding:10px 13px;color:#345442;font-size:13px}.nutrition strong{font-size:17px;color:#173e28}.cta{margin-top:24px;padding:28px 32px;border-radius:26px;background:#e3ecdc;display:flex;align-items:center;justify-content:space-between;gap:24px}.cta h2{margin:0 0 4px}.cta p{margin:0;color:#485a4b}.actions{display:flex;gap:10px;flex-wrap:wrap}.button{display:inline-block;padding:13px 18px;background:#256b45;color:#fff;text-decoration:none;font-weight:800;border-radius:12px;text-align:center;white-space:nowrap}.button.secondary{background:#fff;color:#256b45;border:1px solid #b2cbbb}.footer{max-width:1120px;margin:auto;padding:0 24px 40px;display:flex;gap:22px;color:#607065;font-size:13px}.footer a{color:#607065}.mobile-cta{display:none}@media(max-width:760px){.top{height:64px}.hero,.grid{grid-template-columns:1fr}.hero-media{min-height:230px;max-height:360px}.hero-image{max-height:360px}.hero-placeholder{min-height:230px}.hero-placeholder .plate{font-size:150px}.shell{padding:18px 14px 100px}.hero{border-radius:22px}.hero-content{padding:28px}.panel{border-radius:20px}.cta{display:block}.actions{margin-top:18px}.mobile-cta{display:block;position:fixed;bottom:0;left:0;right:0;padding:10px 14px max(10px,env(safe-area-inset-bottom));background:#fff;border-top:1px solid #dce5da;z-index:5}.mobile-cta .button{display:block}.footer{padding:0 18px 24px}}
${adaptiveStyles}</style></head><body><header class="top"><a class="brand" href="/${language}"><img src="/assets/hyse-app-icon.webp" width="36" height="36" alt="">Hyse</a><a class="download" href="${STORE}">${de ? "App laden ↗" : "Get the app ↗"}</a></header><main class="shell"><article><section class="hero"><div class="hero-media">${imageMarkup}</div><div class="hero-content"><p class="eyebrow">${de ? "Ein Rezept aus Hyse" : "A recipe from Hyse"}</p><h1>${escape(name)}</h1>${description ? `<p class="hero-description">${escape(description)}</p>` : ""}<div class="facts"><span>🍽 ${escape(formatAmount(recipe.servings))} ${de ? "Portionen" : "servings"}</span>${Number(recipe.minutes) > 0 ? `<span>◷ ${escape(Math.round(Number(recipe.minutes)))} min</span>` : ""}<span>🔥 ${escape(Math.round(Number(recipe.kcal) || 0))} kcal / ${de ? "Portion" : "serving"}</span></div></div></section><div class="grid"><section class="panel"><h2>${de ? "Zutaten" : "Ingredients"}</h2><ul class="ingredients">${ingredientRows || `<li>${de ? "Keine Zutaten angegeben" : "No ingredients provided"}</li>`}</ul></section><section class="panel"><h2>${de ? "So geht’s" : "Method"}</h2>${steps.length ? `<ol class="steps">${stepRows}</ol>` : `<p>${de ? "Für dieses Rezept wurden noch keine Schritte hinterlegt." : "No steps have been added to this recipe yet."}</p>`}</section></div><div class="nutrition"><span><strong>${escape(formatAmount(recipe.protein))} g</strong> Protein</span><span><strong>${escape(formatAmount(recipe.carbs))} g</strong> ${de ? "Kohlenhydrate" : "Carbs"}</span><span><strong>${escape(formatAmount(recipe.fat))} g</strong> ${de ? "Fett" : "Fat"}</span></div></article><aside class="cta"><div><h2>${de ? "Mehr aus deinem Rezept machen" : "Make more of this recipe"}</h2><p>${de ? "Speichere Rezepte, plane Mahlzeiten und behalte deine Ernährung in Hyse im Blick." : "Save recipes, plan meals and track nutrition with Hyse."}</p></div><div class="actions"><a class="button" href="${STORE}">${de ? "Hyse kostenlos laden" : "Get Hyse free"}</a><a class="button secondary" href="${appURL}">${de ? "In Hyse öffnen" : "Open in Hyse"}</a></div></aside></main><footer class="footer"><a href="/${language}">Hyse</a><a href="/${de ? "de/datenschutz" : "en/privacy"}">${de ? "Datenschutz" : "Privacy"}</a><a href="/${de ? "de/impressum" : "en/impressum"}">${de ? "Impressum" : "Imprint"}</a><a href="/${de ? "de/support" : "en/support"}">${de ? "Inhalt melden" : "Report content"}</a></footer><div class="mobile-cta"><a class="button" href="${STORE}">${de ? "Hyse kostenlos laden" : "Get Hyse free"}</a></div></body></html>`
    return c.html(200, html)
}

module.exports = { render, load }
