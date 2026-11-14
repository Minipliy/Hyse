/// Reserved split point after the live PocketBase 0.22 schema repair.
/// Dependent indexes are installed in a later, separately committed migration.
migrate((_db) => {}, (_db) => {})
