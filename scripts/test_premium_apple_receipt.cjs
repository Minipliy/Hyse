const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')

const routes = {}
let bundle = 'com.hyse.HyseApp'
let product = 'com.hyse.HyseApp.premium.complete.monthly'
let expires = Date.now() + 86400000
let original = '123456789012345'
let revoked = false
let sandboxCalls = 0
const context = {
    Date, Number, String, Boolean, Object, Array, JSON,
    $os: { getenv: () => 'server-only-secret' },
    $http: { send: ({ url }) => {
        if (!url.includes('sandbox')) return { statusCode: 200, json: { status: 21007 } }
        sandboxCalls++
        return { statusCode: 200, json: { status: 0, receipt: {
            bundle_id: bundle, in_app: [{ product_id: product, original_transaction_id: original,
            expires_date_ms: String(expires), purchase_date_ms: String(Date.now()),
            cancellation_date_ms: revoked ? String(Date.now()) : undefined }]
        } } }
    } },
    routerAdd: (method, path, handler) => { routes[method + path] = handler },
    $apis: { requireRecordAuth: () => () => {} },
    BadRequestError: class extends Error {},
    InternalServerError: class extends Error {}
}
vm.createContext(context)
vm.runInContext(fs.readFileSync('pb_hooks/premium_apple.pb.js', 'utf8'), context)
const verify = context.hyseAppleVerifyReceipt
assert.equal(verify('receipt').transactions[0].product, product)
assert.equal(sandboxCalls, 1)
bundle = 'com.other.App'
assert.throws(() => verify('receipt'), /could not verify/)
bundle = 'com.hyse.HyseApp'
expires = Date.now() - 1000
assert.equal(verify('receipt').transactions.length, 0)
product = 'hyse.complete.lifetime'
assert.equal(verify('receipt').transactions[0].product, product)
revoked = true
assert.equal(verify('receipt').transactions.length, 0)
revoked = false
original = 'invalid'
assert.equal(verify('receipt').transactions.length, 0)
console.log('Apple receipt verification guards passed')
