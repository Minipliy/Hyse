const assert = require('node:assert/strict')
const path = require('node:path')
const usage = require('../pb_hooks/food_usage_helpers.js')

class FakeRecord {
    constructor(fields = {}) { this.fields = { ...fields }; this.id = fields.id || 'usage-1' }
    get(field) { return this.fields[field] }
    set(field, value) { this.fields[field] = value }
    originalCopy() { return new FakeRecord(this.before) }
}

const entry = new FakeRecord({
    id: 'entry-1', user: 'user-1', record_type: 'entry', client_id: 'client-1',
    source_food_client_id: 'food-1', source_key: 'user_food:food-1',
    name: 'Banane', amount: 100, unit: 'g', meal_key: 'breakfast',
    eaten_at: '2026-10-15 08:00:00.000Z'
})
entry.before = { ...entry.fields, micronutrients: {} }
entry.set('micronutrients', { potassium_mg: 358 })
assert.equal(usage.usageChanged(entry), false, 'micronutrient-only updates must skip usage rebuild')
entry.set('amount', 120)
assert.equal(usage.usageChanged(entry), true, 'amount changes must refresh usage')
entry.set('amount', 100)

const rows = []
const dao = {
    findRecordsByFilter(collection) { return collection === 'user_foods' ? [entry] : rows },
    findCollectionByNameOrId() { return {} },
    saveRecord(record) { if (!rows.includes(record)) rows.push(record); this.writes++ },
    deleteRecord(record) { rows.splice(rows.indexOf(record), 1) },
    writes: 0
}
global.Record = FakeRecord
usage.rebuild(dao, 'user-1')
assert.equal(dao.writes, 1, 'first entry must create usage row')
usage.rebuild(dao, 'user-1')
assert.equal(dao.writes, 1, 'unchanged usage row must not be rewritten')
entry.set('amount', 120)
usage.rebuild(dao, 'user-1')
assert.equal(dao.writes, 2, 'changed amount must update usage row')
assert.equal(rows[0].get('last_amount'), 120)

const legacyFood = new FakeRecord({ record_type: 'saved', barcode_raw: 'not-a-barcode', barcode_normalized: 'not-a-barcode' })
usage.prepare(dao, legacyFood)
assert.equal(legacyFood.get('barcode_normalized'), '', 'invalid legacy barcode must not block food sync')
const formattedFood = new FakeRecord({ record_type: 'saved', barcode_raw: '4006 3813-3393.1' })
usage.prepare(dao, formattedFood)
assert.equal(formattedFood.get('barcode_normalized'), '4006381333931')

let updateHook
global.__hooks = path.resolve(__dirname, '../pb_hooks')
global.onRecordBeforeCreateRequest = () => {}
global.onRecordBeforeUpdateRequest = () => {}
global.onRecordAfterCreateRequest = () => {}
global.onRecordAfterUpdateRequest = (callback) => { updateHook = callback }
global.onRecordAfterDeleteRequest = () => {}
global.routerAdd = () => {}
global.$app = { dao: () => dao }
global.$apis = { requireRecordAuth: () => {} }
require('../pb_hooks/user_food_usage.pb.js')
const realRebuild = usage.rebuild
const rebuiltUsers = []
usage.rebuild = (_, user) => { rebuiltUsers.push(user) }
entry.set('amount', 100)
updateHook({ record: entry })
assert.deepEqual(rebuiltUsers, [], 'micronutrient-only PATCH must not rebuild')
entry.set('amount', 120)
updateHook({ record: entry })
assert.deepEqual(rebuiltUsers, ['user-1'], 'usage-changing PATCH must rebuild once')
usage.rebuild = realRebuild
console.log('food usage hook: OK')
