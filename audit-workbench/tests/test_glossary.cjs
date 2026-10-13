'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const root=path.resolve(__dirname,'..');
const env={};env.globalThis=env;
for(const asset of ['os-catalog.js','glossary.js'])vm.runInNewContext(fs.readFileSync(path.join(root,'js',asset),'utf8'),env);
assert(env.AuditOSCatalog.ALL.length>=150);
assert(env.AuditOSCatalog.search('win').length>0);
assert(env.AuditOSCatalog.search('win').every(x=>x.toLowerCase().includes('win')));
assert(env.AuditOSCatalog.ALL.includes('Windows Server 2025 Standard'));
assert(env.AuditGlossary.search('segmentada').some(x=>x.title.includes('Segmentación')));
assert(env.AuditGlossary.TERMS.length>=20);
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const sw=fs.readFileSync(path.join(root,'sw.js'),'utf8');
const bash=fs.readFileSync(path.join(root,'audit-workbench.sh'),'utf8');
const ps=fs.readFileSync(path.join(root,'audit-workbench.ps1'),'utf8');
for(const asset of ['js/os-catalog.js','js/glossary.js','css/glossary.css']){
 assert(html.includes(asset));assert(sw.includes('./'+asset));
 assert(bash.includes(asset));assert(ps.includes(asset));
}
const app=fs.readFileSync(path.join(root,'js/app.js'),'utf8');
assert(app.includes('function renderGlossary()'));
assert(app.includes('datalist'));
assert(app.includes('osCatalog?.ALL'));
assert(html.indexOf('js/os-catalog.js')<html.indexOf('js/app.js'));
console.log('PASS autocomplete + 169 OS variants + glossary + PWA assets');
