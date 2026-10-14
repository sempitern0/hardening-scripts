# sysadmin

Tools for IT administrators and security auditors: **AD operations**, **offline audits**, and **network discovery from an auditor's device**.

**English** · [Español](README_ES.md)

## Choose your task

| Task | Start here |
|---|---|
| Record an audit, inventory, findings and PDF report | [Audit Workbench](audit-workbench/README.md) |
| Discover hosts from a device on the authorized network | [Discovery setup and import](audit-workbench/discovery/README_ES.md) |
| Administer a Samba AD domain on Debian/Ubuntu | `debian-ad-assistant.sh --audit` |
| Administer a Samba AD domain on Rocky/AlmaLinux | `rhel-ad-assistant.sh --audit` |
| Diagnose/manage Windows AD DS | `windows-ad-assistant.ps1 -Mode Audit` |
| Join, diagnose or recover a Linux AD client | `linux-ad-client-assistant.sh --audit` |
| Use the compatible RHEL-branded Linux client | `rhel-ad-client-assistant.sh --audit` |
| Join, diagnose or recover a Windows AD client | `windows-ad-client-assistant.ps1 -Mode Audit` |

## Start in minutes

```bash
git clone https://github.com/sempitern0/sysadmin.git
cd sysadmin
```

**Audit Workbench:** serve locally, then open <http://127.0.0.1:8765>.

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory audit-workbench
```

Create an audit → record inventory and evidence → review findings → generate PDF.
Use JSON export for a restorable audit copy; the PDF is the deliverable, not a backup.
For tablets and offline installation, follow [installation](audit-workbench/INSTALLATION.md).
Data belongs to the browser origin; changing host/port does not migrate it.

**AD assistants:** review the script, inspect help, then audit from an elevated console.

```bash
bash ./linux-ad-client-assistant.sh --help
sudo bash ./linux-ad-client-assistant.sh --audit
# For a Debian/Ubuntu domain controller instead:
sudo bash ./debian-ad-assistant.sh --audit
```

```powershell
Get-Help .\windows-ad-client-assistant.ps1 -Detailed
.\windows-ad-client-assistant.ps1 -Mode Audit
# For a Windows domain controller instead:
.\windows-ad-assistant.ps1 -Mode Audit
```

Use your organization's approved script execution/signing policy on Windows.
All six root scripts remain standalone downloads; no PWA installation is required.

**Discovery:** on the auditor's device, run the guided launcher:

```bash
bash audit-workbench/discovery/setup.sh --check
bash audit-workbench/discovery/run.sh
```

Windows: `audit-workbench\discovery\iniciar.cmd`. Requires Python 3.9+;
Nmap is optional. Review the network and explicitly authorize discovery, then import
the JSON into Hardware and Networks in the PWA. No remote agents or browser security
exceptions are required. Discovery does not enumerate vulnerabilities or installed software.

## Operating expectations

- Start with audit/diagnostics; apply infrastructure changes deliberately with a recovery path.
- Preserve restorable backups and console access before changing DNS, SSH, firewall or domain membership.
- RHEL Samba AD DC provisioning is guarded as an unsupported role; see the [platform notes](docs/OPERATIONS.md#control-plane-enterprise-linux).
- Platform implementations differ. Neither successful syntax checks nor a hardening run certify production readiness or benchmark compliance.

## Reference, recovery and maintenance

| Need | Guide |
|---|---|
| AD commands, DNS, GPO, IDS, backups and recovery | [Operations reference](docs/OPERATIONS.md) |
| Troubleshoot DNS, Kerberos or domain membership | [Troubleshooting](docs/OPERATIONS.md#troubleshooting) |
| Find state, snapshots and logs | [State paths](docs/OPERATIONS.md#rutas-de-estado-y-logs) |
| Workbench data/security model | [Security](audit-workbench/SECURITY.md) |
| Change code and run offline checks | [Maintenance](docs/MAINTENANCE.md) |

```bash
python3 tools/verify.py              # Bash syntax + standalone client parity
python3 tools/verify.py --workbench  # Also offline PWA tests; requires Node.js
```

[MIT license](LICENSE).
