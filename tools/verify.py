#!/usr/bin/env python3
"""Offline checks: never runs administration scripts or scans a network."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workbench", action="store_true", help="also run offline JavaScript and discovery regressions (requires Node.js)")
    args = parser.parse_args()
    required = ["bash"] + (["node"] if args.workbench else [])
    missing = [name for name in required if not shutil.which(name)]
    if missing:
        parser.error("Missing tools: " + ", ".join(missing))
    commands = [[sys.executable, "tools/sync_linux_clients.py", "--check"]]
    commands += [["bash", "-n", str(path.relative_to(ROOT))] for path in sorted(ROOT.rglob("*.sh")) if ".git" not in path.parts]
    if args.workbench:
        commands += [["node", "--check", str(path.relative_to(ROOT))] for path in sorted((ROOT / "audit-workbench/js").glob("*.js"))]
        commands += [["node", "--check", "audit-workbench/sw.js"]]
        commands += [["node", str(path.relative_to(ROOT))] for path in sorted((ROOT / "audit-workbench/tests").glob("*.cjs"))]
        commands += [[sys.executable, "-m", "unittest", "discover", "-s", "audit-workbench/tests", "-p", name] for name in ("test_discovery.py", "test_discovery_wizard.py")]
    failures = []
    for command in commands:
        print("+ " + " ".join(command), flush=True)
        if subprocess.run(command, cwd=ROOT, check=False).returncode:
            failures.append(command)
    print(f"{len(commands) - len(failures)}/{len(commands)} checks passed.")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
