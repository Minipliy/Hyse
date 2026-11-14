const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

const migration = fs.readFileSync(path.join(__dirname, '../pb_migrations/1791000800_koro_manufacturer_cookies.js'), 'utf8')
let up
const records = new Map()
const sourceField = { options: { values: ['seed', 'user', 'open_food_facts'] } }
const collection = { id: 'global_foods', schema: { getFieldByName: () => sourceField } }
class Record {
  constructor() { this.fields = {}; this.id = String(records.size + 1) }
  set(key, value) { this.fields[key] = value }
  get(key) { return this.fields[key] }
}
class Dao {
  findCollectionByNameOrId() { return collection }
  saveCollection() {}
  findFirstRecordByFilter(_id, _filter, params) {
    for (const record of records.values()) {
      if (record.get('barcode_normalized') === params.barcode) return record
    }
    throw new Error('not found')
  }
  saveRecord(record) { records.set(record.get('barcode_normalized'), record) }
}
vm.runInNewContext(migration, { migrate: callback => { up = callback }, Dao, Record })

const existing = new Record()
existing.set('barcode_normalized', '4260654782752')
existing.set('source', 'open_food_facts')
records.set(existing.get('barcode_normalized'), existing)
up({})
assert.equal(records.size, 14)
assert.equal(records.get('4260654782752'), existing, 'existing licensed product must be preserved')
assert(collection.schema.getFieldByName().options.values.includes('manufacturer'))

for (const [barcode, record] of records) {
  if (record === existing) continue
  assert.match(barcode, /^\d{13}$/)
  const digits = [...barcode].map(Number)
  const sum = digits.slice(0, -1).reverse().reduce((value, digit, index) => value + digit * (index % 2 ? 1 : 3), 0)
  assert.equal((10 - sum % 10) % 10, digits.at(-1), `invalid GTIN: ${barcode}`)
  assert.equal(record.get('brand'), 'KoRo')
  assert.match(record.get('name_de'), /KoRo Kekse/)
  assert.equal(record.get('source'), 'manufacturer')
  assert.equal(record.get('moderation_status'), 'approved')
  assert.equal(record.get('source_id'), `KoRo-${barcode}`)
  assert.match(record.get('source_note'), /https:\/\/www\.koro\.com\//)
  for (const field of ['calories', 'carbs', 'protein', 'fat', 'sugar', 'fiber', 'saturated_fat', 'salt']) {
    const value = record.get(field)
    assert(Number.isFinite(value) && value >= 0 && value <= (field === 'calories' ? 900 : 100))
  }
}
up({})
assert.equal(records.size, 14, 'reapplying the migration must not duplicate products')
console.log('KoRo manufacturer catalogue checks passed.')
