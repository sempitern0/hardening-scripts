'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const app=fs.readFileSync(path.join(root,'js/app.js'),'utf8');
const storage=fs.readFileSync(path.join(root,'js/audit-storage.js'),'utf8');
assert(app.includes('const VERSION = 3;'),'Single active audit schema required');
assert(app.includes('raw.schemaVersion!==VERSION'),'Strict individual JSON version checking required');
assert(app.includes('kind:LIBRARY_KIND,schemaVersion:VERSION'),'Full backup needs current canonical format');
assert(app.includes('input?.kind===LIBRARY_KIND')&&app.includes('input.schemaVersion!==VERSION'));
assert(app.includes('kind:PROFILE_KIND,schemaVersion:VERSION'),'Consultancy profile needs canonical format');
assert(app.includes('raw?.kind!==PROFILE_KIND||raw.schemaVersion!==VERSION'));
for(const legacy of ['LEGACY_STORE','nextReportId(','clientKey(','settings.sequences','reportAuto','auditWorkbenchBackup','audit-workbench-consultancy-v1','audit-workbench-consultancy-v2'])
 assert(!app.includes(legacy),'Obsolete compatibility branch: '+legacy);
assert(storage.includes('indexedDB'),'Offline local storage must remain available');
assert(app.includes('if(!Array.isArray(raw[block])||raw[block].length>LIMIT_ROWS)'),'Collections must validate');
assert(!app.includes("if(block==='cves' && raw[block]===undefined)"),'CVE should be part of the canonical audit');
assert(!app.includes("if(block==='legal')continue"),'Legal section should be part of the canonical audit');
console.log('PASS single current audit JSON schema, full backup and consultancy formats');
