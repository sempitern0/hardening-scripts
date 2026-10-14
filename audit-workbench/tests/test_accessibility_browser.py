"""Real-browser accessibility and PDF navigation smoke test (Playwright/Chromium)."""
from contextlib import contextmanager
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]


@contextmanager
def serve():
    httpd = ThreadingHTTPServer(('127.0.0.1', 0), partial(SimpleHTTPRequestHandler, directory=str(ROOT)))
    thread = Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f'http://127.0.0.1:{httpd.server_port}/'
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=3)


with serve() as url, sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True, executable_path='/usr/bin/chromium', args=['--no-sandbox'])
    for width in (1280, 390):
        context = browser.new_context(viewport={'width': width, 'height': 900}, reduced_motion='reduce')
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(url, wait_until='networkidle')
        page.locator('[data-new]').first.click()
        page.locator('#btn-pdf').click()
        assert page.locator('#delivery-options-title').is_visible()
        assert page.evaluate('document.activeElement.id') == 'delivery-options-title'
        assert page.locator('#delivery-options-title').evaluate('(el) => { const y=el.getBoundingClientRect().top; return y>=0 && y<100; }'), 'PDF choices not scrolled into view'
        assert page.locator('#delivery-executive-draft').is_visible()
        assert page.locator('#delivery-technical-draft').is_visible()
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 2'), 'Horizontal overflow'
        page.evaluate('window.print = () => { window.__printed = (window.__printed || 0) + 1; }')
        page.locator('#delivery-executive-draft').click()
        assert page.evaluate('window.__printed') == 1, 'Draft PDF action no longer opens print'
        assert not errors, errors
        context.close()
    browser.close()
    print('PASS PDF navigation and print action: desktop and mobile')
