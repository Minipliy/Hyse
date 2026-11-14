/// Reserved split point. PocketBase 0.22 applies all pending migrations in a
/// shared transaction, so dependent indexes are installed in a later release.
migrate((_db) => {}, (_db) => {})
