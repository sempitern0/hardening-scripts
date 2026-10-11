"""UI smoke: member identity, attribution, print layout, responsive spacing."""
from pathlib import Path
from playwright.sync_api import sync_playwright
import fitz
ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text()
html='\n'.join(line for line in html.splitlines() if 'Content-Security-Policy' not in line)
for name in ['normalize.css','styles.css','team.css','fonts/atkinson.css']:
    html=html.replace(f'<link rel="stylesheet" href="{name}">',f'<style>{(ROOT/name).read_text()}</style>')
shim='''<script>
window.testAuditStore=window.testAuditStore||new Map();
Object.defineProperty(window,'indexedDB',{configurable:true,value:null});
Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>window.testAuditStore.get(k)||null,setItem:(k,v)=>window.testAuditStore.set(k,String(v)),removeItem:k=>window.testAuditStore.delete(k)}});
</script>'''
html=html.replace('<script src="app.js" defer></script>',shim+'<script>'+ (ROOT/'app.js').read_text()+'</script>')
with sync_playwright() as playwright:
    browser=playwright.chromium.launch(headless=True, executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-extensions'])
    page=browser.new_page(viewport={'width':1280,'height':900},accept_downloads=True)
    page_errors=[]
    dialogs=[]
    page.on('pageerror',lambda error:page_errors.append(str(error)))
    page.on('dialog',lambda d:(dialogs.append(d.message),d.accept()))
    page.set_content(html)
    page.locator('[data-go="settings"]').first.click()
    page.locator('#member-add').click()
    name=page.locator('[data-member-field="name"]').first
    name.fill('María Pérez')
    document=page.locator('[data-member-field="documentId"]').first
    kind=page.locator('[data-member-field="idType"]').first
    assert kind.input_value()=='DNI'
    document.fill('12345678A')
    assert document.get_attribute('aria-invalid')=='true'
    assert 'DNI/NIF no válido' in page.locator('.member-card .field-error').first.inner_text()
    document.fill('12345678Z')
    assert document.get_attribute('aria-invalid')=='false', page.locator('.member-card .field-error').first.inner_text()
    page.locator('#member-add').click()
    page.locator('[data-member-field="name"]').nth(1).fill('Alberto Martín')
    page.locator('[data-member-field="idType"]').nth(1).select_option('NIE')
    doc2=page.locator('[data-member-field="documentId"]').nth(1)
    doc2.fill('X1234567L')
    assert doc2.get_attribute('aria-invalid')=='false'
    page.locator('#member-add').click()
    page.locator('[data-member-field="name"]').nth(2).fill('Lina Foster')
    page.locator('[data-member-field="idType"]').nth(2).select_option('Pasaporte / otro')
    doc3=page.locator('[data-member-field="documentId"]').nth(2)
    doc3.fill('abc-12345')
    assert doc3.get_attribute('aria-invalid')=='false'
    page.locator('#member-add').click()
    page.locator('[data-member-field="name"]').nth(3).fill('Sin documento')
    for width in (1280,820,390):
        page.set_viewport_size({'width':width,'height':900})
        page.wait_for_timeout(70)
        widths=page.evaluate('''() => ({doc:document.documentElement.scrollWidth, inner:innerWidth,
          fields:getComputedStyle(document.querySelector('.member-card .fields')).gridTemplateColumns,
          gaps:getComputedStyle(document.querySelector('.member-card .fields')).rowGap})''')
        assert widths['doc']<=width+2,(width,widths)
        assert float(widths['gaps'].replace('px',''))>=18,(width,widths)
        print('Viewport',width,widths)
    page.set_viewport_size({'width':1280,'height':900})
    page.locator('[data-go="records"]').first.click()
    page.locator('[data-new]').click()
    page.locator('[data-auditor-select]').nth(0).check()
    page.locator('[data-auditor-select]').nth(1).check()
    page.locator('[data-auditor-select]').nth(2).check()
    page.locator('[data-auditor-select]').nth(3).click()
    assert not page.locator('[data-auditor-select]').nth(3).is_checked()
    assert any('identificador personal es obligatorio' in message for message in dialogs)
    page.wait_for_timeout(1000)
    records=page.evaluate("JSON.parse(localStorage.getItem('sysadmin-tools:audit-workbench:records:v3')||'[]')")
    assert len(records)==1
    team=records[0]['audit']['meta']['auditTeam']
    assert [x['idType'] for x in team]==['DNI','NIE','Pasaporte / otro'],team
    assert [x['documentId'] for x in team]==['12345678Z','X1234567L','ABC12345'],team
    page.locator('#btn-pdf').click()
    pdf=page.pdf(format='A4',print_background=True)
    document=fitz.open(stream=pdf,filetype='pdf')
    alltext=' '.join(p.get_text() for p in document)
    assert '12345678Z' in alltext and 'X1234567L' in alltext and 'ABC12345' in alltext
    print('PDF validated',len(document),'pages')
    # Editing the consultancy profile does not rewrite an old report's author snapshot.
    page.locator('[data-go="settings"]').first.click()
    page.locator('[data-member-field="documentId"]').first.fill('00000000T')
    page.locator('[data-go="engagement"]:visible').first.click()
    page.locator('#btn-pdf').click()
    modified=page.pdf(format='A4',print_background=True)
    old_text=' '.join(p.get_text() for p in fitz.open(stream=modified,filetype='pdf'))
    assert '12345678Z' in old_text and '00000000T' not in old_text
    assert not page_errors,page_errors
    print('PASS: identity, PDF, immutable attribution, responsive layout. Dialogs',len(dialogs))
    browser.close()
