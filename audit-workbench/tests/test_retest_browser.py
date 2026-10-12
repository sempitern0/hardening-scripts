"""End-to-end reassessment including save/restore and client-facing PDF."""
from pathlib import Path
import re,json
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text()
html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>','',html)
html=re.sub(r'<script[^>]+src="[^"]+"[^>]*></script>','',html)
html=re.sub(r'<link[^>]+rel="stylesheet"[^>]*>','',html)
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
    page=browser.new_page(accept_downloads=True,viewport={'width':900,'height':900})
    errors=[]
    page.on('pageerror',lambda error:errors.append(str(error)))
    page.set_content(html,wait_until='load')
    for css in ('normalize.css','styles.css','team.css','contrast.css','relations.css','templates.css','quality.css','retest.css','comparison.css'):
        page.add_style_tag(content=(ROOT/css).read_text(encoding='utf-8'))
    page.evaluate('''() => {const memory=new Map();Object.defineProperty(window,'indexedDB',{configurable:true,value:undefined});Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>memory.get(k)||null,setItem:(k,v)=>memory.set(k,String(v)),removeItem:k=>memory.delete(k)}});}''')
    for name in ('exporters.js','hardware-catalog.js','audit-relations.js','control-templates.js','audit-quality.js','audit-retest.js','audit-comparison.js','app.js'):
        page.add_script_tag(content=(ROOT/name).read_text(encoding='utf-8'))
    page.locator('[data-new]').first.click()
    for field,val in {'client':'Cliente ejemplo','project':'Reevaluación anual','scope':'Servidores de producción'}.items():
        page.locator(f'[data-block="meta"][data-field="{field}"]').count() or page.locator('#wizard-step-select').select_option('engagement')
        page.locator(f'[data-block="meta"][data-field="{field}"]').fill(val)
    page.locator('#wizard-step-select').select_option('findings')
    page.locator('[data-add="findings"]').click()
    for field,val in {'title':'MFA ausente','verification':'Comprobar MFA para usuario administrador','recommendation':'Habilitar MFA','description':'Sin MFA en cuentas privilegiadas'}.items():
        page.locator(f'[data-block="findings"][data-field="{field}"]').first.fill(val)
    page.locator('[data-block="findings"][data-field="severity"]').first.select_option('Alta')
    page.locator('#wizard-step-select').select_option('followup')
    assert 'Sin reevaluar' in page.locator('.retest-summary').inner_text()
    page.locator('.retest-item details summary').first.click()
    card=page.locator('.retest-item').first
    card.locator('[data-retest-field="result"]').select_option('verified')
    card.locator('[data-retest-field="by"]').fill('Auditor prueba')
    card.locator('[data-retest-field="notes"]').fill('Se verificó acceso y MFA correctamente tras la corrección.')
    page.on('dialog',lambda d:d.accept())
    card.locator('[data-save-retest]').click()
    assert page.locator('.retest-summary div').first.locator('strong').inner_text()=='1'
    assert 'Corrección verificada' in page.locator('.retest-item').inner_text()
    page.wait_for_timeout(550)
    stored=page.evaluate("() => JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3'))[0].audit")
    assert stored['findings'][0]['status']=='Cerrado'
    assert stored['findings'][0]['retests'][0]['result']=='verified'
    assert stored['followupBaseline']['source']=='before-first-retest'
    assert stored['followupBaseline']['findings'][0]['status']=='Abierto'
    assert page.locator('.comparison-summary .comparison-metric').nth(1).locator('strong').inner_text()=='100 %'
    page.locator('.retest-item details summary').first.click()
    card=page.locator('.retest-item').first
    card.locator('[data-retest-field="result"]').select_option('reopened')
    card.locator('[data-retest-field="by"]').fill('Auditor prueba')
    card.locator('[data-retest-field="notes"]').fill('Se retiró la configuración segura y se reabre el hallazgo.')
    card.locator('[data-save-retest]').click()
    assert 'Hallazgo reabierto' in page.locator('.retest-item').inner_text()
    page.wait_for_timeout(600)
    updated=page.evaluate('''() => JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3'))[0].audit''')
    assert updated['findings'][0]['retests'][1]['previousStatus']=='Cerrado'
    assert updated['findings'][0]['status']=='Abierto'
    assert updated['followupBaseline']==stored['followupBaseline']
    assert page.locator('.comparison-summary .comparison-metric').nth(1).locator('strong').inner_text()=='0 %'
    # Use the beforeprint route with the separate reassessment report, and read it.
    page.locator('#retest-pdf').first.click()
    report=page.locator('#report').inner_text()
    assert 'reevaluación' in report and 'MFA ausente' in report, report[:500]
    assert 'Hallazgo reabierto' in report
    assert 'Evolución y decisiones para dirección' in report
    assert 'Correcciones verificadas (referencia)' in report
    assert 'Correcciones verificadas:' in report
    page.locator('#wizard-step-select').select_option('delivery')
    page.locator('#delivery-pdf').click()
    assert 'Plan de remediación' in page.locator('#report').inner_text()
    # Reimportar como expediente independiente, con la cadena de reevaluaciones íntegra.
    page.locator('#input-import').set_input_files(files={'name':'seguimiento.json','mimeType':'application/json','buffer':json.dumps(updated,ensure_ascii=False).encode()})
    page.wait_for_timeout(500)
    page.locator('#wizard-step-select').select_option('followup')
    assert 'Hallazgo reabierto' in page.locator('.retest-item').inner_text()
    assert page.locator('.retest-history li').count()==2
    for width in (390,820,1280):
        page.set_viewport_size({'width':width,'height':850})
        page.locator('#wizard-step-select').select_option('followup')
        assert page.evaluate('document.documentElement.scrollWidth<=window.innerWidth+2'),width
    assert not errors,errors
    browser.close()
    print('PASS reassessment UI, persisted timeline, transitions and both report modes')
