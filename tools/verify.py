#!/usr/bin/env python3
"""Offline syntax and Linux client parity checks (no administrative execution)."""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    if not shutil.which("bash"):
        print("Missing tool: bash", file=sys.stderr)
        return 2
    commands = [[sys.executable, "tools/sync_linux_clients.py", "--check"]]
    commands += [["bash", "-n", str(p.relative_to(ROOT))] for p in sorted(ROOT.glob("*.sh"))]
    failures = []
    for command in commands:
        print("+ " + " ".join(command), flush=True)
        if subprocess.run(command, cwd=ROOT, check=False).returncode:
            failures.append(command)
    print(f"{len(commands) - len(failures)}/{len(commands)} checks passed.")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
