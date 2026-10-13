# Audit Workbench security model

**English** · [Español](SECURITY_ES.md)

## Attack surface

- Web application without a backend, accounts, proprietary servers, tracking cookies, analytics, or external libraries.
- Local audit records in IndexedDB and, if that fails, `localStorage`. The browser does not encrypt ordinarily exported JSON files; users are responsible for secure storage.
- Images/logos pass through canvas and are converted to base64 JPEG; imports validate size, schema type, and allowed fields.
- Text is escaped before insertion into HTML; code from audit JSON records is not evaluated and arbitrary client HTML is not allowed.
- The CSP restricts executable scripts and resources to the origin; `connect-src https:` permits HTTPS integrations explicitly initiated by the auditor (CVE and WebDAV/Nextcloud). No external connection is required by default.
- The service worker caches static assets; it is not designed to retain audit records, CVE responses, PDFs, or credentials. Explicit server connectivity checks bypass the cache.

## Residual threats

Anyone with access to the browser profile or the device's storage may access audit records. A malicious extension, browser synchronization, malware, operating-system backups, a lost device, or a shared account may also compromise confidentiality. Captures may contain IPs, usernames, or accidentally included secrets. Accordingly:

- Encrypt disks/volumes and backup copies; require screen locking and individual access.
- Use separate profiles per client/consultant when procedures allow.
- Never paste passwords, tokens, reusable hashes, or keys without redaction. Inspect captures before including them.
- Preserve original evidence separately from the application with hashes and chain-of-custody identifiers as appropriate.
- Verify recipients before sharing, and classify the report and JSON.
- Do not use `mailto` to transmit documents without manually attaching them; no automatic SMTP/API sending takes place.

## Optional online operations

| Action | Destination | Data transmitted | Trigger |
|---|---|---|---|
| Look up a CVE | `https://cveawg.mitre.org/api/cve/CVE-...` | CVE identifier only | Button and confirmation (query may fail due to CORS) |
| Open CVE.org | CVE.org | CVE identifier in the URL | "View on CVE.org" button |
| Share JSON | Destination selected in the OS sharing dialog | **Complete audit-record JSON** | Button and confirmation; Web Share API where available |
| Prepare email | User's email client | Subject and text including client/project name; **no attachment** | Button, confirmation, manual recipient |
| Upload unencrypted JSON over WebDAV | Configured Nextcloud server | **Complete record without file-level encryption** (TLS in transit) | Unlock connection, button, and confirmation; encrypted backup is preferable |
| Encrypted JSON backup | Configured Nextcloud | AES-256-GCM encrypted file before transmission | Encryption passphrase, button, and confirmation |
| Share PDF | Configured Nextcloud | Complete PDF without file-level encryption | PDF selection, explicit upload, and confirmation |
| Temporary PDF link | Nextcloud OCS API | Request for read-only link with password and expiration | Explicit creation after PDF upload |
| Revoke link | Nextcloud OCS API | Current session's share identifier | Express confirmation |
| Other providers (S3/Google Drive/OneDrive) | Not integrated | None | Requires development or manual delivery |

There is no automated CVE search by product/version or automated scanning; a CVE record does not, by itself, prove that an asset is affected. **The absence of online CVE lookup does not block an audit or PDF generation.**

## Limitations and follow-up

The PWA has no built-in user authentication, multiuser access control, digital signatures, browser-profile access auditing, or signed integrity verification. Audit records remain unencrypted in IndexedDB: **optional encryption protects exported backup files, not the entire local database**. Nextcloud credentials can be stored encrypted under a local passphrase; an unlocked or compromised browser session remains a threat. Other providers will require client authorization, least-privilege permissions, and verifiable revocation. Persistent API secrets must not be embedded in public JavaScript.

## Optional connections and encrypted backups

WebDAV credentials are encrypted locally with AES-GCM, using a key derived from an auditor passphrase through PBKDF2-SHA256 with 310,000 iterations and a random salt. A secure context (HTTPS or localhost) and the Web Crypto API are required. The passphrase is not persisted, and the profile is unlocked manually each session. **There is no key-escrow service or password recovery mechanism**. This protection is not equivalent to an enterprise secrets manager and does not protect compromised endpoints or access to an unlocked session.

Do not use primary personal credentials for WebDAV: create a dedicated, revocable **application password** with minimal permissions. Transfers require valid HTTPS, CORS support on the server, and explicit confirmation by the auditor. If the server does not allow CORS, use manual export. There are two separate paths: ordinary JSON upload adds no file-level encryption (only TLS in transit); **the encrypted backup function** derives an independent key using PBKDF2-SHA256 and encrypts JSON using AES-256-GCM before transmission. PDFs likewise lack file-level encryption, although they travel over HTTPS. Remote-storage custody and its access controls are the responsibility of the server and client.

The CSP permits `connect-src https:` only to support user-configured Nextcloud servers and explicit CVE lookups. There are no analytics, background connections, or injected scripts from external domains. Configure a more restrictive CSP at the reverse proxy if a corporate deployment uses known providers.

The Spanish DNI/NIE checksum algorithms and ordinary entity NIF checks **validate format and check digits**; they do not verify records with the Spanish Tax Agency (AEAT) or the holder's identity.

## Tabular exports and backup folder

- **JSON:** restorable audit-record format. Ordinary exports do not encrypt files and may contain images, identifiers, and personal data; encrypted custody is required.
- **Encrypted backup (`.awenc`):** contains JSON encrypted with a separate passphrase and can be recovered from the connections panel. Losing the passphrase may make recovery impossible.
- **XLSX/CSV:** table exports without images. CSV protects fields beginning with characters that spreadsheet programs might interpret as formulas; XLSX uses text cells, without macros or generated formulas. Review each deliverable before sending.
- **Local folder:** the application writes only to a folder explicitly selected with the File System Access API, when available. Permission may be revoked when the browser closes or updates. Automatic execution while the application is closed is not supported. Folder names and backup times are stored as preferences; permissions are kept locally in IndexedDB.
- Do not use a publicly served Python or web-server directory as a backup destination: audit records could become accessible to third parties.
