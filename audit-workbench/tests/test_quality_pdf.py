"""Print regression with visible action plan and draft status on A4. Uses a test-only offline fixture."""
from pathlib import Path
import re
import tempfile
import os
import fitz
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.getenv('AUDIT_QUALITY_PDF_PATH', str(Path(tempfile.gettempdir())/'audit-workbench-quality-test.pdf')))
src=(ROOT/'index.html').read_text(encoding='utf-8')
src=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>','',src)
src=re.sub(r'<link[^>]+rel="stylesheet"[^>]*>','',src)
src=re.sub(r'<script[^>]+src="[^"]+"[^>]*></script>','',src)
with sync_playwright() as p:
 b=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 page=b.new_page(viewport={'width':1250,'height':820},accept_downloads=True)
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.set_content(src,wait_until='load')
 for css in ['normalize.css','styles.css','team.css','contrast.css','relations.css','templates.css','print.css','quality.css','retest.css','comparison.css']:
  page.add_style_tag(content=(ROOT/css).read_text(encoding='utf-8'))
 page.evaluate('''() => {const m=new Map();Object.defineProperty(window,'indexedDB',{value:undefined,configurable:true});Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)}})}''')
 for js in ['exporters.js','hardware-catalog.js','audit-relations.js','control-templates.js','audit-quality.js','audit-retest.js','audit-comparison.js','app.js']:
  page.add_script_tag(content=(ROOT/js).read_text(encoding='utf-8'))
 page.locator('[data-new]').first.click()
 page.locator('#wizard-step-select').select_option('findings')
 page.locator('[data-add="findings"]').click()
 page.locator('[data-block="findings"][data-field="title"]').fill('Autenticación multifactor ausente')
 page.locator('[data-block="findings"][data-field="severity"]').select_option('Alta')
 page.locator('[data-block="findings"][data-field="recommendation"]').fill('Activar MFA para las cuentas de administración privilegiada; documentar excepciones autorizadas.')
 page.locator('[data-block="findings"][data-field="verification"]').fill('Realizar acceso de prueba verificando que el segundo factor es obligatorio.')
 page.evaluate('window.dispatchEvent(new Event("beforeprint"))')
 pdf=page.pdf(format='A4',print_background=True,prefer_css_page_size=True)
 OUT.write_bytes(pdf)
 print('errors',errors,'bytes',len(pdf))
 assert not errors,errors
 b.close()
with fitz.open(OUT) as doc:
 print('pages',doc.page_count)
 alltext='\n'.join(pg.get_text() for pg in doc)
 assert 'BORRADOR' in alltext
 assert 'Plan de remediación y comprobación' in alltext
 assert 'Activar MFA' in alltext
 for i,pg in enumerate(doc):
  assert round(pg.rect.width)==595 and round(pg.rect.height)==842,(i,pg.rect)
  if i in (0,doc.page_count-1):
   pix=pg.get_pixmap(matrix=fitz.Matrix(1.2,1.2),alpha=False)
   pix.save(str(OUT.with_name(f'quality-page-{i+1}.png')))
 print('PASS A4 draft and remediation report,',doc.page_count,'pages')
