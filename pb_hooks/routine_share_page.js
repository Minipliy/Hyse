const STORE = "https://apps.apple.com/de/app/hyse/id6811359623"
const adaptiveStyles = `:root{color-scheme:light dark}@media(prefers-color-scheme:dark){body{background:#0b100e;color:#edf4ef}.top{background:#111a16;border-color:#2b3a31}.top .download{color:#8bd5a2}.exercise{background:#19231d;border-color:#35463a}.exercise p,.sets li span{color:#a9bbad}.exercise .notes{color:#d6e3d8}.sets li{border-color:#35463a}.index{background:#254531;color:#a2edb7}.cta{background:#1a3022}.cta p{color:#bfd0c1}.button.secondary{background:#243a2b;color:#b7efc8;border-color:#597b61}.footer,.footer a{color:#a9bbad}.mobile-cta{background:#111a16;border-color:#35463a}}`
const escape = (value) => String(value == null ? "" : value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
})[char])
const text = (value, max = 4000) => String(value == null ? "" : value).trim().slice(0, max)
const number = (value, language) => {
    const n = Number(value)
    if (!Number.isFinite(n) || n < 0) return "0"
    const rounded = String(Math.round(n * 10) / 10)
    return language === "de" ? rounded.replace(".", ",") : rounded
}
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
        const record = $app.dao().findRecordById("routine_shares", id)
        return { id, snapshot_json: snapshot(record.get("snapshot_json")), image: text(record.get("image"), 200) }
    } catch (_) { return null }
}

