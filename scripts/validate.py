#!/usr/bin/env python3
"""Reproduce local checks and save evidence, without publishing or network writes."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone, timedelta
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "work" / "validation"


def run(name: str, command: list[str]) -> dict:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8",
                            errors="replace")
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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", action="store_true", help="Require a native runtime test")
    arguments = parser.parse_args()
    checks = []
    for name in ("interop.json", "file_cli.json"):
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
    report = {
        "recorded_at": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "scope": "Local validation only; no remote repository, contest submission or Mooncakes publication",
        "platform": platform.system(), "node": node.stdout.strip(),
        "toolchain": toolchain.stdout.strip(), "checks": checks,
        "source_scale": json.loads(scale.stdout),
        "limitations": [
            "Native execution is not validated on this Windows host without MSVC C++ compiler and SDK",
            "Interleaved two-component scans have local tests only; CharLS reference rejects them",
            "Sample interleave with non-default RESET has local tests only; external sample cases use RESET=64",
            "MAXVAL must equal 2^bits_per_sample - 1; other values fail explicitly",
            "Restart/custom-threshold/push encoder cases use independent CharLS decoding; the wrapper cannot generate those exact combinations",
            "Synthetic vectors are not a complete conformance certification or a real clinical/production corpus",
            "Remote CI configuration has not been executed on a hosting service",
        ],
        "interop": json.loads((LOGS / "interop.json").read_text(encoding="utf-8")) if (LOGS / "interop.json").exists() else None,
        "file_cli": json.loads((LOGS / "file_cli.json").read_text(encoding="utf-8")) if (LOGS / "file_cli.json").exists() else None,
    }
    report["result"] = "FAIL" if any(check["status"] == "FAIL" for check in checks) else "PASS_WITH_LIMITATIONS"
    target = ROOT / "docs" / "LOCAL_VALIDATION.json"
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{report['result']}: evidence saved to docs/LOCAL_VALIDATION.json")
    if report["result"] == "FAIL":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
