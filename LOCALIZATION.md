# Hyse localization rules

English is the product's source language and runtime fallback. New installations
start in English. A user can explicitly select German in Settings; the selection
is persisted in `app_language_v1` and applies immediately through the app's locale
environment.
The same preference is mirrored into the app group so the widget uses English
by default and follows an explicit German selection. Widget strings live in the
corresponding `CalorieWidget/<language>.lproj` catalogs.

For every new user-facing string:

1. Add a stable descriptive key and English source value to
   `CalorieTrackerApp/en.lproj/Localizable.strings`.
2. Add the German translation under the identical key to
   `CalorieTrackerApp/de.lproj/Localizable.strings`.
3. Use `language.text("feature.descriptive_key")` for runtime `String` values, or
   the stable key directly where SwiftUI accepts `LocalizedStringKey`.
4. Keep storage, API payloads, filters and status values language-independent.
   Examples: `breakfast`, `pending`, `synced`, `pending_sync`.
5. Run `ruby scripts/audit_localizations.rb` before committing. It rejects missing
   sources/translations, unused keys, placeholder mismatches and obvious hard-coded
   SwiftUI text.

Never use a German sentence as a localization key and never put translated meal
or status names into PocketBase.
