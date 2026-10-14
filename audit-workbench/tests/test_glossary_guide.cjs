'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const ctx={};ctx.globalThis=ctx;
vm.runInNewContext(fs.readFileSync(path.join(root,'js/glossary.js'),'utf8'),ctx);
const g=ctx.AuditGlossary;
const app=fs.readFileSync(path.join(root,'js/app.js'),'utf8'),css=fs.readFileSync(path.join(root,'css/glossary.css'),'utf8'),sw=fs.readFileSync(path.join(root,'sw.js'),'utf8');
assert(g.CONTEXT_HELP.fields.networks.cidr==='term-3','CIDR context missing');
assert(g.CONTEXT_HELP.fields.findings.likelihood==='term-81','Risk context mismatch');
assert(g.CONTEXT_HELP.fields.findings.residual==='term-16','Residual risk context mismatch');
assert(g.CONTEXT_HELP.fields.legal.retention==='term-95','Privacy context missing');
assert(!g.CONTEXT_HELP.fields.findings.risk,'Ambiguous risk field should not be linked');
for(const mapping of [...Object.values(g.CONTEXT_HELP.fields),g.CONTEXT_HELP.stages])
 for(const id of Object.values(mapping))assert(g.byId(id),'Contextual link points to unknown term: '+id);
assert(app.includes('data-glossary-back')&&app.includes('glossaryReturn'),'Return navigation missing');
assert(app.includes('glossaryStageHint'),'Step contextual help missing');
assert(g.TERMS.length>=100,'Expected expanded glossary');
assert(g.CATEGORIES.length>=9,'Expected thematic categories');
assert(g.search('red segmentada').some(x=>x.title==='Segmentación de red'),'Synonyms must be searchable');
assert(g.search('2FA').some(x=>x.title==='MFA'),'Common acronym not recognized');
assert(g.search('dns','Redes').some(x=>x.title==='DNS'),'Category filter failed');
assert(g.search('dns','Identidad').every(x=>x.category==='Identidad'));
assert(g.TERMS.every(t=>t.title&&t.description&&t.check&&t.why),'Missing explanatory content');
assert.equal(new Set(g.TERMS.map(x=>x.id)).size,g.TERMS.length,'Duplicate term IDs');

