'use strict';
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const html=read('index.html'),sw=read('sw.js'),bash=read('audit-workbench.sh'),ps=read('audit-workbench.ps1');
const scripts=[...html.matchAll(/<script\s+src="([^"]+)"\s+defer><\/script>/g)].map(x=>x[1]);
const styles=[...html.matchAll(/<link\s+[^>]*href="([^"]+\.css)"/g)].map(x=>x[1]);
assert(scripts.length>=9 && styles.length>=10,'Expected all offline modules');
for(const asset of [...scripts,...styles]){
 assert(asset.startsWith('js/')||asset.startsWith('css/'),'Unorganized asset: '+asset);
 assert(fs.statSync(path.join(root,asset)).size>0,'Missing: '+asset);
 assert(sw.includes("'./"+asset+"'"),'PWA resource missing: '+asset);
 assert(bash.includes(asset),'Bash missing: '+asset);
 assert(ps.includes(asset),'PowerShell missing: '+asset);
}
assert(scripts.indexOf('js/audit-storage.js')<scripts.indexOf('js/app.js'));
assert(sw.includes("'./fonts/AtkinsonHyperlegible-Regular.woff2'") || sw.includes("AtkinsonHyperlegible-"));
console.log('PASS organized assets: HTML, SW, Bash, PowerShell');
