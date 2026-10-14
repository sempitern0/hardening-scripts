# Maintenance and local validation

[English overview](../README.md) · [Resumen en español](../README_ES.md)

## Standalone Linux clients

Edit `linux-ad-client-assistant.sh` as the canonical client, then run:

```bash
python3 tools/sync_linux_clients.py
python3 tools/verify.py
```

Commit both scripts when behavior changes. The RHEL variant is generated with
explicit compatibility substitutions (product identity, version, installed CLI,
watcher units and nftables table). Both root files remain complete, independently
downloadable scripts: users need neither Python nor this repository to run them.
Do not replace the RHEL file with a wrapper that downloads or sources another file.

`python3 tools/sync_linux_clients.py --check` detects drift without writing.
If a platform genuinely needs different behavior, update the generator deliberately
and test both outputs. Do not add a fix only to the generated variant.

## Offline checks

```bash
python3 tools/verify.py              # Python 3 + Bash: syntax and client parity
python3 tools/verify.py --workbench  # Also Node.js: PWA units and mocked discovery
```

These commands do not execute administrative modes, install packages, scan the
network or modify system policy. They return nonzero if any check fails.
Browser/PDF integration tests under `audit-workbench/tests/` are separate and need
their browser dependencies. PowerShell parsing and AD lifecycle validation need
a suitable PowerShell/Windows environment; Bash syntax is not proof of runtime parity.

Before releasing infrastructure changes, exercise audit → change → validation →
recovery on disposable Linux and Windows lab hosts, including a reboot. Preserve
existing state paths and service identities when upgrading deployed assistants.

## Review: 2026-10-14

- Split the entry-point documentation from the full English/Spanish operations references.
- Added reproducible Linux/RHEL client parity checks while preserving standalone downloads.
- Fixed unsigned IPv4 subnet comparisons: valid 172.16/12 and 192.168/16 gateways
  could be incorrectly flagged as outside their network. Added /0, /32 and invalid-prefix cases.
- Replaced obsolete cache-version assertions with shared offline-resource checks;
  exercised explicit update activation and network-only connectivity probes.
- Validation: 56/56 offline commands passed, including 12 mocked discovery tests;
  the separate static-resource check also passed. No live network discovery,
  AD changes, Windows execution or browser/PDF integration tests were performed.
