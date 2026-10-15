'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname,'..');
const app = fs.readFileSync(path.join(root,'js/app.js'),'utf8');
const index = fs.readFileSync(path.join(root,'index.html'),'utf8');
const css = fs.readFileSync(path.join(root,'css/workspace-ux.css'),'utf8');
const ctx = {globalThis: {}};
vm.runInNewContext(fs.readFileSync(path.join(root,'js/software-catalog.js'),'utf8'),ctx);
const vendors = Array.from(ctx.globalThis.AuditSoftwareCatalog.PUBLISHERS);
for(const company of ['Oracle','Google','Adobe','Microsoft','Red Hat','SAP','Amazon Web Services (AWS)']){
  assert(vendors.includes(company),'Missing common software publisher '+company);
}
assert.equal(new Set(vendors).size, vendors.length, 'Publishers must be unique');
assert(vendors.every(name=>typeof name==='string'&&name.trim()===name&&name.length>1));
assert(Object.isFrozen(ctx.globalThis.AuditSoftwareCatalog.PUBLISHERS),'Catalog should be read-only');
assert(app.includes("const softwareVendors = globalThis.AuditSoftwareCatalog?.PUBLISHERS || hardwareVendors"));
assert(app.includes("['vendor','Fabricante / editor','picker',softwareVendors]"));
assert(app.includes("['vendor','Fabricante','picker',hardwareVendors]"),'Hardware vendors must stay unchanged');
assert(app.includes('>Otro / escribir…</option>'),'Custom vendor must still be available');
for(const fragment of [
  'state[type].unshift(row);persist();render();focusAddedRecord(row._key)',
  'state[block].unshift(...added)', 'focusAddedRecord(added[0]._key)',
  'state.controls.unshift(...batch)', 'focusAddedRecord(batch[0]._key)',
  'state.findings.unshift(finding)', 'focusAddedRecord(finding._key)',
  'settings.members.unshift(member)',
  "behavior:window.matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth'"
]) assert(app.includes(fragment),'Record insertion or focus broken: '+fragment);
assert(app.includes('data-entry-key='),'Stable record keys needed for focus and relations');
assert(css.includes('.entry { scroll-margin-block-start:'));
assert(index.indexOf('js/software-catalog.js')>index.indexOf('js/hardware-catalog.js'));
assert(index.indexOf('js/software-catalog.js')<index.indexOf('js/app.js'));
for(const name of ['sw.js','audit-workbench.sh','audit-workbench.ps1']){
 const value=fs.readFileSync(path.join(root,name),'utf8');
 assert(value.includes('js/software-catalog.js'),'Distribution missing module: '+name);
}
console.log('PASS new records first, focus management and software publisher catalog');
