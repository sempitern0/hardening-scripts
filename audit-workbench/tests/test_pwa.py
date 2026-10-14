from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
from functools import partial
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]
server=ThreadingHTTPServer(('127.0.0.1',0),partial(SimpleHTTPRequestHandler,directory=str(root)))
Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
  context=browser.new_context(service_workers='allow');page=context.new_page()
  errors=[];page.on('pageerror',lambda error: errors.append(str(error)))
  page.goto('http://127.0.0.1:%d/'%server.server_port)
  page.locator('[data-new]').first.wait_for(timeout=15000)
  page.evaluate("navigator.serviceWorker.ready")
  page.wait_for_function("async () => (await caches.keys()).some(k=>k.includes('shell-v44-single-json'))",timeout=10000)
  context.set_offline(True)
  page.reload(wait_until='domcontentloaded',timeout=15000)
  page.locator('[data-new]').first.wait_for(timeout=10000)
  page.locator('[data-new]').click()
  page.locator('#wizard-step-select').select_option('assets')
  assert page.get_by_text('Inventario de hardware').count()>0
  assert not errors,errors
  print('PWA offline reload PASS',page.title())
  browser.close()
finally: server.shutdown()
