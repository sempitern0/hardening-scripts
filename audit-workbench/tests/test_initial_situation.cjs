'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const app=fs.readFileSync(path.join(root,'js/app.js'),'utf8');
const importJs=fs.readFileSync(path.join(root,'js/inventory-import.js'),'utf8');
const exportsJs=fs.readFileSync(path.join(root,'js/exporters.js'),'utf8');
const templatesJs=fs.readFileSync(path.join(root,'js/control-templates.js'),'utf8');
const css=fs.readFileSync(path.join(root,'css/workspace-ux.css'),'utf8');
const fields={assets:['osLicense','osUpdates','avRealtime','avUpdated','cpuSpeed','ramMax','ramSlots','diskCapacity','diskType','gpuType','ethernetPort','cableCategory','ethernetSpeed','wifiSignal','adminAccounts'],networks:['ssid','wifiSecurity','wifiSignal','wifiChannel','wifiStandard','wifiBand','contractedRate','measuredRate'],software:['licenseType','licenseStatus','installedAt','updateStatus','updatedAt']};
for(const [block,columns] of Object.entries(fields)){
 for(const field of columns){
  assert(app.includes('"'+field+'"'),'App must persist '+block+'.'+field);
  assert(importJs.includes("'"+field+"'"),'Inventory intake must recognize '+field);
  assert(exportsJs.includes("'"+field+"'"),'Tabular export must include '+field);
 }
}
assert(app.includes('renderInventoryFieldGroups(r,block,i)'),'Optional sections grouped per row');
assert(app.includes("!baselineFieldSet[k]?.has(name)||str(row[name]).trim()"),'Empty expanded fields should not clutter PDF');
assert(css.includes('.inventory-baseline > summary'),'Accessible expandable controls');
const sandbox={TextEncoder};sandbox.globalThis=sandbox;
vm.runInNewContext(importJs,sandbox);
const reader=sandbox.AuditInventoryImport;
const sample={kind:reader.KIND,schemaVersion:1,source:{platform:'Windows'},items:{assets:[{name:'desktop-01',avRealtime:'Activada',ramMax:'64',diskType:'SSD M.2 NVMe'}],networks:[],software:[]}};
const parsed=reader.parse(JSON.stringify(sample),{block:'assets'});
assert.equal(parsed.rows[0].avRealtime,'Activada');
assert.equal(parsed.rows[0].ramMax,'64');
assert.equal(parsed.rows[0].diskType,'SSD M.2 NVMe');
const libEnv={};libEnv.globalThis=libEnv;vm.runInNewContext(templatesJs,libEnv);
const pack=libEnv.AuditControlTemplates.getPack('baseline');
assert.equal(pack.controls.length,14);
let num=0;const rows=libEnv.AuditControlTemplates.prepare([],'baseline',pack.controls.map(x=>x.id),()=>String(++num),()=>('CTRL-'+num));
assert.equal(rows.length,14);
assert(rows.every(c=>c.status==='Pendiente'));
console.log('PASS initial situation: optional inventory, import, export, PDFs and 14 pending controls');
