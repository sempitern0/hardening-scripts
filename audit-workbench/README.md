# Audit Workbench · sysadmin

**English** · [Español](README_ES.md)

[← Back to the sysadmin repository](../README.md) · [Installation](INSTALLATION.md) · [Security](SECURITY.md) · [Legal notes](LEGAL.md)

**Offline-first technical auditing, inventory, and documentation tool** for recording assets, evaluating controls, documenting findings and evidence, planning remediation, and preparing client reports.

It runs in the browser without requiring external services. It does not scan networks or modify devices.

## Getting started

From the repository's `audit-workbench/` directory:

```bash
bash ./audit-workbench.sh
```

```powershell
.\audit-workbench.ps1
```

To work through a stable local origin:

```bash
cd audit-workbench
python -m http.server 8765 --bind 127.0.0.1
```

Open `http://127.0.0.1:8765`. For installation as a PWA on a tablet or phone, see **[Installation by device](INSTALLATION.md)**: the initial load requires HTTPS and a compatible browser.

## Guided data entry

Forms provide contextual examples for DNI, NIE, entity CIF/NIF, tax identification, IP, CIDR, VLAN, CVE, CVSS, SHA-256, references, and other specially formatted fields. Phone fields for clients, consulting firms, and auditors support a country flag and dialing code selector, along with a suggested entry mask. Numbers are stored in international format in the existing field (no JSON migration); identity and phone validation stays local and does not verify actual ownership or assignment. Existing phone numbers remain editable.

## Secure distribution of audit records and PDFs

Under **Online connections → Nextcloud**, you can download or upload a locally encrypted JSON backup (AES-256-GCM and PBKDF2). The passphrase is not sent to the server. Recovery downloads a JSON file for review and manual import. WebDAV requires HTTPS, an app password, explicit authorization, and compatible CORS settings.

For PDFs: generate the document using **Generate PDF**, save it through the print dialog, and select it under Connections. A temporary local URL is used to preview it without publication. With authorization, it can be uploaded over WebDAV, and a Nextcloud link can be created through OCS with a password, read-only permission, and an expiration of 1 to 7 days. Nextcloud enforces expiration and permissions: no tunnel to the auditor's device is created. Links created during earlier sessions must be managed in Nextcloud. PDFs are stored without file-level encryption on the server, subject to its access controls and encryption-at-rest configuration.

Google Drive, OneDrive, S3, and automatic binary PDF generation are not connected. Online operations depend on CORS and server configuration.

Contextual dictionary help uses SVG buttons separate from field labels to avoid interfering with native selectors. The dictionary offers a direct return to the step or field from which it was opened. The offline catalog includes additional laptop and desktop families, with custom entry for models not listed.

## Reports and pre-delivery review

The assistant supports **start time** and **end time** in local 24-hour format alongside existing dates. Older JSON files containing only dates remain valid, without assumed times. Chronological order is checked, including audits that start and end on the same day.

Delivery provides two modes: **Generate draft PDF**, always marked as unvalidated work, and **Final report PDF**, which blocks critical quality issues and requires review of remaining warnings. Final-report checks include evidence references, pending controls, sign-off, and chronological consistency; empty time fields produce precision warnings rather than errors for older records. Reports include an internal table of contents, a coverage summary, and improved A4 pagination. Export continues to use the browser without uploading documents to external services.

**Download audit record JSON** requests a local download and displays a status message; the browser decides where to save it according to its configuration. Verify that the file appears in Downloads. The top toolbar uses the same workflow and does not accidentally treat the `click` event as audit content. Draft reports show blockers from the final-report preflight, and the report avoids duplicating the final legal note.

## Recommended workflow

1. **Settings:** register your consultancy and audit team; assign professionals to the audit record.
2. **Library:** create or open an audit, identify the client, and define scope, authorizations, and exclusions.
3. **Inventory:** document hardware, operating systems, networks, and software. Use search and selectors; custom values are supported.
4. **Controls:** select templates for systems, networks, identity, or continuity. All start as *Pending* and require actual verification.
5. **Findings and evidence:** record observations, link assets and controls, describe consequences, recommended actions, and closure criteria. Retain original evidence and its SHA-256 hashes.
6. **Quality and delivery:** review warnings, priorities, and the remediation plan before generating the PDF. If essential information is missing, the report is marked as a draft.
7. **Follow-up:** record verified remediation and issue a separate reassessment report with historical changes and pending decisions.

### Assisted inventory capture

The bottom sidebar indicator reports the browser-declared network state (red: no connection; amber: network detected, not verified). Its check button only requests the PWA's own manifest (green when a response is received), without transmitting audit data; **it does not verify general Internet access**, and a response served by a cache or proxy does not establish external connectivity either.

