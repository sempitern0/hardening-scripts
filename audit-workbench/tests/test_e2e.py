from pathlib import Path
from playwright.sync_api import sync_playwright
import json, fitz
root=Path(__file__).resolve().parents[1]
html=(root/'index.html').read_text()
html='\n'.join(l for l in html.splitlines() if 'Content-Security-Policy' not in l)
html=html.replace('<link rel="stylesheet" href="styles.css">','<style>'+(root/'styles.css').read_text()+'</style>')
mock="""<script>
window.auditStorage = new Map();
Object.defineProperty(window,'localStorage',{value:{
 getItem:k=>window.auditStorage.get(k)||null,
 setItem:(k,v)=>window.auditStorage.set(k,String(v)),
 removeItem:k=>window.auditStorage.delete(k)
}});
Object.defineProperty(window,'indexedDB',{value:null});
</script>"""
html=html.replace('<script src="app.js" defer></script>', mock+'<script>'+(root/'app.js').read_text()+'</script>')
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 page=browser.new_page(accept_downloads=True,viewport={'width':1320,'height':920})
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.set_content(html);page.locator('#navigation button').first.wait_for(timeout=10000)
 page.locator('nav button[data-go="engagement"]').click()
 page.locator('#f-meta-main-client').fill('Alfa Auditorías SL')
 page.locator('#f-meta-main-project').fill('Auditoría de seguridad de red')
 page.locator('nav button[data-go="assets"]').click()
 page.locator('button[data-add="assets"]').click()
 page.locator('#f-assets-0-name').fill('SERVIDOR-PROD-01')
 page.locator('#f-assets-0-type').select_option('Servidor físico')
 page.locator('nav button[data-go="findings"]').click()
 page.locator('button[data-add="findings"]').click()
 page.locator('#f-findings-0-title').fill('Segmentación no adecuada')
 page.locator('#f-findings-0-asset').select_option('SERVIDOR-PROD-01')
 page.locator('nav button[data-go="delivery"]').click()
 page.locator('#f-final-main-executive').fill('Informe ejecutivo Alfa. Riesgos controlados y recomendaciones.')
 page.locator('#palette').select_option('forest')
 page.locator('#open-library').click();page.wait_for_timeout(500)
 assert page.locator('.audit-row').count()==1
 page.locator('[data-new]').click()
 page.locator('#f-meta-main-client').fill('Beta Servicios SL')
 page.locator('#f-meta-main-project').fill('Infraestructura Beta')
 page.locator('#open-library').click();page.wait_for_timeout(500)
 assert page.locator('.audit-row').count()==2
 assert page.evaluate("JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3')).length")==2
 assert page.locator('#palette').input_value()=='forest'
 page.locator('#record-filter').fill('Alfa')
 assert page.locator('.audit-row').count()==1
 page.locator('.audit-row [data-open]').click()
 assert page.locator('.hero h2').inner_text()=='Auditoría de seguridad de red'
 page.locator('nav button[data-go="assets"]').click()
 assert page.locator('#f-assets-0-name').input_value()=='SERVIDOR-PROD-01'
 page.locator('nav button[data-go="findings"]').click()
 assert page.locator('#f-findings-0-title').input_value()=='Segmentación no adecuada'
 page.locator('#btn-pdf').click()
 out=root/'tests'/'audit-e2e.pdf';page.pdf(path=str(out),format='A4',print_background=True)
 pdf=fitz.open(str(out));text=' '.join(pg.get_text() for pg in pdf)
 for v in ['Alfa Auditorías SL','SERVIDOR-PROD-01','Segmentación no adecuada','Informe ejecutivo Alfa']:
  assert v in text,(v,text[:500])
 data=page.evaluate("JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3'))")[0]['audit']
 assert data['schemaVersion']==2 and data['assets'][0]['type']=='Servidor físico'
 page.locator('#open-library').click()
 page.once('dialog',lambda dialog:dialog.accept())
 page.locator('.audit-row').filter(has_text='Infraestructura Beta').locator('[data-delete-record]').click()
 assert page.locator('.audit-row').count()==1
 print('AUDITS',data['meta']['client'],'PDF',len(pdf),'pages','THEME',page.locator('#palette').input_value())
 print('JS errors',errors)
 assert not errors,errors
 browser.close()
