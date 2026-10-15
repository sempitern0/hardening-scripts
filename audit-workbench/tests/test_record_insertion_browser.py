"""Browser smoke test of new-first records and software manufacturer entry."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
server = ThreadingHTTPServer(('127.0.0.1', 0), partial(SimpleHTTPRequestHandler, directory=str(ROOT)))
thread = Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path='/usr/bin/chromium', args=['--no-sandbox'])
        for width in (1280, 390):
            context = browser.new_context(viewport={'width': width, 'height': 820}, reduced_motion='reduce')
            page = context.new_page()
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.goto(f'http://127.0.0.1:{server.server_port}/', wait_until='domcontentloaded')
            page.locator('[data-new]').first.click()
            page.locator('#wizard-step-select').select_option('assets')
            page.locator('[data-add="assets"]').click()
            page.locator('[data-block="assets"][data-field="name"]').first.fill('equipo-antiguo')
            page.locator('[data-add="assets"]').click()
            assert page.locator('[data-block="assets"][data-field="name"]').count() == 2
            assert page.locator('[data-block="assets"][data-field="name"]').first.input_value() == ''
            assert page.locator('[data-block="assets"][data-field="name"]').nth(1).input_value() == 'equipo-antiguo'
            assert page.evaluate("document.activeElement.dataset.field") == 'name'
            assert page.evaluate("document.activeElement.dataset.index") == '0'
            assert page.locator('[data-entry-key]').first.evaluate('(el) => {const r=el.getBoundingClientRect(); return r.top>=0 && r.top<innerHeight;}')
            page.locator('#wizard-step-select').select_option('software')
            page.locator('[data-add="software"]').click()
            publisher = page.locator('select[data-block="software"][data-field="vendor"][data-preset]').first
            assert publisher.locator('option[value="Oracle"]').count() == 1
            assert publisher.locator('option[value="Google"]').count() == 1
            publisher.select_option('Oracle')
            page.locator('[data-add="software"]').click()
            assert page.locator('select[data-block="software"][data-field="vendor"][data-preset]').nth(1).input_value() == 'Oracle'
            publisher = page.locator('select[data-block="software"][data-field="vendor"][data-preset]').first
            publisher.select_option('Google')
            assert publisher.input_value() == 'Google'
            assert not errors, errors
            context.close()
        browser.close()
        print('PASS new-first inventory and software publishers on desktop and mobile')
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=3)
