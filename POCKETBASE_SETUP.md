# Hyse: PocketBase-Einrichtung

## Collections und Regeln

### Aktuelles kontoabhängiges Offline-Schema

Die Migration `pb_migrations/1787490000_account_food_sync.js` erweitert das bestehende Produktionsschema ohne parallele Tagebuch-Collection:

| Collection | Zweck | Zugriff |
|---|---|---|
| `global_foods` | Administrativ gepflegter globaler Katalog | List/View nur angemeldet; Create/Update/Delete nur Superuser/Admin |
| `user_foods` | Persönlich gespeicherte Lebensmittel mit stabiler `client_id` | ausschließlich `user = @request.auth.id`; Create prüft zusätzlich den angemeldeten Nutzer |
| `food_entries` | Gegessene Einträge mit Nährwert-Snapshot, `eaten_at` und stabiler `client_id` | ausschließlich `user = @request.auth.id`; Create prüft zusätzlich den angemeldeten Nutzer |

Eindeutige Indizes auf `(user, client_id)` machen wiederholte Offline-Uploads idempotent. Zusätzliche Indizes auf `(user, eaten_at)`, `(user, name)` sowie globale Namen/Barcodes beschleunigen Wiederherstellung und Suche.

Die App lädt nach Login zuerst die Serverdaten. Nur ausdrücklich als geändert markierte lokale Datensätze werden anschließend hochgeladen. Löschungen werden als persistente Tombstones gespeichert und niemals aus einer lediglich leeren lokalen Liste abgeleitet. Beim Logout bleiben Serverdaten unangetastet; der sichtbare Store wechselt sofort zurück in den getrennten Gastbereich.

`GlobalFoodService` lädt den nur lesbaren Katalog `global_foods` nach Login und beim Öffnen der Lebensmittelauswahl, speichert ihn als geräteweiten Cache und führt ihn anhand von Barcode beziehungsweise normalisiertem Namen und Kernnährwerten mit persönlichen Lebensmitteln zusammen. Die Migration `1787493000_seed_global_foods.js` stellt die drei mit Hyse ausgelieferten Standardlebensmittel idempotent global bereit. Direkte Collection-Schreibrechte bleiben gesperrt; validierte Hyse-Endpunkte veröffentlichen neue und bearbeitete Lebensmittel automatisch.

Neue, selbst angelegte Lebensmittel werden zuerst lokal und als persönlicher `user_foods`-Datensatz gespeichert. `/api/hyse/global-foods/submit-new` beziehungsweise `submit-change` validieren die Daten, deduplizieren sie anhand von Barcode und normalisiertem Nährwertschlüssel und veröffentlichen den Datensatz anschließend sofort als `approved` in `global_foods`. Die Submission-Historie bleibt zur Nachvollziehbarkeit erhalten; der admin-geschützte Review-Endpunkt wird nur noch für ältere ausstehende Einreichungen benötigt.

Die Migration `1787751100_submission_only_global_foods.js` inventarisiert frühere, eindeutig ungeprüfte benutzererstellte globale Datensätze idempotent in `global_food_migration_audit`, erzeugt dazu ausstehende Einreichungen und blendet die Originale über die API-Regeln aus. Sie löscht weder Originale noch Mahlzeiten oder persönliche Lebensmittel. Der Audit-Snapshot und `migration_origin` ermöglichen Prüfung und gezieltes Rollback.

Für das aktuelle Docker-Deployment wird `./pb_migrations` nach `/pb/pb_migrations` eingebunden. Nach einem Restore oder Neuaufsetzen genügt `docker compose up -d`; PocketBase führt nicht angewendete Migrationen beim Start aus. Im Dashboard sind keine weiteren manuellen Schemaänderungen erforderlich.

## Automatische Backups

