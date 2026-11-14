migrate((db) => {
    const dao = new Dao(db)
    const posts = dao.findCollectionByNameOrId("gym_community_posts")
    posts.schema.addField(new SchemaField({
        name: "client_id", type: "text", required: false,
        options: { min: null, max: 36, pattern: "" }
    }))
    posts.indexes.push("CREATE UNIQUE INDEX `idx_community_message_client` ON `gym_community_posts` (`author`, `client_id`) WHERE `client_id` != ''")
    dao.saveCollection(posts)
}, (db) => {
    const dao = new Dao(db)
    const posts = dao.findCollectionByNameOrId("gym_community_posts")
    posts.indexes = posts.indexes.filter((value) => value.indexOf("idx_community_message_client") < 0)
    posts.schema.removeField(posts.schema.getFieldByName("client_id").id)
    dao.saveCollection(posts)
})
