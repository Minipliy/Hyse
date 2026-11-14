#!/usr/bin/env node
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

const routes = new Map()
const brands = Array.from({ length: 250 }, (_, index) => ({
    id: `brand${index}`, name: `Brand ${String(index).padStart(3, "0")}`,
    normalized_name: `brand ${String(index).padStart(3, "0")}`,
    slug: `brand-${index}`, aliases: [], status: "approved", created_by: "user1"
}))
brands.push({ id: "zephyr", name: "Zephyr", normalized_name: "zephyr", slug: "zephyr", aliases: [], status: "approved", created_by: "user1" })
const catalogueNames = ["Alpro", "Ferrero,nutella", "alpro"]
let brandLimit
const dao = {
    findRecordsByFilter(_collection, _filter, _sort, limit) {
        brandLimit = limit
        return brands.map((fields) => ({ id: fields.id, get: (key) => fields[key] }))
    },
    findFirstRecordByFilter() { throw new Error("not found") },
    findCollectionByNameOrId() { return {} },
    saveRecord(record) { record.id = "newbrand"; brands.push({ id: record.id, ...record.fields }) },
    db() {
        return { newQuery(sql) {
            assert.match(sql, /moderation_status = 'approved'/)
            const query = { params: {}, bind(params) { this.params = params; return this }, all(rows) {
                const match = this.params.match?.match(/brand:"([^"]+)/)?.[1]
                rows.push(...catalogueNames.filter((name) => !match || name.toLowerCase().includes(match)).map((name) => ({ name })))
            } }
            return query
        } }
    }
}
class Record {
    constructor() { this.fields = {} }
    set(key, value) { this.fields[key] = value }
    get(key) { return this.fields[key] }
}
const context = {
    routerAdd: (method, path, handler) => routes.set(`${method} ${path}`, handler),
    onRecordBeforeCreateRequest: () => {}, onRecordBeforeUpdateRequest: () => {},
    $apis: { requestInfo: (c) => ({ authRecord: c.auth === false ? null : { id: "user1" }, data: c.data }), requireRecordAuth: () => {}, requireAdminAuth: () => {} },
    $app: { dao: () => dao }, Record,
    DynamicModel: class { constructor(fields) { Object.assign(this, fields) } },
    arrayOf: () => [],
    BadRequestError: class extends Error {}, UnauthorizedError: class extends Error {},
}
vm.runInNewContext(fs.readFileSync("pb_hooks/consents_brands_portions.pb.js", "utf8"), context)
const search = routes.get("GET /api/hyse/brands")
const create = routes.get("POST /api/hyse/brands")
const call = (handler, query = "", data = {}, auth = true) => handler({ queryParam: () => query, data, auth, json: (_status, body) => body })

assert.equal(brandLimit, undefined)
assert(call(search).items.length > 4)
assert(call(search, "", {}, false).items.length > 4)
assert.equal(call(search, "Zephyr", {}, false).items[0].created_by, "")
assert.equal(brandLimit, 0, "brand search must inspect records after the first 200")
assert.equal(call(search, "Zephyr").items[0].id, "zephyr")
const nutella = call(search, "nutella").items
assert.equal(nutella.length, 1)
assert.equal(nutella[0].name, "nutella")
assert.match(nutella[0].id, /^catalog:/)
const created = call(create, "", { name: nutella[0].name })
assert.equal(created.status, "approved")
assert.equal(call(search, "nutella").items[0].id, created.id)
console.log("Brand catalogue search and immediate publication passed.")
