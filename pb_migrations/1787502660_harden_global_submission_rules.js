/// Require authentication before evaluating ownership of private revisions.
migrate((db) => {
  const dao = new Dao(db)
  const submissions = dao.findCollectionByNameOrId("global_food_submissions")
  submissions.listRule = '@request.auth.id != "" && submitted_by = @request.auth.id'
  submissions.viewRule = '@request.auth.id != "" && submitted_by = @request.auth.id'
  dao.saveCollection(submissions)
}, (db) => {
  const dao = new Dao(db)
  const submissions = dao.findCollectionByNameOrId("global_food_submissions")
  submissions.listRule = "submitted_by = @request.auth.id"
  submissions.viewRule = "submitted_by = @request.auth.id"
  dao.saveCollection(submissions)
})
