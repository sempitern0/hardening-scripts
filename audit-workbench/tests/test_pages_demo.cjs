'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const dist=path.resolve(__dirname,'../dist-pages');
const read=p=>fs.readFileSync(path.join(dist,p),'utf8');
const html=read('index.html'),sw=read('sw.js'),app=read('js/app.js');
const profile=read('js/deployment-profile.js'),headers=read('_headers');
assert(profile.includes("profile:'public-demo'")&&!profile.includes("profile:'private-full'"));
assert(html.includes('id="public-demo-banner"'));
assert(html.includes("connect-src 'self';")&&!html.includes("connect-src 'self' https:"));
assert(headers.includes("connect-src 'self';")&&headers.includes("frame-ancestors 'none'"));
assert(headers.includes('/sw.js\n  Cache-Control: no-store'));
assert(sw.includes('audit-workbench-shell-public-'));
assert(sw.includes("'./js/deployment-profile.js'"));
assert(app.includes("const PUBLIC_DEMO = globalThis.AuditDeployment?.profile !== 'private-full'"));
assert(app.includes("if(!PUBLIC_DEMO)globalThis.AuditSecureTransferUI.bind"));
for(const name of ['js/secure-transfer.js','js/secure-transfer-ui.js']){
  assert(!fs.existsSync(path.join(dist,name))&&!html.includes(name)&&!sw.includes("'./"+name+"'"));
}
for(const name of ['deploy','tests','discovery','audit-workbench.ps1','audit-workbench.sh','collect-local.sh','collect-local.ps1']){
  assert(!fs.existsSync(path.join(dist,name)),'Unexpected public resource '+name);
}
for(const m of html.matchAll(/<script src="([^"]+)" defer><\/script>/g)){
  assert(fs.existsSync(path.join(dist,m[1])),'Missing script '+m[1]);
}
for(const m of html.matchAll(/<link[^>]+href="([^"]+\.css)"/g)){
  assert(fs.existsSync(path.join(dist,m[1])),'Missing stylesheet '+m[1]);
}
for(const m of sw.matchAll(/'\.\/([^']+)'/g)){
  assert(fs.existsSync(path.join(dist,m[1]||'index.html')),'Missing offline resource '+m[1]);
}
console.log('PASS: public Pages build contains only local offline application');
