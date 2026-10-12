"""PDF print validation of the separated follow-up report."""
from pathlib import Path
import fitz,re,tempfile,os
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.getenv('AUDIT_RETEST_PDF_PATH', str(Path(tempfile.gettempdir())/'audit-workbench-followup-test.pdf')))
src=(ROOT/'index.html').read_text(encoding='utf-8')
src=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>','',src)
src=re.sub(r'<link[^>]+rel="stylesheet"[^>]*>','',src)
src=re.sub(r'<script[^>]+src="[^"]+"[^>]*></script>','',src)
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    page=browser.new_page(viewport={'width':1150,'height':870},accept_downloads=True)
    errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
    page.set_content(src,wait_until='load')
    for css in ('normalize.css','styles.css','team.css','contrast.css','relations.css','templates.css','print.css','quality.css','retest.css','comparison.css'):
        page.add_style_tag(content=(ROOT/css).read_text(encoding='utf-8'))
    page.evaluate('''() => {const m=new Map();Object.defineProperty(window,'indexedDB',{configurable:true,value:undefined});Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)}});window.print=()=>{};}''')
    for js in ('exporters.js','hardware-catalog.js','audit-relations.js','control-templates.js','audit-quality.js','audit-retest.js','audit-comparison.js','audit-storage.js','app.js'):
        page.add_script_tag(content=(ROOT/js).read_text(encoding='utf-8'))
    page.locator('[data-new]').first.click()
    page.locator('#wizard-step-select').select_option('engagement')
    page.locator('[data-block="meta"][data-field="client"]').fill('Cliente de ejemplo')
    page.locator('[data-block="meta"][data-field="project"]').fill('Seguimiento de correcciones')
    page.locator('#wizard-step-select').select_option('findings')
    page.locator('[data-add="findings"]').click()
    page.locator('[data-block="findings"][data-field="title"]').fill('Cuentas privilegiadas sin MFA')
    page.locator('[data-block="findings"][data-field="recommendation"]').fill('Habilitar MFA y revocar sesiones previas.')
    page.locator('[data-block="findings"][data-field="verification"]').fill('Acceso de prueba con segundo factor obligatorio')
    page.locator('#wizard-step-select').select_option('followup')
    page.locator('.retest-item summary').click()
    item=page.locator('.retest-item')
    item.locator('[data-retest-field="result"]').select_option('verified')
    item.locator('[data-retest-field="by"]').fill('Auditor externo')
    item.locator('[data-retest-field="notes"]').fill('Acceso de prueba correcto y segundo factor obligatorio.')
    page.on('dialog',lambda d:d.accept())
    item.locator('[data-save-retest]').click()
    page.locator('#retest-pdf').click()
    assert 'Corrección verificada' in page.locator('#report').inner_text()
    pdf=page.pdf(format='A4',print_background=True,prefer_css_page_size=True)
    OUT.write_bytes(pdf)
    assert not errors,errors
    browser.close()
with fitz.open(OUT) as doc:
    contents='\n'.join(page.get_text() for page in doc)
    assert 'reevaluación' in contents.lower(),contents[:350]
    assert 'Cuentas privilegiadas sin MFA' in contents
    assert 'Corrección verificada' in contents
    assert 'Evolución y decisiones para dirección' in contents
    assert 'Correcciones verificadas' in contents
    assert 'Acceso de prueba correcto' in contents
    assert doc.page_count>=2
    for index,page in enumerate(doc):
        assert abs(page.rect.width-595)<1 and abs(page.rect.height-842)<1,(index,page.rect)
        for block in page.get_text('blocks'):
            x0,y0,x1,y1,*_=block
            # Small print/footer can approach margins, but no text may be clipped.
            assert x0>=-1 and x1<=page.rect.width+1,(index,block)
    doc[0].get_pixmap(matrix=fitz.Matrix(1.2,1.2)).save(str(OUT.with_suffix('.png')))
    print(f'PASS reevaluation A4: {doc.page_count} pages, {OUT.stat().st_size} bytes')
