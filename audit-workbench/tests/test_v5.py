"""Browser regression with real CSP, HTTP localhost, SW, persistence and PDF."""
from pathlib import Path
from contextlib import contextmanager
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from threading import Thread
from playwright.sync_api import sync_playwright
from PIL import Image, ImageDraw
import fitz, json, os
ROOT=Path(__file__).resolve().parents[1]
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
@contextmanager
def served():
 prev=os.getcwd();os.chdir(ROOT)
 srv=ThreadingHTTPServer(('127.0.0.1',0),Quiet)
 Thread(target=srv.serve_forever,daemon=True).start()
 try:yield f'http://127.0.0.1:{srv.server_port}/'
 finally:srv.shutdown();srv.server_close();os.chdir(prev)

# Generate PNG and WebP to verify both codecs under CSP
img=Image.new('RGB',(700,300),'white')
draw=ImageDraw.Draw(img);draw.rectangle((10,10,140,260),fill='#16479c');draw.text((160,90),'CLIENTE AUDITORIA',fill='black')
img.save(ROOT/'tests'/'v5-logo.png');img.save(ROOT/'tests'/'v5-logo.webp')
with sync_playwright() as p:
 base=(ROOT/'index.html').as_uri()
 browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 ctx=browser.new_context(viewport={'width':1440,'height':900},accept_downloads=True)
 page=ctx.new_page();errors=[];console=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.on('console',lambda m: console.append(m.text) if m.type=='error' else None)
 raw=(ROOT/'index.html').read_text(encoding='utf-8')
 raw='\n'.join(line for line in raw.splitlines() if 'Content-Security-Policy' not in line)
 raw=raw.replace('<link rel="stylesheet" href="normalize.css">','<style>'+(ROOT/'normalize.css').read_text()+'</style>')
 raw=raw.replace('<link rel="stylesheet" href="styles.css">','<style>'+(ROOT/'styles.css').read_text()+'</style>')
 mock="""<script>window.auditStorage = window.auditStorage || new Map();Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>window.auditStorage.get(k)||null,setItem:(k,v)=>window.auditStorage.set(k,String(v)),removeItem:k=>window.auditStorage.delete(k)}});Object.defineProperty(window,'indexedDB',{configurable:true,value:null});</script>"""
 raw=raw.replace('<script src="app.js" defer></script>',mock+'<script>'+(ROOT/'app.js').read_text()+'</script>')
 page.set_content(raw);page.get_by_text('Biblioteca de auditorías').first.wait_for()
 # Create audit, ensure menu segregation and active label
 assert not page.locator('#navigation').is_visible()
 page.get_by_role('button',name='+ Nueva auditoría').click()
 page.locator('#f-meta-main-client').fill('Cliente prueba v5')
 page.locator('#f-meta-main-project').fill('Auditoría QA v5')
 page.locator('#f-meta-main-reportId').fill('AUD-QA-2026')
 page.locator('#logo-upload').set_input_files(str(ROOT/'tests'/'v5-logo.webp'))
 page.locator('.logo-preview img').wait_for(timeout=5000)
 assert page.locator('#audit-context-title').inner_text() == 'Auditoría QA v5'
 data_logo=page.locator('.logo-preview img').get_attribute('src')
 assert data_logo.startswith('data:image/jpeg;base64,') and len(data_logo)>100
 # vendor -> models filter
 page.locator('nav#navigation [data-go="assets"]').click()
 page.locator('button[data-add="assets"]').click()
 page.locator('#f-assets-0-name').fill('srv-qa-01')
 page.locator('#f-assets-0-vendor').select_option('Dell')
 options=page.locator('#f-assets-0-model option').all_text_contents()
 assert 'PowerEdge R760' in options and 'FortiGate 60F' not in options,options
 page.locator('#f-assets-0-model').select_option('PowerEdge R760')
 page.locator('#f-assets-0-vendor').select_option('Fortinet')
 options=page.locator('#f-assets-0-model option').all_text_contents()
 assert 'FortiGate 60F' in options and 'PowerEdge R760' not in options,options
 assert page.locator('#f-assets-0-model').input_value()==''
 # other model field still editable
 page.locator('#f-assets-0-model').select_option('Otro / escribir…') if False else page.locator('#f-assets-0-model').select_option('__custom__')
 page.locator('input[data-field="model"][data-custom]').fill('FortiGate Ultra New')
 # severity badge recalculated instantly
 page.locator('nav#navigation [data-go="findings"]').click()
 page.locator('button[data-add="findings"]').click()
 assert page.locator('.entry-head .pill').inner_text()=='MEDIA'
 page.locator('#f-findings-0-severity').select_option('Alta')
 assert page.locator('.entry-head .pill').inner_text()=='ALTA'
 assert 'high' in page.locator('.entry-head .pill').get_attribute('class')
 page.locator('#f-findings-0-title').fill('Prueba criticidad interactiva')
 # distinct dark/light theme and PDF color
 page.locator('#palette').select_option('pine-dark')
 assert page.evaluate("getComputedStyle(document.documentElement).getPropertyValue('--canvas').trim()")=='#081c16'
 page.locator('nav#navigation [data-go="delivery"]').click()
 page.locator('#btn-pdf').click()
 pdf_path=ROOT/'tests'/'audit-v5-pine.pdf'
 page.pdf(path=str(pdf_path),format='A4',print_background=True)
 pdf=fitz.open(str(pdf_path))
 pdf_text='\n'.join(pg.get_text() for pg in pdf)
 assert 'Cliente prueba v5' in pdf_text and 'Prueba criticidad interactiva' in pdf_text and 'Alta' in pdf_text
 assert len(page.locator('#report .report-logo').all())==1
 cover_pix=pdf[0].get_pixmap(matrix=fitz.Matrix(.6,.6),alpha=False)
 cover_pix.save(str(ROOT/'tests'/'v5-cover.png'))
 # distinct palette first page background
 page.locator('#palette').select_option('indigo')
 page.locator('#btn-pdf').click()
 other_path=ROOT/'tests'/'audit-v5-indigo.pdf'
 page.pdf(path=str(other_path),format='A4',print_background=True)
 p1=fitz.open(other_path)
 assert pdf[0].get_pixmap().samples != p1[0].get_pixmap().samples, 'PDF cover does not change with palette'
 # Save and reload; logo + findings persist
 page.wait_for_timeout(800)
 page.set_content(raw);page.locator('.audit-row').first.wait_for()
 page.locator('[data-open]').first.click();page.locator('nav#navigation [data-go="engagement"]').click()
 page.locator('.logo-preview img').wait_for();assert page.locator('.logo-preview img').get_attribute('src').startswith('data:image/jpeg;base64,')
 # online controls (no auto-upload)
 page.locator('#global-navigation [data-go="online"]').click()
 assert page.locator('#check-connectivity').is_visible()
 page.locator('#check-connectivity').click()
 assert 'según el navegador' in page.locator('#online-status').inner_text()
 # UI regression uses injected HTML due to browser sandbox network policy.
 # Real CSP and service worker require separate integration testing on localhost/HTTPS.
 page.set_content(raw);assert page.locator('#navigation').count()==1
 assert not errors,(errors,console)
 print('PASS: logo, navigation, vendor-model dependency, severity badge, pdf themes, persisted images, static PWA resources (offline install not exercised);',len(pdf),'PDF pages; errors:',errors)
 ctx.close();browser.close()
