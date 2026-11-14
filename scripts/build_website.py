#!/usr/bin/env python3
"""Build Hyse's static, bilingual public website from one route registry."""

from __future__ import annotations

import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / "pb_public"
SOCIAL_CONFIG = ROOT / "config" / "social_links.json"
ORIGIN = "https://hyse.minipliy.net"
SUPPORT = "hyse@minipliy.net"
ICON = "/assets/hyse-app-icon.webp"
SOCIAL = f"{ORIGIN}/assets/hyse-social-card.webp"
GOOGLE_VERIFICATION = "maH7x7UtfgWvq5m7qqm0BgNgROhT0ekCTRk5syPwnPc"
APP_STORE_URL = "https://apps.apple.com/de/app/hyse/id6811359623"


def app_store_button(language: str) -> str:
    label = "Im App Store laden" if language == "de" else "Download on the App Store"
    return f'<a class="button" href="{APP_STORE_URL}">{label}</a>'

PAGES = [
    ("/en", "/de", "English", "Deutsch"),
    ("/en/features", "/de/funktionen", "Nutrition", "Ernährung"),
    ("/en/workouts", "/de/training", "Gym & Workouts", "Gym & Training"),
    ("/en/ios", "/de/ios", "Hyse for iOS", "Hyse für iOS"),
    ("/en/marketing", "/de/marketing", "About Hyse", "Über Hyse"),
    ("/en/support", "/de/support", "Support", "Support"),
    ("/en/privacy", "/de/datenschutz", "Privacy Policy", "Datenschutzerklärung"),
    ("/en/terms", "/de/agb", "Terms of Use", "Nutzungsbedingungen"),
    ("/en/impressum", "/de/impressum", "Imprint", "Impressum"),
]

PAIR = {path: other for en, de, _, _ in PAGES for path, other in ((en, de), (de, en))}
LABEL = {path: title for en, de, en_title, de_title in PAGES for path, title in ((en, en_title), (de, de_title))}

SOCIAL_PLATFORMS = {
    "instagram": ("Instagram", "instagram.com"),
    "tiktok": ("TikTok", "tiktok.com"),
    "youtube": ("YouTube", "youtube.com"),
    "x": ("X", "x.com"),
    "facebook": ("Facebook", "facebook.com"),
    "linkedin": ("LinkedIn", "linkedin.com"),
}


def social_links() -> list[tuple[str, str, str]]:
    """Return only explicitly configured, HTTPS Hyse profile URLs."""
    if not SOCIAL_CONFIG.exists():
        return []
    values = json.loads(SOCIAL_CONFIG.read_text(encoding="utf-8"))
    if not isinstance(values, dict):
        raise ValueError("config/social_links.json must contain an object")
    links = []
    for platform, url in values.items():
        if not url:
            continue
        if platform not in SOCIAL_PLATFORMS:
            raise ValueError(f"Unsupported social platform: {platform}")
        label, hostname = SOCIAL_PLATFORMS[platform]
        if not re.fullmatch(rf"https://(?:www\.)?{re.escape(hostname)}/[^\s?#]+/?(?:\?[^\s#]*)?", url):
            raise ValueError(f"Invalid {label} profile URL")
        links.append((platform, label, url))
    return links


def write(path: str, content: str) -> None:
    target = PUBLIC / path.lstrip("/") / "index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content.strip() + "\n", encoding="utf-8")


def metadata(path: str, title: str, description: str, language: str, schema: dict | list) -> str:
    counterpart = PAIR[path]
    en_path = path if language == "en" else counterpart
    de_path = path if language == "de" else counterpart
    stylesheet = "/assets/site.css?v=a11y-20261107"
    return f"""
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <meta name="description" content="{html.escape(description, quote=True)}">
  <meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">
  <meta name="google-site-verification" content="{GOOGLE_VERIFICATION}">
  <meta name="apple-itunes-app" content="app-id=6811359623">
  <link rel="canonical" href="{ORIGIN}{path}">
  <link rel="alternate" hreflang="en" href="{ORIGIN}{en_path}">
  <link rel="alternate" hreflang="de" href="{ORIGIN}{de_path}">
  <link rel="alternate" hreflang="x-default" href="{ORIGIN}/en">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Hyse">
  <meta property="og:locale" content="{'de_DE' if language == 'de' else 'en_US'}">
  <meta property="og:title" content="{html.escape(title, quote=True)}">
  <meta property="og:description" content="{html.escape(description, quote=True)}">
  <meta property="og:url" content="{ORIGIN}{path}">
  <meta property="og:image" content="{SOCIAL}">
  <meta property="og:image:alt" content="{'Hyse App-Icon auf türkisfarbenem Hintergrund' if language == 'de' else 'Hyse app icon on a teal background'}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{html.escape(title, quote=True)}">
  <meta name="twitter:description" content="{html.escape(description, quote=True)}">
  <meta name="twitter:image" content="{SOCIAL}">
  <link rel="icon" href="{ICON}" type="image/webp">
  <link rel="stylesheet" href="{stylesheet}">
  <script type="application/ld+json">{json.dumps(schema, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')}</script>
  <script src="/assets/language.js" defer></script>"""


def header(path: str, language: str) -> str:
    is_de = language == "de"
    home = "/de" if is_de else "/en"
    features = "/de/funktionen" if is_de else "/en/features"
    workouts = "/de/training" if is_de else "/en/workouts"
    ios = "/de/ios" if is_de else "/en/ios"
    marketing = "/de/marketing" if is_de else "/en/marketing"
    support = "/de/support" if is_de else "/en/support"
    privacy = "/de/datenschutz" if is_de else "/en/privacy"
    terms = "/de/agb" if is_de else "/en/terms"
    imprint = "/de/impressum" if is_de else "/en/impressum"
    counterpart = PAIR[path]
    def nav_link(destination: str, label: str) -> str:
        current = ' aria-current="page"' if path == destination else ""
        return f'<a href="{destination}"{current}>{label}</a>'
    navigation = "".join([
        nav_link(home, "Start" if is_de else "Home"),
        nav_link(features, "Ernährung" if is_de else "Nutrition"),
        nav_link(workouts, "Training" if is_de else "Workouts"),
        nav_link(ios, "iPhone & Watch"),
        nav_link(marketing, "Über Hyse" if is_de else "About Hyse"),
        nav_link(support, "Support"),
        nav_link(privacy, "Datenschutz" if is_de else "Privacy"),
        nav_link(terms, "AGB" if is_de else "Terms"),
        nav_link(imprint, "Impressum" if is_de else "Imprint"),
    ])
    return f"""<a class="skip-link" href="#content">{'Zum Inhalt springen' if is_de else 'Skip to content'}</a>
<header class="site-header"><nav class="nav" aria-label="{'Hauptnavigation' if is_de else 'Main navigation'}">
  <a class="brand" href="{home}"><img src="{ICON}" width="42" height="42" alt="{'Hyse App-Icon' if is_de else 'Hyse app icon'}"><span>Hyse</span></a>
  <div class="nav-links">{navigation}<a href="{counterpart}" hreflang="{'en' if is_de else 'de'}" lang="{'en' if is_de else 'de'}" aria-label="{'EN – Switch to English' if is_de else 'DE – Auf Deutsch wechseln'}">{'EN' if is_de else 'DE'}</a></div>
  <details class="mobile-menu"><summary role="button">{'Menü' if is_de else 'Menu'}</summary><div class="nav-links">{navigation}<a href="{counterpart}" hreflang="{'en' if is_de else 'de'}" lang="{'en' if is_de else 'de'}" aria-label="{'EN – Switch to English' if is_de else 'DE – Auf Deutsch wechseln'}">{'EN' if is_de else 'DE'}</a></div></details>
</nav></header>"""


def social_section(language: str) -> str:
    links = social_links()
    if not links:
        return ""
    is_de = language == "de"
    items = "".join(
        f'<a class="social-link social-{platform}" href="{html.escape(url, quote=True)}" target="_blank" rel="noopener noreferrer me" aria-label="{'Hyse auf' if is_de else 'Hyse on'} {label}"><img class="social-icon" src="/assets/social/{platform}.svg" width="24" height="24" alt=""><span>{label}</span></a>'
        for platform, label, url in links
    )
    return f'''<aside class="social-section" aria-labelledby="social-heading"><div class="social-inner"><div><p class="eyebrow">{'Hyse online' if is_de else 'Hyse online'}</p><h2 id="social-heading">{'Folge uns auf Social Media' if is_de else 'Meet us on Social Media'}</h2><p>{'Neuigkeiten und Einblicke auf unseren offiziellen Kanälen.' if is_de else 'News and updates from our official channels.'}</p></div><div class="social-links">{items}</div></div></aside>'''


