#!/usr/bin/env python3
"""Fails when a simple visible German SwiftUI literal lacks an English catalogue entry."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
catalogue = root / "CalorieTrackerApp/en.lproj/Localizable.strings"
known = set(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', catalogue.read_text(), re.MULTILINE))
visible = re.compile(r'(?:Text|Button|Label|Section|SecureField|TextField|navigationTitle|accessibilityLabel|alert)\(\s*"((?:[^"\\]|\\.)*)"')
german = re.compile(r'[äöüÄÖÜß]|\b(?:Abbrechen|Bearbeiten|Eintrag|Einstellungen|Erstellen|Frühstück|Gespeicherte|Kalorien|Lebensmittel|Löschen|Mahlzeit|Menge|Nährwert|Passwort|Speichern|Trink|Zurück|Zucker)\b')
missing = []
for source in sorted((root / "CalorieTrackerApp").glob("*.swift")):
    for match in visible.finditer(source.read_text()):
        value = match.group(1)
        if "\\(" not in value and german.search(value) and value not in known:
            missing.append(f"{source.name}: {value}")
if missing:
    print("Missing English localizations:")
    print("\n".join(missing))
    sys.exit(1)
print(f"Localization check passed ({len(known)} catalogue keys).")
