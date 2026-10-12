'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { join } = require('node:path');
const root = join(__dirname, '..');
const ctx = { window: {} };
vm.runInNewContext(fs.readFileSync(join(root,'js/hardware-catalog.js'),'utf8'),ctx);
const cat = ctx.window.AuditHardwareCatalog;
assert(Object.keys(cat).length >= 35);
assert(Object.values(cat).reduce((n,models)=>n+models.length,0) >= 400);
for(const [brand, models] of Object.entries(cat)) {
  assert(models.length > 0,brand);
  assert.equal(new Set(models).size,models.length,`Duplicated models for ${brand}`);
  assert(models.every(x=>typeof x==='string' && x.length > 1),brand);
}
assert(cat.Dell.includes('PowerEdge R770'));
assert(!cat.Dell.includes('FortiGate 60F'));
assert(cat.Fortinet.includes('FortiGate 60F'));
assert(!cat.Fortinet.includes('PowerEdge R770'));
assert(cat.Synology.includes('DS925+'));
const html=fs.readFileSync(join(root,'index.html'),'utf8');
assert(html.indexOf('js/hardware-catalog.js') < html.indexOf('app.js'));
assert(html.includes('css/contrast.css'));
const sw=fs.readFileSync(join(root,'sw.js'),'utf8');
assert(sw.includes('js/hardware-catalog.js') && sw.includes('css/contrast.css'));
const css=fs.readFileSync(join(root,'css/contrast.css'),'utf8');
assert(css.includes('@media print') && css.includes('--aw-field-bg'));
console.log(`${Object.keys(cat).length} fabricantes, ${Object.values(cat).reduce((n,x)=>n+x.length,0)} modelos; configuración coherente.`);
