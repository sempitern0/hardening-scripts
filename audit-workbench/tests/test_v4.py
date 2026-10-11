"""Offline integration tests: file-less HTML, fake local storage and print via Chromium."""
from pathlib import Path
from playwright.sync_api import sync_playwright
from PIL import Image, ImageDraw
import json, fitz, re
root=Path(__file__).resolve().parents[1]
raw=(root/'index.html').read_text(encoding='utf-8')
raw='\n'.join(l for l in raw.splitlines() if 'Content-Security-Policy' not in l)
raw=raw.replace('<link rel="stylesheet" href="styles.css">','<style>'+(root/'styles.css').read_text()+'</style>')
mock="""<script>
window.auditStorage = new Map();
Object.defineProperty(window,'localStorage',{value:{getItem:k=>window.auditStorage.get(k)||null,setItem:(k,v)=>window.auditStorage.set(k,String(v)),removeItem:k=>window.auditStorage.delete(k)}});
Object.defineProperty(window,'indexedDB',{value:null});
</script>"""
raw=raw.replace('<script src="app.js" defer></script>',mock+'<script>'+(root/'app.js').read_text()+'</script>')
logo=Image.new('RGB',(500,150),'white');draw=ImageDraw.Draw(logo);draw.rectangle((20,20,120,130),fill='#2855af');draw.text((140,65),'AUDIT CLIENT',fill='black'); logo.save(root/'tests'/'test-logo.png')
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 page=browser.new_page(accept_downloads=True,viewport={'width':1440,'height':950});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.set_content(raw)
 page.locator('nav button[data-go="engagement"]').click()
 page.locator('#f-meta-main-client').fill('Cliente Auditoría CVE SA')
 page.locator('#f-meta-main-project').fill('Auditoría técnica 2026')
 page.locator('#logo-upload').set_input_files(str(root/'tests'/'test-logo.png'))
 page.locator('.logo-preview img').wait_for(timeout=10000)
 page.locator('nav button[data-go="assets"]').click()
 page.locator('button[data-add="assets"]').click()
 page.locator('#f-assets-0-name').fill('srv-es-03')
 page.locator('#f-assets-0-vendor').select_option('Dell')
 page.locator('#f-assets-0-model').select_option('PowerEdge R760')
 page.locator('#f-assets-0-os').select_option('Debian 13')
 page.locator('#f-assets-0-ram').select_option('128 GiB')
 page.locator('nav button[data-go="cves"]').click()
 page.locator('button[data-add="cves"]').click()
 page.locator('#f-cves-0-id').fill('CVE-2021-44228')
 page.locator('#f-cves-0-title').fill('Log4j riesgo de ejecución remota')
 page.locator('#f-cves-0-asset').select_option('srv-es-03')
 page.locator('#f-cves-0-status').select_option('Pendiente de contrastar')
 page.locator('nav button[data-go="legal"]').click()
 page.locator('#f-legal-main-confidentiality').fill('Confidencialidad acordada con cliente, exclusivo de la organización.')
 page.locator('#palette').select_option('pine-dark')
 page.locator('nav button[data-go="delivery"]').click()
 page.locator('#btn-pdf').click()
 pdf_path=root/'tests'/'audit-v4.pdf';page.pdf(path=str(pdf_path),format='A4',print_background=True)
 pdf=fitz.open(str(pdf_path));text='\n'.join(pg.get_text() for pg in pdf)
 assert len(pdf)>3,len(pdf)
 for expected in ('Cliente Auditoría CVE SA','PowerEdge R760','CVE-2021-44228','Confidencialidad acordada'):
  assert expected in text,expected
 # Some branded green accent must be reflected in printed rules / text.
 drawings=[drawing for pg in pdf for drawing in pg.get_drawings() if drawing.get('color')]
 assert any((color[1]>.2 and color[1]>color[0]) for d in drawings if (color:=d['color']))
 # Save a PDF cover image for visual preflight.
 pix=pdf[0].get_pixmap(matrix=fitz.Matrix(1.4,1.4),alpha=False);pix.save(str(root/'tests'/'v4-cover.png'))
 page.locator('#open-library').click()
 page.locator('[data-backup-all]').click()
 # localStorage should retain new optional blocks after saving.
 page.wait_for_timeout(500)
 records=page.evaluate("JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3'))")
 assert records[0]['audit']['cves'][0]['id']=='CVE-2021-44228'
 assert records[0]['audit']['meta']['logo'].startswith('data:image/jpeg;base64,')
 assert records[0]['audit']['assets'][0]['ram']=='128 GiB'
 assert len(records[0]['audit']['legal']['confidentiality'])>12
 # Backup download button should generate actual downloadable file (test is in-memory HTML no page URL).
 with page.expect_download(timeout=10000) as download_info:
  page.locator('[data-backup-all]').click()
 download=download_info.value
 assert download.suggested_filename.startswith('audit-workbench-backup-')
 snapshot=json.loads(Path(download.path()).read_text())
 assert snapshot['auditWorkbenchBackup']==1 and len(snapshot['records'])==1
 # Import the full backup without replacing currently saved data.
 page.once('dialog',lambda d:d.accept())
 page.locator('#input-import').set_input_files({'name':'backup.json','mimeType':'application/json','buffer':json.dumps(snapshot).encode('utf-8')})
 page.wait_for_timeout(500)
 assert page.locator('.audit-row').count()==2
 # Important migration: schema v2 from earlier release without legal/cves/logo.
 old=json.loads(json.dumps(records[0]['audit']));old.pop('legal');old.pop('cves');old['meta'].pop('logo',None)
 page.once('dialog',lambda d:d.accept())
 page.locator('#input-import').set_input_files({'name':'old.json','mimeType':'application/json','buffer':json.dumps(old).encode('utf-8')})
 page.wait_for_timeout(500)
 page.locator('#open-library').click()
 assert page.locator('.audit-row').count()==3
 assert not errors,errors
 print('V4 PASS',len(pdf),'PDF pages; logo/CVE/clauses/dark theme/backup/migration; JS errors:',errors)
 browser.close()