Die Migration `pb_migrations/1787751900_enable_automatic_backups.js` aktiviert PocketBases eingebaute automatische Sicherung täglich um **03:15 Uhr in der Zeitzone des Servers** und begrenzt die Aufbewahrung auf **2** automatisch erzeugte Sicherungen. Die spätere Migration `pb_migrations/1791000500_limit_automatic_backups_to_two.js` setzt dieselbe Grenze auch auf bestehenden Installationen durch; ältere automatische Sicherungen entfernt PocketBase selbstständig. Das Produktions-Volume `./pb_data:/pb/pb_data` speichert die lokalen ZIP-Sicherungen auch dann weiter, wenn der Container ersetzt oder neu gestartet wird.

Die Sicherungen sind im PocketBase-Dashboard unter **Settings → Backups** sichtbar und können dort heruntergeladen oder wiederhergestellt werden. Eine lokale Sicherung schützt nicht vor dem Verlust des gesamten Servers. Für zusätzlichen Schutz kann in diesem Bereich ein ausschließlich für Backups verwendeter S3-kompatibler Bucket eingerichtet werden; Zugangsdaten gehören nur in die Serverkonfiguration und niemals in dieses Repository.

Die ältere Entwicklungs-Migration `pb_migrations/1730000000_create_food_collections.js` dokumentiert das frühere `foods`/`consumed_foods`-Modell und wird auf der bestehenden Produktionsinstanz nicht mehr verwendet.

| Collection | Zweck | Zugriffsregeln |
|---|---|---|
| `foods` | gemeinsamer Katalog: `name`, `brand`, eindeutiger optionaler `barcode`, `calories`, `protein`, `carbs`, `fat` je 100, `servingSize`, `unit`, `category`, optional `createdBy` | Lesen: alle; Anlegen: angemeldet; Ändern/Löschen: nur `createdBy = @request.auth.id` |
| `consumed_foods` | Tagebuch: erforderliches `user`, optionales `food`, `clientId`, `nameSnapshot`, Nährwert-Snapshots, `amount`, `unit`, `consumedAt`, `mealType`, `notes` | Listen/Ansehen/Ändern/Löschen: `user = @request.auth.id`; Anlegen zusätzlich `user = @request.auth.id` |

Die `clientId` verhindert doppelte Uploads nach Offline-Fehlern. Nährwert-Snapshots bleiben unverändert, selbst wenn sich ein Katalog-Lebensmittel später ändert.

## E-Mail-Verifizierung und SMTP

Die Migration `pb_migrations/1787491800_hyse_email_templates.js` richtet die Vorlagen erstmals ein. `pb_migrations/1787494200_hyse_email_design_system.js` führte das gemeinsame Grunddesign ein; die aktuelle Migration `pb_migrations/1787751910_hyse_account_email_refresh.js` installiert das überarbeitete responsive Hyse-Layout für Verifizierung, Passwort-Zurücksetzen und die Bestätigung einer E-Mail-Änderung. Es verwendet statische Hyse-Farben, klar getrennte Sicherheitsinformationen, mobile Vollbreiten-Schaltflächen und einen Dark Mode. Die von PocketBase erzeugte Variable `{ACTION_URL}` bleibt unverändert als Schaltfläche und als kopierbarer Ersatzlink enthalten. Die vom sicheren Hyse-E-Mail-Wechsel in `pb_hooks/secure_email_change.pb.js` direkt versendeten Bestätigungs- und Sicherheitsmails verwenden dasselbe Design.

Die Migration `pb_migrations/1790200000_hyse_email_verification_app_redirect.js` setzt die Action-URL der Konto-Verifizierung auf `https://hyse.minipliy.net/api/hyse/verify-email/{TOKEN}`. Der zugehörige Hook `pb_hooks/email_verification_callback.pb.js` erzwingt diese Adresse zusätzlich im final gerenderten Mailtext, prüft das Token serverseitig und aktiviert das Konto. Anschließend zeigt er eine Hyse-Bestätigungsseite, die `hyseapp://login?verified=1` automatisch öffnet und denselben Deep-Link als sichtbaren Button anbietet. Dadurch öffnet sich Hyse direkt mit dem Anmeldedialog; das Verifizierungs-Token wird dabei nicht an die App weitergegeben.

