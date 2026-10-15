# Audit Workbench HTTPS deployment

[Spanish deployment guide](README_ES.md) · [Installation](../INSTALLATION.md) · [Security](../SECURITY.md)

The PWA can be served securely from a stable HTTPS subdomain using Docker Compose and Caddy, without a backend or server-side audit storage. The Docker image includes only the static site (HTML, CSS, JavaScript, fonts, icons, manifest and service worker); local Discovery scripts and customer files are excluded.

## Prerequisites

A Linux server with Docker Engine/Compose v2, a DNS A/AAAA record pointing to it, and inbound TCP ports 80 and 443 for automatic TLS certificate issuance/renewal.

```bash
cd audit-workbench/deploy
cp .env.example .env
# Configure AUDIT_DOMAIN and ACME_EMAIL in .env.
docker compose config --quiet
docker compose up -d --build
docker compose logs -f audit-workbench
python3 smoke_https.py https://your-audit-domain.example
```

Visit the HTTPS domain on each device and install through the browser menu (Android Chrome/Edge: Install app; iOS/iPadOS Safari: Share → Add to Home Screen). Check offline cache health, test opening the installed app offline, and keep external JSON backups.

**Important:** All audit records stay in that device/browser/origin's IndexedDB. Hosting a common URL does **not** provide accounts, multi-device synchronization, or backups. Changing origin (including moving from localhost to HTTPS) requires exporting/importing JSON. Never deploy customer JSON/PDF/evidence inside the public web root.

Update with `git pull --ff-only` and `docker compose up -d --build`; users confirm installation of a new service-worker version. Do not delete the Caddy volumes unless intentionally discarding TLS credentials. Public ACME certificate issuance requires correct DNS and connectivity; for VPN/private-only deployments use a trusted certificate solution, not TLS bypasses.

See [the Spanish guide](README_ES.md) for deployment constraints, security, troubleshooting and private-network alternatives.
