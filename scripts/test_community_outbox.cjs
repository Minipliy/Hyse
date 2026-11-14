const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const routes = new Map();
const records = [];
let simulateRace = false;
class Record {
  constructor() { this.fields = {}; this.created = this.updated = '2026-09-19T12:00:00Z'; }
  set(k, v) { this.fields[k] = v; }
  get(k) { return this.fields[k]; }
}
const dao = {
  findCollectionByNameOrId: () => ({}),
  findFirstRecordByFilter(collection, filter, args) {
    if (collection === 'gym_community_members') return { get: () => 'member' };
    const found = records.find(r => r.get('author') === args.author && r.get('client_id') === args.client);
    if (!found) throw Error('not found');
    return found;
  },
  findRecordById() { throw Error('deleted reply'); },
  saveRecord(record) {
    record.id = String(records.length + 1);
    records.push(record);
    if (simulateRace) { simulateRace = false; throw Error('unique constraint after parallel insert'); }
  }
};
const user = { id: 'alice', get: () => '' };
const context = {
  routerAdd: (method, path, handler) => routes.set(method + path, handler),
  $apis: { requireRecordAuth: () => {}, requestInfo: c => ({ authRecord: user, data: c.data }) },
  $app: { dao: () => dao }, Record,
  UnauthorizedError: Error, BadRequestError: Error, ForbiddenError: Error, NotFoundError: Error
};
vm.runInNewContext(fs.readFileSync('pb_hooks/gym_communities.pb.js', 'utf8'), context);
const post = routes.get('POST/api/hyse/gym-communities/:id/posts');
function send(id, body = 'Hello', community = 'gym', reply) {
  return post({ data: { client_id: id, body, channel: 'members', reply_to: reply },
    pathParam: () => community, json: (status, value) => ({ status, ...value }) });
}
const id = '12345678-1234-1234-1234-123456789abc';
const first = send(id);
assert.equal(first.status, 201);
const retry = send(id);
assert.equal(retry.post.id, first.post.id);
assert.equal(records.length, 1, 'lost response retry must not create another message');
assert.equal(send(id, 'Hello', 'gym', 'deleted').status, 200, 'acknowledge existing message before revalidating deleted reply');
assert.throws(() => send(id, 'Hello', 'other-gym'));
assert.throws(() => send('invalid'));
simulateRace = true;
assert.equal(send('22345678-1234-1234-1234-123456789abc').status, 200);
assert.equal(records.length, 2);
assert.throws(() => send('32345678-1234-1234-1234-123456789abc', 'Hello', 'gym', 'deleted'));
assert.equal(records.length, 2, 'deleted reply is rejected without saving');
console.log('Community outbox: retry, concurrent duplicate, account key, validation and deleted reply checks passed.');
