"""Restricted-environment browser smoke test: inline resources in an about:blank fixture.
This verifies form interactions; production localhost/PWA still needs an on-device test.
"""
from pathlib import Path
import re
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text()
html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>','',html)
html=re.sub(r'<script[^>]*src="[^"]+"[^>]*></script>','',html)
html=re.sub(r'<link[^>]+rel="stylesheet"[^>]*>','',html)
errors=[]
with sync_playwright() as p:
    b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
    page=b.new_page(accept_downloads=True)
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.add_init_script('''Object.defineProperty(window,'indexedDB',{value:undefined,configurable:true});
      const entries=new Map(); Object.defineProperty(window,'localStorage',{value:{getItem:k=>entries.get(k)||null,setItem:(k,v)=>entries.set(k,String(v)),removeItem:k=>entries.delete(k)},configurable:true});''')
    page.set_content(html,wait_until='load')
    # init script may not run for set_content; ensure fresh storage explicitly
    page.evaluate('''() => {const records=new Map();Object.defineProperty(window,'indexedDB',{value:undefined,configurable:true});Object.defineProperty(window,'localStorage',{value:{getItem:k=>records.get(k)||null,setItem:(k,v)=>records.set(k,String(v)),removeItem:k=>records.delete(k)},configurable:true}); }''')
    for name in ('hardware-catalog.js','exporters.js','audit-relations.js','control-templates.js','audit-quality.js','audit-retest.js','app.js'):
        page.add_script_tag(content=(ROOT/name).read_text())
    page.wait_for_timeout(400)
    print('PAGE',page.locator('h1').all_text_contents()[:2],'errors',errors)
    page.locator('[data-new]').first.click()
    page.locator('#wizard-step-select').select_option('assets')
    page.locator('[data-add="assets"]').click()
    page.locator('[data-block="assets"][data-field="name"]').last.fill('Servidor prueba')
    page.locator('#wizard-step-select').select_option('controls')
    page.locator('[data-add="controls"]').click()
    page.locator('#wizard-step-select').select_option('findings')
    page.locator('[data-add="findings"]').click()
    page.locator('#wizard-step-select').select_option('evidence')
    page.locator('[data-add="evidence"]').click()
    for kind in ('assets','controls','findings'):
        page.locator(f'[data-add-evidence-link][data-relation-kind="{kind}"]').select_option(index=1)
    assert page.locator('.relation-chip').count()==3,page.locator('.relation-chip').all_text_contents()
    page.locator('#wizard-step-select').select_option('delivery')
    assert page.get_by_text('Revisar trazabilidad').count()==0
    # Report builder is triggered by browser print pipeline, without actually printing.
    page.evaluate('window.dispatchEvent(new Event("beforeprint"))')
    assert 'ACT-001' in page.locator('#report').inner_text()
    assert 'FND-001' in page.locator('#report').inner_text()
    page.locator('#wizard-step-select').select_option('evidence')
    page.locator('.relation-chip').first.click()
    assert page.locator('.relation-chip').count()==2
    assert not errors,errors
    print('PASS DOM: link/unlink entities and report')
    b.close()