function render(c, language) {
    const de = language === "de"
    const loaded = load(String(c.pathParam("id") || ""))
    if (!loaded) return c.html(404, "Routine not found")
    const routine = loaded.snapshot_json
    const name = text(routine.name, 180)
    if (!name) return c.html(404, "Routine not found")
    const details = text(routine.details, 4000)
    const exercises = Array.isArray(routine.exercises) ? routine.exercises.slice(0, 100) : []
    const imageFile = loaded.image
    const imageURL = /^[a-zA-Z0-9_.-]+$/.test(imageFile) && imageFile
        ? `${String((typeof $os !== "undefined" && $os.getenv("HYSE_PUBLIC_URL")) || "http://localhost:8090").replace(/\/+$/, "")}/api/files/routine_shares/${loaded.id}/${encodeURIComponent(imageFile)}?thumb=1200x1200`
        : ""
    const webURL = `${String((typeof $os !== "undefined" && $os.getenv("HYSE_PUBLIC_URL")) || "http://localhost:8090").replace(/\/+$/, "")}/${de ? "de" : "en"}/routine/${loaded.id}`
    const appURL = `hyseapp://routine/${loaded.id}`
    const summary = details.split(/\n/)[0].slice(0, 180) || (de ? "Übungen und Sätze dieser Hyse-Routine ansehen und kopieren." : "See the exercises and sets in this Hyse routine and save a copy.")
    const exerciseName = (exercise) => text(de && exercise.germanName ? exercise.germanName : exercise.englishName || exercise.germanName, 180)
    const setText = (set, type) => {
        if (!set || typeof set !== "object") return ""
        const parts = []
        const setTypes = de
            ? { warmup: "Aufwärmen", drop_set: "Dropsatz", failure: "Muskelversagen", superset: "Supersatz" }
            : { warmup: "Warm-up", drop_set: "Drop set", failure: "To failure", superset: "Superset" }
        if (setTypes[set.type]) parts.push(setTypes[set.type])
        const weight = Number(set.weightKilograms)
        const reps = Number(set.reps)
        const duration = Number(set.durationSeconds)
        const distance = Number(set.distanceMeters)
        const assisted = Number(set.assistedKilograms)
        if (type === "duration" || type === "distance_duration") {
            if (distance > 0 && Number.isFinite(distance)) parts.push(`${number(distance / 1000, language)} km`)
            if (duration > 0 && Number.isFinite(duration)) parts.push(`${number(duration, language)} s`)
        } else {
            if (weight > 0 && Number.isFinite(weight)) parts.push(`${number(weight, language)} kg`)
            if (assisted > 0 && Number.isFinite(assisted)) parts.push(`${number(assisted, language)} kg ${de ? "Unterstützung" : "assistance"}`)
            if (reps > 0 && Number.isFinite(reps)) parts.push(`${number(reps, language)} ${de ? "Wdh." : "reps"}`)
        }
        const rpe = Number(set.rpe)
        if (rpe > 0 && Number.isFinite(rpe)) parts.push(`RPE ${number(rpe, language)}`)
        return parts.join(" · ") || (de ? "Offener Satz" : "Open set")
    }
    const rows = exercises.map((exercise, index) => {
        if (!exercise || typeof exercise !== "object") return ""
        const title = exerciseName(exercise)
        if (!title) return ""
        const sets = Array.isArray(exercise.sets) ? exercise.sets.slice(0, 100) : []
        const notes = text(exercise.notes, 2000)
        const rest = Number(exercise.restSeconds)
        const setRows = sets.map((set, setIndex) => `<li><span>${setIndex + 1}.</span><strong>${escape(setText(set, exercise.type))}</strong></li>`).join("")
        return `<section class="exercise"><div class="exercise-heading"><span class="index">${index + 1}</span><div><h2>${escape(title)}</h2><p>${sets.length} ${de ? "Sätze" : "sets"}${rest > 0 && Number.isFinite(rest) ? ` · ${escape(number(rest, language))} s ${de ? "Pause" : "rest"}` : ""}</p></div></div>${notes ? `<p class="notes">${escape(notes)}</p>` : ""}<ol class="sets">${setRows}</ol></section>`
    }).join("")
    const title = `${name} · Hyse`
    const imageMarkup = imageURL ? `<img src="${escape(imageURL)}" alt="${escape(name)}">` : `<div class="placeholder" aria-hidden="true">✦</div>`
    const schema = { "@context": "https://schema.org", "@type": "ExercisePlan", name, description: details || summary, url: webURL }
    if (imageURL) schema.image = imageURL
    const ld = JSON.stringify(schema).replace(/</g, "\\u003c")
    const html = `<!doctype html><html lang="${language}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,follow"><meta name="color-scheme" content="light dark"><meta name="theme-color" media="(prefers-color-scheme:light)" content="#f7f7f2"><meta name="theme-color" media="(prefers-color-scheme:dark)" content="#0b100e"><meta name="apple-itunes-app" content="app-id=6811359623"><title>${escape(title)}</title><meta name="description" content="${escape(summary)}"><link rel="canonical" href="${webURL}"><meta property="og:type" content="article"><meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(summary)}"><meta property="og:url" content="${webURL}">${imageURL ? `<meta property="og:image" content="${escape(imageURL)}">` : ""}<meta name="twitter:card" content="${imageURL ? "summary_large_image" : "summary"}"><script type="application/ld+json">${ld}</script><style>
*{box-sizing:border-box}body{margin:0;background:#f7f7f2;color:#17231d;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;line-height:1.55}a{color:inherit}.top{height:74px;display:flex;align-items:center;justify-content:space-between;gap:16px;padding:0 max(24px,calc((100vw - 1120px)/2));background:#fff;border-bottom:1px solid #e4e9e0}.brand{display:flex;align-items:center;gap:10px;text-decoration:none;font-size:22px;font-weight:800;letter-spacing:-.04em}.brand img{border-radius:11px}.top .download{font-size:14px;font-weight:700;text-decoration:none;color:#246447}.shell{max-width:1120px;margin:auto;padding:32px 24px 110px}.hero{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);border-radius:30px;overflow:hidden;background:#172d23;color:#fff;min-height:380px}.hero-media{min-height:320px}.hero-media img{width:100%;height:100%;max-height:500px;object-fit:cover;display:block}.placeholder{height:100%;min-height:320px;background:radial-gradient(circle at 50% 50%,#b6d2bd 0 18%,#5c8e6c 18% 40%,#28573d 40% 100%);display:grid;place-items:center;color:#fff;font-size:170px}.hero-content{padding:clamp(28px,5vw,64px);display:flex;flex-direction:column;justify-content:center}.eyebrow{margin:0 0 18px;color:#b8d4aa;font-size:12px;font-weight:800;letter-spacing:.16em;text-transform:uppercase}h1{font-size:clamp(34px,4.5vw,60px);letter-spacing:-.055em;line-height:1.08;margin:0 0 22px;overflow-wrap:anywhere}.hero-description{font-size:17px;color:#e0e9df;white-space:pre-line;margin:0 0 24px}.facts span{border:1px solid #ffffff44;border-radius:99px;padding:7px 12px;font-size:13px;font-weight:600}.content{margin-top:24px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.exercise{background:#fff;border:1px solid #e2e9dd;border-radius:24px;padding:24px;min-width:0}.exercise-heading{display:flex;align-items:flex-start;gap:14px}.index{flex:none;width:34px;height:34px;border-radius:50%;display:grid;place-items:center;background:#e2eee3;color:#22603f;font-weight:800}.exercise h2{margin:0;font-size:22px;line-height:1.2;overflow-wrap:anywhere}.exercise p{margin:5px 0 0;color:#607065}.exercise .notes{margin:16px 0;color:#35483c;white-space:pre-line;overflow-wrap:anywhere}.sets{list-style:none;margin:16px 0 0;padding:0}.sets li{display:flex;gap:12px;padding:8px 0;border-top:1px solid #edf0ea}.sets li span{color:#87958a}.sets strong{font-weight:600}.cta{margin-top:24px;padding:28px 32px;border-radius:26px;background:#e3ecdc;display:flex;align-items:center;justify-content:space-between;gap:24px}.cta h2{margin:0 0 4px}.cta p{margin:0;color:#485a4b}.actions{display:flex;gap:10px;flex-wrap:wrap}.button{display:inline-block;padding:13px 18px;background:#256b45;color:#fff;text-decoration:none;font-weight:800;border-radius:12px;text-align:center;white-space:nowrap}.button.secondary{background:#fff;color:#256b45;border:1px solid #b2cbbb}.footer{max-width:1120px;margin:auto;padding:0 24px 40px;display:flex;gap:22px;color:#607065;font-size:13px}.footer a{color:#607065}.mobile-cta{display:none}@media(max-width:760px){.top{height:64px}.hero,.content{grid-template-columns:1fr}.hero-media{min-height:230px;max-height:360px}.hero-media img{max-height:360px}.placeholder{min-height:230px}.shell{padding:18px 14px 100px}.hero{border-radius:22px}.hero-content{padding:28px}.exercise{border-radius:20px}.cta{display:block}.actions{margin-top:18px}.mobile-cta{display:block;position:fixed;bottom:0;left:0;right:0;padding:10px 14px max(10px,env(safe-area-inset-bottom));background:#fff;border-top:1px solid #dce5da;z-index:5}.mobile-cta .button{display:block}.footer{padding:0 18px 24px}}
${adaptiveStyles}</style></head><body><header class="top"><a class="brand" href="/${language}"><img src="/assets/hyse-app-icon.webp" width="36" height="36" alt="">Hyse</a><a class="download" href="${STORE}">${de ? "App laden ↗" : "Get the app ↗"}</a></header><main class="shell"><article><section class="hero"><div class="hero-media">${imageMarkup}</div><div class="hero-content"><p class="eyebrow">${de ? "Eine Workout-Routine aus Hyse" : "A workout routine from Hyse"}</p><h1>${escape(name)}</h1>${details ? `<p class="hero-description">${escape(details)}</p>` : ""}<div class="facts"><span>💪 ${exercises.length} ${de ? "Übungen" : "exercises"}</span></div></div></section><div class="content">${rows || `<p>${de ? "Keine Übungen angegeben" : "No exercises provided"}</p>`}</div></article><aside class="cta"><div><h2>${de ? "Diese Routine trainieren" : "Train this routine"}</h2><p>${de ? "Öffne die Routine in Hyse und speichere eine eigene Kopie." : "Open the routine in Hyse and save your own copy."}</p></div><div class="actions"><a class="button" href="${STORE}">${de ? "Hyse kostenlos laden" : "Get Hyse free"}</a><a class="button secondary" href="${appURL}">${de ? "In Hyse öffnen" : "Open in Hyse"}</a></div></aside></main><footer class="footer"><a href="/${language}">Hyse</a><a href="/${de ? "de/datenschutz" : "en/privacy"}">${de ? "Datenschutz" : "Privacy"}</a><a href="/${de ? "de/impressum" : "en/impressum"}">${de ? "Impressum" : "Imprint"}</a><a href="/${de ? "de/support" : "en/support"}">${de ? "Inhalt melden" : "Report content"}</a></footer><div class="mobile-cta"><a class="button" href="${appURL}">${de ? "In Hyse öffnen" : "Open in Hyse"}</a></div></body></html>`
    return c.html(200, html)
}

module.exports = { render, load }
