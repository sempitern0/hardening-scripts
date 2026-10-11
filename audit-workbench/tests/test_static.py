"""Fast offline structural checks with no browser and no external packages."""
from pathlib import Path
import json, re, subprocess, shutil
root=Path(__file__).resolve().parents[1]
html=(root/'index.html').read_text()
css=(root/'styles.css').read_text()
js=(root/'app.js').read_text()
sw=(root/'sw.js').read_text()
manifest=json.loads((root/'manifest.webmanifest').read_text())
assert "img-src 'self' data: blob:" in html, 'CSP must permit the preexisting image previews'
assert 'reader.readAsDataURL(file)' in js and 'URL.createObjectURL(file)' not in js, 'No blob image decoding'
assert "['image/png','image/jpeg','image/webp']" in js
assert 'vendorModels' in js and 'obj.model=' in js, 'Dependent models'
assert 'badge.outerHTML=pill(obj.severity)' in js, 'Severity pills'
assert 'report-cover{background:var(--pdf-cover-bg)' in css, 'PDF themed cover'
assert 'normalize.css' in html and './normalize.css' in sw
assert 'dragon.svg' in html and './icons/dragon.svg' in sw
for item in ('index.html','app.js','styles.css','normalize.css','manifest.webmanifest','icons/dragon.svg','icons/icon-192.png','icons/icon-512.png'):
 assert (root/item).is_file(),item
assert manifest['display']=='standalone' and manifest['start_url'].startswith('./')
from PIL import Image
for size in (192,512):
 with Image.open(root/f'icons/icon-{size}.png') as img:assert img.size==(size,size)
if shutil.which('node'):subprocess.run(['node','--check',str(root/'app.js')],check=True)
print('STATIC PASS: CSP, files, dependent fields, PWA manifest/cache, themes and JavaScript syntax')
