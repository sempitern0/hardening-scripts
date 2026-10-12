"""Offline browser regression for quality gate, navigable findings and client-facing action plan."""
from pathlib import Path
import re, json
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text()
html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>', '', html)
html=re.sub(r'<script[^>]+src="[^"]+"[^>]*></script>', '',html)
html=re.sub(r'<link[^>]+rel="stylesheet"[^>]*>', '',html)
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    page=browser.new_page(accept_downloads=True,viewport={'width':1200,'height':800})
    errors=[]
    page.on('pageerror',lambda err: errors.append(str(err)))
    page.set_content(html,wait_until='load')
    page.evaluate('''() => {const m=new Map();Object.defineProperty(window,'indexedDB',{configurable:true,value:undefined});Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)}});}''')
    for file in ('exporters.js','hardware-catalog.js','audit-relations.js','control-templates.js','audit-quality.js','audit-retest.js','app.js'):
        page.add_script_tag(content=(ROOT/file).read_text(encoding='utf-8'))
    page.locator('[data-new]').first.click()
    page.locator('#wizard-step-select').select_option('quality')
    assert page.get_by_text('Control de calidad',exact=True).count()==1
    assert page.locator('.quality-severity.blocker').count()>=3
    page.locator('[data-quality-section="engagement"]').first.click()
    assert page.locator('#wizard-step-select').input_value()=='engagement'
    page.locator('[data-block="meta"][data-field="client"]').first.fill('Empresa prueba')
    page.locator('[data-block="meta"][data-field="project"]').first.fill('Revisión de red')
    page.locator('[data-block="meta"][data-field="scope"]').first.fill('192.168.1.0/24')
    page.locator('#wizard-step-select').select_option('findings')
    page.locator('[data-add="findings"]').click()
    page.locator('[data-block="findings"][data-field="title"]').first.fill('Permisos excesivos')
    page.locator('[data-block="findings"][data-field="severity"]').first.select_option('Alta')
    page.locator('[data-block="findings"][data-field="recommendation"]').first.fill('Aplicar mínimo privilegio')
    page.locator('[data-block="findings"][data-field="verification"]').first.fill('Validar ACL y prueba de acceso')
    page.locator('#wizard-step-select').select_option('quality')
    assert 'Permisos excesivos' in page.locator('.remediation-list').inner_text()
    page.locator('[data-quality-section="findings"]').first.click()
    assert page.locator('.quality-target').count()==1
    page.locator('#wizard-step-select').select_option('delivery')
    assert 'Aplicar mínimo privilegio' in page.locator('.remediation-list').inner_text()
    page.evaluate('window.dispatchEvent(new Event("beforeprint"))')
    report=page.locator('#report').inner_text()
    assert 'Plan de remediación y comprobación' in report
    assert 'Aplicar mínimo privilegio' in report
    assert 'Validar ACL y prueba de acceso' in report
    assert 'BORRADOR' not in report,report[:200]
    assert not errors,errors
    page.wait_for_timeout(550)
    exported=page.evaluate("() => JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3'))[0].audit")
    assert exported['findings'][0]['verification']=='Validar ACL y prueba de acceso'
    assert exported['schemaVersion']==3
    page.on('dialog',lambda d:d.accept())
    page.locator('#input-import').set_input_files(files={'name':'auditoria.json','mimeType':'application/json','buffer':json.dumps(exported).encode()})
    page.wait_for_timeout(500)
    page.locator('#wizard-step-select').select_option('findings')
    assert page.locator('[data-block="findings"][data-field="verification"]').first.input_value()=='Validar ACL y prueba de acceso'
    print('PASS browser quality, links, action plan, report, JSON roundtrip')
    browser.close()
