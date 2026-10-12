"""Consultancy team attribution in the browser; all modules are loaded without Internet."""
import json
from pathlib import Path
import re
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text(encoding='utf-8')
html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>','',html)
html=re.sub(r'<script[^>]+src="[^"]+"[^>]*></script>','',html)
html=re.sub(r'<link[^>]+rel="stylesheet"[^>]*>','',html)
with sync_playwright() as driver:
    browser=driver.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    page=browser.new_page(viewport={'width':1280,'height':900},accept_downloads=True)
    errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.set_content(html)
    page.evaluate('''() => {const m=new Map();Object.defineProperty(window,'indexedDB',{configurable:true,value:undefined});Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)}});}''')
    for name in ('js/exporters.js','js/hardware-catalog.js','js/audit-relations.js','js/control-templates.js','js/audit-quality.js','js/audit-retest.js','js/audit-comparison.js','js/audit-storage.js','js/app.js'):
        page.add_script_tag(content=(ROOT/name).read_text(encoding='utf-8'))
    page.locator('[data-go="settings"]').first.click()
    assert page.get_by_role('heading',name='Equipo de auditores').is_visible()
    page.locator('#member-add').click()
    page.locator('[data-member-field="name"]').nth(0).fill('María Pérez')
    page.locator('[data-member-field="documentId"]').nth(0).fill('12345678Z')
    page.locator('[data-member-field="role"]').nth(0).select_option('Responsable de auditoría')
    page.locator('#member-add').click()
    page.locator('[data-member-field="name"]').nth(1).fill('Carlos Bravo')
    page.locator('[data-member-field="documentId"]').nth(1).fill('00000000T')
    page.locator('[data-member-field="role"]').nth(1).select_option('Auditor/a de redes')
    page.locator('[data-go="records"]').first.click()
    page.locator('[data-new]').first.click()
    assert page.locator('[data-auditor-select]').count()==2
    page.locator('[data-auditor-select]').nth(0).check()
    page.locator('[data-auditor-select]').nth(1).check()
    page.wait_for_timeout(650)
    data=page.evaluate("JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3'))[0].audit")
    assert [x['name'] for x in data['meta']['auditTeam']]==['María Pérez','Carlos Bravo']
    assert [x['documentId'] for x in data['meta']['auditTeam']]==['12345678Z','00000000T']
    page.locator('[data-go="settings"]').first.click()
    page.locator('[data-member-field="name"]').first.fill('María Pérez Actualizada')
    page.wait_for_timeout(400)
    page.locator('[data-go="engagement"]:visible').first.click()
    assert 'María Pérez' in page.locator('#workspace').inner_text()
    snapshot=page.evaluate("JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3'))[0].audit.meta.auditTeam")
    assert snapshot[0]['name']=='María Pérez', snapshot
    assert not errors, errors
    browser.close()
    print('PASS consulting team snapshots, identity fields, and browser persistence')
