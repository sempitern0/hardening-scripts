/* Offline exporter smoke test: node audit-workbench/tests/test_exports.cjs */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {TextEncoder} = require('node:util');
const sandbox = {TextEncoder, Blob};
sandbox.globalThis = sandbox;
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../exporters.js'), 'utf8'), sandbox);
const sample = {
  meta: {client: 'Ámbito SA', reportId:'AUD-001', project: 'Auditoría TI'},
  assets: [{name:'srv-001', vendor:'Dell'}], networks:[],software:[],cves:[],controls:[],
  findings:[{id:'AUD-001',title:'=HYPERLINK("https://invalid.example/","click")',severity:'Alta'}],evidence:[]
};
const tables = sandbox.AuditTabular.sections(sample);
assert.equal(tables.length, 8);
assert.deepEqual(tables.map(t=>t.name).join(','),'Resumen,Hardware,Redes,Software,CVE,Controles,Hallazgos,Evidencias');
const csv = sandbox.AuditTabular.csv(tables.find(t=>t.name==='Hallazgos'));
assert.match(csv, /^\ufeff/);
assert.match(csv, /"'=HYPERLINK/);
assert.ok(csv.includes(';'));
(async()=>{
 const book = sandbox.AuditTabular.xlsx(sample);
 const bytes = Buffer.from(await book.arrayBuffer());
 assert.equal(bytes.toString('utf8',0,2),'PK');
 assert.ok(bytes.length > 10000);
 console.log('PASS: CSV UTF-8, formula injection protection, eight-sheet XLSX ZIP:', bytes.length, 'bytes');
})().catch(error=>{console.error(error);process.exitCode=1});
