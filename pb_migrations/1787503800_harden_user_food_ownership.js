/// PocketBase 0.22.x: explicit authenticated ownership for every user_foods operation.
migrate((db) => {
  const dao = new Dao(db)
  const foods = dao.findCollectionByNameOrId("user_foods")
  foods.listRule = '@request.auth.id != "" && user = @request.auth.id'
  foods.viewRule = '@request.auth.id != "" && user = @request.auth.id'
  foods.createRule = '@request.auth.id != "" && user = @request.auth.id'
  foods.updateRule = '@request.auth.id != "" && user = @request.auth.id'
  foods.deleteRule = '@request.auth.id != "" && user = @request.auth.id'
  dao.saveCollection(foods)
}, (db) => {
  const dao = new Dao(db)
  const foods = dao.findCollectionByNameOrId("user_foods")
  foods.listRule = 'user = @request.auth.id'
  foods.viewRule = 'user = @request.auth.id'
  foods.createRule = '@request.auth.id != "" && user = @request.auth.id'
  foods.updateRule = 'user = @request.auth.id'
  foods.deleteRule = 'user = @request.auth.id'
  dao.saveCollection(foods)
})