1. In PocketBase **Settings → Mail settings** SMTP-Host, Port, Benutzer, Passwort und Absender eintragen. Verwende TLS/STARTTLS entsprechend deinem Anbieter und einen dedizierten SMTP-Zugang; keine Zugangsdaten in der iOS-App oder im Repository ablegen.
2. In **Collections → users → Options** Passwort-Anmeldung aktiv lassen und die Verifizierungs-Mailvorlage aktivieren/anpassen. Die Vorlage muss den PocketBase-Verifizierungslink enthalten.
3. Über **Settings → Mail settings → Test email** eine Testmail versenden und Darstellung sowie Zustellung auf Smartphone und Desktop prüfen.

Die App fordert nach Registrierung `request-verification` an, akzeptiert beim Login nur `record.verified == true` und bietet einen erneuten Versand an. Das ist serverseitig geprüft.

Die Anmeldeansicht verwendet außerdem die PocketBase-Standardabläufe `request-password-reset` und `request-email-change`. Reset-Anfragen zeigen unabhängig davon, ob ein Konto existiert, denselben neutralen Erfolgstext. E-Mail-Änderungen werden authentifiziert angefordert und erst nach Öffnen des Links aktiv. Beim App-Start sowie bei jeder Rückkehr in den Vordergrund aktualisiert `auth-refresh` Token und sichtbare Kontodaten. Die Action-URL für die Konto-Verifizierung muss auf den oben genannten Hyse-Callback zeigen; die anderen Action URLs müssen weiterhin auf erreichbare PocketBase-Standardseiten oder gleichwertige öffentliche Bestätigungsseiten zeigen.

## Google OAuth

1. In Google Cloud Console ein OAuth-Client vom Typ **Web application** anlegen.
2. Unter **Google Auth Platform → Clients → Webclient 1 → Autorisierte Weiterleitungs-URIs** exakt eintragen: `https://hyse.minipliy.net/api/hyse/oauth2-callback` (HTTPS, kein Port, kein abschließender Slash).
3. In PocketBase 0.22.21 unter **Settings → Auth providers → Google** den Provider aktivieren und Client-ID sowie Client-Secret des Google-Clients vom Typ **Webanwendung** eintragen. Das Secret bleibt ausschließlich dort.
4. Die iOS-App verwendet den manuellen PocketBase-Codeaustausch mit dem von `auth-methods` gelieferten PKCE-Verifier; sie kennt nie das Google-Secret.

Stand der Live-Prüfung vom 23.08.2026: Google wird von `users/auth-methods` angeboten. PocketBase 0.22.21 liefert in der Provider-URL absichtlich `redirect_uri=` leer; beim manuellen OAuth2-Code-Flow setzt die App die Redirect-URI ein und sendet beim anschließenden POST an `auth-with-oauth2` denselben Wert zusammen mit `codeVerifier`. Das zuvor vorhandene Leerzeichen in der Client-ID wurde entfernt.

Der Google-Client enthielt bei der Prüfung nur `https://hyse.minipliy.net/api/oauth2-redirect`. Diese PocketBase-Systemroute gehört nicht zum mobilen App-Callback und kann `ASWebAuthenticationSession` nicht über das App-Scheme fortsetzen. Für Hyse ist deshalb zusätzlich die obige `/api/hyse/oauth2-callback`-URI erforderlich.

## Apple OAuth

