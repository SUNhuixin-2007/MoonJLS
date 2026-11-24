#!/usr/bin/env python3
"""Report source scale transparently; never count tests or examples as core LOC.

Strict effective = nonblank handwritten core MoonBit lines after stripping line
and block comments, except punctuation-only structural lines. This is an
engineering metric, not a promise about the organizer's own counting method.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SKIP_PARTS = {".git", ".mooncakes", "_build", "target", "work", "node_modules"}
NON_CORE = {"cmd", "examples", "fixtures", "benchmarks", "tests"}
STRUCTURAL = re.compile(r"^[\s{}()\[\],;]*$")


def without_comments(text: str) -> list[str]:
    """Small lexical scanner preserving strings and line boundaries."""
    output = []
    index = 0
    block_depth = 0
    quote = None
    escaped = False
    while index < len(text):
        character = text[index]
        pair = text[index:index + 2]
        if block_depth:
            if pair == "/*":
                block_depth += 1
                index += 2
            elif pair == "*/":
                block_depth -= 1
                index += 2
                output.append(" ")
            else:
                if character == "\n":
                    output.append("\n")
                index += 1
        elif quote:
            output.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            index += 1
        elif pair == "//":
            newline = text.find("\n", index)
            index = len(text) if newline < 0 else newline
        elif pair == "/*":
            block_depth = 1
            index += 2
        else:
            if character in ('"', "'"):
                quote = character
            output.append(character)
            index += 1
    return "".join(output).splitlines()


def measure(path: Path) -> dict:
    text = path.read_text(encoding="utf-8-sig")
    lines = without_comments(text)
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "physical": len(text.splitlines()),
        "code_nonblank": sum(bool(line.strip()) for line in lines),
        "effective_strict": sum(bool(line.strip()) and not STRUCTURAL.fullmatch(line)
                                for line in lines),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--minimum", type=int, default=0,
                        help="Optional gate for strict core effective lines")
    arguments = parser.parse_args()
    categories = {"core": [], "tests": [], "examples_and_tools": []}
    for path in sorted(ROOT.rglob("*.mbt")):
        relative = path.relative_to(ROOT)
        if any(part in SKIP_PARTS for part in relative.parts):
            continue
        if path.name.endswith(("_test.mbt", "_wbtest.mbt", "_bench.mbt")):
            category = "tests"
        elif any(part in NON_CORE for part in relative.parts):
            category = "examples_and_tools"
        else:
            category = "core"
        categories[category].append(measure(path))
    totals = {
        name: {metric: sum(file[metric] for file in files)
               for metric in ("physical", "code_nonblank", "effective_strict")}
        for name, files in categories.items()
    }
    report = {
        "method": "Handwritten .mbt only, comments/blank removed; strict also removes punctuation-only lines",
        "excluded": sorted(SKIP_PARTS), "totals": totals, "files": categories,
    }
    if arguments.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print("category                 physical  code_nonblank  effective_strict")
        for name, counts in totals.items():
            print(f"{name:24s} {counts['physical']:8d} {counts['code_nonblank']:14d} "
                  f"{counts['effective_strict']:17d}")
        print("Core excludes tests, benchmarks, command examples, generated output and work/.")
    if totals["core"]["effective_strict"] < arguments.minimum:
        raise SystemExit(f"Strict core effective LOC below {arguments.minimum}")


if __name__ == "__main__":
    main()
