/// <reference path="../pb_data/types.d.ts" />

onRecordBeforeCreateRequest((e) => { require(`${__hooks}/food_usage_helpers.js`).prepare($app.dao(), e.record) }, "user_foods")
onRecordBeforeUpdateRequest((e) => { require(`${__hooks}/food_usage_helpers.js`).prepare($app.dao(), e.record) }, "user_foods")

onRecordAfterCreateRequest((e) => {
    const usage = require(`${__hooks}/food_usage_helpers.js`)
    if (usage.text(e.record.get("record_type")) === "entry") usage.rebuild($app.dao(), usage.text(e.record.get("user")))
}, "user_foods")
onRecordAfterUpdateRequest((e) => {
    const usage = require(`${__hooks}/food_usage_helpers.js`)
    if (!usage.usageChanged(e.record)) return
    const original = e.record.originalCopy()
    const oldUser = usage.text(original.get("user"))
    const newUser = usage.text(e.record.get("user"))
    if (usage.text(original.get("record_type")) === "entry" && oldUser) usage.rebuild($app.dao(), oldUser)
    if (usage.text(e.record.get("record_type")) === "entry" && newUser &&
        (newUser !== oldUser || usage.text(original.get("record_type")) !== "entry")) usage.rebuild($app.dao(), newUser)
}, "user_foods")
onRecordAfterDeleteRequest((e) => {
    const usage = require(`${__hooks}/food_usage_helpers.js`)
    if (usage.text(e.record.get("record_type")) === "entry") usage.rebuild($app.dao(), usage.text(e.record.get("user")))
}, "user_foods")

routerAdd("POST", "/api/hyse/food-usage/rebuild", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const count = require(`${__hooks}/food_usage_helpers.js`).rebuild($app.dao(), user.id)
    return c.json(200, { ok: true, groups: count })
}, $apis.requireRecordAuth("users"))