for(const marker of ['glossary-index','glossary-detail','glossary-category','glossary-search','renderGlossaryDetail','data-glossary-select'])assert(app.includes(marker),marker);
assert(css.includes('.glossary-layout')&&css.includes('@media(max-width:760px)'),'Adaptive layout missing');
require('./support/sw-contract.js').assertCached('js/glossary.js');
const incident=g.TERMS.find(t=>t.title==='Respuesta a incidentes');
assert(incident?.help?.phone==='017','INCIBE help must be limited to incident response');
assert(incident.help.officialUrl.startsWith('https://www.incibe.es/'),'INCIBE official help URL');
assert(incident.help.reportUrl.startsWith('https://www.incibe.es/'),'Incident notification URL');
assert(g.TERMS.filter(t=>t.help).length===1,'Assistance should not clutter the rest of the glossary');
assert(g.search('017').some(t=>t.id===incident.id),'Phone number should be searchable');
assert(app.includes('<details class="glossary-help-resource">'),'Assistance must be collapsible');
assert(app.includes('renderGlossaryHelp(t)'),'Help render missing');
assert(g.TERMS.length>=144,'Expected 2026 networking concepts');
for(const id of ['term-136','term-137','term-138','term-139','term-140','term-141','term-142','term-143','term-144']){
 const item=g.byId(id);
 assert(item&&item.category==='Redes'&&item.references?.length,'New network term incomplete: '+id);
 assert(g.GUIDES[id]?.commands?.length>=2,'Missing network diagnostic commands: '+id);
}
assert(g.search('wpa3').some(t=>t.id==='term-137'||t.id==='term-31'),'WPA3 guidance not searchable');
assert(g.search('dhcp snooping').some(t=>t.id==='term-141'),'Switch L2 protection not searchable');
assert(g.search('macsec').some(t=>t.id==='term-144'),'MACsec guidance not searchable');
assert(g.CONTEXT_HELP.fields.networks.exposure==='term-136','Networks context must link current network architecture');
assert(g.TERMS.length>=135,'Expected extended acronyms and standards');
for(const name of ['ISO/IEC 27001','ISO/IEC 27002','ISO 22301','IANA','RFC','NIST CSF','OWASP Top 10'])assert(g.TERMS.some(t=>t.title===name),'Missing standard: '+name);
for(const acronym of ['CVE','CVSS','CWE','CPE'])assert(g.TERMS.find(t=>t.title===acronym)?.fullName,'Missing expanded acronym: '+acronym);
assert(g.search('Common Vulnerabilities and Exposures').some(t=>t.title==='CVE'),'Expanded acronym not indexed');
assert(g.TERMS.some(t=>t.references?.some(r=>r.url.includes('iana.org'))),'Missing official IANA references');
assert(g.GUIDES['term-25'].commands.some(c=>c.platform==='macOS'),'Missing macOS diagnostics');
const requiredIcons=['windows','linux','macos'].map(x=>'icons/os-'+x+'.svg');
const shell=fs.readFileSync(path.join(root,'audit-workbench.sh'),'utf8');
const powershell=fs.readFileSync(path.join(root,'audit-workbench.ps1'),'utf8');
for(const icon of requiredIcons){assert(fs.existsSync(path.join(root,icon)),icon);assert(sw.includes('./'+icon),icon+' PWA');assert(shell.includes(icon),icon+' Bash');assert(powershell.includes(icon),icon+' PowerShell');}
assert(app.includes('glossaryPlatformIcon')&&app.includes('glossary-references'),'Missing icon or link rendering');
assert(Object.keys(g.GUIDES).length>=50,'Expected practical diagnostic guides');
assert(g.GUIDES['term-25'].commands.some(x=>x.command.includes('dig')),'DNS diagnostic missing');
assert(g.search('journalctl').some(x=>x.title==='SIEM'||x.title==='Registro de auditoría'),'Console commands should be searchable');
for(const [id,guide] of Object.entries(g.GUIDES)){
 assert(g.byId(id),'Guide without glossary term');
 assert(guide.symptom&&guide.verify&&guide.interpret,'Incomplete troubleshooting: '+id);
 assert(guide.commands.length,'Missing console alternatives: '+id);
 for(const item of guide.commands)assert(item.platform&&item.command&&item.lookFor,'Incomplete command guidance: '+id);
}
assert(app.includes('renderGlossaryGuide')&&app.includes('data-glossary-copy'),'Diagnostic UI missing');
assert(css.includes('.glossary-command')&&css.includes('.glossary-diagnostic'),'Diagnostic styles missing');
const catalogSource=fs.readFileSync(path.join(root,'js/hardware-catalog.js'),'utf8');
const inventoryCatalog={};inventoryCatalog.window=inventoryCatalog;
require('node:vm').runInNewContext(catalogSource,inventoryCatalog);
const hw=inventoryCatalog.AuditHardwareCatalog;
assert(Object.keys(hw).length>=45,'Not enough hardware vendors for desktop/laptop inventory');
for(const brand of ['Dell','HP','Lenovo','ASUS','Acer','Apple','MSI','Dynabook','Framework','Microsoft'])
 assert(hw[brand]?.length>0,'Missing PC manufacturer: '+brand);
assert(hw.Dell.some(x=>x.includes('Latitude'))&&hw.Lenovo.some(x=>x.includes('ThinkPad')),'Missing laptop families');
assert(app.includes('class="field-heading"')&&app.includes('glossary-help')&&app.includes('<svg viewBox="0 0 24 24"'),'Glossary buttons must be independent SVG controls');
assert(app.includes('backToAudit()')&&app.includes('glossary-inline-back'),'Glossary return shortcut missing');
assert(!app.includes('${html(label)}${help}</label>'),'Help must not be nested inside label');
console.log('PASS offline glossary: concepts, synonyms, filters, contextual guidance');
