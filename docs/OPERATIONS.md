# Operations reference

> Before first use, read [launch and deployment](DEPLOYMENT.md): non-elevated preflight, commit pinning, hashes, SSH and Windows.

[Quick start](../README.md) · [Inicio rápido](../README_ES.md)

## Contents

- [Choosing a tool](#que-herramienta-usar)
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
| [`debian-ad-assistant.sh`](../debian-ad-assistant.sh) | Debian 13 / Ubuntu Server 26.04 LTS | Samba AD DC: provisioning, operation, validation, backup, DNS/GPO, security |
| [`rhel-ad-assistant.sh`](../rhel-ad-assistant.sh) | Rocky / AlmaLinux 9–10 | Samba AD DC subject to AD-DC capability and operating system support |
| [`windows-ad-assistant.ps1`](../windows-ad-assistant.ps1) | Windows Server 2019 / 2022 / 2025 | AD DS, directory administration, diagnostics, recovery, and hardening |
| [`linux-ad-client-assistant.sh`](../linux-ad-client-assistant.sh) | Linux with APT or DNF/YUM and systemd | Reversible Linux AD client joins, diagnostics, and snapshots |
| [`rhel-ad-client-assistant.sh`](../rhel-ad-client-assistant.sh) | Linux with APT or DNF/YUM and systemd | Linux AD client variant with join, recovery, and security workflows |
| [`windows-ad-client-assistant.ps1`](../windows-ad-client-assistant.ps1) | Windows / PowerShell 5.1+ | AD membership lifecycle, preflight, diagnostics, and restoration |

**Quick guidance:**

- **Administer a domain controller:** use the assistant for the DC's operating system and run its audit mode before changing anything.
- **Manage domain clients:** use a client assistant, not the DC provisioning assistant.
- **Harden a system:** first assess the impact on identity, DNS, applications, and continuity; hardening is an available operation, not an automatic outcome of an audit.

> **RHEL support note:** Red Hat does not support running Samba as an AD Domain Controller on RHEL. `rhel-ad-assistant.sh` blocks provisioning unless the operator explicitly accepts this unsupported use with `--allow-unsupported-rhel-dc`. Do not assume equivalence with Rocky/AlmaLinux or deploy without assessing support.

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

DC control planes include optional Suricata integration for visibility into networks and protocols related to Active Directory. On Linux, the sensor is configured in **passive** mode: it observes traffic and generates telemetry and alerts, but does not block packets.

### Mental model: activity is not the same as an alert

This distinction avoids one of the most common sources of confusion when starting with an IDS:

```text
ACTIVIDAD
Suricata has observed traffic or a protocol.
Examples: ping, DNS, Kerberos, LDAP, SMB, a TCP connection.

ALERTA
A rule/signature has matched that traffic.
Examples: access to an AD service from outside HOME_NET,
an unusual SMB burst, an ET/Open signature, or a protocol anomaly.
```

Therefore:

> A normal `ping` **should not necessarily trigger an alert**. Recent assistant versions enable EVE `flow` telemetry, so ICMP may appear in **Connection activity** even when `Recent alerts` remains empty.

`flow` records are generally emitted when a flow ends or times out. A ping sent seconds ago may take some time to appear in the activity view.

### Linux / Samba AD

Typical access:

```bash
sudo bash ./debian-ad-assistant.sh --ids
```

The workspace distinguishes the administrator's daily view from technical evidence:

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

#### What to check first

For daily operation, a useful sequence is:

```text
Sensor health
     ↓
Operator overview
     ↓
Connection activity
     ↓
Recent alerts explained
     ↓
AD protocol intelligence if more detail is needed
```

`Operator overview` aims to answer operational questions, not display JSON:

- is recent telemetry arriving?;
- is the sensor dropping packets?;
- who is communicating with this DC?;
- which services are receiving traffic?;
- is there ICMP/ping activity?;
- are there alerts, and what do they mean in practical terms?;
- is the source inside or outside the trusted `HOME_NET`?

`Connection activity` focuses specifically on **who is connecting**. It groups sources, services, and recent activity. A line in this view means Suricata observed traffic; it does not by itself imply malicious activity.

#### Trusted network scope / HOME_NET

`HOME_NET` may include multiple legitimate networks, for example:

```text
192.168.10.0/24,10.20.0.0/16,10.8.0.0/24
```

Include the LANs, management VLANs, VPNs, and site-to-site networks whose clients legitimately need DC access. Local exposure rules use `!$HOME_NET`; omitting a legitimate network from this scope can produce alerts that appear to originate externally.

Do not add a network to the scope merely to silence an alert: first confirm it is actually managed and trusted.

### Safe tests to learn what the sensor sees

Perform these tests only on infrastructure you own or are expressly authorized to assess.

#### 1. ICMP / ping

From another device:

```bash
ping <IP_DEL_DC>
```

Expected:

```text
Connection activity  → ICMP / ping
Recent alerts        → usually no new alert
```

This verifies basic visibility, **not the ability to trigger signatures**.

#### 2. DNS

Linux:

```bash
dig @<IP_DEL_DC> example.org
```

Windows:

```powershell
Resolve-DnsName example.org -Server <IP_DEL_DC>
```

Expected: DNS activity, source IP, and queried names in the activity/intelligence views.

#### 3. Kerberos + SMB from a domain member

Windows:

```powershell
klist purge
dir \\<DC_FQDN>\SYSVOL
```

On a properly domain-joined client, this usually produces Kerberos and SMB activity. `klist purge` removes tickets from the user's cache to force renegotiation; use it only if you understand the effect on that session.

#### 4. Test a local exposure rule

From a laboratory machine whose IP is **outside `HOME_NET`**, make only one connection to the DC service you want to check.

Linux:

```bash
nc -vz <IP_DEL_DC> 445
```

Windows:

```powershell
Test-NetConnection <IP_DEL_DC> -Port 445
```

If the connection passes the sensor and the source is truly outside the trusted scope, the local SMB/RPC rule should be able to produce an alert such as:

```text
DAD IDS External access to AD SMB-RPC TCP surface
```

Do not use scanners or aggressive traffic against third-party systems to "test Suricata".

### Interpreting common alerts

| Signal | Initial interpretation | What to check |
|---|---|---|
| `DAD IDS External access ...` | A source outside `HOME_NET` reached a DC service | source IP, expected network/VPN, port, and any missing legitimate CIDR |
| `DAD IDS High-rate SMB ...` | Many SMB connections in a short time | authorized scanner, inventory, malfunctioning client, or reconnaissance |
| `applayer` / `app-layer` | Suricata could not cleanly interpret an application conversation | source/destination, actual protocol, recurrence, and exact signature |
| `ET SCAN` / firma de scanning | Traffic resembling discovery/reconnaissance | whether the source is an authorized scanner and which ports it touched |
| `ET POLICY` | Traffic relevant to a policy, not necessarily malware | context and operational need |
| malware / trojan / C2 | Pattern associated with compromise or command-and-control | source endpoint, DNS/TLS, process, and additional evidence |

An alert is an **investigative signal**, not a verdict. Always correlate signature, source IP, destination, service, time, Event Center, and endpoint logs.

### What does an `applayer` alert mean?

An `applayer` alert or anomaly may appear when Suricata expects a protocol but receives incomplete, unexpected, encrypted, malformed, or unclassifiable data. This could be noise, unfamiliar software, an uncommon protocol version, or hostile traffic.

Before escalating it as an incident:

1. identify `src_ip`, `dest_ip`, port, and protocol;
2. check whether the source host is known;
3. check whether the alert recurs;
4. review the same IP's activity around that time;
5. check Event Center and service/endpoint logs;
6. escalate if other signs are consistent with scanning, exploitation, or compromise.

### Rule management: maintained feeds before manual rules

The recommended workflow is not to copy individual signatures. `suricata-update` is Suricata's official rule manager and generates the consolidated ruleset at:

```text
/var/lib/suricata/rules/suricata.rules
```

That file is a **generated artifact**. Do not edit it directly. The assistant's architecture is:

```text
                 SURICATA DETECTION PIPELINE

  maintained feeds              local context
  via suricata-update            for the environment
         │                            │
         ├─ ET/Open                   ├─ AD/DC context.rules
         ├─ OISF TrafficID            └─ custom.rules (optional)
         ├─ abuse.ch feeds                  │
         └─ optional sources              │
                 │                          │
                 └──────────┬───────────────┘
                            ↓
                      suricata -T
                            ↓
                     safe rule reload
```

The console now provides:

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

During `Configure passive IDS`, the assistant offers this profile with **Y** as the default response. Enabling it remains explicit: the operator may decline and retain ET/Open plus DC-specific context rules, then apply the baseline later through `Rule management -> Professional baseline`.

The recommended professional passive-sensor profile installs/enables these layers:

| Layer | Source | Purpose |
|---|---|---|
| General | ET/Open | threats, exploits, malware, scans, and policy signatures maintained by ET |
| Visibilidad | `oisf/trafficid` | application/traffic identification through `noalert` rules |
| Threat intelligence | `abuse.ch/feodotracker` | botnet C2 infrastructure |
| Threat intelligence | `abuse.ch/urlhaus` | URLs used for malware distribution |
| Threat intelligence | `abuse.ch/sslbl-blacklist` | TLS certificates associated with malicious infrastructure |
| Contexto | Debian AD Assistant | DC Kerberos/LDAP/SMB/RPC/DNS/NTP exposure and SMB bursts |

ET/Open is the default general-purpose feed in `suricata-update`. If the administrator installs a commercial replacement, the assistant does not blindly combine it with ET/Open.

The baseline **does not**:

- convert `alert` into `drop`;
- enable IPS/NFQUEUE;
- enable resource-intensive hunting feeds by default;
- add commercial feeds without a license/token;
- directly edit `suricata.rules`;
- silently disable vendor categories.

The goal is a useful, maintained baseline without turning the DC into an experiment involving thousands of arbitrary signatures.

#### Additional recommended sources

`Recommended sources` explicitly enables sources from the OISF catalog. In addition to baseline feeds, the assistant currently suggests:

```text
stamus/lateral
    detections for lateral movement in Windows/AD environments

ptrules/open
    additional open detections from Positive Technologies
```

These sources are **optional**. More rules do not automatically mean better security: they may increase CPU, memory consumption, EVE volume, and false positives. Enable an additional feed to address a specific need, then review sensor behavior.

Retrieve the live catalog with:

```bash
suricata-update update-sources
suricata-update list-sources
```

The menu can refresh the catalog and enable any `vendor/name` identifier. The change is retained only if the resulting ruleset passes sensor validation.

#### HTTPS source not listed in the catalog

For a public/private feed not listed in the index, `Add HTTPS source` uses the native mechanism:

```bash
suricata-update add-source custom/<nombre> https://servidor/rules.tar.gz
```

The assistant accepts only HTTPS in this workflow, then rebuilds and validates the ruleset.

The assistant does not put API keys, bearer tokens, or passwords in its own command arguments. If a provider requires credentials and is already indexed by `suricata-update`, use the indexed source so the manager applies its parameters. Always inspect how and where the provider/`suricata-update` stores credentials before using a commercial feed.

#### Local manual rules: only for your own context

Manual editing remains available as an escape hatch, not as the primary update mechanism:

```text
/etc/suricata/debian-ad-rules/context.rules
    managed by the assistant; do not edit

/etc/suricata/debian-ad-rules/custom.rules
    managed by the operator
```

`custom.rules` is intended for information a generic feed cannot know, such as:

- a subnet that must never contact a particular internal service;
- a legacy protocol that must be retired by a given date;
- an in-house application;
- a temporary internal IOC;
- a specific pattern discovered during an incident.

The integrated editor performs:

```text
backup
  ↓
edit
  ↓
suricata -T
  ├─ FAIL -> file rollback
  └─ PASS -> rule reload
```

Each rule must use a globally unique `sid`. Consult SID documentation and `sidallocation.org` before reserving a permanent range. Do not reuse SIDs from ET/Open or other feeds.

Local rules are stored outside `/var/lib/suricata/rules`, since that directory belongs to `suricata-update`. The assistant also migrates its older context rules out of the distribution's rules directory to avoid accidentally loading the same signature twice.

#### Automatic updates

For an operational sensor, relying on the administrator to remember to run updates is not reasonable. `Automatic updates` installs:

```text
debian-ad-suricata-rules.service
debian-ad-suricata-rules.timer
```

Available schedules:

```text
every 6 hours    recommended
every 12 hours
daily
```

The schedule adds `RandomizedDelaySec=15m` so multiple servers do not query their sources at exactly the same time.

The timer runs the installed assistant in non-interactive mode:

```text
--ids-rules-update
```

The pipeline is:

```text
previous ruleset
      ↓ backup
suricata-update
      ↓
does suricata.rules exist and contain data?
      ↓
suricata -T with HOME_NET + overlay + local rules
      ↓
 PASS ───────────────→ sensor reload
 FAIL ───────────────→ restore previous ruleset
```

If live reload fails, the assistant attempts a controlled restart. The timer **does not change which sources are enabled**; it only updates sources already selected by the administrator.

#### Tuning and suppression

`suricata-update` supports declarative policy through `enable.conf`, `disable.conf`, `modify.conf`, and `drop.conf`. Do not edit the consolidated rules file to silence a signature. If a rule is noisy, first investigate why it triggers, then use an appropriate declarative filter or threshold/suppression.

The assistant still keeps advanced tuning separate from feed selection so that a "recommended" profile cannot silently disable detections that may be needed in another environment. The source of truth must remain explicit and auditable.

Official references:

- Suricata rule management: `https://docs.suricata.io/en/latest/rule-management/suricata-update.html`
- suricata-update: `https://suricata-update.readthedocs.io/en/latest/`
- Source index OISF: `https://github.com/OISF/suricata-intel-index`
- Rule/SID documentation: `https://docs.suricata.io/en/latest/rules/meta.html`

The sensor remains **alert-only** in this workflow; managing more sources does not make it an inline IPS.

### Reports and evidence

The console prioritizes readability. Persistent reports retain more technical detail so they can serve as evidence:

```text
/var/lib/debian-ad-assistant/ids/reports/ids-report-*.txt
```

The `Daily local reports → View generated reports` option confirms the file still exists and is readable before opening it; a pager or file error must return to the menu as `WARN`, not terminate the assistant.

`Export evidence` preserves technical views and relevant metadata. The intent is to separate:

```text
CONSOLE / OPERATOR
explanation, context, who, which service, next step

TXT / JSONL EVIDENCE
technical fields, timestamps, signatures, timeline, and audit data
```

### Event Center: human-readable view versus evidence

The **AD Event Center** follows the same approach. Interactive options present the timeline as blocks such as:

```text
[WARN] 2026-10-01 13:02:10  Suricata IDS — Network IDS
       Subject : 10.20.30.40 -> 192.168.1.90
       Detail  : ET ...
       Meaning : a Suricata signature matched; correlate before escalation
```

while exports continue to save technical `timeline.txt` and `timeline.jsonl` files for later analysis.

This does not hide data: it adds a **human triage layer** ahead of raw evidence.

### Windows

The Windows control plane can analyze `eve.json`, produce reports, and display a native dashboard when the environment supports it:

```powershell
.\windows-ad-assistant.ps1 -Mode IDS
```

Installing Suricata/Npcap on Windows remains an explicit administrative action; the script does not silently install third-party packet capture drivers on a Domain Controller.

Functional parity across Debian/Samba, RHEL, and Windows follows the same conceptual model: trusted networks, activity versus alerts, operator overview, human-readable timeline, technical evidence, and safe recovery. Specific implementations can vary according to native platform capabilities.

### What IDS means here

The integration is mainly **passive**:

- flows and connections;
- telemetry;
- alerts;
- DNS;
- Kerberos;
- LDAP;
- SMB;
- TLS/SSH depending on platform/configuration.

Do not assume enabling Suricata turns the DC into an inline IPS or firewall.

---

<a id="backups-snapshots-y-recuperacion"></a>
## Backups, snapshots, and recovery

Not every backup solves the same problem.

### Client snapshot

Used to restore local configuration related to a domain join:

- DNS;
- hostname;
- local identity/configuration depending on the platform;
- lifecycle state.

This is not an Active Directory backup.

### DC configuration backup

Used to preserve evidence and configuration before making changes.

This may not be sufficient to rebuild a domain.

### Recoverable domain backup

Samba AD:

- use Samba-supported domain backup functions;
- keep copies outside the DC itself.

Windows AD DS:

- use System State Backup;
- integrate the strategy with external backups and restoration tests.

### High-impact operations

Before changes such as:

- decommissioning a DC;
- major Kerberos/LDAP changes;
- deletion of critical objects;
- global security GPO;
- SYSVOL repair;
- domain migration;

create a backup appropriate for the operation and verify that it can be restored.

---

<a id="hardening-y-compatibilidad"></a>
## Hardening and compatibility

The project favors a compatible baseline over an extreme policy applied blindly.

Examples of common controls:

- active firewall with a consistent policy;
- Defender where appropriate;
- RDP with NLA;
- SMB signing and legacy protocol restrictions;
- reducing LLMNR;
- PowerShell logging;
- LDAP signing/channel binding according to readiness;
- Kerberos AES/RC4 readiness;
- awareness of legacy SMB and NTLM;
- equivalent Samba hardening where supported by the platform.

Changes that risk compatibility should not be applied solely because they appear in a hardening guide. Validate clients, appliances, service accounts, and legacy software first.

### CIS and other benchmarks

The assistants may implement controls aligned with good practices or benchmarks, but they **do not certify full compliance** with CIS, DISA STIG, or other standards by themselves.

For a formal compliance claim, use the appropriate benchmark, profile, and assessment tool and preserve independent evidence.

---

<a id="virtualizacion-y-hosts-multi-nic"></a>
## Virtualization and multi-NIC hosts

Labs with multiple network interfaces are a frequent source of AD problems.

Typical example:

```text
NIC 1 → NAT / Internet
NIC 2 → internal AD network
NIC 3 → management
```

Recommendations:

- know which interface carries traffic to the DNS/DC;
- prevent DHCP on a secondary network from inserting a public resolver ahead of AD DNS;
- check metrics and routes;
- in production, clearly separate management and service networks when the architecture requires it;
- do not change routing on a remote host without a recovery path.

Client assistants use route-aware interface selection and warn when the chosen NIC does not match the expected path to Active Directory.

### VirtualBox / VMware / Hyper-V

In a lab, NAT-provided DNS may resolve Internet names but not the AD zone. That does not make it a valid DNS server for a domain member.

A common configuration is:

```text
Client → DC DNS → external forwarder
```

No:

```text
Client → DC + NAT DNS + 8.8.8.8
```

---

<a id="troubleshooting"></a>
## Troubleshooting

Start by identifying the failing layer.

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

### 2. Time / Kerberos

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

### 4. Windows join

Windows records detailed domain join information at:

```text
%SystemRoot%\debug\NetSetup.log
```

The Windows AD Client Assistant saves evidence associated with the snapshot and identifies common errors such as:

- domain/DC discovery;
- rejected credentials;
- access denied;
- modern protection against insecure computer account reuse.

If the assistant reports `JOIN_AMBIGUOUS`, use:

```powershell
.\windows-ad-client-assistant.ps1 -Mode Recover
```

Do not delete the state or manually change DNS until you have determined whether Windows accepted the join.

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
## State and log paths

### Samba AD Control Plane

```text
State : /var/lib/debian-ad-assistant
Logs  : /var/log/debian-ad-assistant
```

The exact backup/report path is shown in each run's summary.

### Linux AD Client Assistant

```text
State     : /var/lib/ad-client-assistant
Snapshots : /var/backups/ad-client-assistant
Logs      : /var/log/ad-client-assistant
```

### Windows Server AD Control Plane

By default:

```text
%ProgramData%\WindowsADControlPlane
```

It can be changed using the `-ExportPath` parameter.

### Windows AD Client Assistant

Por defecto:

```text
%ProgramData%\ADClientAssistant
```

Main structure:

```text
current.json     active lifecycle
snapshots\       pre-join snapshots
logs\            per-run log
reports\         per-run JSON summary
```

`current.json` represents an active operation or managed membership. Do not delete it as a recovery method; use `Status`, `Restore`, or `Recover`.

---

<a id="checklist-antes-de-produccion"></a>
## Pre-production checklist

Before deploying or changing an AD environment:

- [ ] external backups available and tested;
- [ ] console/iLO/iDRAC/hypervisor access available when changing networking or firewall;
- [ ] final hostname and domain defined;
- [ ] stable IP address on Domain Controllers;
- [ ] functional AD DNS;
- [ ] DNS forwarding validated if clients need external name resolution;
- [ ] synchronized time;
- [ ] AD ports reachable from client networks;
- [ ] administrative and delegated accounts reviewed;
- [ ] GPOs tested in a pilot OU first;
- [ ] compatibility reviewed before disabling RC4 or legacy SMB, or hardening LDAP;
- [ ] client join/leave validated, including reboot;
- [ ] logs and reports reviewed after execution;
- [ ] second DC / redundancy strategy considered for production.

### Recommended minimum client test

1. run `Audit`;
2. perform a guided join;
3. reboot;
4. run `Status`;
5. validate sign-in with a test user;
6. verify DNS and secure channel;
7. perform a leave on a lab machine;
8. reboot;
9. restore the pre-join state;
10. verify that local DNS/hostname were restored to their original values.

Do not declare a lifecycle workflow production-ready until the recovery path has also been tested.

---

<a id="estado-del-proyecto"></a>
## Project status

The repository is under active development.

The tools use a conservative, recovery-oriented approach, but still administer sensitive systems. Actual coverage depends on the platform, version, topology, existing GPOs, and external components.

Before updating an already deployed version:

1. review the diff;
2. run an audit;
3. test in a lab or pilot environment;
4. retain the previous version during validation;
5. rerun the shortcut/CLI installers where applicable.

---

## License

MIT. See [LICENSE](../LICENSE).
