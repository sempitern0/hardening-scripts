"""UI regression: guided template -> no conforme -> finding -> evidence link -> JSON roundtrip."""
from pathlib import Path
import re, json
from playwright.sync_api import sync_playwright
ROOT = Path(__file__).resolve().parents[1]
page_html=(ROOT/'index.html').read_text(encoding='utf-8')
page_html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>', '',page_html)
page_html=re.sub(r'<script[^>]+src="[^\"]+"[^>]*></script>', '',page_html)
page_html=re.sub(r'<link[^>]+rel="stylesheet"[^>]*>', '',page_html)
with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
    page=browser.new_page(accept_downloads=True)
    errors=[]
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.set_content(page_html,wait_until='load')
    page.evaluate('''() => {
      const entries=new Map();
      Object.defineProperty(window,'indexedDB',{value:undefined,configurable:true});
      Object.defineProperty(window,'localStorage',{value:{getItem:k=>entries.get(k)||null,setItem:(k,v)=>entries.set(k,String(v)),removeItem:k=>entries.delete(k)},configurable:true});
    }''')
    for file in ('js/exporters.js','js/hardware-catalog.js','js/audit-relations.js','js/control-templates.js','js/audit-quality.js','js/audit-retest.js','js/audit-comparison.js','js/audit-storage.js','js/app.js'):
        page.add_script_tag(content=(ROOT/file).read_text(encoding='utf-8'))
    page.locator('[data-new]').first.click()
    page.locator('#wizard-step-select').select_option('controls')
    assert page.get_by_text('Plantillas de comprobaciones').count()==1
    assert page.locator('#template-pack').input_value()=='systems'
    page.locator('details.template-details summary').click()
    assert page.locator('[data-template-choice]').count()==6
    # Choose two checks, no automatic evaluation of controls.
    page.locator('[data-template-choice]').nth(2).uncheck()
    page.locator('[data-template-choice]').nth(3).uncheck()
    page.locator('[data-template-choice]').nth(4).uncheck()
    page.locator('[data-template-choice]').nth(5).uncheck()
    page.locator('[data-apply-template]').click()
    assert page.locator('[data-block="controls"][data-field="name"]').count()==2
    assert page.locator('[data-block="controls"][data-field="status"]').first.input_value()=='Pendiente'
    assert page.get_by_text('2 comprobaciones añadidas').count()==1
    page.locator('details.template-details summary').click()
    assert page.locator('[data-template-choice]:disabled').count()==2
    page.locator('#template-pack').select_option('networks')
    page.locator('details.template-details summary').click()
    assert page.locator('[data-template-choice]:disabled').count()==0
    # Re-use pre-existing evidence link into a generated finding.
    page.locator('#wizard-step-select').select_option('evidence')
    page.locator('[data-add="evidence"]').click()
    page.locator('[data-block="evidence"][data-field="title"]').first.fill('Captura de revisión')
    page.locator('[data-add-evidence-link][data-relation-kind="controls"]').select_option(index=1)
    page.locator('#wizard-step-select').select_option('controls')
    page.locator('[data-block="controls"][data-field="status"]').first.select_option('No conforme')
    assert page.locator('[data-finding-from-control]').count()==1
    page.locator('[data-finding-from-control]').click()
    assert page.locator('#wizard-step-select').input_value()=='findings'
    assert page.locator('[data-block="findings"][data-field="severity"]').first.input_value()=='Sin evaluar'
    assert page.locator('.finding-origin').count()==1
    page.locator('#wizard-step-select').select_option('evidence')
    assert page.locator('.relation-chip').count()==2
    page.locator('#wizard-step-select').select_option('delivery')
    assert page.get_by_text('Revisar calidad →').count()==1
    page.evaluate('window.dispatchEvent(new Event("beforeprint"))')
    assert 'Control de origen' in page.locator('#report').inner_text()
    page.wait_for_timeout(420)
    exported=page.evaluate("() => JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3'))[0].audit")
    import json
    assert exported['controls'][0]['templateKey']=='systems/SYS-01'
    assert exported['controls'][0]['expectedEvidence']
    assert exported['findings'][0]['originControlKey']==exported['controls'][0]['_key']
    assert exported['evidence'][0]['links']['findings']==[exported['findings'][0]['_key']]
    page.on('dialog',lambda dialog:dialog.accept())
    page.locator('#input-import').set_input_files(files={'name':'audit.json','mimeType':'application/json','buffer':json.dumps(exported).encode('utf-8')})
    page.wait_for_timeout(550)
    page.locator('#wizard-step-select').select_option('controls')
    assert page.locator('[data-block="controls"][data-field="name"]').count()==2
    assert page.locator('[data-block="controls"][data-field="status"]').first.input_value()=='No conforme'
    page.locator('#wizard-step-select').select_option('findings')
    assert page.locator('.finding-origin').count()==1
    assert not errors, errors
    print('PASS: template application, no duplicate, finding and evidence propagated, print')
    browser.close()