1. In Apple Developer die **Services ID** `com.minipliy.hyse.auth` öffnen. Unter **Sign in with Apple → Configure** die Domain `hyse.minipliy.net` und als Return URL exakt `https://hyse.minipliy.net/api/hyse/oauth2-callback` hinterlegen (HTTPS, kein abschließender Slash).
2. Einen Sign-in-with-Apple-Key erstellen und Key-ID, Team-ID, Services-ID/Client-ID und die `.p8`-Datei sicher verwahren.
3. In PocketBase bei Apple OAuth2 diese Werte hinterlegen. Über **Settings → Mail settings / OAuth2** (je nach PocketBase-Version) den Apple Client Secret JWT erzeugen lassen oder mit PocketBase `generateAppleClientSecret` aus Key-ID, Team-ID, Client-ID und privatem Schlüssel generieren. Der JWT hat eine begrenzte Laufzeit und muss vor Ablauf ersetzt werden.
4. Für native iOS-Anmeldung zusätzlich die Capability **Sign in with Apple** für die App-ID `com.hyse.HyseApp` aktivieren.

Apple liefert Name und E-Mail nur bei der ersten Zustimmung; ordne bestehende Konten deshalb über PocketBases OAuth2-Identität bzw. verifizierte E-Mail zu, nicht über den Anzeigenamen.

Stand der Live-Prüfung vom 12.09.2026: Apple wird von `users/auth-methods` angeboten und PocketBase liefert `response_mode=form_post`. Apple lehnt die produktive Callback-Adresse derzeit jedoch als `Invalid web redirect url.` ab; Domain und Return URL müssen deshalb für die Services ID `com.minipliy.hyse.auth` wie oben beschrieben gespeichert werden. Außerdem antwortet die produktive Route auf `GET`, aber noch nicht auf den für Apple erforderlichen `POST`. Nach dem Bereitstellen von `pb_hooks/oauth2_callback.pb.js` muss der PocketBase-Container neu gestartet und der POST-Test unten erneut ausgeführt werden.

## Mobiler OAuth-Callback

Google und insbesondere Apple benötigen eine öffentliche HTTPS-Redirect-URL. Auf `hyse.minipliy.net` muss deshalb folgende Route erreichbar sein:

`GET https://hyse.minipliy.net/api/hyse/oauth2-callback`

Für Apple muss dieselbe Route zusätzlich `POST` mit `application/x-www-form-urlencoded` akzeptieren, da Apple Autorisierungscode und Status bei angefordertem Namen oder E-Mail-Feld per `form_post` zurücksendet.

Sie liest ausschließlich `code`, `state`, `error` und `error_description` aus der Query und antwortet mit einem HTTP-302-Redirect auf:

`hyseapp://oauth-callback?code=…&state=…`

beziehungsweise im Fehlerfall:

`hyseapp://oauth-callback?error=…&error_description=…&state=…`

Die Route darf den Code weder protokollieren noch selbst tauschen. Sie muss Query-Werte beim Aufbau der Ziel-URL percent-encoden. Die App vergleicht `state` mit dem unmittelbar zuvor von PocketBase gelieferten Wert und tauscht den Code anschließend mit demselben PKCE-Verifier und der Redirect-URL `https://hyse.minipliy.net/api/hyse/oauth2-callback`.

Im Xcode-Projekt ist der URL Type bereits für die Bundle-ID `com.hyse.HyseApp` und das Scheme `hyseapp` eingetragen. Für diesen Custom-Scheme-Flow sind keine Associated Domains erforderlich.

Stand der Live-Prüfung vom 23.08.2026: Die Route ist auf dem Produktionsserver bereitgestellt. Ein Test mit percent-encodierten Parametern antwortete mit HTTP 302 auf `hyseapp://oauth-callback` und bewahrte `code` und `state` korrekt.

Die Implementierung liegt unter `pb_hooks/oauth2_callback.pb.js`. Auf dem Produktionsserver ist `pb_hooks` ebenso wie `pb_data` als persistentes Volume in den PocketBase-Docker-Container eingebunden. Nach Änderungen am Hook muss der PocketBase-Container neu gestartet werden. Ein Aufruf der Route mit Testparametern muss per HTTP 302 auf `hyseapp://oauth-callback` weiterleiten.

### Adressen je Umgebung

