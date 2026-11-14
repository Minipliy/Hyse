#!/usr/bin/env python3
"""Check search-index updates for metadata edits, renaming and visibility."""
import json
from pathlib import Path
import sqlite3
import subprocess

root = Path(__file__).resolve().parent.parent
migration = root / 'pb_migrations/1788700539_global_food_fts_update_guard.js'
queries = json.loads(subprocess.check_output(['node', '-e', '''
const fs = require('fs'), vm = require('vm');
const queries = {up: [], down: []};
vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), {
  migrate(up, down) {
    for (const [name, fn] of [['up', up], ['down', down]]) {
      fn({newQuery(sql) { return {execute() { queries[name].push(sql); }}; }});
    }
  }
});
process.stdout.write(JSON.stringify(queries));
''', str(migration)], text=True))
db = sqlite3.connect(':memory:')
db.executescript("""
CREATE TABLE global_foods(id TEXT PRIMARY KEY, name TEXT, name_de TEXT,
  brand TEXT, moderation_status TEXT, source TEXT);
CREATE VIRTUAL TABLE global_foods_fts USING fts5(record_id UNINDEXED, name, name_de, brand);
INSERT INTO global_foods VALUES ('one', 'Apple', 'Apfel', '', 'approved', '');
INSERT INTO global_foods_fts VALUES ('one', 'Apple', 'Apfel', '');
""")
for sql in queries['up']:
    db.execute(sql)
before = db.total_changes
db.execute("UPDATE global_foods SET source='open_food_facts'")
assert db.total_changes - before == 1, 'Metadata edits rewrote the search index'
db.execute("UPDATE global_foods SET name='Pear', name_de='Birne'")
assert db.execute("SELECT count(*) FROM global_foods_fts WHERE global_foods_fts MATCH 'Apple'").fetchone()[0] == 0
assert db.execute("SELECT count(*) FROM global_foods_fts WHERE global_foods_fts MATCH 'Pear'").fetchone()[0] == 1
db.execute("UPDATE global_foods SET moderation_status='pending'")
assert db.execute('SELECT count(*) FROM global_foods_fts').fetchone()[0] == 0
db.execute("UPDATE global_foods SET moderation_status='approved', brand='Example'")
assert db.execute("SELECT count(*) FROM global_foods_fts WHERE global_foods_fts MATCH 'Example'").fetchone()[0] == 1
db.execute("UPDATE global_foods SET id='two'")
assert db.execute('SELECT record_id FROM global_foods_fts').fetchall() == [('two',)]
for sql in queries['down']:
    db.execute(sql)
before = db.total_changes
db.execute("UPDATE global_foods SET source='user'")
assert db.total_changes - before > 1, 'Rollback did not restore the old trigger'
print('Search-index update guard and rollback passed.')