def footer(language: str) -> str:
    is_de = language == "de"
    return f"""<footer class="site-footer"><div class="footer-inner"><div><strong>Hyse</strong><br>{'Ernährung, Training und Gym Community für iPhone, iPad und Apple Watch' if is_de else 'Nutrition, training and gym community for iPhone, iPad and Apple Watch'}</div><div class="footer-links"><a href="{APP_STORE_URL}">{'Im App Store laden' if is_de else 'Download on the App Store'}</a><a href="{'/de' if is_de else '/en'}">{'Startseite' if is_de else 'Home'}</a><a href="{'/de/funktionen' if is_de else '/en/features'}">{'Ernährung' if is_de else 'Nutrition'}</a><a href="{'/de/training' if is_de else '/en/workouts'}">{'Training' if is_de else 'Workouts'}</a><a href="{'/de/ios' if is_de else '/en/ios'}">iPhone &amp; Watch</a><a href="{'/de/marketing' if is_de else '/en/marketing'}">{'Über Hyse' if is_de else 'About Hyse'}</a><a href="{'/de/support' if is_de else '/en/support'}">Support</a><a href="{'/de/datenschutz' if is_de else '/en/privacy'}">{'Datenschutz' if is_de else 'Privacy'}</a><a href="{'/de/datenschutz#cookies' if is_de else '/en/privacy#cookies'}">Cookies</a><a href="{'/de/agb' if is_de else '/en/terms'}">{'AGB' if is_de else 'Terms'}</a><a href="{'/de/impressum' if is_de else '/en/impressum'}">{'Impressum' if is_de else 'Imprint'}</a></div></div></footer>"""


def document(path: str, language: str, title: str, description: str, body: str, schema: dict | list, include_social_section: bool = True) -> str:
    social = social_section(language) if include_social_section else ""
    return f"""<!doctype html><html lang="{language}"><head>{metadata(path, title, description, language, schema)}</head><body>{header(path, language)}<main id="content">{body}</main>{social}{footer(language)}</body></html>"""


def breadcrumb(path: str, language: str, label: str) -> dict:
    home = "/de" if language == "de" else "/en"
    return {"@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "Startseite" if language == "de" else "Home", "item": ORIGIN + home},
        {"@type": "ListItem", "position": 2, "name": label, "item": ORIGIN + path},
    ]}


