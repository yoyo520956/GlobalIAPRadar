#!/usr/bin/env python3
"""Audit the in-app localisation table against its call sites.

The table is a plain dictionary, so a missing key cannot fail the build -- it
just renders the raw key (or an empty label) at runtime. That is silent, and it
is exactly the class of bug that reaches a user instead of the compiler.

Checks:
  1. every key used at a call site exists in the table
  2. every table key has BOTH a Simplified Chinese and an English value
  3. every key is actually referenced somewhere, directly by an L10n.* call or
     indirectly through a computed property such as `status.labelKey`
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE_FILE = ROOT / "GlobalIAPRadar" / "Localization" / "L10n.swift"
SOURCES = [ROOT / "GlobalIAPRadar"]

# "app.tagline": ("中文", "English")
ENTRY = re.compile(r'^\s*"([^"]+)"\s*:\s*\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)')
# L10n.t("key", language)
CALL = re.compile(r'L10n\.\w+\(\s*"((?:[^"\\]|\\.)*)"')
# Any bare string literal, e.g. the return value of `status.labelKey`
LITERAL = re.compile(r'"([^"\n]+)"')


def load_table():
    """Key -> (zh, en, line number) parsed out of the L10n table."""
    table = {}
    for number, line in enumerate(TABLE_FILE.read_text(encoding="utf-8").splitlines(), 1):
        match = ENTRY.match(line)
        if match:
            table[match.group(1)] = (match.group(2), match.group(3), number)
    return table


def load_direct_calls():
    """Key -> first file that passes it straight to an L10n function."""
    used = {}
    for base in SOURCES:
        for path in sorted(base.rglob("*.swift")):
            if path == TABLE_FILE:
                continue
            text = path.read_text(encoding="utf-8")
            for key in CALL.findall(text):
                used.setdefault(key, str(path.relative_to(ROOT)))
    return used


def load_literal_mentions():
    """Every string literal -> files containing it (used for indirect keys)."""
    found = {}
    for base in SOURCES:
        for path in sorted(base.rglob("*.swift")):
            if path == TABLE_FILE:
                continue
            text = path.read_text(encoding="utf-8")
            for literal in LITERAL.findall(text):
                found.setdefault(literal, []).append(path.relative_to(ROOT))
    return found


def main():
    problems = []
    table = load_table()
    direct = load_direct_calls()
    literals = load_literal_mentions()

    if not table:
        print("FAIL: could not parse any entry out of the localisation table")
        return 2

    # A dictionary literal with two identical keys silently keeps the later one
    # and drops the earlier -- a real trap, so verify uniqueness explicitly.
    import re as _re
    entry_re = _re.compile(r'^\s*"([^"]+)"\s*:\s*\(')
    lines = TABLE_FILE.read_text(encoding="utf-8").splitlines()
    occurrences = {}
    for number, line in enumerate(lines, 1):
        match = entry_re.match(line)
        if match:
            occurrences.setdefault(match.group(1), []).append(number)
    for key, numbers in sorted(occurrences.items()):
        if len(numbers) > 1:
            problems.append(f"DUPLICATE KEY  {key}  at lines {numbers}")

    for key, site in sorted(direct.items()):
        if key not in table:
            problems.append(f"MISSING KEY  {key}  ({site})")

    for key, (zh, en, number) in sorted(table.items()):
        if not zh:
            problems.append(f"EMPTY ZH     {key}  (L10n.swift:{number})")
        if not en:
            problems.append(f"EMPTY EN     {key}  (L10n.swift:{number})")

    indirect = {key for key in table if key not in direct and key in literals}
    dead = sorted(set(table) - set(direct) - indirect)

    print(f"table entries          : {len(table)}")
    print(f"keys used directly     : {len(direct)}")
    print(f"keys used indirectly   : {len(indirect)}")
    print(f"unused strings         : {len(dead)}" + (f" -> {', '.join(dead)}" if dead else ""))

    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print("  " + problem)
        return 1

    print("\nlocalisation table OK: every used key exists, both languages populated")
    return 0


if __name__ == "__main__":
    sys.exit(main())