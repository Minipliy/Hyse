const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function loadAt(isoTime) {
  class FixedDate extends Date {
    constructor(...args) { super(...(args.length ? args : [isoTime])); }
    static now() { return new Date(isoTime).getTime(); }
  }
  const routes = [];
  const members = [
    { user: 'one', challenge_week: '2026-09-28' },
    { user: 'two', challenge_week: '2026-09-28' },
    { user: 'three', challenge_week: '' },
  ].map((data) => ({ get: (key) => data[key], set: (key, value) => { data[key] = value; } }));
  const workouts = { one: 2, two: 3, three: 8 };
  const dao = {
    findFirstRecordByFilter(_collection, _filter, args) {
      const found = members.find((value) => value.get('user') === args.user);
      if (!found) throw new Error('not a member');
      return found;
    },
    findRecordsByFilter(collection, filter, _sort, limit, _offset, args) {
      if (collection === 'gym_community_members') return members.filter((value) => value.get('challenge_week') === args.week);
      assert.match(filter, /status = 'completed'/);
      assert.equal(limit, 3);
      return Array(Math.min(limit, workouts[args.user] || 0)).fill({});
    },
    saveRecord() {},
  };
  const sandbox = {
    Date: FixedDate,
    routerAdd: (method, path, handler) => routes.push({ method, path, handler }),
    $apis: { requireRecordAuth: () => null, requestInfo: (c) => ({ authRecord: c.user, data: c.data }) },
    $app: { dao: () => dao },
    ForbiddenError: class ForbiddenError extends Error {},
    UnauthorizedError: class UnauthorizedError extends Error {},
  };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync('pb_hooks/community_challenges.pb.js', 'utf8'), sandbox);
  const call = (method, user, data = {}) => {
    const route = routes.find((item) => item.method === method);
    return route.handler({ user: user && { id: user }, data, pathParam: () => 'gym', json: (_code, value) => value });
  };
  return { routes, call };
}

const sunday = loadAt('2026-10-04T23:59:59Z');
assert.deepEqual(sunday.routes.map(({ method, path }) => [method, path]), [
  ['GET', '/api/hyse/gym-communities/:id/challenge'],
  ['POST', '/api/hyse/gym-communities/:id/challenge'],
]);
const first = sunday.call('GET', 'one');
assert.equal(first.week, '2026-09-28');
assert.equal(first.joined, true);
assert.equal(first.my_count, 2);
assert.equal(first.participants, 2);
assert.equal(first.completed, 1);
assert.equal(sunday.call('GET', 'three').joined, false);
const joined = sunday.call('POST', 'three', { enabled: true });
assert.equal(joined.joined, true);
assert.equal(joined.participants, 3);
assert.equal(joined.completed, 2);
assert.equal(sunday.call('POST', 'three', { enabled: false }).joined, false);
assert.throws(() => sunday.call('GET', 'stranger'), /Join this community first/);
assert.equal(loadAt('2026-10-05T00:00:00Z').call('GET', 'one').week, '2026-10-05');
console.log('Community challenge week, membership, opt-in and aggregate checks passed.');