def build_marketing_pages() -> None:
    for language in ("en", "de"):
        de = language == "de"
        home_path = "/de" if de else "/en"
        home_title = "Hyse – Ernährungs-, Gym- und Workout-Tracker" if de else "Hyse – nutrition, gym and workout tracker for iPhone"
        home_description = ("Hyse verbindet Kalorien, Makros und Rezepte mit Gym- und Workout-Planung, Routinen, Trainingsverlauf und Statistiken auf dem iPhone."
                            if de else "Hyse combines calories, macros and recipes with gym and workout planning, routines, training history and statistics on iPhone.")
        home_body = f"""
<section class="hero"><div><p class="eyebrow">{'Ernährung und Training. Eine App.' if de else 'Nutrition and training. One app.'}</p><h1>{'Dein Alltag.<br>Deine Ziele. Hyse.' if de else 'Your day.<br>Your goals. Hyse.'}</h1><p class="lead">{'Hyse verbindet Ernährungstracking mit einem vollständigen Gym- und Workout-Planer. Plane Routinen, protokolliere Sätze und behalte Fortschritt, Mahlzeiten und persönliche Ziele gemeinsam im Blick.' if de else 'Hyse combines nutrition tracking with a complete gym and workout planner. Build routines, log sets and keep progress, meals and personal goals together.'}</p><div class="hero-actions"><a class="button" href="{'/de/training' if de else '/en/workouts'}">{'Workout-Planer ansehen' if de else 'Explore workout planner'}</a><a class="button secondary" href="{'/de/funktionen' if de else '/en/features'}">{'Alle Funktionen' if de else 'All features'}</a></div></div><div class="app-card"><img src="{ICON}" width="210" height="210" alt="{'Hyse App-Icon – Ernährungs- und Workout-Tracker' if de else 'Hyse app icon – nutrition and workout tracker'}"><p>{'Ernährung, Gym und Workouts für iPhone' if de else 'Nutrition, gym and workouts for iPhone'}</p></div></section>
<section class="section"><p class="eyebrow">{'Alles für deinen Fortschritt' if de else 'Everything for your progress'}</p><h2>{'Weniger Wechseln, mehr Überblick' if de else 'Fewer apps, more clarity'}</h2><div class="grid"><article class="card"><h3>{'Kalorien & Makros' if de else 'Calories & macros'}</h3><p>{'Erfasse Energie, Kohlenhydrate, Protein, Fett und weitere Nährwerte pro Tag und Mahlzeit.' if de else 'Log energy, carbohydrates, protein, fat and additional nutrients by day and meal.'}</p></article><article class="card"><h3>{'Lebensmittel & Rezepte' if de else 'Foods & recipes'}</h3><p>{'Speichere eigene Lebensmittel, nutze Barcodes und berechne Rezepte aus anpassbaren Zutatenmengen.' if de else 'Save foods, use barcodes and calculate recipes from adjustable ingredient quantities.'}</p></article><article class="card"><h3>{'Gym- & Workout-Planer' if de else 'Gym & workout planner'}</h3><p>{'Erstelle Routinen, starte freie Workouts und erfasse Gewicht, Wiederholungen, RPE und Pausen.' if de else 'Create routines, start free workouts and track weight, reps, RPE and rest periods.'}</p><a class="card-link" href="{'/de/training' if de else '/en/workouts'}">{'Training entdecken →' if de else 'Explore training →'}</a></article><article class="card"><h3>{'Trainingsfortschritt' if de else 'Training progress'}</h3><p>{'Sieh Verlauf, Kalender, Volumen, persönliche Bestleistungen und Fortschrittsdiagramme.' if de else 'Review history, calendar, volume, personal records and progress charts.'}</p></article><article class="card"><h3>{'Freunde & Feed' if de else 'Friends & feed'}</h3><p>{'Verbinde dich per Benutzername und sieh die letzten Trainings deiner Freunde.' if de else 'Connect by username and see your friends’ latest workouts.'}</p></article><article class="card"><h3>{'Trink-Tracker' if de else 'Water tracker'}</h3><p>{'Halte deine Trinkmenge mit einem persönlichen Tagesziel schnell und unkompliziert fest.' if de else 'Record water quickly against a personal daily target.'}</p></article></div></section>
<section class="soft"><div class="soft-inner"><h2>{'Lokal nutzbar, Konto optional' if de else 'Works locally, account optional'}</h2><p class="section-intro">{'Hyse lässt sich als Gast verwenden. Ein optionales Konto synchronisiert ausgewählte Daten über das selbst betriebene Hyse-Backend.' if de else 'Hyse can be used as a guest. An optional account synchronises selected data through the self-hosted Hyse backend.'}</p><div class="hero-actions"><a class="button secondary" href="{'/de/datenschutz' if de else '/en/privacy'}">{'Datenschutz lesen' if de else 'Read privacy policy'}</a></div></div></section>
<section class="section"><div class="contact-box"><div><h2>{'Fragen zu Hyse?' if de else 'Questions about Hyse?'}</h2><p>{'Support und Datenschutzanfragen beantwortet der Betreiber per E-Mail.' if de else 'The operator answers support and privacy requests by email.'}</p></div><a class="button" href="mailto:{SUPPORT}">{SUPPORT}</a></div></section>"""
        organization = {"@context": "https://schema.org", "@type": "Organization", "name": "Hyse", "url": ORIGIN + home_path, "email": SUPPORT, "logo": ORIGIN + ICON}
        configured_profiles = [url for _, _, url in social_links()]
        if configured_profiles:
            organization["sameAs"] = configured_profiles
        schema = [
            organization,
            {"@context": "https://schema.org", "@type": "WebSite", "name": "Hyse", "url": ORIGIN + home_path, "inLanguage": language},
            {"@context": "https://schema.org", "@type": "MobileApplication", "name": "Hyse", "applicationCategory": "HealthApplication", "operatingSystem": "iOS", "description": home_description, "url": ORIGIN + ("/de/ios" if de else "/en/ios")},
        ]
        write(home_path, document(home_path, language, home_title, home_description, home_body, schema))

        features_path = "/de/funktionen" if de else "/en/features"
        features_title = "Hyse Ernährungstracker – Kalorien, Makros und Rezepte" if de else "Hyse nutrition tracker – calories, macros and recipes"
        features_description = ("Entdecke Ernährungstracking, Rezepte, Gym-Routinen, Workout-Protokollierung, Trainingsstatistiken, Freunde und Apple Health in Hyse."
                                if de else "Explore nutrition tracking, recipes, gym routines, workout logging, training statistics, friends and Apple Health in Hyse.")
        questions = [
            ("Kann ich Hyse ohne Konto verwenden?", "Ja. Gastdaten werden lokal auf deinem Gerät gespeichert. Ein Konto ist für die grundlegende Nutzung nicht erforderlich."),
            ("Ersetzt Hyse medizinische Beratung?", "Nein. Hyse ist ein persönliches Tracking-Werkzeug und keine medizinische Diagnose- oder Behandlungsanwendung."),
            ("Welche Werte kann ich erfassen?", "Neben Kalorien und Nährwerten lassen sich Workouts, Übungen, Sätze, Gewicht, Wiederholungen, RPE, Pausen, Körpergewicht und Wasser dokumentieren."),
        ] if de else [
            ("Can I use Hyse without an account?", "Yes. Guest data is stored locally on your device. An account is not required for core tracking."),
            ("Does Hyse replace medical advice?", "No. Hyse is a personal tracking tool, not a medical diagnosis or treatment application."),
            ("What can I track?", "Alongside calories and nutrients, Hyse can record workouts, exercises, sets, weight, reps, RPE, rest periods, body weight and water."),
        ]
        cards = [
            ("Kalorienzähler & Mahlzeiten", "Ordne Einträge Mahlzeiten zu und vergleiche sie mit einem festen oder dynamischen Tagesziel."),
            ("Makro- und Nährwert-Tracker", "Behalte Makros und weitere Nährwerte in einer klaren Tagesübersicht im Blick."),
            ("Ernährungstagebuch", "Wechsle zwischen Tagen, bearbeite Einträge und behalte vergangene Mahlzeiten unverändert."),
            ("Lebensmittel & Barcode", "Lege Lebensmittel selbst an oder suche Produktinformationen mithilfe eines Barcodes."),
            ("Rezepte", "Kombiniere Zutaten, ändere Mengen und berechne Nährwerte automatisch neu."),
            ("Trink-Tracker", "Erfasse Getränke mit einem persönlichen Tagesziel in einer minimalistischen Ansicht."),
            ("Gym- und Workout-Planer", "Erstelle Routinen oder starte ein freies Workout und erfasse Sätze, Gewicht, Wiederholungen und RPE."),
            ("Trainingsverlauf & Statistiken", "Analysiere Trainingszeit, Volumen, Bestleistungen, Übungsfortschritt und deine letzten Workouts."),
        ] if de else [
            ("Calorie tracker & meals", "Organise entries by meal and compare them with a fixed or dynamic daily goal."),
            ("Macro and nutrition tracker", "See macros and additional nutrients in a clear daily overview."),
            ("Food diary", "Move between dates, edit entries and keep previous meals unchanged."),
            ("Foods & barcodes", "Create foods yourself or look up product information with a barcode."),
            ("Recipes", "Combine ingredients, edit quantities and recalculate nutrition automatically."),
            ("Water tracker", "Log drinks against a personal daily goal in a minimal interface."),
            ("Gym and workout planner", "Create routines or start a free workout and log sets, weight, repetitions and RPE."),
            ("Training history & statistics", "Review training time, volume, personal records, exercise progress and recent workouts."),
        ]
        features_body = f"""<article class="section content-page"><p class="eyebrow">{'Ernährungstracker' if de else 'Nutrition tracker'}</p><h1>{'Ernährung einfach im Blick behalten' if de else 'Keep nutrition clearly in view'}</h1><p class="lead">{features_description}</p><div class="grid">{''.join(f'<section class="card"><h2>{html.escape(a)}</h2><p>{html.escape(b)}</p></section>' for a,b in cards)}</div><aside class="notice"><strong>{'Hinweis:' if de else 'Note:'}</strong> {'Hyse ist ein persönliches Tracking-Werkzeug und ersetzt keine medizinische Beratung oder professionelle Trainingsbetreuung.' if de else 'Hyse is a personal tracking tool and does not replace medical advice or professional coaching.'}</aside><section class="faq"><p class="eyebrow">FAQ</p><h2>{'Häufige Fragen' if de else 'Common questions'}</h2>{''.join(f'<details><summary>{html.escape(q)}</summary><p>{html.escape(a)}</p></details>' for q,a in questions)}</section></article>"""
        faq_schema = {"@type": "FAQPage", "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in questions]}
        write(features_path, document(features_path, language, features_title, features_description, features_body, {"@context": "https://schema.org", "@graph": [breadcrumb(features_path, language, LABEL[features_path]), faq_schema]}))

        workouts_path = "/de/training" if de else "/en/workouts"
        workouts_title = "Hyse Gym- & Workout-Planer für iPhone" if de else "Hyse gym and workout planner for iPhone"
        workouts_description = ("Plane Gym-Routinen, protokolliere Gewicht, Wiederholungen und RPE und analysiere deinen Trainingsfortschritt direkt in Hyse."
                                if de else "Plan gym routines, log weight, reps and RPE, and analyse your training progress directly in Hyse.")
        workout_cards = [
            ("Routinen planen", "Stelle Übungen in deiner gewünschten Reihenfolge zusammen und starte gespeicherte Pläne direkt beim nächsten Training."),
            ("Übungen finden", "Durchsuche die Übungsbibliothek, nutze Favoriten und füge eigene Übungen für dein Training hinzu."),
            ("Jeden Satz protokollieren", "Erfasse Gewicht, Wiederholungen und RPE ohne den Trainingsfluss zu unterbrechen."),
            ("Pausen im Blick", "Der Pausentimer erinnert dich mit den Hyse-Sounds daran, wann es mit dem nächsten Satz weitergeht."),
            ("Verlauf & Statistiken", "Behalte Trainingszeit, Volumen, persönliche Bestleistungen und vergangene Workouts im Blick."),
            ("Fortschritt verstehen", "Analysiere Übungsfortschritt in kg oder lb über verschiedene Zeiträume und prüfe einzelne Messpunkte."),
        ] if de else [
            ("Plan routines", "Arrange exercises in your preferred order and start saved plans directly in your next session."),
            ("Find exercises", "Search the exercise library, use favourites and add your own exercises for training."),
            ("Log every set", "Record weight, reps and RPE without interrupting your workout flow."),
            ("Stay on top of rest", "The rest timer uses Hyse sounds to let you know when it is time for the next set."),
            ("History & statistics", "Review training time, volume, personal records and previous workouts."),
            ("Understand progress", "Analyse exercise progress in kg or lb across several time ranges and inspect individual data points."),
        ]
        workouts_body = f"""<article class="section content-page"><p class="eyebrow">{'Gym & Training' if de else 'Gym & Workouts'}</p><h1>{'Gym- und Workout-Planung in Hyse' if de else 'Gym and workout planning in Hyse'}</h1><p class="lead">{workouts_description}</p><section id="funktionen"><p class="eyebrow">{'Dein Training, klar organisiert' if de else 'Your training, clearly organised'}</p><h2>{'Das bietet der Planer in der App' if de else 'What the planner offers in the app'}</h2><p class="section-intro">{'Hyse begleitet dich in der App durch das gesamte Workout, ohne Ernährung und Körpergewicht aus dem Zusammenhang zu reißen.' if de else 'In the app, Hyse supports the entire workout without separating it from nutrition and body-weight progress.'}</p><div class="grid">{''.join(f'<article class="card"><h3>{html.escape(a)}</h3><p>{html.escape(b)}</p></article>' for a,b in workout_cards)}</div></section><section class="text-feature"><p class="eyebrow">{'Gemeinsam trainieren' if de else 'Train together'}</p><h2>{'Freunde, Feed und dein Profil' if de else 'Friends, feed and your profile'}</h2><p class="section-intro">{'In der App kannst du einen Benutzernamen erstellen, dich mit Freunden verbinden und ihre letzten Trainings sehen. Dein Profil bündelt deine eigenen Workouts und Statistiken.' if de else 'In the app, you can create a username, connect with friends and see their latest workouts. Your profile brings your own sessions and statistics together.'}</p></section><section class="text-feature"><p class="eyebrow">{'Einfach umsteigen' if de else 'Easy to switch'}</p><h2>{'Bestehende Hevy-Daten importieren' if de else 'Import existing Hevy data'}</h2><p class="section-intro">{'Die Hyse App kann kompatible Trainingsdaten übernehmen, damit du dein Training dort weiterführen kannst.' if de else 'The Hyse app can bring across compatible training data so you can continue tracking there.'}</p><div class="hero-actions"><a class="button" href="{'/de/ios' if de else '/en/ios'}">{'Mehr zur iPhone-App' if de else 'Learn about the iPhone app'}</a></div></section></article>"""
        workouts_schema = {"@context": "https://schema.org", "@graph": [breadcrumb(workouts_path, language, LABEL[workouts_path]), {"@type": "SoftwareApplication", "name": "Hyse Gym & Workout Planner", "applicationCategory": "HealthApplication", "operatingSystem": "iOS", "description": workouts_description, "url": ORIGIN + workouts_path}]}
        write(workouts_path, document(workouts_path, language, workouts_title, workouts_description, workouts_body, workouts_schema))

        ios_path = "/de/ios" if de else "/en/ios"
        ios_title = "Hyse für iOS – Ernährung, Gym und Workouts" if de else "Hyse for iOS – nutrition, gym and workouts"
        ios_description = "Hyse für iPhone: Kalorien, Makros, Rezepte, Gym-Routinen, Workouts und Trainingsfortschritt gemeinsam erfassen." if de else "Hyse for iPhone: track calories, macros, recipes, gym routines, workouts and training progress together."
        store_action = app_store_button(language)
        ios_body = f"""<article class="section content-page"><p class="eyebrow">iPhone</p><h1>{'Hyse für iOS' if de else 'Hyse for iOS'}</h1><p class="lead">{ios_description}</p><div class="app-download"><img src="{ICON}" width="180" height="180" alt="Hyse App-Icon"><div><h2>{'Ernährung und Training in einer App' if de else 'Nutrition and training in one app'}</h2><p>{'Dokumentiere Mahlzeiten und Körpergewicht, plane Routinen und analysiere deine Workouts. Apple Health lässt sich auf Wunsch verbinden.' if de else 'Log meals and body weight, plan routines and analyse workouts. Apple Health can be connected optionally.'}</p>{store_action}</div></div></article>"""
        ios_schema = {"@context": "https://schema.org", "@graph": [breadcrumb(ios_path, language, LABEL[ios_path]), {"@type": "MobileApplication", "name": "Hyse", "operatingSystem": "iOS", "applicationCategory": "HealthApplication", "description": ios_description, "url": ORIGIN + ios_path}]}
        write(ios_path, document(ios_path, language, ios_title, ios_description, ios_body, ios_schema))

def copy_legal(source: str, destination: str, language: str, title: str, description: str) -> None:
    text = (PUBLIC / source / "index.html").read_text(encoding="utf-8")
    body_match = re.search(r"<main\b[^>]*>(.*)</main>", text, re.S | re.I)
    if not body_match:
        raise RuntimeError(f"Missing main element in {source}")
    body = body_match.group(1)
    replacements = {
        'href="/privacy"': 'href="/en/privacy"',
        'href="/terms"': 'href="/en/terms"',
        'href="/datenschutz"': 'href="/de/datenschutz"',
        'href="/nutzungsbedingungen"': 'href="/de/agb"',
        'href="/"': 'href="/en"',
    }
    for old, new in replacements.items():
        body = body.replace(old, new)
    # Presentation-only wrapper for legacy legal pages without an article.
    if not body.lstrip().startswith('<article class="legal">'):
        body = f'<article class="legal">{body}</article>'
    schema = {"@context": "https://schema.org", "@graph": [breadcrumb(destination, language, LABEL[destination]), {"@type": "WebPage", "name": title, "description": description, "inLanguage": language, "isPartOf": {"@type": "WebSite", "name": "Hyse", "url": ORIGIN + ("/de" if language == "de" else "/en")}}]}
    write(destination, document(destination, language, title, description, body, schema))


def build_support_pages() -> None:
    for language in ("en", "de"):
        is_de = language == "de"
        path = "/de/support" if is_de else "/en/support"
        title = "Hyse Support – Hilfe und Kontakt" if is_de else "Hyse Support – Help and contact"
        description = ("Hilfe zur Hyse App und direkter Kontakt zum Hyse Support per E-Mail."
                       if is_de else "Help with the Hyse app and direct email contact with Hyse Support.")
        subject = "Hyse%20Supportanfrage" if is_de else "Hyse%20support%20request"
        body = f"""
<article class="section content-page support-page">
  <p class="eyebrow">Hyse Support</p>
  <h1>{'Wie können wir helfen?' if is_de else 'How can we help?'}</h1>
  <p class="lead">{'Wenn etwas nicht funktioniert oder du eine Frage zu Hyse hast, kannst du uns direkt per E-Mail schreiben.' if is_de else 'If something is not working or you have a question about Hyse, you can email us directly.'}</p>
  <section class="contact-box">
    <div><h2>{'Support kontaktieren' if is_de else 'Contact support'}</h2><p>{'Die Nachricht wird in deiner E-Mail-App geöffnet. Bitte beschreibe kurz, was passiert ist.' if is_de else 'The message opens in your email app. Please briefly describe what happened.'}</p></div>
    <a class="button" href="mailto:{SUPPORT}?subject={subject}">{'E-Mail schreiben' if is_de else 'Write an email'}</a>
  </section>
  <section class="contact-box">
    <div><h2>{'Inhalte in der App melden' if is_de else 'Report content in the app'}</h2><p>{'Öffne in Hyse Einstellungen → Datenschutz & Recht → Inhalt melden. Das geht auch ohne Konto: Gib den Link oder die ID des Inhalts, den Grund, eine Erläuterung und deine E-Mail-Adresse für Rückfragen ein. Falls du die App nicht verwenden kannst, kontaktiere uns über die Support-Adresse oben.' if is_de else 'In Hyse, open Settings → Privacy & Legal → Report content. This works without an account: enter the content link or ID, reason, explanation and your email for follow-up. If you cannot use the app, contact us at the support address above.'}</p></div>
  </section>
  <div class="grid support-grid">
    <section class="card"><div class="icon" aria-hidden="true">?</div><h2>{'Hilfreiche Angaben' if is_de else 'Helpful details'}</h2><p>{'Nenne möglichst die App-Version, dein iPhone-Modell und die Schritte, die zum Problem geführt haben. Bitte sende keine Passwörter oder Gesundheitsdaten.' if is_de else 'If possible, include the app version, your iPhone model and the steps that led to the issue. Do not send passwords or health data.'}</p></section>
    <section class="card"><div class="icon" aria-hidden="true">@</div><h2>{'Support-Adresse' if is_de else 'Support address'}</h2><p><a href="mailto:{SUPPORT}?subject={subject}">{SUPPORT}</a></p></section>
    <section class="card"><div class="icon" aria-hidden="true">↗</div><h2>{'Datenschutz' if is_de else 'Privacy'}</h2><p>{'Informationen zum Umgang mit Supportanfragen findest du in der Datenschutzerklärung.' if is_de else 'Information about how support requests are handled is available in the privacy policy.'}</p><a class="card-link" href="{'/de/datenschutz' if is_de else '/en/privacy'}">{'Datenschutzerklärung öffnen →' if is_de else 'Open privacy policy →'}</a></section>
  </div>
</article>"""
        schema = {"@context": "https://schema.org", "@graph": [
            breadcrumb(path, language, LABEL[path]),
            {"@type": "ContactPage", "name": title, "description": description, "inLanguage": language, "url": ORIGIN + path},
            {"@type": "Organization", "name": "Hyse", "url": ORIGIN, "email": SUPPORT,
             "contactPoint": {"@type": "ContactPoint", "contactType": "customer support", "email": SUPPORT, "availableLanguage": ["German", "English"]}},
        ]}
        write(path, document(path, language, title, description, body, schema))


def build_product_pages() -> None:
    """Build the public product pages from the current app feature set."""

    def cards(items: list[tuple[str, str, str]]) -> str:
        return "".join(
            f'<article class="card"><span class="card-kicker">{kicker}</span><h3>{title}</h3><p>{copy}</p></article>'
            for kicker, title, copy in items
        )

    for language in ("en", "de"):
        de = language == "de"
        home_path = "/de" if de else "/en"
        features_path = "/de/funktionen" if de else "/en/features"
        workouts_path = "/de/training" if de else "/en/workouts"
        ios_path = "/de/ios" if de else "/en/ios"

        home_title = "Hyse – Ernährung, Training und Gym Community" if de else "Hyse – nutrition, training and gym community"
        home_description = (
            "Hyse vereint Ernährung, Kalorien, Rezepte, Workouts, Apple Health, Apple Watch und Gym Communities in einer App."
            if de else
            "Hyse brings nutrition, calories, recipes, workouts, Apple Health, Apple Watch and gym communities together in one app."
        )
        home_body = f"""
<section class="hero"><div>
  <span class="release-pill">{'Neu: Texterfassung, Gym Communities und Monatsberichte' if de else 'New: text logging, gym communities and monthly reports'}</span>
  <p class="eyebrow">{'Ernährung und Training. Ein System.' if de else 'Nutrition and training. One system.'}</p>
  <h1>{'Alles, was deinen Fortschritt bewegt.' if de else 'Everything that moves your progress.'}</h1>
  <p class="lead">{'Hyse verbindet Kalorien und Makros mit Mahlzeiten, Workouts, Apple Health, Apple Watch und deinem Gym. Weniger App-Wechsel, mehr Überblick über das, was du jeden Tag wirklich tust.' if de else 'Hyse brings calories and macros together with meals, workouts, Apple Health, Apple Watch and your gym. Fewer app switches, more clarity about what you actually do every day.'}</p>
  <div class="hero-actions">{app_store_button(language)}<a class="button secondary" href="{features_path}">{'Hyse entdecken' if de else 'Explore Hyse'}</a></div>
  <ul class="hero-points"><li>{'Lokal als Gast nutzbar' if de else 'Local guest mode'}</li><li>{'Konto optional' if de else 'Account optional'}</li><li>{'Für iPhone, iPad und Apple Watch' if de else 'For iPhone, iPad and Apple Watch'}</li></ul>
</div><div class="product-preview" role="img" aria-label="{'Beispielansicht von Hyse: verbleibende Kalorien, Protein, ein aktives Training und eine Gym Community' if de else 'Sample Hyse screen: calories left, protein, an active workout and a gym community'}">
  <div class="preview-top"><div class="preview-brand"><img src="{ICON}" width="44" height="44" alt=""><span>{'Dein Tag' if de else 'Your day'}</span></div><span class="preview-date">{'HEUTE' if de else 'TODAY'}</span></div>
  <div class="metric-grid"><div class="metric-card primary"><span class="metric-label">{'Kalorien übrig' if de else 'Calories left'}</span><span class="metric-value">1.248</span><span class="metric-note">{'Ziel passt sich deinem Plan an' if de else 'Target adapts to your plan'}</span></div><div class="metric-card"><span class="metric-label">Protein</span><span class="metric-value">92 g</span><span class="metric-note">{'von 150 g' if de else 'of 150 g'}</span></div></div>
  <div class="preview-stack"><div class="preview-row"><span class="preview-icon">↗</span><span><strong>Push Day</strong><small>{'Training auf iPhone &amp; Watch' if de else 'Training on iPhone &amp; Watch'}</small></span><span class="preview-status">{'Aktiv' if de else 'Active'}</span></div><div class="preview-row"><span class="preview-icon">●</span><span><strong>Gym Community</strong><small>{'Neue Nachricht · 3 Reaktionen' if de else 'New message · 3 reactions'}</small></span><span class="preview-status">{'Öffnen' if de else 'Open'}</span></div></div>
</div></section>
<div class="trust-strip"><div class="trust-item"><span aria-hidden="true">⌂</span><span><strong>Local first.</strong> {'Kerndaten bleiben auch ohne Konto nutzbar.' if de else 'Core data works without an account.'}</span></div><div class="trust-item"><span aria-hidden="true">♥</span><span><strong>Apple Health.</strong> {'Gewicht, Schritte, Energie und Wasser verbinden.' if de else 'Connect weight, steps, energy and water.'}</span></div><div class="trust-item"><span aria-hidden="true">⌚</span><span><strong>Apple Watch.</strong> {'Workouts und Sätze direkt am Handgelenk.' if de else 'Workouts and sets right on your wrist.'}</span></div></div>
<section class="section"><p class="eyebrow">{'Ein Alltag, ein Überblick' if de else 'One day, one overview'}</p><h2>{'Vom Frühstück bis zum letzten Satz' if de else 'From breakfast to your final set'}</h2><p class="section-intro">{'Hyse bringt die Bereiche zusammen, die sonst auf mehrere Apps verteilt sind.' if de else 'Hyse brings together the areas that are usually spread across several apps.'}</p><div class="bento">
  <article class="card wide"><span class="card-kicker">{'Ernährung' if de else 'Nutrition'}</span><h3>{'Kalorien, Makros und Lebensmittel ohne Umwege' if de else 'Calories, macros and foods without the friction'}</h3><p>{'Suche Lebensmittel, scanne Barcodes, speichere eigene Produkte und Rezepte, erfasse mehrere Einträge gesammelt und erfasse Lebensmittel aus Text auf deinem Gerät.' if de else 'Search foods, scan barcodes, save your own products and recipes, add several entries at once, and log foods from text on your device.'}</p><ul class="feature-list"><li>{'Feste oder dynamische Kalorienziele' if de else 'Fixed or dynamic calorie targets'}</li><li>{'Portionen, Mahlzeiten, Wasser und weitere Nährwerte' if de else 'Portions, meals, water and additional nutrients'}</li></ul><a class="card-link" href="{features_path}">{'Ernährung entdecken →' if de else 'Explore nutrition →'}</a></article>
  <article class="card"><span class="card-kicker">{'Training' if de else 'Training'}</span><h3>{'Workouts, die mitdenken' if de else 'Workouts that keep up'}</h3><p>{'Routinen und freie Workouts, Supersätze, Satztypen, Pausentimer, RPE, Volumen, Rekorde und Muskelgruppen in einem Trainingsfluss.' if de else 'Routines and empty workouts, supersets, set types, rest timers, RPE, volume, records and muscle groups in one training flow.'}</p><a class="card-link" href="{workouts_path}">{'Zum Workout-Planer →' if de else 'Open workout planner →'}</a></article>
  <article class="card"><span class="card-kicker">{'Alltag & Gesundheit' if de else 'Daily wellbeing'}</span><h3>{'Mehr als eine Kalorienzahl' if de else 'More than a calorie number'}</h3><p>{'Behalte Gewicht, Schritte, Wasser, Fasten, Ruheenergie und aktive Energie im Zusammenhang. Erinnerungen und Streaks helfen bei der Konstanz.' if de else 'Keep weight, steps, water, fasting, resting energy and active energy together. Reminders and streaks help you stay consistent.'}</p></article>
  <article class="card wide"><span class="card-kicker">Apple Watch</span><h3>{'Das aktive Training bleibt am Handgelenk' if de else 'Your active workout stays on your wrist'}</h3><p>{'Starte ein Workout auf dem iPhone und begleite es auf der Watch. Bearbeite Gewicht und Wiederholungen, schließe Sätze ab und sieh Dauer, Puls und aktive Kalorien.' if de else 'Start a workout on iPhone and follow it on Apple Watch. Edit weight and reps, complete sets, and see duration, heart rate and active calories.'}</p><a class="card-link" href="{ios_path}">{'iPhone &amp; Watch ansehen →' if de else 'Explore iPhone &amp; Watch →'}</a></article>
  <article class="card"><span class="card-kicker">{'Freunde &amp; Feed' if de else 'Friends &amp; feed'}</span><h3>{'Fortschritt gemeinsam teilen' if de else 'Share progress together'}</h3><p>{'Vernetze dich per Benutzername, teile Trainings, kommentiere, reagiere und bündle deine öffentlichen Workouts im Profil.' if de else 'Connect by username, share workouts, comment, react and collect your public sessions in your profile.'}</p></article>
  <article class="card"><span class="card-kicker">Gym Communities</span><h3>{'Mit deinem Gym verbunden' if de else 'Connected to your gym'}</h3><p>{'Finde Communities nach Gym oder Stadt, lies offizielle Neuigkeiten und tausche dich im Mitgliederkanal aus.' if de else 'Find communities by gym or city, read official updates and chat in the member channel.'}</p></article>
</div></section>
<section class="spotlight"><div><p class="eyebrow">{'Aktuelle Erweiterungen' if de else 'Recent additions'}</p><h2>{'Hyse wächst mit deinem Alltag.' if de else 'Hyse grows with your routine.'}</h2><p class="section-intro">{'Neu dabei sind unter anderem lokale Texterfassung für Lebensmittel, Sammelerfassung, Monatsberichte mit Share Cards und Gym Communities mit Rollen.' if de else 'Recent additions include local text food logging, batch logging, monthly reports with share cards and role-based gym communities.'}</p></div><div class="community-demo"><div class="message"><strong>{'Gym-Team' if de else 'Gym team'}</strong><br>{'Samstag öffnen wir schon um 7 Uhr.' if de else 'We open at 7 am on Saturday.'}<small>{'Neuigkeiten · 08:12' if de else 'News · 08:12'}</small><span class="reaction">💪 12</span></div><div class="message mine"><strong>{'Du' if de else 'You'}</strong><br>{'Perfekt, dann bis morgen!' if de else 'Perfect, see you tomorrow!'}<small>{'Mitglieder · bearbeitet' if de else 'Members · edited'}</small></div></div></section>
<section class="section"><div class="cta-panel"><div><h2>{'Bereit für weniger App-Wechsel?' if de else 'Ready for fewer app switches?'}</h2><p>{'Lade Hyse für iPhone, iPad und Apple Watch im App Store.' if de else 'Get Hyse for iPhone, iPad and Apple Watch on the App Store.'}</p></div>{app_store_button(language)}</div></section>"""
        home_organization = {"@context": "https://schema.org", "@type": "Organization", "name": "Hyse", "url": ORIGIN + home_path, "email": SUPPORT, "logo": ORIGIN + ICON}
        configured_profiles = [url for _, _, url in social_links()]
        if configured_profiles:
            home_organization["sameAs"] = configured_profiles
        home_schema = [
            home_organization,
            {"@context": "https://schema.org", "@type": "MobileApplication", "name": "Hyse", "applicationCategory": "HealthApplication", "operatingSystem": "iOS, iPadOS, watchOS", "description": home_description, "url": ORIGIN + ios_path, "installUrl": APP_STORE_URL},
        ]
        write(home_path, document(home_path, language, home_title, home_description, home_body, home_schema))

        features_title = "Hyse Ernährung – Kalorien, Fasten und Health" if de else "Hyse nutrition – calories, fasting and Health"
        features_description = (
            "Kalorien, Makros, Barcodes, Rezepte, lokale Texterfassung, dynamische Ziele, Wasser, Fasten, Streaks und Apple Health in Hyse."
            if de else
            "Calories, macros, barcodes, recipes, local text logging, dynamic targets, water, fasting, streaks and Apple Health in Hyse."
        )
        nutrition_cards = [
            ("Tagesübersicht", "Kalorien und Nährwerte im Zusammenhang", "Ordne Einträge Mahlzeiten zu, wechsle zwischen Tagen und verfolge Kalorien, Protein, Kohlenhydrate, Fett, Ballaststoffe, Zucker, Salz und weitere Werte."),
            ("Lebensmittel", "Suchen, scannen, selbst anlegen", "Verbinde lokale Lebensmittel mit Favoriten, zuletzt verwendeten Einträgen, Barcodes und dem gemeinsamen Katalog. Ergänze Namen, Marken, Portionsangaben und Nährwerte selbst."),
            ("Texterfassung", "Text als Vorschlag", "Erfasse Lebensmittel aus einer Beschreibung direkt auf deinem Gerät. Prüfe die erkannten Lebensmittel und Mengen, bevor du sie in die Tagesübersicht übernimmst."),
            ("Rezepte", "Mengen flexibel berechnen", "Kombiniere Zutaten, pflege Portionen und Zubereitungsschritte und lasse Nährwerte für jede gewünschte Menge automatisch neu berechnen."),
            ("Schneller erfassen", "Quick Entry und Sammelerfassung", "Speichere einfache Einträge direkt, füge mehrere Lebensmittel in einer Liste zusammen und bearbeite Mengen, Einheiten und Mahlzeiten vor dem Speichern."),
            ("Ziele", "Feste oder dynamische Kalorienziele", "Nutze ein festes Tagesziel oder lasse das Budget auf Basis deiner Einstellungen und optionaler Aktivitätsenergie aus Apple Health dynamisch berechnen."),
            ("Wasser & Fasten", "Hydration und Fasten im Tagesrhythmus", "Erfasse Wasser gegen ein persönliches Ziel und starte gängige oder eigene Fastenintervalle mit gespeichertem Verlauf."),
            ("Körper & Health", "Gewicht, Schritte und Energie", "Führe einen Gewichtsverlauf und verbinde auf Wunsch Gewicht, Schritte, Ruheenergie, aktive Energie und Wasser mit Apple Health."),
            ("Erinnerungen", "Hilfreiche Impulse selbst steuern", "Aktiviere Motivations-, Essens-, Wasser-, geplante-Training- oder fehlende-Tagesdaten-Erinnerungen und lege Häufigkeit und Sprache fest."),
            ("Streak Rewards", "Konstanz sichtbar machen", "Sammle Eiskristalle für den ersten Essenseintrag und das erste Training des Tages und schütze Serien mit Ernährungs- oder Trainings-Freezes."),
        ] if de else [
            ("Daily overview", "Calories and nutrients in context", "Assign entries to meals, move between dates, and follow calories, protein, carbohydrates, fat, fibre, sugar, salt and more."),
            ("Foods", "Search, scan, create your own", "Combine local foods with favourites, recent entries, barcodes and the shared catalogue. Add names, brands, serving details and nutrients yourself."),
            ("Text logging", "Text as a suggestion", "Log foods from a description directly on your device. Review detected foods and amounts before adding them to your day."),
            ("Recipes", "Recalculate any amount", "Combine ingredients, maintain portions and preparation steps, and recalculate nutrition for the amount you want."),
            ("Quick logging", "Quick Entry and batch logging", "Save simple entries directly, collect several foods in one list, and edit amounts, units and meals before saving."),
            ("Targets", "Fixed or dynamic calorie goals", "Use a fixed daily target or let Hyse calculate the budget dynamically from your settings and optional activity energy from Apple Health."),
            ("Water & fasting", "Hydration and fasting in your rhythm", "Track water against a personal goal and start common or custom fasting intervals with a saved history."),
            ("Body & Health", "Weight, steps and energy", "Keep a weight history and optionally connect weight, steps, resting energy, active energy and water with Apple Health."),
            ("Reminders", "Choose helpful nudges", "Enable motivation, food, water, planned-training or missing-daily-data reminders and control frequency and language."),
            ("Streak rewards", "Make consistency visible", "Earn ice crystals for your first food entry and workout each day and protect streaks with nutrition or training freezes."),
        ]
        faq = [
            ("Kann ich Hyse ohne Konto verwenden?", "Ja. Die Kernfunktionen und Gastdaten funktionieren lokal auf deinem Gerät. Ein Konto ist optional und synchronisiert ausgewählte Daten."),
            ("Wie funktioniert die Texterfassung?", "Hyse wertet deine Beschreibung auf dem Gerät aus. Prüfe und bearbeite die Vorschläge vor dem Speichern."),
            ("Ist Apple Health erforderlich?", "Nein. Apple Health ist optional. Hyse bleibt ohne Health-Berechtigungen nutzbar und verwendet nur freigegebene Kategorien."),
        ] if de else [
            ("Can I use Hyse without an account?", "Yes. Core features and guest data work locally on your device. An account is optional and syncs selected data."),
            ("How does text logging work?", "Hyse processes your description on the device. Review and edit the suggestions before saving."),
            ("Do I need Apple Health?", "No. Apple Health is optional. Hyse works without Health permissions and only uses categories you grant."),
        ]
        faq_html = "".join(f'<details><summary>{q}</summary><p>{a}</p></details>' for q, a in faq)
        features_body = f"""
<section class="page-hero"><span class="release-pill">{'Aktuelle Hyse-Version' if de else 'Current Hyse version'}</span><p class="eyebrow">{'Ernährung &amp; Gesundheit' if de else 'Nutrition &amp; wellbeing'}</p><h1>{'Verstehen, was deinen Tag ausmacht.' if de else 'Understand what shapes your day.'}</h1><p class="lead">{features_description}</p></section>
<section class="section" aria-labelledby="overview-heading"><h2 id="overview-heading" class="visually-hidden">{'Funktionen im Überblick' if de else 'Features at a glance'}</h2><div class="bento">{cards(nutrition_cards)}</div><p class="notice" role="note"><strong>{'Hinweis:' if de else 'Note:'}</strong> {'Hyse ist ein persönliches Tracking-Werkzeug und ersetzt keine medizinische Beratung.' if de else 'Hyse is a personal tracking tool and does not replace medical advice.'}</p><section class="faq"><p class="eyebrow">FAQ</p><h2>{'Häufige Fragen' if de else 'Common questions'}</h2>{faq_html}</section></section>"""
        features_schema = {"@context": "https://schema.org", "@graph": [breadcrumb(features_path, language, LABEL[features_path]), {"@type": "SoftwareApplication", "name": "Hyse Nutrition Tracker", "applicationCategory": "HealthApplication", "operatingSystem": "iOS, iPadOS", "description": features_description, "url": ORIGIN + features_path}]}
        write(features_path, document(features_path, language, features_title, features_description, features_body, features_schema))

        workouts_title = "Hyse Training – Workouts, Statistiken und Gym Communities" if de else "Hyse training – workouts, statistics and gym communities"
        workouts_description = (
            "Plane Routinen, protokolliere Sätze auf iPhone und Apple Watch, analysiere Fortschritt, importiere Hevy-Daten und verbinde dich mit deiner Gym Community."
            if de else
            "Plan routines, log sets on iPhone and Apple Watch, analyse progress, import Hevy data and connect with your gym community."
        )
        training_cards = [
            ("Aktives Workout", "Routinen planen oder freie Workouts", "Starte ein leeres Workout oder einen gespeicherten Plan, übernimm vorherige Werte und passe die Reihenfolge der Übungen direkt an."),
            ("Übungsbibliothek", "Übungen finden und verstehen", "Durchsuche die Bibliothek nach Muskelgruppe oder Equipment, nutze Favoriten, lokale Übungsbilder und Ausführungshinweise."),
            ("Eigene Übungen", "Dein eigener Trainingskatalog", "Erstelle private Übungen, ergänze Namen, Muskelgruppen, Equipment und optional ein eigenes Foto oder eine Ausführungshilfe."),
            ("Sätze", "Gewicht, Wiederholungen, RPE", "Protokolliere jeden Satz mit Gewicht, Wiederholungen und optionaler RPE. Warm-up-, Drop-set- und Failure-Sätze sowie Supersätze bleiben unterscheidbar."),
            ("Pausentimer", "Timer, Sounds und Haptik", "Passe Pausen an, nutze den Resttimer mit auswählbaren Hyse-Sounds und bekomme den Abschluss einer Pause auch als Benachrichtigung."),
            ("Fortschritt", "Volumen, Zeit und Rekorde", "Sieh Trainingsdauer, Volumen, Wiederholungen, persönliche Rekorde, Wochen-Streaks und trainierte Muskelgruppen in übersichtlichen Statistiken."),
            ("Muskelanalyse", "Körperansicht und Diagramme", "Analysiere Satzverteilung nach Muskeln, Radar- und Körperansichten sowie Top- und Rekordübungen über mehrere Zeiträume."),
            ("Monatsberichte", "Jeden Monat als Rückblick", "Monatsberichte fassen Trainings, Dauer, Volumen, Sätze, Rekorde, Muskelverteilung und Wochen-Streak zusammen und lassen sich als Share Card teilen."),
            ("Training teilen", "Erfolge sichtbar machen", "Teile abgeschlossene Workouts und Routinen als Karte oder Text und bestimme, welche Trainings in deinem Profil öffentlich erscheinen."),
            ("Hevy-Import", "Verlauf und Routinen übernehmen", "Importiere kompatible Hevy-CSV-Dateien für Workouts, Übungen und Körpermessungen. Hyse erstellt aus Workouts des letzten Monats bearbeitbare Routinen."),
            ("In der Nähe", "Fitnessstudios mit Apple Karten finden", "Suche nach dem Training echte Fitnessstudios in deiner Nähe, sortiert nach Entfernung, wenn du den Standortzugriff freigibst."),
        ] if de else [
            ("Active workout", "Plan routines or start empty", "Start an empty workout or a saved plan, carry over previous values and adjust exercise order as you train."),
            ("Exercise library", "Find and understand exercises", "Search by muscle group or equipment, use favourites, local exercise images and execution guidance."),
            ("Custom exercises", "Your own training catalogue", "Create private exercises with names, muscles, equipment and an optional photo or execution guide."),
            ("Sets", "Weight, reps and RPE", "Log every set with weight, repetitions and optional RPE. Warm-up, drop-set and failure sets and supersets stay distinguishable."),
            ("Rest timer", "Timer, sounds and haptics", "Adjust rest periods, use the rest timer with selectable Hyse sounds and get a notification when a rest period ends."),
            ("Progress", "Volume, time and records", "Review workout duration, volume, repetitions, personal records, weekly streaks and trained muscle groups in clear statistics."),
            ("Muscle analysis", "Body views and charts", "Analyse sets by muscle, radar and body views, plus top and record exercises across several time ranges."),
            ("Monthly reports", "A monthly look back", "Monthly reports summarise workouts, duration, volume, sets, records, muscle distribution and weekly streaks, with a share card."),
            ("Share training", "Make progress visible", "Share completed workouts and routines as a card or text and choose which sessions are public on your profile."),
            ("Hevy import", "Bring your history and routines", "Import compatible Hevy CSV files for workouts, exercises and body measurements. Hyse creates editable routines from workouts in the past month."),
            ("Nearby gyms", "Find gyms with Apple Maps", "After training, search real nearby gyms sorted by distance when you grant location access."),
        ]
        workouts_body = f"""
<section class="page-hero"><span class="release-pill">{'Training gemeinsam erleben' if de else 'Experience training together'}</span><p class="eyebrow">{'Workout-Planer' if de else 'Workout planner'}</p><h1>{'Vom ersten Satz bis zum nächsten Rekord.' if de else 'From your first set to your next record.'}</h1><p class="lead">{workouts_description}</p></section>
<section class="section" aria-labelledby="overview-heading"><h2 id="overview-heading" class="visually-hidden">{'Funktionen im Überblick' if de else 'Features at a glance'}</h2><div class="bento">{cards(training_cards)}</div></section>
<section class="spotlight"><div><p class="eyebrow">Gym Communities</p><h2>{'Freunde, Feed und Neuigkeiten aus deinem Gym.' if de else 'Friends, feed and news from your gym.'}</h2><p class="section-intro">{'Suche nach Gym, Community oder Stadt. Erstelle eine Community mit Bild und Beschreibung, verwalte Mitgliederrollen und veröffentliche offizielle Neuigkeiten oder schreibe im Mitgliederkanal. Reaktionen, Antworten, Bearbeiten, Löschen und Melden halten den Austausch übersichtlich.' if de else 'Search by gym, community or city. Create a community with an image and description, manage member roles, and publish official news or chat in the member channel. Reactions, replies, editing, deletion and reporting keep conversations clear.'}</p></div><div class="community-demo"><div class="message"><strong>{'Gym-Team' if de else 'Gym team'}</strong><br>{'Neue Geräte sind ab heute im Freihantelbereich.' if de else 'New equipment is available in the free-weight area today.'}<small>{'Neuigkeiten' if de else 'News'}</small><span class="reaction">🔥 8</span></div><div class="message mine"><strong>{'Du' if de else 'You'}</strong><br>{'Schon getestet – richtig gut!' if de else 'Tried it already – really good!'}<small>{'Mitglieder · bearbeitet' if de else 'Members · edited'}</small></div></div></section>
<section class="section"><div class="cta-panel"><div><h2>{'Dein Training, dein Verlauf, dein Gym.' if de else 'Your training, your history, your gym.'}</h2><p>{'Lade Hyse herunter und starte dein nächstes Workout.' if de else 'Download Hyse and start your next workout.'}</p></div>{app_store_button(language)}</div></section>"""
        workouts_schema = {"@context": "https://schema.org", "@graph": [breadcrumb(workouts_path, language, LABEL[workouts_path]), {"@type": "SoftwareApplication", "name": "Hyse Gym & Workout Planner", "applicationCategory": "HealthApplication", "operatingSystem": "iOS, iPadOS, watchOS", "description": workouts_description, "url": ORIGIN + workouts_path}]}
        write(workouts_path, document(workouts_path, language, workouts_title, workouts_description, workouts_body, workouts_schema))

        ios_title = "Hyse für iPhone, iPad und Apple Watch" if de else "Hyse for iPhone, iPad and Apple Watch"
        ios_description = (
            "Hyse verbindet Ernährung, Training, Apple Health, Live Activities und Apple Watch auf iPhone, iPad und am Handgelenk."
            if de else
            "Hyse connects nutrition, training, Apple Health, Live Activities and Apple Watch across iPhone, iPad and your wrist."
        )
        store_action = app_store_button(language)
        watch_cards = [
            ("Quick Entry", "Kalorien und Makros schnell ergänzen", "Trage Kalorien, Kohlenhydrate, Protein und Fett ein und sende den Ernährungseintrag an dein iPhone."),
            ("Workout", "Aktives Training begleiten", "Sieh Workoutname, Dauer, Pause, Puls und aktive Kalorien und behalte den aktuellen Satz im Blick."),
            ("Satz-Editor", "Gewicht und Wiederholungen ändern", "Passe Werte auf der Watch an, schließe Sätze ab und erhalte den gespeicherten Status direkt zurück."),
            ("Zuverlässig", "Gespeichert oder später synchronisiert", "Wenn das iPhone gerade nicht erreichbar ist, werden Aktionen in die Warteschlange gelegt und später synchronisiert."),
        ] if de else [
            ("Quick Entry", "Add calories and macros quickly", "Add calories, carbohydrates, protein and fat and send the nutrition entry to your iPhone."),
            ("Workout", "Follow an active workout", "See workout name, duration, rest, heart rate and active calories while keeping the current set in view."),
            ("Set editor", "Edit weight and repetitions", "Adjust values on the Watch, complete sets and receive the saved status directly."),
            ("Reliable", "Saved or synced later", "If the iPhone is temporarily unavailable, actions are queued and synced later."),
        ]
        ios_body = f"""
<section class="page-hero ios-hero"><p class="eyebrow">iPhone, iPad &amp; Apple Watch</p><h1>{'Dein Tag in der Tasche. Dein Workout am Handgelenk.' if de else 'Your day in your pocket. Your workout on your wrist.'}</h1><p class="lead">{ios_description}</p><div class="hero-actions">{store_action}</div></section>
<section class="section"><div class="app-download"><img src="{ICON}" width="180" height="180" alt="Hyse App-Icon"><div><h2>{'Die aktuelle Hyse-App' if de else 'The current Hyse app'}</h2><p>{'Mit lokalem Gastmodus, optionaler Kontosynchronisierung, Apple Health, Live Activity, Gym Communities und deutscher sowie englischer Oberfläche.' if de else 'With local guest mode, optional account sync, Apple Health, Live Activity, gym communities, and German and English interfaces.'}</p>{store_action}</div></div>
<div class="feature-band"><article><strong>Apple Health</strong><p>{'Gewicht, Schritte, Ruheenergie, aktive Energie und Wasser mit deiner Freigabe.' if de else 'Weight, steps, resting energy, active energy and water with your permission.'}</p></article><article><strong>Apple Watch</strong><p>{'Schnelle Ernährungseinträge, Workout automatisch starten, Sätze bearbeiten und abschließen.' if de else 'Quick nutrition entries, automatic workout start, set editing and completion.'}</p></article><article><strong>Live Activity</strong><p>{'Aktives Training, Dauer und Pausenstatus auf Sperrbildschirm und Dynamic Island.' if de else 'Active workout, duration and rest status on the Lock Screen and Dynamic Island.'}</p></article><article><strong>{'Offline first' if not de else 'Offline first'}</strong><p>{'Kerndaten, Synchronisationswarteschlange und Übungsbilder bleiben lokal verfügbar.' if de else 'Core data, the sync queue and exercise images remain available locally.'}</p></article></div></section>
<section class="section"><p class="eyebrow">{'Apple Watch im Detail' if de else 'Apple Watch in detail'}</p><h2>{'Die wichtigsten Aktionen direkt am Handgelenk' if de else 'The key actions right on your wrist'}</h2><div class="grid">{cards(watch_cards)}</div></section>
<section class="soft"><div class="soft-inner"><p class="eyebrow">{'Flexibel und privat' if de else 'Flexible and private'}</p><h2>{'Du entscheidest über Konto, Health und Benachrichtigungen.' if de else 'You choose your account, Health and notifications.'}</h2><p class="section-intro">{'Hyse funktioniert als Gast lokal. Ein Konto synchronisiert ausgewählte Daten über mehrere Geräte. Apple-Health- und Push-Berechtigungen sind optional und jederzeit in iOS steuerbar.' if de else 'Hyse works locally as a guest. An account syncs selected data across devices. Apple Health and push permissions are optional and can be controlled in iOS at any time.'}</p></div></section>"""
        ios_schema = {"@context": "https://schema.org", "@graph": [breadcrumb(ios_path, language, LABEL[ios_path]), {"@type": "MobileApplication", "name": "Hyse", "operatingSystem": "iOS, iPadOS, watchOS", "applicationCategory": "HealthApplication", "description": ios_description, "url": ORIGIN + ios_path, "installUrl": APP_STORE_URL}]}
        write(ios_path, document(ios_path, language, ios_title, ios_description, ios_body, ios_schema))


def build_app_marketing_pages() -> None:
    for language in ("en", "de"):
        is_de = language == "de"
        path = "/de/marketing" if is_de else "/en/marketing"
        title = ("Hyse App – Ernährung, Training und Gym Community" if is_de
                 else "Hyse App – nutrition, training and gym community")
        description = ("Entdecke Hyse: Ernährungstracking, Workouts, Apple Health, Apple Watch und Gym Communities in einer App."
                       if is_de else "Discover Hyse: nutrition tracking, workouts, Apple Health, Apple Watch and gym communities in one app.")
        body = f"""
<section class="hero marketing-hero">
  <div>
    <span class="release-pill">{'Hyse für iPhone & Apple Watch' if is_de else 'Hyse for iPhone & Apple Watch'}</span>
    <p class="eyebrow">{'Ernährung. Training. Fortschritt.' if is_de else 'Nutrition. Training. Progress.'}</p>
    <h1>{'Eine App für deinen ganzen Fortschritt.' if is_de else 'One app for all your progress.'}</h1>
    <p class="lead">{'Hyse verbindet Kalorien und Makros, Workouts, Gesundheitsdaten und dein Gym in einem klaren persönlichen Überblick.' if is_de else 'Hyse brings calories and macros, workouts, health data and your gym into one clear personal overview.'}</p>
    <div class="hero-actions">
      <a class="button" href="{'/de/ios' if is_de else '/en/ios'}">{'Hyse für iOS ansehen' if is_de else 'Explore Hyse for iOS'}</a>
      <a class="button secondary" href="{'/de/funktionen' if is_de else '/en/features'}">{'Alle Funktionen' if is_de else 'All features'}</a>
    </div>
    <ul class="hero-points"><li>{'Lokal als Gast nutzbar' if is_de else 'Local guest mode'}</li><li>{'Konto optional' if is_de else 'Account optional'}</li><li>{'Deutsch und Englisch' if is_de else 'German and English'}</li></ul>
  </div>
  <div class="app-card"><img src="{ICON}" width="210" height="210" alt="{'Hyse App-Icon' if is_de else 'Hyse app icon'}"><h2>Hyse</h2><p>{'Ernährung, Workouts und Gym Community' if is_de else 'Nutrition, workouts and gym community'}</p></div>
</section>
<section class="section">
  <p class="eyebrow">{'Alles an einem Ort' if is_de else 'Everything in one place'}</p>
  <h2>{'Weniger App-Wechsel. Mehr Überblick.' if is_de else 'Fewer app switches. More clarity.'}</h2>
  <p class="section-intro">{'Hyse begleitet deinen Alltag vom ersten Lebensmittel bis zum letzten Trainingssatz.' if is_de else 'Hyse supports your day from the first food entry to the final workout set.'}</p>
  <div class="bento">
    <article class="card wide"><span class="card-kicker">{'Ernährung' if is_de else 'Nutrition'}</span><h3>{'Kalorien, Makros und Mahlzeiten einfach erfassen' if is_de else 'Track calories, macros and meals with ease'}</h3><p>{'Suche Lebensmittel, scanne Barcodes, speichere eigene Produkte und Rezepte und behalte dein persönliches Tagesziel im Blick.' if is_de else 'Search foods, scan barcodes, save your own products and recipes, and keep your personal daily target in view.'}</p></article>
    <article class="card"><span class="card-kicker">{'Training' if is_de else 'Training'}</span><h3>{'Workouts planen und protokollieren' if is_de else 'Plan and log workouts'}</h3><p>{'Erstelle Routinen, erfasse Gewicht und Wiederholungen und verfolge Volumen, Rekorde und trainierte Muskelgruppen.' if is_de else 'Build routines, record weight and reps, and follow volume, records and trained muscle groups.'}</p></article>
    <article class="card"><span class="card-kicker">Apple Watch</span><h3>{'Das Training am Handgelenk' if is_de else 'Your workout on your wrist'}</h3><p>{'Schließe Sätze auf der Watch ab und behalte Pausen, Dauer und Trainingswerte im Blick.' if is_de else 'Complete sets on Apple Watch and keep rest periods, duration and workout metrics in view.'}</p></article>
    <article class="card wide"><span class="card-kicker">Gym Communities</span><h3>{'Mit deinem Fitnessstudio verbunden' if is_de else 'Connected to your gym'}</h3><p>{'Finde die Community deines Gyms, lies Neuigkeiten und tausche dich mit anderen Mitgliedern aus.' if is_de else 'Find your gym community, read updates and connect with other members.'}</p></article>
  </div>
</section>
<section class="soft"><div class="soft-inner"><p class="eyebrow">{'Apple-Ökosystem' if is_de else 'Apple ecosystem'}</p><h2>{'iPhone, Apple Watch und Apple Health arbeiten zusammen.' if is_de else 'iPhone, Apple Watch and Apple Health work together.'}</h2><p class="section-intro">{'Verbinde auf Wunsch Gewicht, Schritte, Energie und Wasser. Berechtigungen bleiben unter deiner Kontrolle.' if is_de else 'Optionally connect weight, steps, energy and water. Permissions remain under your control.'}</p></div></section>
<section class="section"><div class="cta-panel"><div><h2>{'Lerne Hyse kennen.' if is_de else 'Discover Hyse.'}</h2><p>{'Alle Informationen zur App für iPhone und Apple Watch.' if is_de else 'Everything about the app for iPhone and Apple Watch.'}</p></div><div class="hero-actions"><a class="button" href="{'/de/ios' if is_de else '/en/ios'}">{'Zur iOS-Seite' if is_de else 'Go to iOS page'}</a><a class="button secondary" href="{'/de/support' if is_de else '/en/support'}">Support</a></div></div></section>"""
        schema = {"@context": "https://schema.org", "@graph": [
            breadcrumb(path, language, LABEL[path]),
            {"@type": "MobileApplication", "name": "Hyse", "applicationCategory": "HealthApplication",
             "operatingSystem": "iOS, watchOS", "description": description, "url": ORIGIN + path,
             "image": ORIGIN + SOCIAL},
        ]}
        write(path, document(path, language, title, description, body, schema))


def add_public_page_links_to_preserved_pages() -> None:
    # Product pages are editorial HTML and are intentionally not regenerated by
    # this script. Add stable public destinations to their existing navigation
    # and footer without
    # replacing their layout or copy.
    for language in ("en", "de"):
        support_path = f"/{language}/support"
        marketing_path = f"/{language}/marketing"
        privacy_path = "/de/datenschutz" if language == "de" else "/en/privacy"
        support_link = f'<a href="{support_path}">Support</a>'
        marketing_link = f'<a href="{marketing_path}">{"Über Hyse" if language == "de" else "About Hyse"}</a>'
        marker = f'<a href="{privacy_path}"'
        localized_root = PUBLIC / language
        paths = [localized_root / "index.html", *localized_root.glob("*/index.html")]
        for path in paths:
            if path.parent.name in {"support", "marketing"}:
                continue
            content = path.read_text(encoding="utf-8")
            if marker not in content:
                continue
            links = ""
            if f'href="{marketing_path}"' not in content:
                links += marketing_link
            if f'href="{support_path}"' not in content:
                links += support_link
            if links:
                path.write_text(content.replace(marker, links + marker), encoding="utf-8")


def build_support_files() -> None:
    (PUBLIC / "assets").mkdir(exist_ok=True)
    # The language switch script is maintained as a static asset. Do not
    # regenerate an automatic preference cookie for passive visits.
    (PUBLIC / "robots.txt").write_text("""User-agent: *
Allow: /en
Allow: /de
Allow: /assets/
Disallow: /api/
Disallow: /_/
Disallow: /email-change/
Disallow: /oauth2-redirect

Sitemap: https://hyse.minipliy.net/sitemap.xml
""", encoding="utf-8")
    routes = [path for pair in PAGES for path in pair[:2]]
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">']
    for path in routes:
        other = PAIR[path]
        en_path, de_path = (path, other) if path.startswith("/en") else (other, path)
        x_default = en_path if path.endswith("/impressum") else "/en"
        lines += ["  <url>", f"    <loc>{ORIGIN}{path}</loc>", f"    <xhtml:link rel=\"alternate\" hreflang=\"en\" href=\"{ORIGIN}{en_path}\"/>", f"    <xhtml:link rel=\"alternate\" hreflang=\"de\" href=\"{ORIGIN}{de_path}\"/>", f"    <xhtml:link rel=\"alternate\" hreflang=\"x-default\" href=\"{ORIGIN}{x_default}\"/>", "  </url>"]
    lines.append("</urlset>")
    (PUBLIC / "sitemap.xml").write_text("\n".join(lines) + "\n", encoding="utf-8")
    well_known = PUBLIC / ".well-known"
    well_known.mkdir(exist_ok=True)
    association = {"applinks": {"details": [{"appIDs": ["ABCDE12345.com.deinname.hyse"], "components": [{"/": "/*", "exclude": True, "comment": "All HTTPS links stay in the browser"}]}]}}
    (well_known / "apple-app-site-association").write_text(json.dumps(association, indent=2) + "\n", encoding="utf-8")
    root = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,follow"><meta name="google-site-verification" content="{GOOGLE_VERIFICATION}"><link rel="alternate" hreflang="en" href="{ORIGIN}/en"><link rel="alternate" hreflang="de" href="{ORIGIN}/de"><link rel="alternate" hreflang="x-default" href="{ORIGIN}/en"><title>Hyse</title><script>const saved=document.cookie.match(/(?:^|; )hyse_language=(de|en)/)?.[1];const preferred=(navigator.languages||[navigator.language||'en']).some(v=>v.toLowerCase().startsWith('de'))?'de':'en';location.replace('/'+(saved||preferred));</script></head><body><main><h1>Hyse</h1><p>Redirecting…</p></main></body></html>"""
    (PUBLIC / "index.html").write_text(root + "\n", encoding="utf-8")


def main() -> None:
    # Legal pages remain sourced from the existing approved legal copy. Product
    # pages are generated above so their feature inventory stays maintainable.
    copy_legal("privacy", "/en/privacy", "en", "Privacy Policy – Hyse", "How Hyse processes website, account, nutrition and optional health data, including user rights and retention.")
    copy_legal("datenschutz", "/de/datenschutz", "de", "Datenschutzerklärung – Hyse", "Informationen zur Verarbeitung von Website-, Konto-, Ernährungs- und optionalen Gesundheitsdaten durch Hyse.")
    copy_legal("terms", "/en/terms", "en", "Terms of Use – Hyse", "Terms governing accounts, permitted use, availability, liability and account deletion for the Hyse app and website.")
    copy_legal("nutzungsbedingungen", "/de/agb", "de", "Nutzungsbedingungen – Hyse", "Nutzungsbedingungen für Konten, erlaubte Nutzung, Verfügbarkeit, Haftung und Kontolöschung bei Hyse.")
    copy_legal("en/impressum", "/en/impressum", "en", "Imprint – Hyse", "Provider information, contact details and legal notice for the Hyse app and website.")
    copy_legal("de/impressum", "/de/impressum", "de", "Impressum – Hyse", "Anbieterkennzeichnung, Kontaktdaten und rechtliche Hinweise für die Hyse App und Website.")
    build_product_pages()
    build_app_marketing_pages()
    build_support_pages()
    add_public_page_links_to_preserved_pages()
    build_support_files()
    print("Refreshed localized product, legal, support and website support files.")


if __name__ == "__main__":
    main()
