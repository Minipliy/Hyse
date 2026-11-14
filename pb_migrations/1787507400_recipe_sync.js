/// PocketBase 0.22.x: private offline-first recipes and moderated global catalogue.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const userFoods = dao.findCollectionByNameOrId("user_foods")
  const relation = (name, collection, required = true, cascadeDelete = true) => new SchemaField({ name, type: "relation", required, options: { collectionId: collection.id, cascadeDelete, maxSelect: 1 } })
  const text = (name, required = false, max = 0) => new SchemaField({ name, type: "text", required, options: { min: null, max: max || null, pattern: "" } })
  const number = (name, noDecimal = false) => new SchemaField({ name, type: "number", options: { min: null, max: null, noDecimal } })
  const json = (name) => new SchemaField({ name, type: "json" })
  const select = (name, values, required = false) => new SchemaField({ name, type: "select", required, options: { maxSelect: 1, values } })
  const own = '@request.auth.id != "" && user = @request.auth.id'

  const globals = new Collection({
    name: "global_recipes", type: "base", system: false,
    listRule: '@request.auth.id != "" && moderation_status = "approved"',
    viewRule: '@request.auth.id != "" && moderation_status = "approved"',
    createRule: null, updateRule: null, deleteRule: null,
    schema: [
      relation("creator", users, true, false), text("client_id", true, 36), text("name", true, 180),
      text("normalized_key", true, 2000), select("moderation_status", ["approved", "superseded"], true),
      json("snapshot_json"), number("calories"), number("carbs"), number("protein"), number("fat"),
      number("sugar"), number("fiber"), number("saturated_fat"), number("salt"),
      new SchemaField({ name: "image", type: "file", options: { maxSelect: 1, maxSize: 10485760, mimeTypes: ["image/jpeg", "image/png", "image/webp"], thumbs: ["320x320", "800x800"], protected: true } })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_global_recipes_key` ON `global_recipes` (`normalized_key`) WHERE `moderation_status` = 'approved'",
      "CREATE INDEX `idx_global_recipes_name` ON `global_recipes` (`name`)"
    ]
  })
  dao.saveCollection(globals)

  const submissions = new Collection({
    name: "global_recipe_submissions", type: "base", system: false,
    listRule: '@request.auth.id != "" && submitted_by = @request.auth.id',
    viewRule: '@request.auth.id != "" && submitted_by = @request.auth.id',
    createRule: null, updateRule: null,
    deleteRule: '@request.auth.id != "" && submitted_by = @request.auth.id && status != "approved"',
    schema: [
      relation("submitted_by", users), relation("source_recipe", globals, false, false), relation("global_recipe", globals, false, false),
      text("client_id", true, 36), text("normalized_key", true, 2000), select("status", ["pending", "approved", "rejected"], true),
      json("snapshot_json"), text("reviewed_by", false, 40), new SchemaField({ name: "reviewed_at", type: "date" }),
      text("rejection_reason", false, 2000),
      new SchemaField({ name: "image", type: "file", options: { maxSelect: 1, maxSize: 10485760, mimeTypes: ["image/jpeg", "image/png", "image/webp"], thumbs: ["320x320", "800x800"], protected: true } })
    ],
    indexes: [
      "CREATE INDEX `idx_global_recipe_submissions_owner` ON `global_recipe_submissions` (`submitted_by`, `status`)",
      "CREATE INDEX `idx_global_recipe_submissions_client` ON `global_recipe_submissions` (`submitted_by`, `client_id`)"
    ]
  })
  dao.saveCollection(submissions)

  const privateRecipes = new Collection({
    name: "user_recipes", type: "base", system: false,
    listRule: own, viewRule: own, createRule: own, updateRule: own, deleteRule: own,
    schema: [
      relation("user", users), text("client_id", true, 36), text("name", true, 180), text("description", false, 8000),
      json("ingredients"), number("servings"), number("total_weight_grams"), json("preparation_steps"),
      number("preparation_minutes", true), json("tags"), json("filters"), new SchemaField({ name: "is_favorite", type: "bool" }),
      relation("global_recipe", globals, false, false), relation("global_submission", submissions, false, false),
      number("calories"), number("carbs"), number("protein"), number("fat"), number("sugar"), number("fiber"), number("saturated_fat"), number("salt"),
      new SchemaField({ name: "created_at_local", type: "date" }), new SchemaField({ name: "updated_at_local", type: "date" }),
      json("snapshot_json"),
      new SchemaField({ name: "image", type: "file", options: { maxSelect: 1, maxSize: 10485760, mimeTypes: ["image/jpeg", "image/png", "image/webp"], thumbs: ["320x320", "800x800"], protected: true } })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_user_recipes_user_client` ON `user_recipes` (`user`, `client_id`)",
      "CREATE INDEX `idx_user_recipes_user_updated` ON `user_recipes` (`user`, `updated_at_local`)"
    ]
  })
  dao.saveCollection(privateRecipes)

  userFoods.schema.addField(relation("user_recipe", privateRecipes, false, false))
  userFoods.schema.addField(relation("global_recipe", globals, false, false))
  userFoods.schema.addField(text("recipe_client_id", false, 36))
  dao.saveCollection(userFoods)
}, (db) => {
  const dao = new Dao(db)
  try {
    const userFoods = dao.findCollectionByNameOrId("user_foods")
    for (const name of ["user_recipe", "global_recipe", "recipe_client_id"]) {
      try { userFoods.schema.removeField(userFoods.schema.getFieldByName(name).id) } catch (_) {}
    }
    dao.saveCollection(userFoods)
  } catch (_) {}
  for (const name of ["user_recipes", "global_recipe_submissions", "global_recipes"]) {
    try { dao.deleteCollection(dao.findCollectionByNameOrId(name)) } catch (_) {}
  }
})