From **Hardware, Networks, or Software → Assisted capture**, import a CSV or JSON file, review its records locally, detect duplicates, and select only new entries. Existing records are not overwritten, and confirmation is required before adding data to the audit. CSV requires a header row (comma or semicolon separator); JSON accepts `assets`, `networks`, and `software` collections or the `audit-workbench-discovery-v1` capture format. Maximum 2 MiB/500 rows. Imported entries remain pending verification.

The `collect-local.sh` (Linux/macOS with Python 3) and `collect-local.ps1` (Windows PowerShell) collectors gather basic information **only from the local computer**. Run them only with authorization and without unnecessary privilege elevation. Examples: `bash collect-local.sh --output captura.json` or `powershell -File .\\collect-local.ps1 -Output captura.json`. The resulting file contains system identifiers: review it and protect its storage. The collectors also gather interfaces, local disks, services, and a limited inventory of installed packages or applications; they do not discover remote hosts or transmit data to third parties. A service inventory does not establish vulnerabilities, versions, or exposure.

The **Technical dictionary** includes 135 concepts, synonym search, and, where applicable, troubleshooting guides and alternative console diagnostics (Windows/PowerShell, Linux, macOS, and specialized tools). Commands are illustrative and copyable; **the PWA never executes them**. Many require specific privileges or connections to authorized systems; replace example targets, check tool versions, and protect results before using them as evidence. The reference also includes expanded acronyms, ISO/IEC, NIST, IETF/IANA, and OWASP standards, and official links that require a connection only when the auditor chooses to open them. Windows, Linux, and macOS icons are included locally as reusable SVG assets. Wizard sections and fields where clarification is useful include contextual dictionary help. Navigation context is preserved so the auditor can return directly to the originating field; links are assigned by section to avoid ambiguous references.

The **Incident response** entry contains an expandable section for Spain's public **INCIBE 017** service, the official service information, and the separate INCIBE-CERT corporate incident reporting channel. This resource is optional, without global alerts or transmission of audit data. An isolated observation does not establish a vulnerability.

## Where data is stored

Audit records are stored **in the browser**, preferably in **IndexedDB**, with `localStorage` as a fallback. JSON files are **not** automatically created in the installation directory.

**Do not treat browser storage as a backup.** Before updating or switching devices, use **Backups and exports → Download full backup (.json)** and check the downloaded file.

| Format | Purpose | Restorable |
| --- | --- | --- |
| Individual JSON | Continue an audit in another browser | Yes |
| Full JSON backup | Back up and recover all audit records | Yes |
| PDF | Formal delivery of an audit or reassessment | No |
| XLSX | Editable tabular inventory and tracking | No |
| CSV | Exchange a section with other tools | No |

To restore a record, choose **Import** and select the JSON file. Check the recovered information before deleting earlier copies. Some browsers support periodic backups to an authorized folder **only while the application remains open**; this does not replace an external backup system.

Changing the URL, port, profile, or browser may change the storage namespace. For example, `localhost` and `127.0.0.1` do not necessarily share the same audit records.

## Compatibility and offline use

- **Desktop:** modern browsers on Windows, Linux, and macOS.
- **Tablet/mobile:** PWA installation over HTTPS where supported; once assets are cached, it can open without a connection.
- **Typeface:** Atkinson Hyperlegible (regular, bold, italic, and bold italic), served locally.
- **Themes:** light and dark; select the palette that is easiest to read. The PDF uses an A4 print-ready layout.
- **Connected operations:** CVE lookups, WebDAV/Nextcloud, and sharing tools only when expressly requested. Audit records are never transmitted automatically.

The operating system and model catalog is illustrative; **it does not certify support status, vulnerabilities, or compliance**.

## Security and limitations

- JSON and PDF files may contain **confidential information**, personal identifiers, and infrastructure details. Store them on encrypted media and share only with authorized recipients.
- WebDAV credentials can be protected by a local passphrase. **This does not encrypt audit records in IndexedDB or ordinary exported JSON files.**
- Legal texts are editable templates, **not legal advice**, and do not replace an audit agreement or data-processing agreement.
- Control templates alone do not establish compliance. An unchecked control must not be presented as compliant.
- Audit results are limited to the scope, date, and evidence actually reviewed.

See **[Security and privacy](SECURITY.md)** and **[Model clauses (Spain)](LEGAL.md)**.

## Help and troubleshooting

| Situation | What to check |
| --- | --- |
| My audits are missing | Verify the same URL/origin, browser, and profile; restore from JSON |
| Interface fails to load after an update | Force a reload; inspect the cache/service worker without deleting IndexedDB |
| Cannot install on a tablet | Check HTTPS, manifest, and browser support |
| Fonts or colors are missing | Check `css/`, `fonts/`, paths, and CSP errors in the console |
| PDF is incomplete | Review **Quality**, enable background printing, and verify A4 |

Full installation, updating, and troubleshooting instructions are in **[INSTALLATION.md](INSTALLATION.md)**.

## Organization

