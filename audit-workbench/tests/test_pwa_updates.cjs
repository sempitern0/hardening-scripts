'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'js/pwa-updates.js'),'utf8');
const app=fs.readFileSync(path.join(root,'js/app.js'),'utf8');
const sw=fs.readFileSync(path.join(root,'sw.js'),'utf8');
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const css=fs.readFileSync(path.join(root,'css/styles.css'),'utf8');
const ctx={navigator:{serviceWorker:{}},location:{protocol:'https:',hostname:'audits.example'},document:{},console};ctx.globalThis=ctx;
vm.runInNewContext(source,ctx);
assert.equal(ctx.AuditPwaUpdates.supported(),true);
ctx.location.protocol='file:';assert.equal(ctx.AuditPwaUpdates.supported(),false);
for(const id of ['pwa-update-notice','pwa-update-status','pwa-update-apply','pwa-update-later','pwa-update-check'])
 assert(html.includes('id="'+id+'"'),id+' missing');
assert(html.indexOf('js/pwa-updates.js')<html.indexOf('js/app.js'));
assert(sw.includes('v41-contextual-fields')&&sw.includes("'./js/pwa-updates.js'"));
assert(sw.includes("event.data?.type!=='AUDIT_WORKBENCH_APPLY_UPDATE'"),'Only explicit activation allowed');
assert(sw.indexOf('await self.skipWaiting()')>sw.indexOf("event.data?.type!=='AUDIT_WORKBENCH_APPLY_UPDATE'"),'Activation must only be in consent handler');
assert(sw.includes('await self.skipWaiting()'),'Consent handler must activate worker');
assert(app.includes('saveBeforeReload:flush')&&app.includes('isSafeToReload'),'Must guard dirty audit');
assert(source.includes("registration.update()")&&source.includes('registration.waiting'));
assert(source.includes("controllerchange")&&source.includes("location.reload()"));
assert(source.includes("credentials")===false,'No credentials should be used for update checks');
assert(css.includes('.pwa-update-notice[hidden]'));
for(const file of ['audit-workbench.sh','audit-workbench.ps1'])
 assert(fs.readFileSync(path.join(root,file),'utf8').includes('js/pwa-updates.js'),'installer missing '+file);
console.log('PASS consent, pre-reload save, offline shell, packaging');