Jede Umgebung benötigt eine vom OAuth-Anbieter erreichbare HTTPS-Redirect-URI und einen passenden Web-OAuth-Client. `localhost`, `127.0.0.1` und private LAN-Adressen des Macs sind vom echten iPhone beziehungsweise von Google nicht zuverlässig erreichbar und dürfen nicht mit der Produktions-URI vermischt werden.

| Umgebung | PocketBase-Basisadresse | Google-Redirect-URI |
|---|---|---|
| Produktion, Simulator und echtes iPhone gegen Produktion | `https://hyse.minipliy.net` | `https://hyse.minipliy.net/api/hyse/oauth2-callback` |
| Lokale Entwicklung im Simulator | z. B. `http://127.0.0.1:8090` | separater, öffentlich erreichbarer HTTPS-Dev-Host mit derselben Callback-Route |
| Lokale Entwicklung auf echtem iPhone | LAN-Adresse des Macs reicht für Google OAuth nicht aus | separater HTTPS-Dev-Host/Tunnel; dessen vollständige URI separat im Dev-Webclient registrieren |

Basisadresse und Redirect-URI dürfen niemals aus verschiedenen Umgebungen kombiniert werden. Für Produktion verwendet die App derzeit bewusst die fest eingetragene Produktionsadresse.

## Öffentliche Website und OAuth-Branding

Die statischen Seiten in `pb_public` werden von PocketBase ohne Anmeldung ausgeliefert. Der Produktionscontainer bindet das Verzeichnis über `./pb_public:/pb/pb_public` ein; die vollständige Compose-Konfiguration liegt in `docker-compose.production.yml`.

| Google-Branding-Feld | Öffentliche URL |
|---|---|
| Startseite der Anwendung | `https://hyse.minipliy.net/` |
| Datenschutzerklärung | `https://hyse.minipliy.net/datenschutz` |
| Nutzungsbedingungen | `https://hyse.minipliy.net/nutzungsbedingungen` |

`minipliy.net` bleibt in Google Cloud als autorisierte Domain eingetragen. `robots.txt` erlaubt die Indexierung und verweist auf `sitemap.xml`. Die Betreiber- und Hostingangaben sind eingetragen; die Rechtstexte sollten vor einer endgültigen Freigabe trotzdem fachkundig geprüft werden.

Die URL-Präfix-Property `https://hyse.minipliy.net/` ist in der Google Search Console per dauerhaftem `google-site-verification`-Meta-Tag bestätigt. Dieses Meta-Tag in `pb_public/index.html` darf nicht entfernt werden, da sonst die Inhaberschaftsbestätigung verloren gehen kann. Stand 23.08.2026 ist das OAuth-Branding überprüft, veröffentlicht und wird Nutzern angezeigt.

## Kontolöschung

Angemeldete Nutzer können ihr Konto unter **Einstellungen → Account → Konto dauerhaft löschen** entfernen. Die App ruft dafür authentifiziert `DELETE /api/hyse/account` auf. Die geschützte Hook-Route in `pb_hooks/account_deletion.pb.js` löscht zuerst alle kontobezogenen Backenddatensätze und anschließend das PocketBase-Benutzerkonto in einer Transaktion. Lokale Gast- beziehungsweise Gerätedaten bleiben bewusst erhalten und können separat vom Nutzer gelöscht werden.

## Testplan

1. Registrierung: Mail kommt an; Login vor Bestätigung ist gesperrt; nach Link-Bestätigung ist Login möglich; erneuter Versand funktioniert.
2. Google und Apple: Erfolgreich anmelden, abbrechen, bereits vorhandenes Konto und fehlende Provider-Konfiguration testen.
3. Auf Gerät A zwei Einträge anlegen, ausloggen, App löschen/neu installieren, wieder anmelden: beide Einträge erscheinen. Auf Gerät B ändern/löschen und erneut öffnen.
4. Als Gast Lebensmittel erfassen und einloggen: eindeutige Gast-Lebensmittel werden automatisch in das angemeldete Konto übernommen; inhaltlich gleiche Datensätze dürfen nicht doppelt erscheinen. Kontrollieren, dass beim anderen Konto keine Daten dieses Kontos erscheinen.
5. Ein Rezept mit `g` und `ml` anlegen, Menge/Einheit bearbeiten, eine Zutat löschen; Speichern bei `0` oder negativer Menge muss gesperrt sein. Kombinierte Rezeptfilter setzen und zurücksetzen.
# Food usage and barcode lookup

