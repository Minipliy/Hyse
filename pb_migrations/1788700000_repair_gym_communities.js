/// Repairs production installations where the gym-community hook was mounted
/// before its schema migration ran. Safe both after the original migration and
/// on an installation where one or all community collections are absent.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const find = (name) => {
    try { return dao.findCollectionByNameOrId(name) } catch (_) { return null }
  }
  const relation = (name, collection) => new SchemaField({
    name, type: "relation", required: true,
    options: { collectionId: collection.id, cascadeDelete: true, maxSelect: 1 }
  })
  const text = (name, required, max) => new SchemaField({
    name, type: "text", required,
    options: { min: required ? 1 : null, max, pattern: "" }
  })

  let communities = find("gym_communities")
  if (!communities) {
    communities = new Collection({
      name: "gym_communities", type: "base", system: false,
      listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
      schema: [
        relation("owner", users), text("name", true, 100), text("slug", true, 120),
        text("gym_name", true, 120), text("city", false, 100), text("description", false, 1200)
      ],
      indexes: [
        "CREATE UNIQUE INDEX `idx_gym_communities_slug` ON `gym_communities` (`slug`)",
        "CREATE INDEX `idx_gym_communities_name` ON `gym_communities` (`name`)",
        "CREATE INDEX `idx_gym_communities_city` ON `gym_communities` (`city`)"
      ]
    })
    dao.saveCollection(communities)
  }

  let members = find("gym_community_members")
  if (!members) {
    members = new Collection({
      name: "gym_community_members", type: "base", system: false,
      listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
      schema: [
        relation("community", communities), relation("user", users), text("membership_key", true, 40),
        new SchemaField({ name: "role", type: "select", required: true, options: { maxSelect: 1, values: ["owner", "admin", "member"] } })
      ],
      indexes: [
        "CREATE UNIQUE INDEX `idx_gym_community_members_unique` ON `gym_community_members` (`membership_key`)",
        "CREATE INDEX `idx_gym_community_members_community` ON `gym_community_members` (`community`, `created`)",
        "CREATE INDEX `idx_gym_community_members_user` ON `gym_community_members` (`user`, `created`)"
      ]
    })
    dao.saveCollection(members)
  }

  if (!find("gym_community_posts")) {
    const posts = new Collection({
      name: "gym_community_posts", type: "base", system: false,
      listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
      schema: [
        relation("community", communities), relation("author", users),
        new SchemaField({ name: "channel", type: "select", required: true, options: { maxSelect: 1, values: ["news", "members"] } }),
        text("body", true, 2000), new SchemaField({ name: "pinned", type: "bool" })
      ],
      indexes: [
        "CREATE INDEX `idx_gym_community_posts_channel` ON `gym_community_posts` (`community`, `channel`, `created`)",
        "CREATE INDEX `idx_gym_community_posts_author` ON `gym_community_posts` (`author`)"
      ]
    })
    dao.saveCollection(posts)
  }
}, (_db) => {})
