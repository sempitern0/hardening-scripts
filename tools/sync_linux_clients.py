#!/usr/bin/env python3
"""Keep the standalone RHEL client in sync with the canonical Linux client."""
import argparse
import difflib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "linux-ad-client-assistant.sh"
TARGET = ROOT / "rhel-ad-client-assistant.sh"
# Compatibility identities: preserve existing service, nftables and CLI names.
REPLACEMENTS = (
    ("linux-ad-client-assistant", "rhel-ad-client-assistant"),
    ("1.6.0-defense-parity-sanitization", "2.0.1-runtime-sanitization"),
    ("Linux AD Client Assistant", "RHEL AD Client Assistant"),
    ("ad_client_guard", "rhel_ad_guard"),
    ("RHEL AD Client Assistant guarded IPS", "RHEL AD Assistant guarded IPS"),
    ("RHEL AD Client Assistant security notification", "RHEL AD Assistant security notification"),
    ("Linux AD endpoint", "RHEL AD endpoint"),
    ("linux-ad-security-watch", "rhel-ad-security-watch"),
    ("Linux AD Client IDS", "RHEL AD Client IDS"),
)


def render(source):
    for old, new in REPLACEMENTS:
        source = source.replace(old, new)
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report drift without writing")
    args = parser.parse_args()
    expected = render(SOURCE.read_text(encoding="utf-8"))
    current = TARGET.read_text(encoding="utf-8")
    if current == expected:
        print("PASS: standalone Linux clients are in sync")
        return 0
    if args.check:
        print("".join(difflib.unified_diff(current.splitlines(True), expected.splitlines(True),
                                         fromfile=TARGET.name, tofile="generated version")), end="")
        print("Run python3 tools/sync_linux_clients.py after reviewing the canonical client.")
        return 1
    TARGET.write_text(expected, encoding="utf-8")
    print(f"Updated {TARGET.name}; review the diff before committing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
