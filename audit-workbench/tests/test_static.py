"""Dependency-light checks for the single current Audit Workbench codebase."""
from pathlib import Path
import json
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
html = (root / "index.html").read_text(encoding="utf-8")
app = (root / "js/app.js").read_text(encoding="utf-8")
sw = (root / "sw.js").read_text(encoding="utf-8")
manifest = json.loads((root / "manifest.webmanifest").read_text(encoding="utf-8"))
scripts = re.findall(r'<script[^>]+src="([^"]+)"', html)
styles = re.findall(r'<link[^>]+href="([^"]+\.css)"', html)

assert "Content-Security-Policy" in html
assert scripts and scripts[-1] == "js/app.js", "Application should load after its modules"
for resource in scripts + styles:
    assert (root / resource).is_file(), f"Missing HTML resource: {resource}"
    assert "'./" + resource + "'" in sw, f"Offline resource not cached: {resource}"
assert "audit-workbench-shell-v45-single-json" in sw
assert "const VERSION = 3;" in app and "raw.schemaVersion!==VERSION" in app
assert "LEGACY_STORE" not in app and "nextReportId(" not in app
assert "auditWorkbenchBackup" not in app and "settings.sequences" not in app
assert "kind:LIBRARY_KIND,schemaVersion:VERSION" in app
assert "kind:PROFILE_KIND,schemaVersion:VERSION" in app
assert "js/audit-identifiers.js" in scripts and "js/document-control.js" in scripts
assert "js/audit-storage.js" in scripts and "js/exporters.js" in scripts
assert manifest["display"] == "standalone" and manifest["start_url"].startswith("./")
assert all((root / ("icons/icon-%d.png" % size)).is_file() for size in (192, 512))
if shutil.which("node"):
    for script in scripts + ["sw.js"]:
        subprocess.run(["node", "--check", str(root / script)], check=True)
print("STATIC PASS: single v3 JSON, script dependencies, offline resources and JS syntax")
