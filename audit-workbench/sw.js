/* Audit Workbench: versioned, offline-first app shell. No audit data is stored in CacheStorage. */
'use strict';
const CACHE_NAME='audit-workbench-shell-v51-clean-print';
const CACHE_PREFIX='audit-workbench-shell-';
const OPTIONAL_FONTS = ['Regular','Bold','Italic','BoldItalic'].map(weight => `./fonts/AtkinsonHyperlegible-${weight}.woff2`);
const CORE = [
  './', './index.html', './css/styles.css', './js/app.js', './js/audit-storage.js', './js/audit-import-plan.js',
  './css/normalize.css', './css/team.css', './css/contrast.css', './css/relations.css', './js/audit-relations.js', './js/audit-evidence-images.js', './js/audit-identifiers.js', './css/templates.css', './css/quality.css', './js/field-assist.js', './js/audit-quality.js', './css/retest.css', './js/audit-retest.js', './css/comparison.css', './js/audit-comparison.js', './js/control-templates.js', './css/print.css', './js/exporters.js', './js/hardware-catalog.js', './js/software-catalog.js', './js/os-catalog.js', './js/glossary.js', './js/inventory-import.js', './js/input-guidance.js', './js/secure-transfer.js', './js/secure-transfer-ui.js', './js/document-control.js', './js/pwa-updates.js', './js/offline-health.js', './css/glossary.css', './css/atkinson.css', './css/workspace-ux.css', './manifest.webmanifest', './icons/os-windows.svg', './icons/os-linux.svg', './icons/os-macos.svg', './icons/dragon.svg', './icons/icon-192.png', './icons/icon-512.png'
];
const urlFor=path=>new URL(path,self.registration.scope).href;
const reply=(event,payload)=>{try{event.ports?.[0]?.postMessage(payload)}catch(_ignored){}};
async function shellHealth(){
  const cache=await caches.open(CACHE_NAME);
  const keys=CORE.map(urlFor);
  const available=await Promise.all(keys.map(key=>cache.match(key)));
  const missing=CORE.filter((_,index)=>!available[index]);
  return {
    ok:missing.length===0,version:CACHE_NAME,total:CORE.length,
    cached:CORE.length-missing.length,missing:missing.slice(0,8),
    missingCount:missing.length
  };
}
async function repairMissing(){
  const cache=await caches.open(CACHE_NAME);
  const before=await shellHealth();
  for(const path of CORE){
    const url=urlFor(path);
    if(await cache.match(url))continue;
    // Repair only absent resources; never replace already cached files with a mixed release.
    const response=await fetch(new Request(url,{cache:'reload',credentials:'same-origin'}));
    if(!response.ok||response.type==='opaque'||response.redirected)
      throw Error('No se pudo recuperar '+path+' del servidor original.');
    await cache.put(url,response);
  }
  const after=await shellHealth();
  return {...after,repaired:before.missingCount-after.missingCount};
}
self.addEventListener('message',event=>{
  const type=event.data?.type;
  if(type==='AUDIT_WORKBENCH_APPLY_UPDATE'){
    event.waitUntil((async()=>{
      try{await self.skipWaiting();reply(event,{ok:true})}
      catch(_error){reply(event,{ok:false,reason:'No se pudo activar la actualización.'})}
    })());
  }else if(type==='AUDIT_WORKBENCH_HEALTH'){
    event.waitUntil(shellHealth().then(result=>reply(event,result))
      .catch(_error=>reply(event,{ok:false,error:'No se pudo leer la caché offline.'})));
  }else if(type==='AUDIT_WORKBENCH_REPAIR_SHELL'){
    event.waitUntil(repairMissing().then(result=>reply(event,result))
      .catch(error=>reply(event,{ok:false,error:String(error.message||error)})));
  }
});
self.addEventListener('install',event=>{
  event.waitUntil((async()=>{
    const cache=await caches.open(CACHE_NAME);
    try{
      // Reload bypasses stale HTTP cache. Installation fails unless EVERY essential file exists.
      await cache.addAll(CORE.map(path=>new Request(urlFor(path),{cache:'reload',credentials:'same-origin'})));
      const readiness=await shellHealth();
      if(!readiness.ok)throw Error('La versión offline está incompleta.');
      await Promise.all(OPTIONAL_FONTS.map(async path=>{
        try{const response=await fetch(new Request(urlFor(path),{cache:'reload'}));
          if(response.ok&&!response.redirected)await cache.put(urlFor(path),response);
        }catch(_ignored){}
      }));
    }catch(error){
      // Never activate a partial release; the existing active worker and its cache remain intact.
      await caches.delete(CACHE_NAME);
      throw error;
    }
  })());
});
self.addEventListener('activate',event=>{
  event.waitUntil((async()=>{
    // Keep one previous shell as a recovery reserve; cap historical storage use.
    const keys=(await caches.keys()).filter(key=>key.startsWith(CACHE_PREFIX)&&key!==CACHE_NAME);
    await Promise.all(keys.slice(0,-1).map(key=>caches.delete(key)));
    await self.clients.claim();
  })());
});
self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET')return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin||!url.pathname.startsWith(new URL(self.registration.scope).pathname))return;
  // Connectivity probes must not be answered from CacheStorage.
  if(request.cache==='no-store'){event.respondWith(fetch(request));return;}
  event.respondWith((async()=>{
    const cache=await caches.open(CACHE_NAME);
    const hit=await cache.match(request);
    if(hit)return hit;
    // Handles ?query navigation and PWA launches when Python/HTTPS server is unavailable.
    if(request.mode==='navigate'){
      const shell=await cache.match(urlFor('./index.html'))||await cache.match(urlFor('./'));
      if(shell)return shell;
    }
    try{
      const response=await fetch(request);
      if(response.ok&&!response.redirected&&url.pathname.endsWith('.woff2')&&url.pathname.includes('/fonts/')){
        event.waitUntil(cache.put(request,response.clone()));
      }
      return response;
    }catch(_error){
      return new Response(request.mode==='navigate'?'La aplicación offline no está preparada. Reconecta con el origen para repararla.':'Recurso no disponible offline.',
        {status:503,headers:{'Content-Type':'text/plain;charset=utf-8','Cache-Control':'no-store'}});
    }
  })());
});
