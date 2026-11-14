/// <reference path="../pb_data/types.d.ts" />

routerAdd("GET", "/de/rezept/:id", (c) => require(`${__hooks}/recipe_share_page.js`).render(c, "de"))
routerAdd("GET", "/en/recipe/:id", (c) => require(`${__hooks}/recipe_share_page.js`).render(c, "en"))
routerAdd("GET", "/api/hyse/public-recipes/:id", (c) => {
    const recipe = require(`${__hooks}/recipe_share_page.js`).load(String(c.pathParam("id") || ""))
    return recipe ? c.json(200, { id: recipe.id, snapshot_json: recipe.snapshot_json, image: recipe.image }) : c.json(404, { error: "Recipe not found" })
})
