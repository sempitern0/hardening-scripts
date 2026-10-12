'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const sw = fs.readFileSync(path.join(root, 'sw.js'), 'utf8');
const bash = fs.readFileSync(path.join(root, 'audit-workbench.sh'), 'utf8');
const ps = fs.readFileSync(path.join(root, 'audit-workbench.ps1'), 'utf8');
for (const name of ['audit-storage.js', 'audit-relations.js', 'audit-quality.js', 'audit-retest.js', 'audit-comparison.js']) {
  assert(html.includes(`src="${name}"`), `${name} missing from HTML`);
  assert(sw.includes(`./${name}`), `${name} missing from PWA cache`);
  assert(bash.includes(name), `${name} missing from Bash installer`);
  assert(ps.includes(name), `${name} missing from PowerShell installer`);
  assert(fs.statSync(path.join(root,name)).size>0, `${name} missing from repository`);
}
assert(html.indexOf('audit-storage.js') < html.indexOf('src="app.js"'), 'storage must precede application');
const css=html.matchAll(/<link\s+[^>]*href="([^"]+\.css)"/g);
for (const [,asset] of css)assert(fs.existsSync(path.join(root,asset)), `CSS resource unavailable: ${asset}`);
console.log('PASS PWA / HTML / installers reference the same local modules');
