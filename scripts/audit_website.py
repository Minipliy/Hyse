#!/usr/bin/env python3
"""Validate Hyse's generated SEO, language routes and internal links."""

from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from build_website import APP_STORE_URL, ORIGIN, PAGES, PAIR, PUBLIC, SOCIAL_CONFIG, social_links


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = ""
        self.in_title = False
        self.h1 = 0
        self.meta = {}
        self.links = []
        self.nav_links = []
        self.nav_depth = 0
        self.alternates = {}
        self.canonical = ""
        self.scripts = []
        self.in_json = False
        self.json_buffer = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "nav": self.nav_depth += 1
        if tag == "title": self.in_title = True
        if tag == "h1": self.h1 += 1
        if tag == "meta" and values.get("name"): self.meta[values["name"]] = values.get("content", "")
        if tag == "a" and values.get("href"):
            self.links.append(values["href"])
            if self.nav_depth: self.nav_links.append(values["href"])
        if tag == "link" and values.get("rel") == "canonical": self.canonical = values.get("href", "")
        if tag == "link" and values.get("rel") == "alternate": self.alternates[values.get("hreflang", "")] = values.get("href", "")
        if tag == "script" and values.get("type") == "application/ld+json": self.in_json = True

    def handle_endtag(self, tag):
        if tag == "nav" and self.nav_depth: self.nav_depth -= 1
        if tag == "title": self.in_title = False
        if tag == "script" and self.in_json:
            self.in_json = False
            self.scripts.append("".join(self.json_buffer))
            self.json_buffer = []

    def handle_data(self, data):
        if self.in_title: self.title += data
        if self.in_json: self.json_buffer.append(data)


def target_for(path: str) -> Path:
    return PUBLIC / path.lstrip("/") / "index.html"


def main() -> None:
    errors = []
    configured_social = social_links()
    routes = [path for pair in PAGES for path in pair[:2]]
    for path in routes:
        file = target_for(path)
        if not file.exists():
            errors.append(f"Missing page: {path}")
            continue
        source = file.read_text(encoding="utf-8")
        parser = PageParser(); parser.feed(source)
        language = "de" if path.startswith("/de") else "en"
        other = PAIR[path]
        en_path, de_path = (path, other) if language == "en" else (other, path)
        expected = {"en": ORIGIN + en_path, "de": ORIGIN + de_path, "x-default": ORIGIN + "/en"}
        if not parser.title.strip(): errors.append(f"Missing title: {path}")
        if len(parser.meta.get("description", "")) < 60: errors.append(f"Short/missing description: {path}")
        if parser.canonical != ORIGIN + path: errors.append(f"Wrong canonical: {path}")
        if parser.alternates != expected: errors.append(f"Wrong hreflang: {path} {parser.alternates}")
        if parser.h1 != 1: errors.append(f"Expected one h1: {path}, got {parser.h1}")
        if "index" not in parser.meta.get("robots", ""): errors.append(f"Page not indexable: {path}")
        if parser.meta.get("apple-itunes-app") != "app-id=6811359623": errors.append(f"Missing App Store smart banner: {path}")
        if APP_STORE_URL not in parser.links: errors.append(f"Missing App Store link: {path}")
        if "App-Store-Link folgt" in source or "App Store link available after release" in source:
            errors.append(f"Outdated App Store placeholder: {path}")
        if not parser.scripts: errors.append(f"Missing structured data: {path}")
        for value in parser.scripts:
            try:
                structured = json.loads(value)
                serialized = json.dumps(structured)
                for _, _, profile_url in configured_social:
                    if path in ("/en", "/de") and profile_url not in serialized:
                        errors.append(f"Social profile missing from sameAs on {path}: {profile_url}")
            except json.JSONDecodeError as error: errors.append(f"Invalid JSON-LD: {path}: {error}")
        if re.search(r"\b(?:settings|add_entry)\.[a-z0-9_]+", source): errors.append(f"Visible translation key risk: {path}")
        language_routes = {pair[1] if language == "de" else pair[0] for pair in PAGES}
        expected_nav = language_routes | {other}
        if not expected_nav.issubset(set(parser.nav_links)):
            errors.append(f"Navigation does not reach every page from {path}: missing={expected_nav-set(parser.nav_links)}")
        for _, _, profile_url in configured_social:
            if profile_url not in parser.links: errors.append(f"Social profile missing from bottom section on {path}: {profile_url}")
        if path == "/de/training":
            for marker in ("Routinen planen", "RPE", "Pausentimer", "Hevy", "Freunde", "Workouts des letzten Monats"):
                if marker not in source: errors.append(f"Missing German workout content on {path}: {marker}")
            if "workout-preview" in source or "AKTIVES WORKOUT" in source: errors.append(f"Interactive workout preview must not appear on {path}")
            if "Die Website informiert ausschließlich" in source: errors.append(f"Unwanted workout warning remains on {path}")
        if path == "/en/workouts":
            for marker in ("Plan routines", "RPE", "rest timer", "Hevy", "Friends", "workouts in the past month"):
                if marker not in source: errors.append(f"Missing English workout content on {path}: {marker}")
            if "workout-preview" in source or "ACTIVE WORKOUT" in source: errors.append(f"Interactive workout preview must not appear on {path}")
            if "This website only provides information" in source: errors.append(f"Unwanted workout warning remains on {path}")
        for link in parser.links:
            if not link.startswith("/") or link.startswith("//"): continue
            clean = link.split("#", 1)[0].split("?", 1)[0]
            if clean in ("", "/"): continue
            if clean.startswith("/assets/"):
                exists = (PUBLIC / clean.lstrip("/")).exists()
            else:
                exists = target_for(clean).exists() or (PUBLIC / clean.lstrip("/")).is_file()
            if not exists: errors.append(f"Broken link on {path}: {link}")

    sitemap = ET.parse(PUBLIC / "sitemap.xml")
    namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    listed = {node.text for node in sitemap.findall("s:url/s:loc", namespace)}
    expected_urls = {ORIGIN + route for route in routes}
    if listed != expected_urls: errors.append(f"Sitemap routes differ: missing={expected_urls-listed}, extra={listed-expected_urls}")
    for retired in (PUBLIC / "de" / "social-media" / "index.html", PUBLIC / "en" / "social" / "index.html"):
        if retired.exists(): errors.append(f"Retired standalone social page still exists: {retired}")

    email_change = (PUBLIC / "email-change" / "index.html").read_text(encoding="utf-8")
    if "noindex" not in email_change: errors.append("Email-change confirmation must stay noindex")
    association = json.loads((PUBLIC / ".well-known" / "apple-app-site-association").read_text(encoding="utf-8"))
    if "applinks" not in association: errors.append("Invalid Apple association file")
    if not SOCIAL_CONFIG.exists(): errors.append("Missing central social link configuration")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        raise SystemExit(1)
    print(f"Website audit passed ({len(routes)} bilingual pages, sitemap, links, JSON-LD and private-route checks).")


if __name__ == "__main__": main()
