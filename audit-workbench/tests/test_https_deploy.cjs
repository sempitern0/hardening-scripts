'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const docker=read('deploy/Dockerfile'),caddy=read('deploy/Caddyfile'),compose=read('deploy/compose.yaml');
const ignored=read('.dockerignore'),manifest=JSON.parse(read('manifest.webmanifest'));
for(const asset of ['index.html','sw.js','manifest.webmanifest','css/','js/','fonts/','icons/'])
 assert(docker.includes(asset),'Expected PWA resource in Dockerfile: '+asset);
for(const forbidden of ['discovery/','collect-local.sh','collect-local.ps1','tests/','README_ES.md'])
 assert(!docker.includes('COPY '+forbidden),'Must never expose '+forbidden);
assert(ignored.includes('**')&&ignored.includes('!deploy/Caddyfile'),'Allowlisted build context required.');
assert(docker.includes('USER 10001:10001'),'Non-root runtime required.');
assert(compose.includes('read_only: true')&&compose.includes('no-new-privileges:true'),'Container hardening required.');
assert(compose.includes('caddy_data:/data'),'ACME certificate volume must persist.');
assert(compose.includes('80:8080')&&compose.includes('443:8443'),'Public certificate challenge ports required.');
assert(caddy.includes('admin off'),'Admin API disabled.');
assert(caddy.includes('file_server')&&!caddy.includes('try_files'),'No HTML catch-all allowed.');
for(const value of ['Strict-Transport-Security','X-Frame-Options','Content-Security-Policy','X-Content-Type-Options','/sw.js','/manifest.webmanifest','no-store'])
 assert(caddy.includes(value),'Missing security/caching directive '+value);
assert(manifest.start_url.startsWith('./')&&manifest.scope==='./');
assert(fs.existsSync(path.join(root,'deploy/smoke_https.py')),'HTTPS post-deploy smoke test missing.');
console.log('PASS deployment: static PWA only, HTTPS, TLS storage, security and caching');
