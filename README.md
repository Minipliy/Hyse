# Hyse – Ernährung und Training auf deinem eigenen Server

> **Wichtiger Hinweis vorab**
>
> Der Code in diesem Repository wurde **mit künstlicher Intelligenz (KI) erstellt** und ist **nicht meine eigene Arbeit**. Ich habe ihn nicht Zeile für Zeile selbst geschrieben und kann nicht für jede Stelle garantieren, dass sie fehlerfrei ist. Nutze ihn auf eigene Verantwortung.
>
> Dieses Repository ist für Menschen gedacht, denen **Privatsphäre wichtig** ist. Statt deine Ernährungs-, Trainings- und Gesundheitsdaten auf einem fremden Server zu speichern, betreibst du Hyse komplett selbst: auf deinem eigenen Server, mit deiner eigenen App-Kennung. Deine Daten bleiben bei dir.

Hyse ist eine iPhone-App mit Widgets und einer Apple-Watch-App. Du kannst damit Mahlzeiten und Kalorien erfassen, Workouts aufzeichnen, Fortschritte verfolgen und optional mit Apple Health zusammenarbeiten.

Diese Anleitung geht davon aus, dass du **noch nie** einen Server eingerichtet oder eine App selbst gebaut hast. Nimm dir Zeit: Beim ersten Mal dauert alles zusammen ungefähr **zwei bis vier Stunden**.

---

## Inhalt

