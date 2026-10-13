# sysadmin · System Administration Toolkit

[![Status](https://img.shields.io/badge/status-active%20development-0A7EA4)](#estado-del-proyecto)
[![License](https://img.shields.io/badge/license-MIT-2E8540)](./LICENSE)
[![Linux](https://img.shields.io/badge/platform-Linux-455A64?logo=linux&logoColor=white)](#que-herramienta-usar)
[![Windows](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white)](#que-herramienta-usar)
[![Audit Workbench](https://img.shields.io/badge/PWA-Audit%20Workbench-5B5FC7)](./audit-workbench/)
[![Security](https://img.shields.io/badge/approach-audit--first%20%7C%20recovery--aware-25806D)](#principios-de-operacion)

**sysadmin** brings together tools for practical **system and infrastructure administration**: troubleshooting, auditing, inventory, identity and domain management, maintenance, remote operations, backup, recovery, and security.

**Hardening is one capability within the toolkit, not its sole purpose.** The Active Directory assistants help deploy and operate Windows/Linux environments; [Audit Workbench](./audit-workbench/README.md) documents audits in the browser, even offline. These independent tools share a conservative operational approach.

> **Current scope:** six console assistants at the repository root, focused mainly on Active Directory and its clients, plus an auditing PWA in `audit-workbench/`. This is not an automated remote inventory suite, vulnerability scanner, or centralized management platform. The catalog will grow as validated tools are added.

> **Before working on production:** review each script and its help output; run auditing or diagnostics first; define scope and permissions; retain restorable backups and an alternative administrative access path. Infrastructure-changing workflows require preparation and validation.

## Explore by task

| I need to… | Component |
|---|---|
| Document an audit, inventory assets, link evidence, and generate reports | **[Audit Workbench](./audit-workbench/README.md)** · Offline-first PWA |
| Operate, audit, and recover a Samba AD domain on Debian/Ubuntu | [Debian AD Assistant](./debian-ad-assistant.sh) |
| Manage a Samba AD DC on Rocky/AlmaLinux with support checks | [Enterprise Linux AD Assistant](./rhel-ad-assistant.sh) |
| Operate and diagnose AD DS on Windows Server | [Windows AD Assistant](./windows-ad-assistant.ps1) |
| Join, diagnose, or remove a Linux client from Active Directory | [Linux AD Client](./linux-ad-client-assistant.sh) or [RHEL AD Client](./rhel-ad-client-assistant.sh) |
| Reversibly manage Windows domain membership | [Windows AD Client](./windows-ad-client-assistant.ps1) |
| Review security settings and apply justified hardening measures | **Security/Hardening** workspaces in supported assistants |

### Components and documentation

- **[Audit Workbench](./audit-workbench/README.md):** operation, inventories, technical dictionary, evidence, and report delivery. Includes [installation and PWA](./audit-workbench/INSTALLATION.md), [security model](./audit-workbench/SECURITY.md), and [legal notes](./audit-workbench/LEGAL.md).
- **Root-level assistants:** self-contained scripts that can be downloaded individually, with their own options, dependencies, and logs. Audit Workbench is not required to use them.
- **Active Directory operations guide (below):** concrete procedures for provisioning, DNS, Kerberos, GPO, IDS, snapshots, hardening, and troubleshooting.

## Contents

- [Choosing a tool](#que-herramienta-usar)
- [Audit Workbench: auditing and evidence management](#audit-workbench)
- [Operating principles](#principios-de-operacion)
- [Quick start](#inicio-rapido)
- [Samba AD Control Plane (Debian / Ubuntu)](#control-plane-samba-ad)
- [Samba AD Control Plane (Rocky / AlmaLinux)](#control-plane-enterprise-linux)
- [Windows Server Control Plane](#control-plane-windows-server)
- [AD client assistants](#asistentes-de-clientes-ad)
- [DNS: a fundamental requirement](#dns-requisito-fundamental)
- [Remote operations](#operaciones-remotas)
- [GPO and SYSVOL: permissions and diagnostics](#gpo-y-sysvol-permisos-y-diagnostico)
- [Suricata IDS](#suricata-ids)
- [Backups, snapshots, and recovery](#backups-snapshots-y-recuperacion)
- [Hardening and compatibility](#hardening-y-compatibilidad)
- [Virtualization and multi-NIC hosts](#virtualizacion-y-hosts-multi-nic)
- [Troubleshooting](#troubleshooting)
- [State and log paths](#rutas-de-estado-y-logs)
- [Pre-production checklist](#checklist-antes-de-produccion)
- [Project status](#estado-del-proyecto)

---

<a id="que-herramienta-usar"></a>
## Choosing a tool

| Tool | Primary platform | Purpose |
|---|---|---|
| [`audit-workbench/`](./audit-workbench/README.md) | Desktop or tablet browser; PWA | Technical auditing, inventory, controls, evidence, remediation, reporting, and optional backups |
| [`debian-ad-assistant.sh`](./debian-ad-assistant.sh) | Debian 13 / Ubuntu Server 26.04 LTS | Samba AD DC: provisioning, operation, validation, backup, DNS/GPO, security |
| [`rhel-ad-assistant.sh`](./rhel-ad-assistant.sh) | Rocky / AlmaLinux 9–10 | Samba AD DC subject to AD-DC capability and operating system support |
| [`windows-ad-assistant.ps1`](./windows-ad-assistant.ps1) | Windows Server 2019 / 2022 / 2025 | AD DS, directory administration, diagnostics, recovery, and hardening |
| [`linux-ad-client-assistant.sh`](./linux-ad-client-assistant.sh) | Linux with APT or DNF/YUM and systemd | Reversible Linux AD client joins, diagnostics, and snapshots |
| [`rhel-ad-client-assistant.sh`](./rhel-ad-client-assistant.sh) | Linux with APT or DNF/YUM and systemd | Linux AD client variant with join, recovery, and security workflows |
| [`windows-ad-client-assistant.ps1`](./windows-ad-client-assistant.ps1) | Windows / PowerShell 5.1+ | AD membership lifecycle, preflight, diagnostics, and restoration |

**Quick guidance:**

- **Audit and document without administering a DC:** start with Audit Workbench. It does not require a domain.
- **Administer a domain controller:** use the assistant for the DC's operating system and run its audit mode before changing anything.
- **Manage domain clients:** use a client assistant, not the DC provisioning assistant.
- **Harden a system:** first assess the impact on identity, DNS, applications, and continuity; hardening is an available operation, not an automatic outcome of an audit.

> **RHEL support note:** Red Hat does not support running Samba as an AD Domain Controller on RHEL. `rhel-ad-assistant.sh` blocks provisioning unless the operator explicitly accepts this unsupported use with `--allow-unsupported-rhel-dc`. Do not assume equivalence with Rocky/AlmaLinux or deploy without assessing support.

---

<a id="audit-workbench"></a>
## Audit Workbench · auditing and evidence management

**[Read Audit Workbench documentation](./audit-workbench/README.md)** · [Installation](./audit-workbench/INSTALLATION.md) · [Security](./audit-workbench/SECURITY.md)

The `audit-workbench/` PWA complements the console assistants; **it does not execute them from the browser or automatically scan the network**.

- Audit-record library with local persistence and JSON import/export.
- Hardware, software, and network inventories; assisted CSV/JSON capture and read-only local collectors.
- Controls, findings, linked evidence, a contextual technical dictionary, and follow-up.
- Pre-report validation, draft/final delivery, exports, and PDF generation through browser printing.
- Local backups and explicitly activated remote-distribution options (subject to security and server requirements).

**Optional local execution** from the repository root:

```bash
cd audit-workbench
python3 -m http.server 8765 --bind 127.0.0.1
```

Open `http://127.0.0.1:8765`. For tablets, initial PWA installation, origin policies, and HTTPS, see [INSTALLATION.md](./audit-workbench/INSTALLATION.md). Audit records stored under one browser origin are not synchronized merely by publishing the application.

---

<a id="principios-de-operacion"></a>
## Operating principles

The usual workflow is:

```text
DETECT
  ↓
AUDIT / PREFLIGHT
  ↓
PLAN
  ↓
BACKUP / SNAPSHOT
  ↓
CONFIRM
  ↓
APPLY
  ↓
VALIDATE
  ↓
REBOOT / RE-AUDIT
```

Shared principles:

- detect before modifying;
- never silently reprovision existing infrastructure;
- preserve a recovery path;
- keep auditing and remediation separate;
- require explicit confirmation for high-impact operations;
- use native system tools whenever practical;
- never store administrative passwords;
- retain logs and operational evidence;
- verify DNS, Kerberos, and connectivity before interpreting a failure as a credentials issue;
- avoid aggressive rollback when the state of a domain operation is ambiguous;
- do not claim full CIS compliance based on validating only a subset of controls.

### What the project does not attempt

It does not attempt to replace Active Directory design or turn a DC into a one-click installer. Decisions such as DNS topology, trusts, delegation, Kerberos policies, LDAP channel binding, network segmentation, and backup strategy still require administrative judgment.

---

<a id="inicio-rapido"></a>
## Quick start

### 1. Clone and review

```bash
git clone https://github.com/sempitern0/sysadmin.git
cd sysadmin
```

Before running a script with elevated privileges, review it and check the mode you intend to use.

### 2. Choose a workflow

To **document an audit**, use Audit Workbench and follow its [guide](./audit-workbench/README.md). To **audit or operate AD**, start with the relevant assistant's read-only mode.

### 3. Start with an audit

Samba AD / Linux:

```bash
sudo bash ./debian-ad-assistant.sh --audit
```

Windows Server:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-ad-assistant.ps1 -Mode Audit
```

Linux client:

```bash
sudo bash ./linux-ad-client-assistant.sh --audit
```

Windows client:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-ad-client-assistant.ps1 -Mode Audit
```

> Running an audit before provisioning or hardening helps reveal incorrect DNS, existing roles, unexpected interfaces, pending states, and other conflicts before changing the host.

---

<a id="control-plane-samba-ad"></a>
## Samba AD Control Plane

`debian-ad-assistant.sh` manages a Samba Active Directory Domain Controller on Debian / Ubuntu Server.

### Primary targets

- Debian 13;
- Ubuntu Server 26.04 LTS;
- Bash;
- systemd;
- Samba AD DC;
- IPv4 as the primary administration/AD path.

Other Debian derivatives may work on a best-effort basis, but they are not considered equivalent targets until tested.

### Common operations

```bash
sudo bash ./debian-ad-assistant.sh --audit
sudo bash ./debian-ad-assistant.sh --validate
sudo bash ./debian-ad-assistant.sh --bootstrap
sudo bash ./debian-ad-assistant.sh --manage
sudo bash ./debian-ad-assistant.sh --status
sudo bash ./debian-ad-assistant.sh --backup
```

Always consult the installed version's help for the full set of modes:

```bash
sudo bash ./debian-ad-assistant.sh --help
```

#### Bootstrapping a new DC

```bash
sudo bash ./debian-ad-assistant.sh --bootstrap
```

Before starting:

- define the permanent hostname;
- use a stable address for the DC;
- choose the DNS domain and realm;
- verify time and connectivity;
- retain console/hypervisor access if you intend to change networking or firewall rules;
- do not reuse a server with an unknown Samba installation as if it were empty.

The assistant detects an existing AD database and avoids reprovisioning it as a new domain.

#### Daily administration

```bash
sudo bash ./debian-ad-assistant.sh --manage
```

The control plane groups functions by workspace:

```text
[O] Daily operations       [D] Directory
[P] Policy / GPO           [S] Security
[R] Remote operations      [I] Insights / IDS
[M] Maintenance            [A] All modules
```

Main areas:

- users and groups;
- computers and permissions;
- Group Policy;
- DNS y Kerberos;
- DC validation;
- hardening;
- dependencies;
- backups;
- migration;
- Suricata IDS;
- remote operations;
- controlled decommission/reset.

#### Installable CLI

The assistant can install administrative command shortcuts:

```bash
sudo bash ./debian-ad-assistant.sh --install-cli
```

Commands such as the following may then be available:

```text
adctl
ad-ops
ad-users
ad-groups
ad-computers
ad-permissions
ad-gpo
ad-security
ad-samba
ad-kerberos
ad-migrate
ad-reset
ad-deps
ad-ids
ad-remote
ad-audit
ad-validate
ad-status
ad-backup
```

After replacing the main script with a new version, refresh the shortcuts to avoid running an older installed copy.

#### After a reboot

A DC must not be considered validated simply because provisioning has completed. After rebooting, check at least:

```bash
sudo bash ./debian-ad-assistant.sh --validate
```

And inspect:

```bash
systemctl status samba-ad-dc --no-pager
chronyc tracking
samba-tool dbcheck --cross-ncs
```

---

<a id="control-plane-enterprise-linux"></a>
## Samba AD Control Plane · Rocky / AlmaLinux

`rhel-ad-assistant.sh` provides a Samba AD DC assistant for **Rocky Linux 9/10 and AlmaLinux 9/10**, provided the installed Samba build actually supports domain controller capabilities.

```bash
sudo bash ./rhel-ad-assistant.sh --audit
sudo bash ./rhel-ad-assistant.sh --validate
sudo bash ./rhel-ad-assistant.sh --status
sudo bash ./rhel-ad-assistant.sh --manage
```

For a **new** domain, and only after checking support and prerequisites:

```bash
sudo bash ./rhel-ad-assistant.sh --bootstrap
```

It also provides DNS, GPO/SYSVOL, security, Kerberos, IDS, backup, and remote operations workspaces. See `--help` for current modes; do not confuse AD validation with official product support.

**Critical limitation:** Red Hat does not support the Samba AD DC role on RHEL. The assistant requires `--allow-unsupported-rhel-dc` and express confirmation for this exceptional unsupported scenario; this guide does not recommend it as a standard installation. Do not disable SELinux or bypass capability checks to force the operation.

---

<a id="control-plane-windows-server"></a>
## Windows Server Control Plane

`windows-ad-assistant.ps1` manages Windows Server and Active Directory Domain Services using native Microsoft tooling.

### Targets principales

- Windows Server 2019;
- Windows Server 2022;
- Windows Server 2025;
- Windows PowerShell 5.1+.

### Main modes

```powershell
.\windows-ad-assistant.ps1 -Mode Audit
.\windows-ad-assistant.ps1 -Mode Validate
.\windows-ad-assistant.ps1 -Mode Harden
.\windows-ad-assistant.ps1 -Mode Backup
.\windows-ad-assistant.ps1 -Mode ADAdmin
.\windows-ad-assistant.ps1 -Mode Provision
.\windows-ad-assistant.ps1 -Mode Migration
.\windows-ad-assistant.ps1 -Mode DirectorySecurity
.\windows-ad-assistant.ps1 -Mode Dependencies
.\windows-ad-assistant.ps1 -Mode IDS
.\windows-ad-assistant.ps1 -Mode RemoteOps
```

Without `-Mode`, the interactive control plane opens.

#### Workspaces

```text
[O] Daily operations       [D] Directory
[P] Policy / DNS           [S] Security
[R] Remote operations      [I] Insights / IDS
[M] Maintenance            [A] All modules
```

Relevant capabilities:

- provisioning a new forest;
- host inventory and auditing;
- users, groups, computers, and OUs;
- GPO and integrated DNS;
- DCDiag, replication, SYSVOL, and FSMO;
- hardening Windows and directory protocols;
- configuration and system-state backups;
- Windows dependencies and features;
- domain migration;
- Suricata/EVE;
- WinRM/SSH remote operations;
- controlled demotion/decommission.

#### Provisioning

```powershell
.\windows-ad-assistant.ps1 -Mode Provision
```

It uses supported AD DS tools and performs prerequisite checks before promotion.

Before establishing the first DC in a forest, prepare:

- permanent hostname;
- static IPv4 address;
- DNS domain and NetBIOS name;
- local administrative access;
- correct time;
- an alternative access path when working remotely.

#### Domain Controller backup

A configuration export is not a substitute for an AD DS recovery backup. On Windows Server, use **System State Backup** and an external backup policy suited to your environment for actual DC recovery.

---

<a id="asistentes-de-clientes-ad"></a>
## AD client assistants

Client assistants are designed to make domain joins **observable and recoverable**, particularly around DNS and reboots.

### Linux AD Client Assistant

File:

```text
linux-ad-client-assistant.sh
```

Primary targets:

- Debian / Ubuntu and APT derivatives;
- RHEL / Fedora / Rocky / Alma and DNF/YUM derivatives;
- systemd;
- realmd + SSSD + adcli.

Usage:

```bash
sudo bash ./linux-ad-client-assistant.sh --audit
sudo bash ./linux-ad-client-assistant.sh --join
sudo bash ./linux-ad-client-assistant.sh --status
sudo bash ./linux-ad-client-assistant.sh --leave
sudo bash ./linux-ad-client-assistant.sh --restore
sudo bash ./linux-ad-client-assistant.sh --snapshots
```

Without arguments, the interactive control plane opens.

The join workflow includes:

- route-aware interface selection;
- snapshot of resolver, hostname, and identity;
- controlled installation of dependencies when needed;
- direct AD DNS verification;
- verification of external DNS forwarding;
- Active Directory discovery;
- Kerberos authentication using a private credential cache;
- realmd/SSSD join;
- post-join validation;
- local rollback while domain membership has not yet been committed;
- recovery of interrupted attempts.

### RHEL AD Client Assistant

`rhel-ad-client-assistant.sh` is another **Linux Active Directory client** assistant variant (not a DC). Its code supports APT and DNF/YUM families, with systemd as the basis for automated lifecycle management.

```bash
sudo bash ./rhel-ad-client-assistant.sh --audit
sudo bash ./rhel-ad-client-assistant.sh --connectivity
sudo bash ./rhel-ad-client-assistant.sh --diagnostics
sudo bash ./rhel-ad-client-assistant.sh --status
```

Membership changes use `--join`, `--leave`, `--switch`, `--restore`, and `--snapshots`. These workflows require permissions and DNS/Kerberos validation; run `--help` in the version you intend to use. `linux-ad-client-assistant.sh` and this variant **do not need to be deployed together**: choose one after checking their differences and compatibility.

### Windows AD Client Assistant

Archivo:

```text
windows-ad-client-assistant.ps1
```

Run from Windows PowerShell 5.1+ as Administrator.

#### Modes

```powershell
.\windows-ad-client-assistant.ps1 -Mode Audit
.\windows-ad-client-assistant.ps1 -Mode Join
.\windows-ad-client-assistant.ps1 -Mode Status
.\windows-ad-client-assistant.ps1 -Mode Leave
.\windows-ad-client-assistant.ps1 -Mode Restore
.\windows-ad-client-assistant.ps1 -Mode Snapshots
.\windows-ad-client-assistant.ps1 -Mode Recover
```

Without `-Mode`, the interactive menu opens.

#### Join workflow

```text
direct DNS preflight
        ↓
NIC / route selection
        ↓
snapshot pre-join
        ↓
configure AD DNS
        ↓
discovery + ports + time
        ↓
Add-Computer
        ↓
reboot
        ↓
secure channel + nltest + DNS
```

The snapshot preserves the information required to restore the pre-join DNS/hostname state.

#### Lifecycle states

The assistant maintains a persistent phase to distinguish safe operations from states requiring caution. Some states you may encounter are:

```text
SNAPSHOT_CREATED
DNS_APPLIED
JOIN_SUBMITTED
JOIN_AMBIGUOUS
JOIN_PENDING_REBOOT
JOINED
JOINED_DEGRADED
LEAVE_PENDING_REBOOT
RESTORE_READY
RESTORE_PENDING_REBOOT
```

You do not need to memorize every state. The important rule is:

> If the assistant reports `JOIN_SUBMITTED`, `JOIN_AMBIGUOUS`, or `JOIN_PENDING_REBOOT`, **do not manually restore DNS** until you have verified whether Windows accepted the membership.

Use:

```powershell
.\windows-ad-client-assistant.ps1 -Mode Recover
```

Recovery combines the persistent state, membership reported by Windows, and evidence in `NetSetup.log`. When it cannot establish whether the join was committed, automatic rollback is avoided.

#### Snapshots

```powershell
.\windows-ad-client-assistant.ps1 -Mode Snapshots
```

Lists retained snapshots with the target domain, computer, interface, and associated state.

Snapshots are retained as evidence even after the active lifecycle has completed.

#### Strict DNS forwarding

Before replacing the client's resolver, the assistant checks every configured AD DNS server:

1. it must return the domain's SRV records;
2. it must resolve a name outside the AD zone.

By default, it uses:

```text
www.microsoft.com
```

You can select another probe:

```powershell
.\windows-ad-client-assistant.ps1 `
  -Mode Join `
  -ExternalDnsProbe 'www.example.net'
```

For deliberately isolated networks, an explicit override is available:

```powershell
.\windows-ad-client-assistant.ps1 `
  -Mode Join `
  -AllowAdDnsWithoutExternalResolution
```

Do not use the override to conceal a broken forwarder on a network that requires external resolution.

#### Leaving and restoration

On Windows, `Remove-Computer` requires a reboot to complete domain removal. Therefore, the correct workflow is:

```text
Leave
  ↓
AD DNS is retained temporarily
  ↓
reboot
  ↓
Restore / Recover
  ↓
pre-join DNS + hostname
```

Do not restore DNS before rebooting after leaving the domain.

---

<a id="dns-requisito-fundamental"></a>
## DNS: a fundamental requirement

Active Directory relies on its DNS SRV records.

The recommended pattern is:

```text
AD clients
    │
    ├─ DNS → DC01
    └─ DNS → DC02
               │
               ├─ AD zones
               └─ forwarders → external/corporate resolution
```

### Do not mix public DNS servers into AD client settings

Avoid configuring the following as alternate DNS servers on AD clients:

```text
8.8.8.8
1.1.1.1
9.9.9.9
home router
hypervisor NAT DNS
```

The client may select that resolver and lose Active Directory discovery.

External resolvers belong in **domain DNS forwarding**, not in the DNS server list of a domain member.

### Linux tests

```bash
dig _ldap._tcp.dc._msdcs.corp.example.com SRV

dig @10.0.10.10 \
  _ldap._tcp.dc._msdcs.corp.example.com SRV

getent hosts dc01.corp.example.com
```

### Windows tests

```powershell
Resolve-DnsName `
  -Name _ldap._tcp.dc._msdcs.corp.example.com `
  -Type SRV

Resolve-DnsName `
  -Name _ldap._tcp.dc._msdcs.corp.example.com `
  -Type SRV `
  -Server 10.0.10.10

nltest /dsgetdc:corp.example.com
```

If a query directly to an AD DNS server succeeds but the system resolver fails, the issue lies in the client's local DNS path, not necessarily in Active Directory.

---

<a id="operaciones-remotas"></a>
## Remote operations

Both DC control planes include a remote operations center for endpoints registered in Active Directory.

### From Windows Server

Recommended path:

```text
Windows → Windows : WinRM / PowerShell Remoting / Kerberos
Windows → Linux   : OpenSSH
```

Windows can retain alternative credentials in memory during the session when the operator chooses to do so.

### From Samba AD / Linux

Camino recomendado:

```text
Linux → Linux     : OpenSSH
Linux → Windows   : OpenSSH
                    Samba RPC as a limited power-control fallback
```

### Guardrails

Remote consoles are intended for specific administrative tasks:

- readiness;
- active sessions;
- user messages;
- controlled logoff;
- diagnostics;
- limited service management;
- restart / shutdown;
- evidence export.

An arbitrary shell is not exposed as a standard menu option.

For delegated operations, use:

```text
Windows → JEA / role capabilities
Linux   → restricted sudoers
Network → WinRM/SSH only from management networks
```

---

<a id="gpo-y-sysvol-permisos-y-diagnostico"></a>
## GPO and SYSVOL: permissions and diagnostics

Creating a GPO on a Samba AD DC combines **local privileges** and **domain authorization**. These are separate layers:

```text
operator shell
      │
      ├─ sudo/root ────────────────> local files, runtime, backups, tools
      │
      └─ administrator's Kerberos ticket
              │
              ├─ LDAP ────────────> CN=Policies,CN=System,...
              │
              └─ CIFS/SMB ────────> \\DC\SYSVOL\dominio\Policies\{GUID}
```

The assistant elevates itself through `sudo` when launched as a regular user. Therefore, running:

```bash
./debian-ad-assistant.sh --gpo
```

is valid; you do not need to prepend `sudo` manually as long as it is available and the local user may use it. The control plane displays and retains the original invoking user, but local operations run as root.

**Root does not replace Active Directory administrator privileges.** `samba-tool gpo create` uses the operator's Kerberos credentials to access both LDAP and SYSVOL. A root process can still be denied by LDAP or SMB.

### GPO mutation preflight

Before a GPO change, the assistant automatically runs a preflight and reuses its result for a few minutes within the same execution. It can also be run manually from:

```text
Group Policy Control
  -> [11] GPO mutation preflight
```

The preflight:

1. confirms the effective process is running as root;
2. destroys the previous private credential cache and obtains a **fresh Kerberos TGT** for the selected administrator;
3. verifies the exact principal identity;
4. checks administrative group membership recorded in the directory;
5. requests tickets for `ldap/<DC_FQDN>` and `cifs/<DC_FQDN>` when `kvno` is available;
6. verifies GPO read access through LDAP;
7. runs `samba-tool ntacl sysvolcheck`;
8. accesses SYSVOL with `smbclient` using **the same credential cache**;
9. creates and removes a temporary `.DAD-GPO-PROBE-*` directory under `SYSVOL/<domain>/Policies` to verify actual SMB write access;
10. runs `gpo aclcheck` to diagnose consistency across existing GPOs;
11. captures the DS ACL for `CN=Policies,CN=System,<baseDN>` and the NT ACL for the `Policies` directory.

The write test runs only within a GPO change/diagnostic path and immediately removes the temporary directory. If cleanup fails, the assistant displays the exact path for manual review.

Evidence is stored under:

```text
/var/lib/debian-ad-assistant/runs/<run>/gpo-diagnostics/
```

Relevant files may include:

```text
execution-context.txt
kvno-ldap.txt
kvno-cifs.txt
gpo-listall.txt
sysvolcheck.txt
sysvol-smb-read.txt
sysvol-smb-write.txt
gpo-aclcheck.txt
policies-container-dsacl.txt
policies-filesystem-acl.txt
gpo-create-<name>.txt
```

### Why valid group membership can still fail

Ver:

```text
Domain Admins       : member
GPO Creator Owners  : member
```

confirms **directory state**, but does not prove that an existing Kerberos TGT contains those authorizations. If a user was recently added to a privileged group, an older ticket may still represent the previous token.

The preflight therefore forces a new `kinit` before the first GPO change in the run. This avoids misdiagnosing an old PAC/ticket as a broken ACL.

Historically, Samba has also had differences and issues surrounding delegation through `Group Policy Creator Owners`. For critical administrative operations, `Domain Admins` membership with a fresh ticket is stronger diagnostic evidence; do not modify SYSVOL ACLs merely to compensate for delegation that has not yet been properly isolated.

### Interpreting a `samba-tool gpo create` failure

The assistant preserves the full output and provides an initial classification:

| Evidence | Likely boundary | First step |
|---|---|---|
| `LDAP_INSUFFICIENT_ACCESS_RIGHTS`, `LDAP error 50` | ACL/authorization in `CN=Policies,CN=System` or an old Kerberos token | refresh the ticket and inspect `policies-container-dsacl.txt` |
| `NT_STATUS_ACCESS_DENIED` | SYSVOL SMB/NT ACL authorization | inspect `sysvol-smb-write.txt` and the `Policies` ACL |
| `KDC_ERR*`, SPNEGO/GSSAPI, `LOGON_FAILURE` | Kerberos, DNS, SPN, or time | inspect `kvno-ldap.txt`, `kvno-cifs.txt`, DNS, and clock |
| error creating temporary directory | local `/tmp`, free space, or Unix privilege issue | inspect root, permissions, and storage |
| `gpo aclcheck` fails but `sysvolcheck` and the write probe succeed | inconsistency in an existing GPO | inspect `gpo-aclcheck.txt`; do not assume all of SYSVOL is broken |

### `sysvolcheck`, `gpo aclcheck`, and `sysvolreset` are not equivalent

`ntacl sysvolcheck` checks whether SYSVOL ACLs match Samba's expectations. `gpo aclcheck` compares GPO ACL properties between LDAP and SYSVOL. A failure in either check does not automatically identify the correct repair.

Do not run `samba-tool ntacl sysvolreset` merely because GPO creation or `gpo aclcheck` fails. This is a broad SYSVOL ACL operation and should be treated as a **last resort**, after:

- backing up the domain;
- determining whether access is denied by LDAP or SMB;
- verifying the active Kerberos ticket;
- inspecting the specific affected ACLs;
- confirming the Samba version and expected inheritance behavior.

The assistant keeps `sysvolreset` in the advanced workflow and never runs it automatically after a GPO failure.

### Recommended workflow for a GPO that cannot be created

```text
[11] GPO mutation preflight
          │
          ├─ LDAP ticket FAIL ──> DNS / time / SPN / Kerberos
          │
          ├─ CIFS ticket FAIL ──> SPN CIFS / DNS / Kerberos
          │
          ├─ SYSVOL read FAIL ──> SMB authentication / share
          │
          ├─ SYSVOL create FAIL -> NT ACL / effective authorization
          │
          ├─ sysvolcheck FAIL ──> investigate local ACL/NT ACL before repair
          │
          └─ todo PASS
                 │
                 └─ retry Create GPO
                        │
                        └─ if it fails: inspect gpo-create-*.txt
                           to distinguish LDAP add from SMB/set_acl
```

For a delegated administrator recently added to privileged groups, signing out of and back into a desktop session **is not the relevant mechanism for this assistant**: it uses a private credential cache for each run, and the preflight explicitly requests a fresh ticket.

---

<a id="suricata-ids"></a>
## Suricata IDS

Los control planes de DC incluyen integración opcional con Suricata para visibilidad de red y protocolos relacionados con Active Directory. En Linux el sensor se configura en modo **pasivo**: observa tráfico, genera telemetría y alertas, pero no bloquea paquetes.

### Modelo mental: actividad no es lo mismo que alerta

Esta distinción evita una de las confusiones más frecuentes al empezar con un IDS:

```text
ACTIVIDAD
Suricata ha visto tráfico o un protocolo.
Ejemplos: ping, DNS, Kerberos, LDAP, SMB, una conexión TCP.

ALERTA
Una regla/signature ha coincidido con ese tráfico.
Ejemplos: acceso a una superficie AD desde fuera de HOME_NET,
ráfaga anómala de SMB, una firma ET/Open o una anomalía de protocolo.
```

Por tanto:

> Un `ping` normal **no debería generar necesariamente una alerta**. En las versiones recientes del asistente se habilita telemetría EVE `flow`, por lo que el ICMP puede aparecer en **Connection activity** aunque `Recent alerts` siga vacío.

Los registros `flow` suelen emitirse cuando el flujo termina o expira. Un ping enviado hace unos segundos puede tardar algo en aparecer en la vista de actividad.

### Linux / Samba AD

Acceso habitual:

```bash
sudo bash ./debian-ad-assistant.sh --ids
```

El workspace diferencia la vista diaria del administrador de la evidencia técnica:

```text
[1]  IDS readiness assessment
[2]  Install / repair Suricata
[3]  Configure passive IDS
[4]  Sensor health
[5]  Operator overview
[6]  Recent alerts explained
[7]  AD protocol intelligence
[8]  Rule management
[9]  Daily local reports
[10] Export evidence
[11] Disable IDS integration
[12] Trusted network scope
[13] Connection activity
```

#### Qué mirar primero

Para operación diaria, una secuencia útil es:

```text
Sensor health
     ↓
Operator overview
     ↓
Connection activity
     ↓
Recent alerts explained
     ↓
AD protocol intelligence si necesitas detalle
```

`Operator overview` intenta responder preguntas operativas, no mostrar JSON:

- ¿está llegando telemetría reciente?;
- ¿hay pérdida de paquetes del sensor?;
- ¿quién está hablando con este DC?;
- ¿qué servicios reciben tráfico?;
- ¿hay ICMP/ping?;
- ¿hay alertas y qué significan en términos prácticos?;
- ¿el origen está dentro o fuera del `HOME_NET` confiable?

`Connection activity` está orientado específicamente a **quién se conecta**. Agrupa fuentes, servicios y actividad reciente. Una línea de esa vista significa que Suricata vio tráfico; no implica por sí sola actividad maliciosa.

#### Trusted network scope / HOME_NET

`HOME_NET` puede contener varias redes legítimas, por ejemplo:

```text
192.168.10.0/24,10.20.0.0/16,10.8.0.0/24
```

Incluye aquí las LAN, VLAN de administración, VPN y redes site-to-site cuyos clientes deban acceder legítimamente al DC. Las reglas locales de exposición utilizan `!$HOME_NET`; una red legítima olvidada en este scope puede producir alertas que parecen externas.

No añadas una red al scope únicamente para silenciar una alerta: primero confirma que realmente sea una red administrada y confiable.

### Pruebas seguras para aprender qué ve el sensor

Haz estas pruebas únicamente en infraestructura propia o expresamente autorizada.

#### 1. ICMP / ping

Desde otro equipo:

```bash
ping <IP_DEL_DC>
```

Esperado:

```text
Connection activity  → ICMP / ping
Recent alerts        → normalmente ninguna alerta nueva
```

Esto prueba visibilidad básica, **no la capacidad de disparar firmas**.

#### 2. DNS

Linux:

```bash
dig @<IP_DEL_DC> example.org
```

Windows:

```powershell
Resolve-DnsName example.org -Server <IP_DEL_DC>
```

Esperado: actividad DNS, IP origen y nombres consultados en las vistas de actividad/inteligencia.

#### 3. Kerberos + SMB desde un miembro del dominio

Windows:

```powershell
klist purge
dir \\<DC_FQDN>\SYSVOL
```

En un cliente correctamente unido al dominio esto suele generar actividad Kerberos y SMB. `klist purge` elimina tickets del cache del usuario para forzar una nueva negociación; úsalo solo si entiendes el efecto sobre esa sesión.

#### 4. Probar una regla local de exposición

Desde una máquina de laboratorio cuya IP esté **fuera de `HOME_NET`**, realiza únicamente una conexión al servicio del DC que quieras comprobar.

Linux:

```bash
nc -vz <IP_DEL_DC> 445
```

Windows:

```powershell
Test-NetConnection <IP_DEL_DC> -Port 445
```

Si la ruta llega al sensor y el origen está realmente fuera del scope confiable, la regla local de SMB/RPC debería poder producir una alerta similar a:

```text
DAD IDS External access to AD SMB-RPC TCP surface
```

No utilices scanners ni tráfico agresivo contra sistemas de terceros para "probar Suricata".

### Cómo interpretar alertas comunes

| Señal | Interpretación inicial | Qué comprobar |
|---|---|---|
| `DAD IDS External access ...` | Un origen fuera de `HOME_NET` alcanzó una superficie del DC | IP origen, red/VPN esperada, puerto y si falta una CIDR legítima |
| `DAD IDS High-rate SMB ...` | Muchas conexiones SMB en poco tiempo | scanner autorizado, inventario, cliente roto o reconocimiento |
| `applayer` / `app-layer` | Suricata no pudo interpretar limpiamente una conversación de aplicación | origen/destino, protocolo real, recurrencia y firma exacta |
| `ET SCAN` / firma de scanning | Tráfico parecido a discovery/reconocimiento | si el origen es un scanner autorizado y qué puertos tocó |
| `ET POLICY` | Tráfico relevante para una política, no necesariamente malware | contexto y necesidad operativa |
| malware / trojan / C2 | Patrón asociado a compromiso o command-and-control | endpoint origen, DNS/TLS, proceso y evidencia adicional |

Una alerta es una **señal de investigación**, no una sentencia. Correlaciona siempre firma, IP origen, destino, servicio, hora, Event Center y logs del endpoint.

### ¿Qué significa una alerta `applayer`?

Una alerta o anomalía `applayer` puede aparecer porque Suricata esperaba un protocolo y recibió datos incompletos, inesperados, cifrados, malformados o que su parser no pudo clasificar. Puede ser ruido, software extraño, una versión de protocolo poco común o tráfico hostil.

Antes de escalarla como incidente:

1. identifica `src_ip`, `dest_ip`, puerto y protocolo;
2. comprueba si el host origen es conocido;
3. mira si la alerta se repite;
4. revisa la actividad de la misma IP alrededor de esa hora;
5. comprueba Event Center y logs del servicio/endpoint;
6. escala si hay otras señales coherentes con scanning, explotación o compromiso.

### Rule management: feeds mantenidos antes que reglas manuales

El flujo recomendado no consiste en copiar firmas una a una. `suricata-update` es el gestor oficial de reglas de Suricata y genera el ruleset consolidado en:

```text
/var/lib/suricata/rules/suricata.rules
```

Ese fichero es un **artefacto generado**. No debe editarse directamente. La arquitectura del asistente es:

```text
                 SURICATA DETECTION PIPELINE

  feeds mantenidos              contexto local
  por suricata-update            del entorno
         │                            │
         ├─ ET/Open                   ├─ AD/DC context.rules
         ├─ OISF TrafficID            └─ custom.rules (opcional)
         ├─ abuse.ch feeds                  │
         └─ fuentes opcionales              │
                 │                          │
                 └──────────┬───────────────┘
                            ↓
                      suricata -T
                            ↓
                     safe rule reload
```

La consola ofrece ahora:

```text
Suricata IDS
  -> [8] Rule management

SURICATA RULE MANAGEMENT
 [1] Professional baseline
 [2] Rule status
 [3] Update now
 [4] Recommended sources
 [5] Browse source catalog
 [6] Enable indexed source
 [7] Disable source
 [8] Add HTTPS source
 [9] Local custom rules
 [10] Automatic updates
```

#### Professional baseline

Durante `Configure passive IDS`, el asistente propone este perfil con respuesta predeterminada **Y**. La activación sigue siendo explícita: el operador puede rechazarla y quedarse con ET/Open + las reglas contextuales del DC, y aplicarla más adelante desde `Rule management -> Professional baseline`.

El perfil recomendado para un sensor pasivo profesional instala/activa estas capas:

| Capa | Fuente | Función |
|---|---|---|
| General | ET/Open | amenazas, exploits, malware, scans y policy signatures mantenidas por ET |
| Visibilidad | `oisf/trafficid` | identificación de aplicaciones/tráfico mediante reglas `noalert` |
| Threat intelligence | `abuse.ch/feodotracker` | infraestructura C2 de botnets |
| Threat intelligence | `abuse.ch/urlhaus` | URLs usadas para distribución de malware |
| Threat intelligence | `abuse.ch/sslbl-blacklist` | certificados TLS asociados a infraestructura maliciosa |
| Contexto | Debian AD Assistant | exposición de Kerberos/LDAP/SMB/RPC/DNS/NTP del DC y ráfagas SMB |

ET/Open es el feed general por defecto de `suricata-update`. Si el administrador instala una fuente comercial que lo sustituya, el asistente no intenta mezclarla de forma ciega con ET/Open.

El baseline **no**:

- convierte `alert` en `drop`;
- habilita IPS/NFQUEUE;
- activa feeds de hunting de alto coste por defecto;
- añade fuentes comerciales sin licencia/token;
- edita directamente `suricata.rules`;
- deshabilita categorías del vendor silenciosamente.

El objetivo es disponer de una base útil y mantenida sin transformar el DC en un experimento de miles de firmas arbitrarias.

#### Fuentes adicionales propuestas

`Recommended sources` permite añadir de forma explícita fuentes del catálogo OISF. Además de las incluidas en el baseline, el asistente propone actualmente:

```text
stamus/lateral
    detecciones orientadas a movimiento lateral en entornos Windows/AD

ptrules/open
    conjunto adicional de detecciones abiertas de Positive Technologies
```

Son **opcionales**. Más reglas no equivalen automáticamente a más seguridad: pueden aumentar CPU, memoria, volumen de EVE y falsos positivos. Activa una fuente adicional porque responde a una necesidad concreta y revisa después el comportamiento del sensor.

El catálogo en vivo se obtiene con:

```bash
suricata-update update-sources
suricata-update list-sources
```

Desde el menú puedes refrescarlo y habilitar cualquier identificador `vendor/name`. La fuente solo se conserva como cambio válido si el ruleset resultante pasa la validación del sensor.

#### Fuente HTTPS no incluida en el catálogo

Para un feed público/privado no indexado, `Add HTTPS source` utiliza el mecanismo nativo:

```bash
suricata-update add-source custom/<nombre> https://servidor/rules.tar.gz
```

El workflow del asistente acepta únicamente HTTPS y después reconstruye y valida el ruleset.

No introduce API keys, bearer tokens ni contraseñas en argumentos propios del asistente. Si un proveedor requiere credenciales y ya existe en el índice de `suricata-update`, utiliza la fuente indexada para que el gestor aplique sus parámetros. Revisa siempre cómo y dónde el proveedor/`suricata-update` persiste esas credenciales antes de usar un feed comercial.

#### Reglas manuales locales: solo para contexto propio

La edición manual sigue disponible como escape hatch, pero no como mecanismo principal de actualización:

```text
/etc/suricata/debian-ad-rules/context.rules
    gestionado por el asistente; no editar

/etc/suricata/debian-ad-rules/custom.rules
    gestionado por el operador
```

`custom.rules` sirve para información que un feed genérico no puede conocer, por ejemplo:

- una subred que jamás debe contactar determinado servicio interno;
- un protocolo legacy que debe desaparecer después de una fecha;
- una aplicación propia;
- una IOC interna temporal;
- un patrón específico descubierto durante un incidente.

El editor integrado realiza:

```text
backup
  ↓
edit
  ↓
suricata -T
  ├─ FAIL -> rollback del fichero
  └─ PASS -> rule reload
```

Cada regla debe utilizar un `sid` globalmente único. Consulta la documentación de SID y `sidallocation.org` antes de reservar un rango permanente. No reutilices SID de ET/Open u otros feeds.

Las reglas locales se almacenan fuera de `/var/lib/suricata/rules`, porque esa ruta pertenece a `suricata-update`. El asistente también migra sus reglas contextuales antiguas fuera del directorio de reglas de la distribución para evitar cargar accidentalmente una misma firma dos veces.

#### Actualizaciones automáticas

Para un sensor operativo no es razonable depender de que el administrador recuerde ejecutar el updater. `Automatic updates` instala:

```text
debian-ad-suricata-rules.service
debian-ad-suricata-rules.timer
```

Cadencias disponibles:

```text
cada 6 horas     recomendado
cada 12 horas
diario
```

La programación añade `RandomizedDelaySec=15m` para que muchos servidores no consulten las fuentes exactamente a la vez.

El timer ejecuta el asistente instalado mediante un modo no interactivo:

```text
--ids-rules-update
```

El pipeline es:

```text
ruleset anterior
      ↓ backup
suricata-update
      ↓
¿suricata.rules existe y no está vacío?
      ↓
suricata -T con HOME_NET + overlay + reglas locales
      ↓
 PASS ───────────────→ reload del sensor
 FAIL ───────────────→ restaurar ruleset anterior
```

Si el live reload falla, el asistente intenta un restart controlado. El timer **no cambia qué fuentes están habilitadas**; únicamente actualiza las fuentes que el administrador ya seleccionó.

#### Tuning y supresiones

`suricata-update` soporta política declarativa mediante `enable.conf`, `disable.conf`, `modify.conf` y `drop.conf`. No edites el fichero consolidado para silenciar una firma. Si una regla resulta ruidosa, primero investiga por qué dispara y después utiliza un filtro declarativo o threshold/suppression adecuado.

El asistente todavía mantiene el tuning avanzado separado de la selección de feeds para evitar que un perfil “recomendado” desactive silenciosamente detecciones que pueden ser necesarias en otro entorno. La fuente de verdad debe seguir siendo explícita y auditable.

Referencias oficiales:

- Suricata rule management: `https://docs.suricata.io/en/latest/rule-management/suricata-update.html`
- suricata-update: `https://suricata-update.readthedocs.io/en/latest/`
- Source index OISF: `https://github.com/OISF/suricata-intel-index`
- Rule/SID documentation: `https://docs.suricata.io/en/latest/rules/meta.html`

El sensor continúa siendo **alert-only** en este workflow; gestionar más fuentes no lo convierte en IPS inline.

### Informes y evidencia

La consola prioriza una representación legible. Los informes persistentes mantienen más detalle técnico para poder conservarlos como evidencia:

```text
/var/lib/debian-ad-assistant/ids/reports/ids-report-*.txt
```

La opción `Daily local reports → View generated reports` valida que el fichero siga existiendo y sea legible antes de abrirlo; un fallo del pager o del fichero debe volver al menú como `WARN`, no finalizar el asistente.

`Export evidence` conserva las vistas técnicas y metadatos relevantes. La intención es separar:

```text
CONSOLE / OPERADOR
explicación, contexto, quién, qué servicio, siguiente paso

EVIDENCIA TXT / JSONL
campos técnicos, timestamps, firmas, timeline y datos para auditoría
```

### Event Center: vista humana frente a evidencia

El **AD Event Center** aplica la misma filosofía. Las opciones interactivas traducen la timeline a bloques del tipo:

```text
[WARN] 2026-10-01 13:02:10  Suricata IDS — Network IDS
       Subject : 10.20.30.40 -> 192.168.1.90
       Detail  : ET ...
       Meaning : una firma de Suricata coincidió; correlacionar antes de escalar
```

mientras que la exportación sigue guardando `timeline.txt` y `timeline.jsonl` técnicos para análisis posterior.

Esto no intenta ocultar datos: ofrece una capa de **triage humano** delante de la evidencia cruda.

### Windows

El control plane de Windows puede analizar `eve.json`, generar informes y mostrar un dashboard nativo cuando el entorno lo permite:

```powershell
.\windows-ad-assistant.ps1 -Mode IDS
```

La instalación de Suricata/Npcap en Windows se mantiene como una acción administrativa explícita; el script no instala silenciosamente un driver de captura de terceros en un Domain Controller.

La paridad funcional buscada entre Debian/Samba, RHEL y Windows incluye el mismo modelo conceptual: redes confiables, diferencia entre actividad y alerta, vista de operador, timeline humana, evidencia técnica y recuperación segura. La implementación concreta puede variar según las capacidades nativas de cada plataforma.

### Qué significa IDS aquí

La integración es principalmente **pasiva**:

- flujos y conexiones;
- telemetría;
- alertas;
- DNS;
- Kerberos;
- LDAP;
- SMB;
- TLS/SSH según plataforma/configuración.

No asumas que habilitar Suricata convierte el DC en un IPS o firewall inline.

---

<a id="backups-snapshots-y-recuperacion"></a>
## Backups, snapshots y recuperación

No todos los backups sirven para el mismo problema.

### Snapshot de cliente

Sirve para restaurar configuración local relacionada con un join:

- DNS;
- hostname;
- identidad/configuración local según plataforma;
- estado de lifecycle.

No es un backup de Active Directory.

### Backup de configuración del DC

Sirve para conservar evidencia y configuración antes de cambios.

No siempre es suficiente para reconstruir un dominio.

### Backup recuperable del dominio

Samba AD:

- utiliza las funciones de backup de dominio soportadas por Samba;
- conserva copias fuera del propio DC.

Windows AD DS:

- utiliza System State Backup;
- integra la estrategia con backup externo y pruebas de restauración.

### Operaciones de alto impacto

Antes de cambios como:

- decommission de un DC;
- cambios fuertes de Kerberos/LDAP;
- eliminación de objetos críticos;
- GPO de seguridad global;
- reparación de SYSVOL;
- migración de dominio;

crea un backup apropiado para la operación y verifica que sea restaurable.

---

<a id="hardening-y-compatibilidad"></a>
## Hardening y compatibilidad

El proyecto favorece un baseline compatible antes que una política extrema aplicada a ciegas.

Ejemplos de controles habituales:

- firewall activo y con política coherente;
- Defender donde corresponda;
- RDP con NLA;
- SMB signing y restricciones de protocolos heredados;
- reducción de LLMNR;
- logging de PowerShell;
- LDAP signing/channel binding según readiness;
- Kerberos AES/RC4 readiness;
- SMB y NTLM legacy awareness;
- hardening Samba equivalente donde la plataforma lo soporte.

Cambios con riesgo de compatibilidad no deberían aplicarse únicamente porque aparezcan en una guía de hardening. Valida primero clientes, appliances, service accounts y software heredado.

### CIS y otros benchmarks

Los asistentes pueden implementar controles alineados con buenas prácticas o benchmarks, pero **no certifican cumplimiento completo** de CIS, DISA STIG u otro estándar por sí solos.

Para una afirmación formal de compliance utiliza el benchmark, perfil y herramienta de evaluación correspondientes y conserva evidencia independiente.

---

<a id="virtualizacion-y-hosts-multi-nic"></a>
## Virtualización y hosts multi-NIC

Los laboratorios con varias interfaces son una fuente frecuente de problemas AD.

Ejemplo típico:

```text
NIC 1 → NAT / Internet
NIC 2 → red interna AD
NIC 3 → management
```

Recomendaciones:

- conoce qué interfaz transporta tráfico hacia el DNS/DC;
- evita que DHCP de una red secundaria inyecte un resolver público por encima del DNS AD;
- revisa métricas y rutas;
- en producción, separa claramente red de administración y red de servicio cuando la arquitectura lo requiera;
- no cambies routing de un host remoto sin una vía de recuperación.

Los asistentes de cliente utilizan selección de interfaz consciente de ruta y avisan cuando la NIC elegida no coincide con el camino esperado hacia Active Directory.

### VirtualBox / VMware / Hyper-V

En laboratorio, el DNS proporcionado por NAT puede resolver Internet pero no la zona AD. Esto no lo convierte en un DNS válido para un miembro del dominio.

Una configuración frecuente es:

```text
Cliente → DNS del DC → forwarder externo
```

No:

```text
Cliente → DC + DNS NAT + 8.8.8.8
```

---

<a id="troubleshooting"></a>
## Troubleshooting

Empieza por identificar la capa que falla.

### 1. DNS

Linux:

```bash
dig _ldap._tcp.dc._msdcs.corp.example.com SRV
realm discover corp.example.com
```

Windows:

```powershell
Resolve-DnsName _ldap._tcp.dc._msdcs.corp.example.com -Type SRV
nltest /dsgetdc:corp.example.com
```

### 2. Hora / Kerberos

Linux:

```bash
chronyc tracking
klist
```

Windows:

```powershell
w32tm /query /status
w32tm /stripchart /computer:dc01.corp.example.com /samples:3 /dataonly
```

### 3. Secure channel

Linux client:

```bash
adcli testjoin -D corp.example.com
```

Windows client:

```powershell
Test-ComputerSecureChannel
nltest /sc_verify:corp.example.com
```

### 4. Join de Windows

Windows registra información detallada de unión al dominio en:

```text
%SystemRoot%\debug\NetSetup.log
```

El Windows AD Client Assistant guarda evidencia asociada al snapshot e identifica errores comunes como:

- domain/DC discovery;
- credenciales rechazadas;
- access denied;
- protección moderna contra reutilización insegura de computer accounts.

Si el asistente muestra `JOIN_AMBIGUOUS`, utiliza:

```powershell
.\windows-ad-client-assistant.ps1 -Mode Recover
```

No borres el estado ni cambies DNS manualmente hasta determinar si Windows llegó a aceptar el join.

### 5. Samba AD DC

```bash
systemctl status samba-ad-dc --no-pager
samba-tool dbcheck --cross-ncs
samba-tool dns zonelist localhost -U Administrator
```

### 6. Windows Domain Controller

```powershell
dcdiag /q
repadmin /replsummary
Get-ADReplicationFailure -Target * -Scope Forest
```

---

<a id="rutas-de-estado-y-logs"></a>
## Rutas de estado y logs

### Samba AD Control Plane

```text
State : /var/lib/debian-ad-assistant
Logs  : /var/log/debian-ad-assistant
```

La ruta concreta de backups/reportes se muestra en el resumen de cada ejecución.

### Linux AD Client Assistant

```text
State     : /var/lib/ad-client-assistant
Snapshots : /var/backups/ad-client-assistant
Logs      : /var/log/ad-client-assistant
```

### Windows Server AD Control Plane

Por defecto:

```text
%ProgramData%\WindowsADControlPlane
```

Puede cambiarse mediante el parámetro `-ExportPath`.

### Windows AD Client Assistant

Por defecto:

```text
%ProgramData%\ADClientAssistant
```

Estructura principal:

```text
current.json     lifecycle activo
snapshots\       snapshots pre-join
logs\            log por ejecución
reports\         resumen JSON por ejecución
```

`current.json` representa una operación activa o una membresía gestionada. No lo elimines como método de recuperación; utiliza `Status`, `Restore` o `Recover`.

---

<a id="checklist-antes-de-produccion"></a>
## Checklist antes de producción

Antes de desplegar o modificar un entorno AD:

- [ ] backups externos disponibles y probados;
- [ ] consola/ILO/iDRAC/hipervisor disponible si vas a tocar red o firewall;
- [ ] hostname y dominio definitivos;
- [ ] IP estable en los Domain Controllers;
- [ ] DNS AD funcional;
- [ ] forwarding DNS validado si los clientes necesitan resolución externa;
- [ ] hora sincronizada;
- [ ] puertos AD alcanzables desde las redes de clientes;
- [ ] cuentas de administración y delegación revisadas;
- [ ] GPO probadas primero en una OU piloto;
- [ ] compatibilidad revisada antes de retirar RC4, SMB heredado o endurecer LDAP;
- [ ] join/leave de clientes validado incluyendo reboot;
- [ ] logs y reportes revisados después de la ejecución;
- [ ] segundo DC / estrategia de redundancia considerada para producción.

### Prueba mínima recomendada para un cliente

1. ejecutar `Audit`;
2. ejecutar join guiado;
3. reiniciar;
4. ejecutar `Status`;
5. validar inicio de sesión con un usuario de prueba;
6. comprobar DNS y secure channel;
7. ejecutar leave en un equipo de laboratorio;
8. reiniciar;
9. restaurar estado pre-join;
10. verificar que DNS/hostname local quedaron como antes.

No declares un flujo de lifecycle listo para producción hasta haber probado también el camino de recuperación.

---

<a id="estado-del-proyecto"></a>
## Estado del proyecto

El repositorio está en desarrollo activo.

Las herramientas están diseñadas con un enfoque conservador y orientado a recuperación, pero siguen administrando sistemas sensibles. La cobertura real depende de plataforma, versión, topología, GPO existentes y componentes externos.

Antes de actualizar una versión ya desplegada:

1. revisa el diff;
2. ejecuta auditoría;
3. prueba en laboratorio o piloto;
4. conserva la versión anterior durante la validación;
5. vuelve a ejecutar los instaladores de shortcuts/CLI cuando corresponda.

---

## Licencia

MIT. Consulta [LICENSE](./LICENSE).
