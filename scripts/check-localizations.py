#!/usr/bin/env python3
"""Check Apple .strings resources without external dependencies."""
import ast
import re
import sys
from pathlib import Path

LANGUAGES = ("it", "en", "de", "fr", "es", "zh-Hans", "ja")
ROOT = Path(__file__).resolve().parents[1] / "Sources/FolderSpannerCore/Resources"
PAIR = re.compile(r'^\s*("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*");\s*$')
PLACEHOLDERS = re.compile(r'%(?:\d+\$)?(?:ld|@)')


def read_table(lang):
    path = ROOT / f"{lang}.lproj" / "Localizable.strings"
    if not path.is_file():
        raise ValueError(f"Missing {path}")
    data = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        match = PAIR.fullmatch(line)
        if not match:
            raise ValueError(f"Invalid .strings syntax {path}:{line_number}")
        key, value = (ast.literal_eval(segment) for segment in match.groups())
        if key in data:
            raise ValueError(f"Duplicate key in {path}:{line_number}: {key!r}")
        if not value:
            raise ValueError(f"Empty translation in {path}:{line_number}: {key!r}")
        data[key] = value
    return data


def main():
    tables = {lang: read_table(lang) for lang in LANGUAGES}
    base = tables["it"]
    if len(base) < 130:
        raise ValueError("Unexpectedly small translation catalog")
    for lang, table in tables.items():
        missing = set(base) - set(table)
        extra = set(table) - set(base)
        if missing or extra:
            raise ValueError(f"{lang}: missing={sorted(missing)!r} extra={sorted(extra)!r}")
        for key, value in table.items():
            if sorted(PLACEHOLDERS.findall(key)) != sorted(PLACEHOLDERS.findall(value)):
                raise ValueError(f"{lang}: placeholder mismatch for {key!r}")
        print(f"{lang}: {len(table)} verified keys")
    print("Localization validation passed: 7 languages and matching placeholders")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, SyntaxError) as exc:
        sys.exit(f"Localization validation failed: {exc}")