1. [So funktioniert Hyse (in einfachen Worten)](#1-so-funktioniert-hyse-in-einfachen-worten)
2. [Was du brauchst und was es kostet](#2-was-du-brauchst-und-was-es-kostet)
3. [Teil A: Den Server einrichten](#teil-a-den-server-einrichten)
4. [Teil B: Die App auf dein iPhone bringen](#teil-b-die-app-auf-dein-iphone-bringen)
5. [Erste Anmeldung in der App](#erste-anmeldung-in-der-app)
6. [Updates einspielen](#updates-einspielen)
7. [Was ohne Zusatzaufwand nicht funktioniert](#was-ohne-zusatzaufwand-nicht-funktioniert)
8. [Wenn andere Menschen deinen Server nutzen](#wenn-andere-menschen-deinen-server-nutzen)
9. [Hilfe bei Problemen](#hilfe-bei-problemen)
10. [Was in diesem Repository steckt](#was-in-diesem-repository-steckt)

---

## 1. So funktioniert Hyse (in einfachen Worten)

Hyse besteht aus zwei Teilen:

- **Der Server** ist ein Computer im Internet, der rund um die Uhr läuft. Auf ihm liegt die Datenbank mit deinem Konto, deinen Mahlzeiten und deinen Workouts. Wir verwenden dafür das Programm **PocketBase**. Damit die Verbindung verschlüsselt ist (HTTPS), läuft davor das Programm **Caddy**, das sich automatisch um das Sicherheitszertifikat kümmert.
- **Die App** läuft auf deinem iPhone (und optional auf der Apple Watch). Sie speichert alles zuerst auf dem Gerät und gleicht es dann mit deinem Server ab.

Du richtest zuerst den Server ein (Teil A) und baust danach die App so, dass sie mit genau deinem Server spricht (Teil B).

> **Begriffe, die dir begegnen werden**
>
> - **Terminal**: ein Fenster, in das du Befehle eintippst. Auf dem Mac findest du es über die Spotlight-Suche (⌘ + Leertaste, dann „Terminal“ eingeben).
> - **SSH**: eine sichere Verbindung, mit der du vom Terminal aus Befehle auf deinem Server ausführst.
> - **Domain**: eine Internetadresse wie `meine-domain.de`. Eine **Subdomain** ist z. B. `hyse.meine-domain.de`.
> - **DNS-Eintrag**: sagt dem Internet, welcher Server zu deiner (Sub-)Domain gehört.
> - **Docker**: ein Programm, das andere Programme (hier PocketBase und Caddy) fertig verpackt startet.
> - **Xcode**: Apples kostenloses Programm, mit dem man iPhone-Apps baut.

---

## 2. Was du brauchst und was es kostet

| Was | Wofür | Ungefähre Kosten |
| --- | --- | --- |
| Einen **Mac** mit aktuellem macOS | Um die App mit Xcode zu bauen | – (vorhanden) |
| Ein **iPhone** mit iOS 17.4 oder neuer | Darauf läuft die App | – (vorhanden) |
| Optional eine **Apple Watch** mit watchOS 10.4 oder neuer | Für die Watch-App | – (vorhanden) |
| Ein **Apple-Developer-Konto** (Apple Developer Program) | Hyse nutzt App-Gruppen, Apple Health, Push und „Mit Apple anmelden“. Diese Funktionen gibt es nur mit dem bezahlten Konto. | 99 € pro Jahr |
| Einen kleinen **Server (VPS)** bei einem Hoster, z. B. mit 1–2 CPU-Kernen, 2 GB Arbeitsspeicher und Ubuntu | Darauf läuft die Datenbank | ca. 4–6 € pro Monat |
| Eine **Domain** (oder eine Subdomain einer Domain, die du schon hast) | Damit die App deinen Server unter einer festen Adresse findet | ca. 1–15 € pro Jahr |
| Optional ein **E-Mail-Postfach mit SMTP-Zugang** | Damit der Server Bestätigungs-E-Mails verschicken kann | oft bei der Domain dabei |

> **Tipp:** Wähle beim Server einen Anbieter mit Rechenzentrum in Deutschland oder der EU, wenn dir Datenschutz wichtig ist.

---

## Teil A: Den Server einrichten

### A1. Server mieten

1. Miete bei einem Hoster deiner Wahl einen kleinen Server (VPS) mit **Ubuntu 24.04**.
2. Nach dem Kauf bekommst du eine **IP-Adresse** (z. B. `203.0.113.10`) und Zugangsdaten. Am sichersten ist die Anmeldung mit einem **SSH-Schlüssel**; die meisten Hoster erklären in ihrem Kundenbereich, wie du ihn hinterlegst.

### A2. Domain auf den Server zeigen lassen

1. Öffne die Verwaltung deiner Domain (beim Domain-Anbieter).
2. Lege einen **A-Eintrag** an:
   - **Name/Host:** `hyse` (dann heißt deine Adresse `hyse.meine-domain.de`)
   - **Wert/Ziel:** die IP-Adresse deines Servers
3. Speichern. Es kann ein paar Minuten bis Stunden dauern, bis der Eintrag überall bekannt ist.

Ab hier nennen wir deine Adresse **`hyse.meine-domain.de`**. Ersetze sie überall durch deine eigene.

### A3. Mit dem Server verbinden

Öffne auf deinem Mac das **Terminal** und gib ein (IP-Adresse ersetzen):

```bash
ssh root@203.0.113.10
```

Beim ersten Mal fragt das Terminal, ob du dem Server vertraust. Tippe `yes` und drücke Enter. Jetzt laufen alle Befehle, die du eintippst, auf deinem Server.

### A4. Server aktualisieren und Docker installieren

Kopiere die folgenden Befehle nacheinander ins Terminal und drücke nach jedem Enter:

```bash
apt update && apt upgrade -y
```

```bash
apt install -y git
```

```bash
curl -fsSL https://get.docker.com | sh
```

Prüfe, ob Docker läuft:

```bash
docker --version
```

Es sollte eine Versionsnummer erscheinen.

### A5. Hyse herunterladen

```bash
git clone https://github.com/Minipliy/Hyse.git
```

```bash
cd Hyse/server
```

### A6. Einstellungen eintragen

Erstelle aus der Vorlage deine eigene Einstellungsdatei:

```bash
cp .env.example .env
```

Öffne sie zum Bearbeiten:

```bash
nano .env
```

Ändere diese Zeilen (mit den Pfeiltasten bewegen, tippen wie gewohnt):

```text
HYSE_DOMAIN=hyse.meine-domain.de
HYSE_PUBLIC_URL=https://hyse.meine-domain.de
HYSE_SENDER_EMAIL=du@meine-domain.de
HYSE_CONTACT_EMAIL=du@meine-domain.de
```

Speichern mit **Strg + O**, dann **Enter**, beenden mit **Strg + X**.

### A7. Server starten

```bash
docker compose up -d --build
```

Beim ersten Mal dauert das ein paar Minuten. Docker lädt PocketBase und Caddy herunter, Caddy holt das HTTPS-Zertifikat, und PocketBase legt die Datenbank an.

Prüfe danach im Browser auf deinem Mac:

- `https://hyse.meine-domain.de/api/health` → Es sollte `"API is healthy."` erscheinen.

Falls nicht: Warte ein paar Minuten (der DNS-Eintrag ist eventuell noch nicht aktiv) und sieh dir die Meldungen an mit `docker compose logs`.

### A8. Administrator-Konto anlegen

1. Öffne im Browser `https://hyse.meine-domain.de/_/`.
2. Lege dort ein **Administrator-Konto** mit E-Mail-Adresse und einem langen, sicheren Passwort an. Dieses Konto ist nur für die Verwaltung gedacht, nicht für die App.

### A9. E-Mail-Versand einrichten (empfohlen)

Hyse verlangt, dass neue Konten ihre E-Mail-Adresse bestätigen. Dafür muss der Server E-Mails verschicken können.

1. Im Verwaltungsbereich (`/_/`) auf **Settings → Mail settings**.
2. **SMTP** aktivieren und die Daten deines E-Mail-Anbieters eintragen (Server, Port, Benutzer, Passwort). Diese Daten findest du in der Hilfe deines E-Mail-Anbieters unter „SMTP“.
3. Als Absender deine E-Mail-Adresse eintragen und mit **Send test email** prüfen.

> **Ohne E-Mail-Versand:** Du kannst ein Konto auch von Hand bestätigen. Nach der Registrierung in der App öffnest du im Verwaltungsbereich **Collections → users**, klickst auf dein Konto, setzt den Schalter **Verified** und speicherst.

### A10. Backups

PocketBase erstellt automatisch jede Nacht eine Sicherung (im Verwaltungsbereich unter **Settings → Backups**). Sie liegt auf demselben Server. Lade ab und zu eine Sicherung herunter und bewahre sie woanders auf.

Der Server-Teil ist fertig. 🎉

---

## Teil B: Die App auf dein iPhone bringen

### B1. Apple-Developer-Konto

1. Melde dich unter [developer.apple.com/programs](https://developer.apple.com/programs/) mit deiner Apple-ID für das **Apple Developer Program** an (99 € pro Jahr). Die Freischaltung kann bis zu zwei Tage dauern.
2. Notiere deine **Team-ID**: Sie steht unter [developer.apple.com/account](https://developer.apple.com/account) im Bereich **Mitgliedschaft** und besteht aus 10 Zeichen, z. B. `AB12CD34EF`.

### B2. Xcode installieren

1. Installiere **Xcode** kostenlos aus dem Mac App Store (groß, ca. 10–15 GB).
2. Starte Xcode einmal und bestätige alle Fragen zur Installation zusätzlicher Komponenten.
3. Wenn du die Watch-App nutzen willst: In Xcode unter **Xcode → Einstellungen → Components** die Plattform **watchOS** herunterladen. Ohne sie lässt sich das Projekt nicht bauen, weil die Watch-App fest dazugehört.
4. Unter **Xcode → Einstellungen → Accounts** mit dem **+** deine Apple-ID hinzufügen.

### B3. Hyse auf den Mac holen

Öffne das Terminal **auf deinem Mac** (nicht auf dem Server) und gib ein:

```bash
cd ~/Desktop
```

```bash
git clone https://github.com/Minipliy/Hyse.git
```

Jetzt liegt auf deinem Schreibtisch der Ordner **Hyse**.

### B4. Die vier Einstellungen der App ändern

Öffne im Ordner **Hyse** die Datei **`Hyse.xcconfig`** mit TextEdit (Rechtsklick → Öffnen mit → TextEdit). Ändere die Werte:

```text
HYSE_DEVELOPMENT_TEAM = AB12CD34EF            ← deine Team-ID aus B1
HYSE_BUNDLE_ID = com.deinname.hyse            ← eine eigene Kennung, z. B. com.maxmuster.hyse
HYSE_APP_GROUP = group.com.deinname.hyse      ← "group." + deine Kennung
HYSE_SERVER_HOST = hyse.meine-domain.de       ← deine Server-Adresse, ohne https://
HYSE_CONTACT_EMAIL = du@meine-domain.de       ← deine E-Mail-Adresse
```

Wichtig:

- Die Kennung darf nur aus Kleinbuchstaben, Zahlen, Punkten und Bindestrichen bestehen und muss **weltweit einmalig** sein. Mit deinem Namen darin bist du auf der sicheren Seite.
- Beim Server **kein** `https://` und **kein** `/` am Ende.

Speichern und schließen.

### B5. Projekt in Xcode öffnen

1. Doppelklicke im Ordner **Hyse** auf **`Hyse.xcodeproj`**. Xcode öffnet sich.
2. Klicke links oben in der Seitenleiste auf den blauen Eintrag **Hyse**.
3. Wähle in der Mitte nacheinander die Targets **Hyse**, **HyseWIdget** und **HyseWatch** und öffne jeweils den Reiter **Signing & Capabilities**:
   - **Automatically manage signing** muss angehakt sein.
   - Unter **Team** sollte dein Team stehen. Falls nicht, wähle es aus.
   - Xcode legt die App-Kennungen und die App-Gruppe dann selbst bei Apple an. Rote Fehlermeldungen verschwinden meist nach ein paar Sekunden. Falls eine Meldung zu „App Groups“ bleibt, klicke bei **App Groups** auf das **+** und trage dieselbe Gruppe wie in `Hyse.xcconfig` ein.

### B6. iPhone vorbereiten

1. Verbinde dein iPhone per Kabel mit dem Mac und tippe auf dem iPhone auf **Vertrauen**.
2. Aktiviere auf dem iPhone den **Entwicklermodus**: **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** einschalten. Das iPhone startet neu.

### B7. App bauen und starten

1. Wähle in Xcode oben in der Mitte als Ziel dein **iPhone** aus (statt eines Simulators).
2. Drücke **⌘ + R** (oder das ▶︎-Symbol oben links).
3. Der erste Build dauert ein paar Minuten. Danach öffnet sich Hyse auf deinem iPhone.

Falls das iPhone meldet, dass der Entwickler nicht vertrauenswürdig ist: **Einstellungen → Allgemein → VPN & Geräteverwaltung**, dort dein Entwicklerprofil antippen und **Vertrauen** wählen.

> **Hinweis:** Eine so installierte App läuft, solange dein Developer-Konto aktiv ist. Wenn du sie Freunden oder Familie geben möchtest, kannst du sie über **TestFlight** verteilen (in Xcode: **Product → Archive**, dann **Distribute App**).

### B8. Apple Watch (optional)

Ist deine Apple Watch mit dem iPhone gekoppelt, installiert Xcode die Watch-App beim Starten automatisch mit. Sonst öffne auf dem iPhone die App **Watch** und installiere Hyse dort unter **Verfügbare Apps**.

---

## Erste Anmeldung in der App

1. Öffne Hyse und tippe auf **Registrieren**.
2. Gib Benutzername, E-Mail-Adresse und Passwort ein.
3. Bestätige die E-Mail über den Link, den dein Server verschickt (oder bestätige das Konto von Hand, siehe A9).
4. Melde dich an. Ab jetzt landen deine Daten auf deinem Server.

Du kannst Hyse auch **ohne Konto** nutzen. Dann bleiben alle Daten nur auf dem iPhone.

---

## Updates einspielen

**Server** (im Terminal per SSH verbunden):

```bash
cd ~/Hyse && git pull && cd server && docker compose up -d --build
```

**App** (im Terminal auf dem Mac):

```bash
cd ~/Desktop/Hyse && git pull
```

Danach in Xcode erneut **⌘ + R** drücken. Falls `git pull` wegen deiner geänderten `Hyse.xcconfig` meckert: Sichere die Datei, führe `git checkout Hyse.xcconfig` und `git pull` aus und trage deine Werte danach wieder ein.

---

## Was ohne Zusatzaufwand nicht funktioniert

Diese Funktionen brauchen zusätzliche Konten oder Schlüssel. Ohne sie läuft Hyse ganz normal, nur diese Teile nicht:

| Funktion | Was dafür nötig wäre |
| --- | --- |
| **Mit Google anmelden / Mit Apple anmelden** | Eigene Zugangsdaten bei Google bzw. Apple und Eintrag in PocketBase unter **Settings → Auth providers**. Details in [`POCKETBASE_SETUP.md`](POCKETBASE_SETUP.md). Anmeldung mit E-Mail und Passwort funktioniert immer. |
| **Push-Mitteilungen** (z. B. Community-Neuigkeiten) | Ein Apple-Push-Schlüssel und das Programm in [`push_gateway/`](push_gateway/). |
| **Geteilte Links öffnen direkt die App** (Universal Links) | In `server/.env` den Wert `HYSE_APPLE_APP_ID` auf `DEINE-TEAM-ID.deine.bundle.id` setzen und den Server neu starten. Hintergrund in [`UNIVERSAL_LINKS_SETUP.md`](UNIVERSAL_LINKS_SETUP.md). |
| **Fotoerkennung von Mahlzeiten über einen KI-Dienst** | Ist auf dem Server abgeschaltet. Die Erkennung direkt auf dem iPhone funktioniert. |
| **Käufe in der App** | Nicht nötig: Auf einem eigenen Server sind alle Funktionen frei. |

---

## Wenn andere Menschen deinen Server nutzen

Solange nur du selbst Hyse auf deinem Server nutzt, ist das eine private Angelegenheit. Sobald andere Menschen ein Konto auf deinem Server anlegen, verarbeitest du **deren Gesundheits- und Fitnessdaten**. Dann gelten in der EU unter anderem die Regeln der DSGVO, und auf der Webseite deines Servers sind in der Regel ein Impressum und eine Datenschutzerklärung nötig. Die Rechtstexte des ursprünglichen Hyse-Betreibers sind bewusst **nicht** in diesem Repository enthalten. Informiere dich vorher, z. B. bei einer Verbraucherzentrale oder einer Anwältin oder einem Anwalt.

---

## Hilfe bei Problemen

Ehrlicher Stand: Der Server-Teil wurde mit einer frischen Datenbank getestet (alle Migrationen laufen durch, der Server startet). Das Bauen der App mit einem **fremden** Apple-Developer-Konto wurde noch nicht auf einem echten iPhone ausprobiert. Wenn etwas hakt, liegt es am wahrscheinlichsten an der Signierung (B5).

| Problem | Lösung |
| --- | --- |
| `https://…/api/health` lädt nicht | DNS-Eintrag prüfen (A2), ein paar Minuten warten, dann `docker compose logs caddy` ansehen. Die Ports 80 und 443 müssen beim Hoster offen sein. |
| Xcode: „watchOS … must be installed“ | Unter **Xcode → Einstellungen → Components** die watchOS-Plattform installieren (B2). |
| Xcode: Fehler bei „Signing“ oder „Provisioning Profile“ | Team ausgewählt? Kennung wirklich einmalig? Bei allen drei Targets **Automatically manage signing** anhaken (B5). |
| App sagt, der Server sei nicht erreichbar | In `Hyse.xcconfig` steht der Server ohne `https://` und ohne `/`? App danach neu bauen. |
| Keine Bestätigungs-E-Mail | SMTP einrichten (A9) oder das Konto von Hand bestätigen. Auch im Spam-Ordner nachsehen. |
| „Developer Mode“ fehlt in den Einstellungen | iPhone einmal per Kabel mit dem Mac verbinden und Xcode geöffnet haben; dann erscheint der Schalter. |

---

## Was in diesem Repository steckt

| Ordner / Datei | Inhalt |
| --- | --- |
| `CalorieTrackerApp/` | Die iPhone-App (Swift/SwiftUI) |
| `CalorieWidget/` | Widgets und Live Activity |
| `HyseWatch/` | Die Apple-Watch-App |
| `Hyse.xcconfig` | Die Einstellungen, die du in B4 änderst |
| `server/` | Alles für deinen Server: Docker, Caddy, Vorlage für `.env` |
| `pb_migrations/` | Legt die Datenbank-Tabellen an (läuft beim Start automatisch) |
| `pb_hooks/` | Serverlogik (z. B. Suche, Teilen, E-Mails) |
| `pb_public/` | Webseiten, die dein Server ausliefert |
| `pb_seeds/` | Lebensmittel-Datenbanken (BLS, USDA) mit Quellenangaben |
| `push_gateway/` | Optionales Programm für Push-Mitteilungen |
| `Tests/`, `scripts/` | Automatische Tests und Hilfsskripte |

Lebensmitteldaten: Bundeslebensmittelschlüssel 4.0 (Max Rubner-Institut, CC BY 4.0) sowie Daten des US-Landwirtschaftsministeriums (USDA). Die Quellenangaben liegen in `pb_seeds/`.

Einige Migrationen sind in diesem öffentlichen Repository bewusst leer. Sie betrafen nur den Betrieb der ursprünglichen Installation (Testkonten für die App-Prüfung und Daten einer bestimmten Fitnessstudio-Community) und enthielten Zugangsdaten oder Daten echter Personen.

## Lizenz

Der Code steht unter der [MIT-Lizenz](LICENSE). Die Lebensmitteldaten in `pb_seeds/` haben eigene Lizenzen, siehe die Quellenangaben dort.
