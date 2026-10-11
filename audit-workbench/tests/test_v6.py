from pathlib import Path
from playwright.sync_api import sync_playwright
from PIL import Image
import fitz
root=Path(__file__).resolve().parents[1]
raw=root.joinpath('index.html').read_text()
raw='\n'.join(l for l in raw.splitlines() if 'Content-Security-Policy' not in l)
for name in ['normalize.css','styles.css']:
 raw=raw.replace(f'<link rel="stylesheet" href="{name}">','<style>'+root.joinpath(name).read_text()+'</style>')
pre="""<script>window.auditStorage = window.auditStorage || new Map();Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>window.auditStorage.get(k)||null,setItem:(k,v)=>window.auditStorage.set(k,String(v)),removeItem:k=>window.auditStorage.delete(k)}});Object.defineProperty(window,'indexedDB',{configurable:true,value:null});</script>"""
raw=raw.replace('<script src="app.js" defer></script>',pre+'<script>'+root.joinpath('app.js').read_text()+'</script>')
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':1440,'height':900},accept_downloads=True)
 errors=[];console=[];dialog=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.on('console',lambda m:console.append(m.text) if m.type=='error' else None)
 page.on('dialog',lambda d:(dialog.append(d.message),d.accept()))
 page.set_content(raw);page.locator('[data-go="settings"]').first.click()
 assert page.locator('h1').first.inner_text()=='Configuración de la consultora'
 page.locator('#f-settings-main-company').fill('Bosques Security SL')
 page.locator('#f-settings-main-taxId').fill('B12345670')
 assert page.locator('#f-settings-main-taxId').get_attribute('aria-invalid')=='true'
 page.locator('#f-settings-main-taxId').fill('B12345674')
 assert page.locator('#f-settings-main-taxId').get_attribute('aria-invalid')=='false'
 page.locator('#f-settings-main-auditor').fill('Auditora Ejemplo')
 img=Image.new('RGB',(160,100),(20,66,80));img.save(root/'tests'/'logo-test-v6.png')
 page.locator('#settings-logo-upload').set_input_files(str(root/'tests'/'logo-test-v6.png'))
 page.locator('.logo-preview img').wait_for()
 print('logo saved settings',page.locator('.logo-preview img').count())
 page.locator('[data-go="records"]').first.click()
 page.locator('[data-new]').first.click()
 assert page.locator('#navigation').is_hidden()
 assert page.locator('.wizard-controls').is_visible()
 assert page.locator('#main-audit-context').is_visible()
 assert page.locator('#f-meta-main-auditor').input_value()=='Auditora Ejemplo'
 assert page.locator('.logo-preview img').is_visible()
 page.locator('#f-meta-main-client').fill('Cliente CIP');page.locator('#f-meta-main-client').blur()
 id1=page.locator('#f-meta-main-reportId').input_value();print('new report ID',id1)
 assert id1=='AUD-001',id1
 page.locator('#f-meta-main-clientIdType').select_option('NIF entidad / CIF')
 page.locator('#f-meta-main-clientTaxId').fill('B12345670')
 assert page.locator('#f-meta-main-clientTaxId').get_attribute('aria-invalid')=='true'
 page.locator('#f-meta-main-clientTaxId').fill('B12345674')
 assert page.locator('#f-meta-main-clientTaxId').get_attribute('aria-invalid')=='false'
 page.locator('#wizard-step-select').select_option('assets')
 page.locator('[data-add="assets"]').click()
 page.locator('#f-assets-0-vendor').select_option('Dell')
 assert 'PowerEdge R760' in page.locator('#f-assets-0-model option').all_text_contents()
 page.locator('.wizard-buttons [data-go="networks"]').click()
 assert 'Infraestructura de red' in page.locator('h1').first.inner_text()
 page.locator('#palette').select_option('amethyst-dark')
 page.locator('#btn-pdf').click()
 path=Path('/tmp/audit-workbench-v6-smoke.pdf')
 page.pdf(path=str(path),format='A4',print_background=True)
 pdf=fitz.open(str(path));txt='\n'.join(pg.get_text() for pg in pdf)
 assert 'Cliente CIP' in txt and 'B12345674' in txt and 'Auditora Ejemplo' in txt
 assert page.locator('#report .report-logo').count()==1
 pdf[0].get_pixmap(matrix=fitz.Matrix(.5,.5)).save('/tmp/audit-workbench-v6-cover.png')
 page.locator('[data-go="records"]').first.click();page.locator('[data-new]').first.click()
 page.locator('#f-meta-main-client').fill('Cliente CIP');page.locator('#f-meta-main-client').blur()
 id2=page.locator('#f-meta-main-reportId').input_value();print('second report ID',id2)
 assert id2=='AUD-002',id2
 page.locator('[data-go="connections"]').first.click()
 assert page.locator('h1').first.inner_text()=='Conexiones y entrega'
 assert page.locator('#dav-save').is_visible()
 page.locator('input[name=channel][value=email]').check()
 assert page.locator('#connection-email').is_visible() and page.locator('#connection-nextcloud').is_hidden()
 page.locator('input[name=channel][value=share]').check()
 assert page.locator('#connection-share').is_visible() and page.locator('#connection-upload').is_hidden()
 print('error messages',errors,'console errors',console[:8])
 assert not errors,errors
 page.set_viewport_size({'width':768,'height':1024});page.locator('[data-go="records"]').first.click();page.locator('[data-open]').first.click();page.screenshot(path='/tmp/audit-workbench-v6-tablet.png')
 print('PASS: settings, NIF, customer sequences, navigation, logo, PDF, etc; PDF pages',len(pdf))
 browser.close()
