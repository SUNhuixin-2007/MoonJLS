#!/usr/bin/env python3
"""Reproduce local checks and save evidence, without publishing or network writes."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone, timedelta
import json
import hashlib
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "work" / "validation"


def run(name: str, command: list[str]) -> dict:
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8",
                                errors="replace")
    except OSError as error:
        result = subprocess.CompletedProcess(command, 127, "", str(error))
    LOGS.mkdir(parents=True, exist_ok=True)
    (LOGS / f"{name}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check = {"name": name, "command": command, "exit_code": result.returncode,
             "status": "PASS" if result.returncode == 0 else "FAIL"}
    match = re.search(r"Total tests: (\d+), passed: (\d+), failed: (\d+)", result.stdout)
    if match:
        check["tests"] = dict(zip(("total", "passed", "failed"), map(int, match.groups())))
    print(f"{check['status']}: {name}", flush=True)
    if result.returncode:
        print((result.stdout + result.stderr)[-6000:], flush=True)
    return check


def fingerprint() -> dict:
    # Source archives contain no .git directory and must remain reproducible.
    skip = {".git", ".mooncakes", "_build", "target", "work", "out", "node_modules", "__pycache__", "docs"}
    names = []
    for directory, folders, files in os.walk(ROOT):
        folders[:] = [name for name in folders if name not in skip]
        names.extend((Path(directory) / name).relative_to(ROOT).as_posix() for name in files)
    hashes = {}
    for name in sorted(names):
        path = ROOT / name
        if path.is_file() and (name.endswith(".mbt") or path.name in {"moon.mod", "moon.pkg", "package.json"}
                               or name.startswith(("scripts/", "fixtures/", ".github/"))):
            # Normalize Git-managed text line endings, leaving binary fixtures exact.
            data = path.read_bytes()
            if path.suffix in {".mbt", ".py", ".mjs", ".json", ".mod", ".pkg", ".yml", ".yaml", ".md", ".txt"}:
                data = data.replace(b"\r\n", b"\n")
            hashes[name] = hashlib.sha256(data).hexdigest()
    digest = hashlib.sha256()
    for name, checksum in hashes.items():
        digest.update(name.encode("utf-8") + b"\0" + checksum.encode("ascii") + b"\n")
    return {"sha256": digest.hexdigest(), "files": hashes,
            "scope": "Core/tests, compiler configuration, scripts and fixtures; excludes docs, generated interfaces and build output"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", action="store_true", help="Require a native runtime test")
    arguments = parser.parse_args()
    target = ROOT / "docs" / "LOCAL_VALIDATION.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"result": "RUNNING", "started_at": datetime.now(timezone(timedelta(hours=8))).isoformat()}, indent=2) + "\n", encoding="utf-8")
    before = fingerprint()
    checks = []
    for name in ("interop.json", "file_cli.json", "t87-maxval.json"):
        (LOGS / name).unlink(missing_ok=True)
    commands = [
        ("format", ["moon", "fmt", "--check"]),
        ("compile_all", ["moon", "check", "--target", "all", "--deny-warn"]),
        ("test_wasm", ["moon", "test", "--target", "wasm", "--deny-warn"]),
        ("test_wasm_gc", ["moon", "test", "--target", "wasm-gc", "--deny-warn"]),
        ("test_js", ["moon", "test", "--target", "js", "--deny-warn"]),
        ("demo", ["moon", "run", "cmd/demo", "--target", "js", "--deny-warn"]),
        ("interfaces", ["moon", "info"]),
        ("source_scale", [sys.executable, "scripts/count_loc.py", "--minimum", "4000"]),
        ("independent_interop", [sys.executable, "scripts/interop.py"]),
        ("t87_maxval", [sys.executable, "scripts/t87_interop.py"]),
        ("file_cli", [sys.executable, "scripts/test_file_cli.py"]),
    ]
    for name, command in commands:
        checks.append(run(name, command))
    if arguments.native or platform.system() != "Windows" or shutil.which("cl") or shutil.which("clang-cl"):
        checks.append(run("test_native", ["moon", "test", "--target", "native", "--deny-warn"]))
    else:
        checks.append({"name": "test_native", "status": "NOT_RUN",
                       "reason": "Windows MSVC C++ compiler/linker and SDK are unavailable in this environment"})
    scale = subprocess.run([sys.executable, "scripts/count_loc.py", "--json"],
                           cwd=ROOT, capture_output=True, encoding="utf-8", check=True)
    toolchain = subprocess.run(["moon", "version", "--all"], cwd=ROOT,
                              capture_output=True, encoding="utf-8", check=True)
    node = subprocess.run(["node", "--version"], cwd=ROOT,
                         capture_output=True, encoding="utf-8", check=True)
    after = fingerprint()
    checks.append({"name": "source_unchanged_during_validation",
                   "status": "PASS" if before == after else "FAIL"})
    report = {
        "recorded_at": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "scope": "Local validation only; remote CI, registry publication and contest status are recorded separately",
        "platform": platform.system(), "node": node.stdout.strip(),
        "toolchain": toolchain.stdout.strip(), "checks": checks,
        "source_scale": json.loads(scale.stdout),
        "source_fingerprint": after,
        "limitations": [
            "Native execution is not validated on this Windows host without MSVC C++ compiler and SDK",
            "Interleaved two-component scans have local tests only; CharLS reference rejects them",
            "Sample interleave with non-default RESET has local tests only; external sample cases use RESET=64",
            "Arbitrary MAXVAL live independent evidence is stratified grayscale; MAXVAL 1/2 use standard-derived vectors because the official reference rejects them",
            "Full baseline conformance remains a final project goal; mapping tables, point transform, subsampling, DNL and wider DRI are not yet implemented",
            "Restart/custom-threshold/push encoder cases use independent CharLS decoding; the wrapper cannot generate those exact combinations",
            "Synthetic vectors are not a complete conformance certification or a real clinical/production corpus",
            "Remote CI execution status is recorded separately in docs/SUBMISSION_STATUS.md",
        ],
        "interop": json.loads((LOGS / "interop.json").read_text(encoding="utf-8")) if (LOGS / "interop.json").exists() else None,
        "t87_maxval": json.loads((LOGS / "t87-maxval.json").read_text(encoding="utf-8")) if (LOGS / "t87-maxval.json").exists() else None,
        "file_cli": json.loads((LOGS / "file_cli.json").read_text(encoding="utf-8")) if (LOGS / "file_cli.json").exists() else None,
    }
    report["result"] = "FAIL" if any(check["status"] == "FAIL" for check in checks) else "PASS_WITH_LIMITATIONS"
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{report['result']}: evidence saved to docs/LOCAL_VALIDATION.json")
    if report["result"] == "FAIL":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
