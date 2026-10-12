"""Persistence regression in a real browser using a private localhost HTTP server.

Requires Playwright and Chromium, intentionally not part of dependency-free CI.
"""
from contextlib import contextmanager
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from playwright.sync_api import sync_playwright, Error as PlaywrightError
import sys

ROOT = Path(__file__).resolve().parents[1]

@contextmanager
def server():
    handler = partial(SimpleHTTPRequestHandler, directory=str(ROOT))
    service = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    worker = Thread(target=service.serve_forever, daemon=True)
    worker.start()
    try:
        yield f'http://localhost:{service.server_port}/'
    finally:
        service.shutdown()
        service.server_close()
        worker.join(timeout=3)

with server() as url, sync_playwright() as driver:
    browser = driver.chromium.launch(headless=True, executable_path='/usr/bin/chromium', args=['--no-sandbox'])
    context = browser.new_context(viewport={'width': 1280, 'height': 900})
    page = context.new_page()
    errors=[]
    page.on('pageerror', lambda err: errors.append(str(err)))
    try:
        page.goto(url, wait_until='networkidle')
    except PlaywrightError as error:
        if 'ERR_BLOCKED_BY_ADMINISTRATOR' in str(error):
            browser.close()
            print('SKIP localhost/browser integration: blocked by sandbox network policy')
            sys.exit(0)
        raise
    assert page.locator('[data-new]').first.is_visible(), 'biblioteca no inicializada'
    page.locator('[data-new]').first.click()
    page.locator('[data-block="meta"][data-field="client"]').fill('Cliente persistencia')
    page.locator('[data-block="meta"][data-field="project"]').fill('Control de ciclo de vida')
    page.wait_for_timeout(650)
    assert 'IndexedDB' in page.locator('#save-status').inner_text(), 'repository should use IndexedDB'
    rows=page.evaluate('''() => new Promise((resolve,reject)=>{
        const request=indexedDB.open('audit-workbench-offline',1);
        request.onsuccess=()=>{
            const tx=request.result.transaction('audits','readonly');
            const q=tx.objectStore('audits').getAll();
            q.onsuccess=()=>resolve(q.result);
            q.onerror=()=>reject(q.error);
        };
        request.onerror=()=>reject(request.error);
    })''')
    assert len(rows)==1 and rows[0]['audit']['meta']['client']=='Cliente persistencia', rows
    page.reload(wait_until='networkidle')
    assert page.locator('input[data-block="meta"][data-field="client"]').input_value()=='Cliente persistencia'
    assert not errors, errors
    # Offline reopening is permitted once the service worker has installed its static cache.
    page.evaluate('navigator.serviceWorker.ready')
    context.set_offline(True)
    page.reload(wait_until='domcontentloaded')
    assert page.locator('input[data-block="meta"][data-field="client"]').input_value()=='Cliente persistencia'
    assert not errors, errors
    browser.close()
    print('PASS Chromium: IndexedDB write/reload, offline PWA reload, no JS errors')
