/// <reference path="../pb_data/types.d.ts" />

routerAdd("GET", "/de/routine/:id", (c) => require(`${__hooks}/routine_share_page.js`).render(c, "de"))
routerAdd("GET", "/en/routine/:id", (c) => require(`${__hooks}/routine_share_page.js`).render(c, "en"))
routerAdd("GET", "/api/hyse/public-routines/:id", (c) => {
    const routine = require(`${__hooks}/routine_share_page.js`).load(String(c.pathParam("id") || ""))
    return routine
        ? c.json(200, { id: routine.id, snapshot_json: routine.snapshot_json, image: routine.image })
        : c.json(404, { error: "Routine not found" })
})
