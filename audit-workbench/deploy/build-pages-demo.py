#!/usr/bin/env python3
"""Create a static public-demo distribution for Cloudflare Pages (stdlib only)."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist-pages"
FILES = {"css": {".css"}, "js": {".js"}, "fonts": {".woff2"}, "icons": {".svg", ".png"}}
EXCLUDED = ("js/secure-transfer.js", "js/secure-transfer-ui.js")
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; "
       "font-src 'self'; img-src 'self' data: blob:; connect-src 'self'; "
       "object-src 'none'; frame-src blob:; form-action 'none'; "
       "base-uri 'none'; manifest-src 'self'; worker-src 'self'; "
       "frame-ancestors 'none'")
HEADERS = ("/*\n"
    "  X-Content-Type-Options: nosniff\n"
    "  X-Frame-Options: DENY\n"
    "  Referrer-Policy: no-referrer\n"
    "  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()\n"
    "  Strict-Transport-Security: max-age=31536000\n"
    "  X-Robots-Tag: noindex\n"
    "  Content-Security-Policy: " + CSP + "\n\n"
    "/\n  Cache-Control: no-store\n\n"
    "/index.html\n  Cache-Control: no-store\n\n"
    "/sw.js\n  Cache-Control: no-store\n\n"
    "/manifest.webmanifest\n  Cache-Control: no-store\n")


def main():
    if os.getenv("CF_PAGES") == "1" and os.getenv("CF_PAGES_BRANCH") != "pages-production":
        raise SystemExit("Build refused outside approved pages-production branch")
    if DIST.is_symlink():
        raise SystemExit("Distribution path may not be a symlink")
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()

    for folder, extensions in FILES.items():
        for src in sorted((ROOT / folder).rglob("*")):
            if src.is_symlink():
                raise SystemExit("Refusing symlink " + str(src))
            if not src.is_file():
                continue
            rel = src.relative_to(ROOT)
            if src.suffix not in extensions or src.name.startswith("."):
                raise SystemExit("Unexpected public file " + str(rel))
            if rel.as_posix() in EXCLUDED:
                continue
            target = DIST / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, target)

    html = (ROOT / "index.html").read_text(encoding="utf-8")
    if "js/deployment-profile.js" not in html or "connect-src 'self' https:" not in html:
        raise SystemExit("Missing deployment profile or original CSP")
    for remote in EXCLUDED:
        pattern = r'(?m)^\s*<script src="' + re.escape(remote) + r'" defer></script>\s*$'
        html, count = re.subn(pattern, "\n", html)
        if count != 1:
            raise SystemExit("Expected one script tag for " + remote)
    html = html.replace("connect-src 'self' https:", "connect-src 'self'")
    (DIST / "index.html").write_text(html, encoding="utf-8")
    (DIST / "manifest.webmanifest").write_bytes((ROOT / "manifest.webmanifest").read_bytes())
    (DIST / "js/deployment-profile.js").write_text(
        "'use strict';\nglobalThis.AuditDeployment = Object.freeze({profile:'public-demo'});\n",
        encoding="utf-8",
    )

    sw = (ROOT / "sw.js").read_text(encoding="utf-8")
    for remote in EXCLUDED:
        needle = ", './" + remote + "'"
        if needle not in sw:
            raise SystemExit("Missing worker resource " + remote)
        sw = sw.replace(needle, "")
    if "'./js/deployment-profile.js'" not in sw:
        raise SystemExit("Offline cache must contain profile")

    checksum = hashlib.sha256()
    for p in sorted(DIST.rglob("*")):
        if p.is_file():
            checksum.update(p.relative_to(DIST).as_posix().encode())
            checksum.update(p.read_bytes())
    fingerprint = checksum.hexdigest()[:16]
    sw, n = re.subn(r"const CACHE_NAME='[^']+';",
                    "const CACHE_NAME='audit-workbench-shell-public-" + fingerprint + "';",
                    sw, count=1)
    if n != 1:
        raise SystemExit("Service worker cache constant missing")
    (DIST / "sw.js").write_text(sw, encoding="utf-8")
    (DIST / "_headers").write_text(HEADERS, encoding="utf-8")
    (DIST / "robots.txt").write_text("User-agent: *\nDisallow: /\n", encoding="utf-8")

    manifest = json.loads((DIST / "manifest.webmanifest").read_text(encoding="utf-8"))
    if manifest.get("scope") != "./" or manifest.get("start_url") != "./index.html":
        raise SystemExit("Installed PWA identity/scope has changed")
    if any((DIST / forbidden).exists() for forbidden in EXCLUDED):
        raise SystemExit("Remote transfer module was leaked")
    print("InfraAudit public-demo: cache=" + fingerprint)


if __name__ == "__main__":
    main()
