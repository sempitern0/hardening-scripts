"""End-to-end regression for consultancy team and per-audit attribution."""
import json
import pathlib
import subprocess
import time
from contextlib import contextmanager
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import threading
from playwright.sync_api import sync_playwright

ROOT=pathlib.Path(__file__).resolve().parents[1]

@contextmanager
def server():
    handler=lambda *args,**kwargs: SimpleHTTPRequestHandler(*args,directory=str(ROOT),**kwargs)
    http=ThreadingHTTPServer(('127.0.0.1',0), handler)
    thread=threading.Thread(target=http.serve_forever, daemon=True)
    thread.start()
    try:yield f'http://127.0.0.1:{http.server_port}/'
    finally:http.shutdown();http.server_close();thread.join(timeout=2)

raw=(ROOT/'index.html').read_text()
raw='\n'.join(line for line in raw.splitlines() if 'Content-Security-Policy' not in line)
for name in ['normalize.css','styles.css','team.css','fonts/atkinson.css']:
    raw=raw.replace('<link rel="stylesheet" href="'+name+'">','<style>'+ (ROOT/name).read_text()+'</style>')
shim="""<script>window.testAuditStore=window.testAuditStore||new Map(); Object.defineProperty(window,'indexedDB',{configurable:true,value:null}); Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>window.testAuditStore.get(k)||null,setItem:(k,v)=>window.testAuditStore.set(k,String(v)),removeItem:k=>window.testAuditStore.delete(k)}});</script>"""
raw=raw.replace('<script src="app.js" defer></script>',shim+'<script>'+ (ROOT/'app.js').read_text()+'</script>')
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-extensions'])
    page=browser.new_page(viewport={'width':1280,'height':920},accept_downloads=True)
    errors=[];warnings=[]
    page.on('pageerror',lambda exc:errors.append(str(exc)))
    page.on('console',lambda m:warnings.append(m.text) if m.type=='error' else None)
    page.on('dialog',lambda d:d.accept())
    page.set_content(raw)
    page.locator('[data-go="settings"]').first.click()
    assert page.get_by_role('heading',name='Equipo de auditores').is_visible()
    page.locator('#f-settings-main-company').fill('Auditoría Íntegra SL')
    page.locator('#member-add').click()
    page.locator('[data-member-field="name"]').nth(0).fill('María Pérez')
    page.locator('[data-member-field="role"]').nth(0).select_option('Responsable de auditoría')
    page.locator('[data-member-field="email"]').nth(0).fill('maria@example.org')
    page.locator('#member-add').click()
    page.locator('[data-member-field="name"]').nth(1).fill('Carlos Bravo')
    page.locator('[data-member-field="role"]').nth(1).select_option('Auditor/a de redes')
    page.locator('[data-go="records"]').first.click()
    page.locator('[data-new]').click()
    assert page.locator('#f-meta-main-auditor').count()==0
    assert page.locator('[data-auditor-select]').count()==2
    page.locator('[data-auditor-select]').nth(0).check()
    page.locator('[data-auditor-select]').nth(1).check()
    page.locator('#f-meta-main-client').fill('Cliente de prueba')
    page.locator('#f-meta-main-client').blur()
    page.wait_for_timeout(800)
    content=page.evaluate("JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3')||'[]')")
    assert len(content)==1,content
    assert [m['name'] for m in content[0]['audit']['meta']['auditTeam']]==['María Pérez','Carlos Bravo']
    page.locator('[data-go="settings"]').first.click()
    page.locator('[data-member-field="name"]').first.fill('María Pérez Actualizada')
    page.locator('[data-member-remove]').nth(1).click()
    page.locator('[data-go="engagement"]:visible').first.click()
    assert page.get_by_text('Profesional archivado en este informe').count()==1
    page.locator('#btn-pdf').click()
    pdf=page.pdf(format='A4',print_background=True)
    import fitz
    doc=fitz.open(stream=pdf,filetype='pdf')
    text=' '.join(pg.get_text() for pg in doc)
    assert 'María Pérez' in text and 'Carlos Bravo' in text
    assert 'María Pérez Actualizada' not in text
    assert 'Responsable de auditoría' in text
    assert 'Auditor/a de redes' in text
    print('PDF',len(doc),'pages; attribution preserved')
    page.set_content(raw)
    page.locator('[data-go="settings"]').first.click()
    assert page.locator('[data-member-field="name"]').count()==1
    assert page.locator('[data-member-field="name"]').first.input_value()=='María Pérez Actualizada'
    print('Fonts',page.evaluate("({regular:document.fonts.check('16px Atkinson Hyperlegible'),bold:document.fonts.check('700 16px Atkinson Hyperlegible')})"))
    assert not errors,errors
    print('Browser JS errors:',errors)
    print('Console errors:',warnings[:10])
    browser.close()
