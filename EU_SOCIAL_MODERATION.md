# EU-Moderations- und Datenschutzumfang für Hyse

Diese Umsetzung ist eine technische Grundlage und keine Rechtsberatung. Bei
Gym Communities, Profilen, Nachrichten und öffentlichen Trainings speichert
Hyse Inhalte, die Nutzer untereinander verbreiten. Dafür ist ein sauberer
Melde-, Moderations- und Beschwerdeprozess wichtiger als nur ein Button.

## Umgesetzter Umfang

- Meldeformular in der App unter Einstellungen → Datenschutz & Recht, auch ohne
  Hyse-Konto. Es übermittelt Link oder ID, Grund, Erläuterung und Kontaktadresse
  direkt an den privaten PocketBase-Meldebestand. Die Website erklärt diesen Weg
  und nennt die Support-Adresse als Ausweichmöglichkeit.
- Ein elektronischer, authentifizierter Meldeweg für Profil, Profilbild,
  Community, Community-Nachricht, öffentliches Training und Trainingskommentar.
- Kategorien für mutmaßlich rechtswidrige Inhalte, Belästigung, Hassrede,
  sexualisierte Inhalte, Gewalt, Privatsphäre, Spam/Betrug,
  Urheberrecht und sonstige Regelverstöße.
- Freitext-Begründung (10–2.000 Zeichen), Ziel-Snapshot und Bestätigung der
  Meldung nach bestem Wissen und in gutem Glauben.
- Serverseitige Zielprüfung, Zugriffsschutz, Deduplizierung und ein Limit von
  50 Meldungen je Nutzer und 24 Stunden.
- Eingangsbestätigung, Statusansicht unter „Einstellungen → Datenschutz &
  Recht → Meine Meldungen“ und kostenfreie Einspruchsmöglichkeit nach einer
  Entscheidung.
- Direkte Account-Löschung bleibt verfügbar. Reports werden bei Löschung des
  meldenden Accounts über die Reporter-Beziehung mitgelöscht.
- Entscheidungen enthalten Felder für Status, Entscheidungscode und eine
  verständliche Begründung. Die Moderation kann diese Felder im PocketBase
  Admin-Backend setzen; die App zeigt sie dem meldenden Nutzer an.

## Noch vor dem öffentlichen Launch festlegen

1. `hyse@minipliy.net` täglich auf Meldungen prüfen und eine verantwortliche
   Moderationsperson benennen. Eingang zeitnah bestätigen; bei Entscheidungen
   die betroffene Person und die meldende Person mit einer konkreten Begründung
   informieren, soweit Kontakt möglich und rechtlich zulässig. Auch Meldungen ohne Konto aus `public_content_reports` sowie E-Mail-
   Ausweichmeldungen in den Moderationsprozess aufnehmen.
2. Eine verbindliche, nach EU-Mitgliedstaaten geprüfte Liste illegaler Inhalte
   und Community-Regeln definieren; die Kategorien in der App sind nur die
   technische Auswahl.
3. Moderations-SLAs, Eskalation für akute Gefahren und den Umgang mit
   Verdachtsfällen strafbarer Handlungen festlegen. Automatische Moderation
   ist derzeit nicht aktiviert.
4. Einen dokumentierten internen Review-Prozess mit qualifiziertem Personal
   und einer nachvollziehbaren Begründung je Entscheidung einführen.
5. Falls Hyse als Online-Plattform im Sinne des DSA eingeordnet wird, die
   notwendigen Transparenzberichte, Statements of Reasons und den Zugang zu
   einer zertifizierten außergerichtlichen Streitbeilegungsstelle ergänzen.
6. Datenschutzinformation und Löschfristen für Meldungen, Ziel-Snapshots,
   Moderationsentscheidungen und Einsprüche mit der zuständigen Stelle
   abstimmen. Meldungen dürfen nicht länger als für Moderation,
   Missbrauchsschutz oder gesetzliche Pflichten nötig aufbewahrt werden.
7. Einen Datenexport für die eigenen personenbezogenen Daten anbieten bzw.
   den vorhandenen Export-Endpunkt auf Community- und Social-Daten erweitern.

## Technischer Ablauf

`POST /api/hyse/reports` erstellt die Meldung für angemeldete Nutzer.
`POST /api/hyse/reports/public` nimmt das Gastformular aus der App entgegen;
`public_content_reports` ist nur für die Moderation sichtbar. Die Kontakt-E-Mail
wird für Rückfragen und die Entscheidung verwendet. Der kurzlebige IP-Hash zur
Missbrauchsbegrenzung wird nach 48 Stunden aus den Meldungen entfernt.

`GET /api/hyse/reports` zeigt
nur die eigenen Meldungen. Nach einer Entscheidung kann der meldende Nutzer
`POST /api/hyse/reports/:id/appeal` mit einer neuen Begründung einen internen
Einspruch einreichen. Die Collection ist für direkte PocketBase-API-Zugriffe
geschlossen; alle Validierungen passieren in `pb_hooks/content_reports.pb.js`.

## Rechtsgrundlagen, die beim Produkt-Review berücksichtigt wurden

- DSA Art. 16: zugänglicher, nutzerfreundlicher Notice-and-Action-Mechanismus
  mit hinreichend präzisen und begründeten Meldungen.
- DSA Art. 17: klare und spezifische Begründungen, wenn Inhalte oder Zugänge
  eingeschränkt werden.
- DSA Art. 20: leicht zugängliches, kostenloses internes Beschwerdesystem.
- DSA Art. 21: Möglichkeit der außergerichtlichen Streitbeilegung, sofern die
  Plattformpflichten auf Hyse zutreffen.
- DSGVO Art. 17 und 20: Löschung und Datenübertragbarkeit; die Account-Löschung
  muss neben dem Benutzerkonto alle accountbezogenen Social-Daten abdecken.

Die konkrete Einstufung von Hyse, Aufbewahrungsfristen, Meldepflichten und
zuständiger Behörde muss vor dem Launch fachlich/rechtlich bestätigt werden.