Migration `1787751000_food_usage_and_normalized_barcodes.js` creates the private
`user_food_usage` aggregate. Its create/update/delete API rules are locked; only
`user_food_usage.pb.js` may rebuild it from account-owned `user_foods` meal
entries. `(user, client_id)` remains the idempotency boundary for meals and
`(user, source_key)` is unique for aggregates. Deleting or editing a meal runs a
full per-account rebuild, so meal history always wins over an old aggregate.
`POST /api/hyse/food-usage/rebuild` offers the same authenticated, idempotent
repair operation and is called during account hydration.

The migration performs the initial rebuild for existing accounts and stores a
snapshot `source_key` on historical entries. This preserves history after a
catalogue relation is removed. Personal foods linked to a global record later
are canonicalized to the global key on rebuild, avoiding double counts.

Barcode fields keep both `barcode_raw` and `barcode_normalized`. EAN-8, UPC-A,
EAN-13 and GTIN-14 use the GS1 check digit. PocketBase indexes normalized
personal barcodes by owner and permits only one approved global catalogue row
per normalized barcode. Pending conflicts stay in moderation.

The scanner checks the user-scoped local cache, private PocketBase foods, and
approved global PocketBase foods before Open Food Facts. Open Food Facts is an
8-second fallback with in-flight request coalescing and a five-minute negative
cache. Imported records retain provider, provider ID, and fetch time and remain
private until a separate catalogue-submission action. Open Food Facts data is
subject to its ODbL database license and product images/data may carry CC BY-SA
attribution requirements.

`pb_migrations/1788093000_open_food_facts_de_top_1000.js` ergänzt den globalen
PocketBase-Katalog um 1.000 häufig in Deutschland gescannte Produkte. Grundlage
ist der tägliche Open-Food-Facts-CSV-Export vom 30.08.2026: zuerst die deutsche
Top-1.000-Ranggruppe 2025, nach Barcode- und Nährwertprüfung aufgefüllt aus der
deutschen Top-5.000-Ranggruppe. Der Import ist anhand des normalisierten GTIN
idempotent, überschreibt keine kuratierten oder nutzererstellten Datensätze und
veröffentlicht nur geprüfte Datensätze als `approved`. Produktbilder werden
nicht übernommen. `GlobalFoodService` lädt den Katalog in 500er-Seiten, während
die Barcode-Abfrage weiterhin direkt den vorhandenen PocketBase-Index nutzt.

Der reproduzierbare Generator liegt unter
`scripts/generate_open_food_facts_de_seed.py`. Open Food Facts wird als Quelle
mit ODbL-1.0-Hinweis in jedem Datensatz gespeichert. Vor einer späteren
Aktualisierung sollten Exportdatum und verwendete deutsche Popularitätsperiode
im Generator bewusst angehoben und die Regressionstests erneut ausgeführt
werden.

### Diversitätserweiterung des OFF-Katalogs

`scripts/expand_open_food_facts_catalog.py` streamt den vollständigen kompakten
OFF-Export, ohne ihn oder eine große Kandidatenliste auf dem Server abzulegen.
Deutschland wird über `countries_tags` beziehungsweise deutsche Popularitäts-
Tags erkannt. Pro normalisiertem Lebensmittelkonzept werden höchstens drei
Produktvarianten übernommen; vorhandene Barcodes und Katalogschlüssel werden
übersprungen. Der Import speichert weiterhin keine Produktbilder oder Zutaten-
Blobs. Er stoppt barcodierte Produkte bei 1,65 GB und alle Schreibvorgänge bei
1,8 GB Datenbankgröße, sodass SQLite-WAL und Sicherungen unterhalb der vom
Betreiber gesetzten 2-GB-Obergrenze bleiben.

