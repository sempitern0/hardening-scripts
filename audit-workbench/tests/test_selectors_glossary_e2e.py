"""Manual/CI Chromium regression for native pickers and glossary return on localhost."""
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
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
  context=browser.new_context()
  page=context.new_page()
  errors=[]
  page.on('pageerror',lambda exc:errors.append(str(exc)))
  page.goto('http://127.0.0.1:%d/'%server.server_port)
  page.locator('[data-new]').first.click()
  page.locator('#wizard-step-select').select_option('assets')
  page.locator('[data-add="assets"]').click()
  typ=page.locator('select[data-block="assets"][data-field="type"][data-preset]').first
  assert typ.is_visible()
  typ.select_option('Portátil')
  assert typ.input_value()=='Portátil'
  typ.select_option('Estación de trabajo')
  assert typ.input_value()=='Estación de trabajo'
  vendors=page.locator('select[data-block="assets"][data-field="vendor"][data-preset]').first
  vendors.select_option('Dell')
  model=page.locator('select[data-block="assets"][data-field="model"][data-preset]').first
  assert model.locator('option').filter(has_text='Latitude').count()>0
  model.select_option('Latitude 5450')
  assert model.input_value()=='Latitude 5450'
  vendors.select_option('Lenovo')
  model=page.locator('select[data-block="assets"][data-field="model"][data-preset]').first
  assert model.locator('option').filter(has_text='ThinkPad').count()>0
  model.select_option('__custom__')
  custom=page.locator('input[data-block="assets"][data-field="model"][data-custom]').first
  assert custom.is_visible()
  custom.fill('Modelo corporativo no catalogado')
  custom.dispatch_event('change')
  page.locator('#wizard-step-select').select_option('networks')
  page.locator('[data-add="networks"]').click()
  cidr=page.locator('input[data-block="networks"][data-field="cidr"]').first
  info=page.locator('.field').filter(has=cidr).locator('button.glossary-help')
  assert info.count()==1
  assert page.locator('.field-heading > button.glossary-help').count()>0
  info.click()
  assert page.locator('.glossary-article').is_visible()
  page.locator('[data-glossary-back]').first.click()
  assert cidr.is_visible()
  assert page.locator('input[data-block="networks"][data-field="cidr"]').first.evaluate('(el)=>document.activeElement===el')
  assert not errors,errors
  browser.close()
finally:
 server.shutdown()
