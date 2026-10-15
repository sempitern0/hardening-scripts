"""Print layout regression: browser PDF A4, safe gutters and no browser headers.

Requires Chromium, Playwright and PyMuPDF. This test embeds local code/CSS to
avoid any HTTP dependency; no audit data or secrets are transmitted.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright
import fitz

ROOT = Path(__file__).resolve().parents[1]
html = (ROOT / 'index.html').read_text(encoding='utf-8')
import re
html = re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>', '', html)
html = re.sub(r'<script[^>]+src="[^"]+"[^>]*></script>', '', html)
html = re.sub(r'<link[^>]+rel="stylesheet"[^>]*>', '', html)

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True, executable_path='/usr/bin/chromium',
                                         args=['--no-sandbox', '--disable-extensions'])
    page = browser.new_page(viewport={'width': 1280, 'height': 850})
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('dialog', lambda dialog: dialog.accept())
    page.set_content(html)
    for css in ('css/normalize.css','css/styles.css','css/team.css','css/contrast.css','css/relations.css','css/templates.css','css/quality.css','css/retest.css','css/comparison.css','css/print.css'):
        page.add_style_tag(content=(ROOT/css).read_text(encoding='utf-8'))
    page.evaluate('''() => {const m=new Map();Object.defineProperty(window,'indexedDB',{configurable:true,value:undefined});Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)}});}''')
    for name in ('js/exporters.js','js/hardware-catalog.js','js/software-catalog.js','js/os-catalog.js','js/glossary.js','js/audit-relations.js','js/audit-evidence-images.js','js/audit-identifiers.js','js/control-templates.js','js/field-assist.js','js/audit-quality.js','js/audit-retest.js','js/audit-comparison.js','js/audit-storage.js','js/audit-import-plan.js','js/inventory-import.js','js/input-guidance.js','js/secure-transfer.js','js/secure-transfer-ui.js','js/document-control.js','js/pwa-updates.js','js/offline-health.js','js/app.js'):
        page.add_script_tag(content=(ROOT/name).read_text(encoding='utf-8'))
    page.locator('[data-new]').first.click()
    for selector, value in (
        ('[data-field="client"]', 'Empresa de prueba S.L.'),
        ('[data-field="project"]', 'Auditoría de sistemas y redes'),
    ):
        field = page.locator(selector)
        if field.count(): field.first.fill(value)

    # Place stress content after production report construction (beforeprint).
    page.evaluate('''() => window.addEventListener('beforeprint', () => {
      const section = document.createElement('section');
      section.className = 'report-section';
      section.innerHTML = '<h2>12. Prueba de tablas extensas</h2>' +
        '<table class="report-table"><thead><tr><th>Activo</th><th>Descripción</th><th>Resultado</th></tr></thead><tbody>' +
        Array.from({length: 32}, (_, i) => '<tr><td>Servidor-'+i+'</td><td>' +
          ('Control de acceso verificado con evidencia técnica y política documentada. ').repeat(3) +
          '</td><td>Requiere revisión</td></tr>').join('') + '</tbody></table>';
      document.getElementById('report').appendChild(section);
    })''')
    pdf = page.pdf(prefer_css_page_size=True, print_background=True, display_header_footer=True)
    document = fitz.open(stream=pdf, filetype='pdf')
    assert len(document) >= 7, len(document)
    for number, paper in enumerate(document, 1):
        assert abs(paper.rect.width - 595.28) < 1 and abs(paper.rect.height - 841.89) < 1
        page_text = paper.get_text()
        assert 'Audit Workbench · Auditoría offline' not in page_text, f'Browser title leaked into margin: {number}'
        assert 'localhost:' not in page_text, f'Browser URL leaked into margin: {number}'
        assert 'about:blank' not in page_text, f'Browser URL leaked into margin: {number}'
        assert 'Audit Workbench · Auditoría offline' not in page_text, f'Title leaked into margin: {number}'
        assert 'about:blank' not in page_text, f'Print URL leaked into margin: {number}'
        # Browser-added automatic numbering must also disappear. All metadata belongs on the cover.
        assert not any(word.strip().startswith('http://') or word.strip().startswith('https://') for word in page_text.split()), (number, 'URL leaked')
        for block in paper.get_text('blocks'):
            if not str(block[4]).strip(): continue
            assert block[0] >= 39, (number, 'left', block[0], str(block[4])[:60])
            assert block[1] >= 36, (number, 'top', block[1], str(block[4])[:60])
            assert block[2] <= paper.rect.width - 38, (number, 'right', block[2], str(block[4])[:60])
            assert block[3] <= paper.rect.height - 36, (number, 'bottom', block[3], str(block[4])[:60])
    assert not errors, errors
    print('PASS: A4 print, repeated content gutters, long tables and no browser metadata:', len(document), 'pages')
    browser.close()