Spezifische Blattkategorien der offiziellen OFF-Taxonomie werden aus bis zu neun
plausiblen, häufig gescannten Produkten robust gemittelt und als barcodefreie
Durchschnittseinträge veröffentlicht. `scripts/add_off_homemade_aggregates.py`
ergänzt typische selbstgemachte Suchbegriffe wie Bananenbrot, Kuchen, Soßen,
Salate und Hausgerichte aus bereits importierten OFF-Produkten. Diese Datensätze
tragen `average_values = true` und nennen OFF/ODbL in Quelle und Hinweis.

Da ein großer Katalog nicht vollständig auf jedes iPhone geladen werden darf,
hält `GlobalFoodService` nur einen kompakten Offline-Grundbestand. Texteingaben
ab zwei Zeichen werden nach 120 ms über die authentifizierte, auf 80 Ergebnisse
begrenzte Route `/api/hyse/global-foods/search` gesucht und anschließend lokal
zwischengespeichert. Barcodeabfragen verwenden weiterhin den eigenen Index.

## Remote-Lebensmittelanalyse (ausgesetzt)

Die Endpunkte `/api/hyse/ai/food-photo` und `/api/hyse/ai/food-text` antworten
mit HTTP 503 und leiten keine Inhalte an Gemini weiter. Die App bietet nur die
lokale Texterfassung an. Ein vorhandener `GEMINI_API_KEY` hat keine Wirkung.
Vor einer erneuten Aktivierung müssen insbesondere Anbieterbedingungen für
Minderjährige und EWR-Clients, ein bezahlter API-Dienst, eine echte freiwillige
Einwilligung für Gesundheitsdaten, Vertrags- und Datenschutzhinweise sowie
Produktversprechen erneut geprüft und umgesetzt werden.

## Meldungen ohne Konto aus der App

`pb_migrations/1791000600_public_content_reports.js` legt den privaten
Meldebestand `public_content_reports` an. `pb_hooks/public_content_reports.pb.js`
nimmt unter `POST /api/hyse/reports/public` Meldungen aus der App entgegen,
auch im Gastmodus. Die Sammlung darf nicht für direkte API-Zugriffe geöffnet
werden. Moderation muss sowohl `content_reports` als auch
`public_content_reports` prüfen und Entscheidungen zur Gastmeldung an die
angegebene Kontaktadresse senden. Den vom Reverse Proxy ermittelten Client-IP-
Wert und PocketBases Proxy-Konfiguration vor dem Livegang testen; er dient nur
zur Begrenzung von Massenmeldungen. Die Rate-Schlüssel werden stündlich nach
spätestens 48 Stunden entfernt.

## Gym Communities

`pb_migrations/1788570000_gym_communities.js` legt Communities,
Mitgliedschaften und Beiträge als getrennte Collections an. Direkter Zugriff
auf diese Collections bleibt gesperrt; die authentifizierten Routen in
`pb_hooks/gym_communities.pb.js` prüfen Mitgliedschaft und Rolle für jede
Aktion. Community-Inhaber und Administratoren dürfen im Kanal `news`
veröffentlichen, während alle Mitglieder im Kanal `members` schreiben können.

Die iOS-App speichert Communitylisten und bereits geladene Beiträge lokal und
aktualisiert sie höchstens nach Ablauf des Cache-Zeitraums, bei einer Suche
oder nach explizitem Aktualisieren. Erstellen, Beitreten, Verlassen und Senden
sind bewusste Nutzeraktionen und werden deshalb sofort an PocketBase gesendet.
Nach Deployment der Migration und des Hooks muss PocketBase neu gestartet
werden, bevor der Bereich in der Produktions-App verwendet werden kann.
