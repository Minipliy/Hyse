/// Im öffentlichen Repository geleert.
/// Diese frühe Entwicklungs-Migration (altes Modell "foods"/"consumed_foods")
/// nutzte eine neuere PocketBase-Schnittstelle und wurde im Betrieb nie
/// verwendet. Das aktuelle Schema entsteht durch die folgenden Migrationen.
migrate((db) => {}, (db) => {})
