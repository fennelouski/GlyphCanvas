#!/usr/bin/env python3
"""Audit Localizable.strings: key parity, placeholders, identical-to-source report."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "GlyphCanvas"
EN_FILE = ROOT / "en.lproj" / "Localizable.strings"
ENTRY_RE = re.compile(
    r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";$',
    re.MULTILINE,
)
PLACEHOLDER_RE = re.compile(
    r"(%(?:\d+\$)?[@df]|%[%ldf]?|\\.\\([^)]*\\)|\\\\n|%%)"
)

# Keys intentionally kept identical to English (filters, brands, universal labels).
INTENTIONALLY_SAME_KEYS = frozenset(
    {
        "A–Z",
        "a–z",
        "JULIAN VANCE",
        "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024",
        "Operator Julian Vance, ID 8829 MK 4",
        "OK",
        "Emoji",
        "Format",
        "Menu",
        "Photos",
        "Studio",
        "STUDIO",
        "Error",
        "IRREVERSIBLE",
        "PARAMETERS",
        "https://…",
    }
)

LOCK_SUBSTRINGS = (
    ".navigationTitle(",
    'Toggle("',
    "CT_SPEC_",
    "STUDIO_SESSION",
    "viewModel.",
    "manifest.",
    "config.",
    "GalleryArchiveNaming",
    "Self.formatted",
    "characterSetSummaryLine",
    "profileActiveStampCount",
    "activeStamps.count",
    "measuredIterationsPerSecond",
    "iterationsPerSecond",
    "iterationCount",
    "playbackIndex",
    "glyphCount",
    "endPercent",
    "GalleryTheme.marketingVersion",
    "optimizationMode ==",
    "format: .number",
    "r.x),",
    "r.width)",
    "Debug —",
    "Scored \\(",
    "\\(item.stampCount)",
    "\\(recent.stampCount)",
    "https://",
    "V.\\(Gallery",
    "v\\(GalleryTheme",
    "\\(config.fps)",
    "\\(config.frameCount) frames",
    "\\(dims.width)",
    "\\(GalleryArchiveNaming",
    "Fitness (higher better)",
    "Loss (lower better)",
    "Evolution \\(",
    "Glyph \\(",
    "Region \\(",
    "Use first \\(",
    "Created \\(",
    "Build version v \\(",
)


def unescape(token: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(token):
        ch = token[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        if i + 1 >= len(token):
            out.append(ch)
            i += 1
            continue
        nxt = token[i + 1]
        if nxt == "n":
            out.append("\n")
            i += 2
        elif nxt in {'"', "\\"}:
            out.append(nxt)
            i += 2
        else:
            out.append("\\")
            out.append(nxt)
            i += 2
    return "".join(out)


def parse_strings(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for m in ENTRY_RE.finditer(text):
        out[unescape(m.group(1))] = unescape(m.group(2))
    return out


def extract_placeholders(value: str) -> list[str]:
    return PLACEHOLDER_RE.findall(value)


def should_lock(key: str) -> bool:
    return any(s in key for s in LOCK_SUBSTRINGS)


def main() -> int:
    if not EN_FILE.exists():
        print(f"Missing source: {EN_FILE}", file=sys.stderr)
        return 1

    english = parse_strings(EN_FILE)
    source_keys = list(english.keys())
    locales = sorted(
        p.name.replace(".lproj", "")
        for p in ROOT.glob("*.lproj")
        if (p / "Localizable.strings").exists()
    )

    failures = 0
    review_failures = 0
    identical_full: list[str] = []
    intentional_unchanged: dict[str, int] = {}
    translated_count: dict[str, int] = {}
    placeholder_issues: list[str] = []

    print(f"Source locale: en ({len(source_keys)} keys)\n")

    for locale in locales:
        path = ROOT / f"{locale}.lproj" / "Localizable.strings"
        data = parse_strings(path)
        missing = [k for k in source_keys if k not in data]
        extra = [k for k in data if k not in english]
        same_as_en = [k for k in source_keys if data.get(k) == english.get(k)]
        unintentional_same = [
            k
            for k in same_as_en
            if k not in INTENTIONALLY_SAME_KEYS and not should_lock(k)
        ]
        intentional = [k for k in same_as_en if k in INTENTIONALLY_SAME_KEYS or should_lock(k)]

        if locale == "en":
            identical_full.append(locale)
        elif len(same_as_en) == len(source_keys):
            identical_full.append(locale)

        intentional_unchanged[locale] = len(intentional)
        translated_count[locale] = len(source_keys) - len(same_as_en)

        print(f"## {locale}")
        print(f"  keys: {len(data)} (source {len(source_keys)})")
        print(f"  missing: {len(missing)}  extra: {len(extra)}")
        print(f"  same as en: {len(same_as_en)}  unintentional: {len(unintentional_same)}")

        if missing:
            failures += 1
            print(f"  MISSING: {missing[:5]}{'...' if len(missing) > 5 else ''}")
        if extra:
            failures += 1
            print(f"  EXTRA: {extra[:5]}{'...' if len(extra) > 5 else ''}")

        for key in source_keys:
            if key not in data:
                continue
            en_ph = extract_placeholders(english[key])
            loc_ph = extract_placeholders(data[key])
            if en_ph != loc_ph:
                failures += 1
                placeholder_issues.append(
                    f"{locale} key={key!r} en={en_ph} loc={loc_ph}"
                )

        if unintentional_same and locale != "en":
            review_failures += len(unintentional_same)
            print(f"  review ({len(unintentional_same)}):")
            for k in unintentional_same[:8]:
                print(f"    - {k!r}")
            if len(unintentional_same) > 8:
                print(f"    ... +{len(unintentional_same) - 8} more"
                )

    print("\n=== Summary ===")
    print(f"Locales processed: {len(locales)}")
    print(f"Fully identical to en: {identical_full}")
    print(f"Placeholder mismatches: {len(placeholder_issues)}")
    if placeholder_issues:
        for line in placeholder_issues[:20]:
            print(f"  {line}")
        failures += len(placeholder_issues)

    non_en = [loc for loc in locales if loc != "en"]
    fully_translated = [
        loc
        for loc in non_en
        if loc not in identical_full
        and all(
            parse_strings(ROOT / f"{loc}.lproj" / "Localizable.strings").get(k)
            != english.get(k)
            or k in INTENTIONALLY_SAME_KEYS
            or should_lock(k)
            for k in source_keys
            if parse_strings(ROOT / f"{loc}.lproj" / "Localizable.strings").get(k)
            == english.get(k)
        )
    ]
    print(f"Locales with no unintentional English copies: {len(fully_translated)}/{len(non_en)}")

    if review_failures:
        failures += review_failures
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