```text
audit-workbench/
├── index.html
├── manifest.webmanifest
├── sw.js                  # At root: maintains the PWA's offline scope
├── audit-workbench.sh
├── audit-workbench.ps1
├── js/                    # Catalogs, storage, relationships, and UI
├── css/                   # Themes, forms, and printing
├── fonts/                 # Local Atkinson Hyperlegible
├── icons/
└── tests/
```

Audit Workbench is part of **sysadmin**, a collection of system administration tools. It operates independently of the Active Directory assistants at the repository root: its purpose is to record and analyze audits, not to perform administration or hardening actions on remote systems.

## Document confirmation and exceptional amendments

Audit Workbench distinguishes **draft**, **confirmed**, and **amendment in progress**. Drafts can be edited and reviewed without claiming final approval. The final-report preflight additionally checks the responsible auditor, authorization, executive summary, duplicate identifiers, referenced evidence, sign-off, and other existing consistency checks.

Under **Final report**, identify the responsible person and confirm the audited record after reviewing the warnings. Confirmation stores a local SHA-256 digest and a revision entry and disables ordinary editing. To correct a confirmed audit, select **Open exceptional amendment**, identify the responsible person and explain the reason. After editing, run the definitive checks and choose **Validate changes and close amendment**; the local journal records the revision, reason, changed field paths, and before/after SHA-256 digests. A PDF for final delivery requires the confirmed content to match its digest. Older records remain drafts until explicitly confirmed.

**Scope of assurance:** this is a local workflow safeguard, not a digital signature, trusted timestamp, immutable log, or regulated e-signature. A person controlling browser storage or exported JSON can modify or replace the journal. Store each approved JSON/PDF version in an external, access-controlled repository with independent retention and backups. Changes to already delivered reports should be communicated as a new revision rather than silently replacing earlier documents.

## Controlled PWA updates

When Audit Workbench is served from a stable HTTPS or localhost origin, it checks for updates when opened, when connectivity returns, when the app becomes visible, and periodically while open. A prepared version is announced inside the interface; **it is not activated automatically while an audit is being edited**. Choose **Save and update** to save pending changes, verify local persistence, activate the waiting service worker, and reload. Choose **Later** to continue on the current version. **Check for updates** is also available manually. The application never uploads audit records during update checks.

**Initial migration:** PWA installations predating this update manager may need to close all Audit Workbench tabs and reopen the app once to acquire the new interface. A source repository commit is not a deployment: the server hosting the PWA must also be updated. If a local file installer was used, refresh its installation directory first. Close other open tabs before activating an update because a service-worker activation affects all tabs sharing its scope; other tabs are not automatically reloaded by this workflow. Do not clear browser site data to force updates, as that can delete locally stored audit records. Export a backup before major releases.

## Offline availability safeguards

The service worker installs a complete, versioned application shell before a release can activate. A failed install leaves the previously active version intact. Offline navigation falls back to the cached entry point; the current and one previous app-shell cache are retained as a limited recovery reserve. The new **Offline protection** panel checks missing essential resources, shows a best-effort storage quota estimate, offers a browser request for persistent storage, and can explicitly repair missing cached files when the original server is available. Repair does not download audit data or transmit records.

Persistent storage is subject to browser policy and does not replace backups. The application does not promise 99.9% measured uptime, cannot recover data deleted by the user/OS, and cannot guarantee compatibility after a browser or device failure. Test the actual device by stopping the server and relaunching the installed PWA, and export JSON backups before updates.

## Executive and technical PDF reports

**The same audit record produces two distinct documents without adding fields or duplicating data.** Under **Reports**, choose **Executive** (risk, business impact, priority, ownership, and decisions) or **Technical** (documented methods, findings, control results, inventories, CVEs, linked evidence, and detailed remediation). Each has **Draft** and **Final** options and shares the same report reference, confirmed revision, and preflight requirements. The separate reassessment report remains available.

The executive report does not embed technical screenshots or asset inventories. The technical report reproduces the information the auditor entered; it does not invent commands, proof of exploitation, or verification results. Both use browser printing to produce PDFs locally. The audit JSON format and wizard remain unchanged.

## Enterprise Wi-Fi and Ethernet security guidance (2026)

The offline **Technical dictionary → Networks** includes nine practical guides on enterprise network architecture, WPA3-Enterprise, EAP-TLS/RADIUS certificate validation, Protected Management Frames (PMF), guest/BYOD/IoT separation, Ethernet switch access protections, management plane security, legacy Wi-Fi migration, and MACsec. Existing entries on VLAN, 802.1X/NAC, WPA2/WPA3, RADIUS, and guest networks have been expanded. Each new guide contains a risk rationale, audit checks, official source references, and read-only Windows/Linux/macOS diagnostic examples where useful. Commands never run automatically. Recommendations distinguish preferred new deployment defaults from compatibility exceptions; risk acceptance and changes must be documented and approved.
