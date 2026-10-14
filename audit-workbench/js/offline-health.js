/* Local availability diagnostics; no network calls except explicit cache repair. */
'use strict';
(()=>{
 const $=id=>document.getElementById(id);
 const send=(worker,type)=>new Promise((resolve,reject)=>{
   if(!worker)return reject(Error('Service Worker no activo.'));
   const channel=new MessageChannel();
   const timeout=setTimeout(()=>{channel.port1.close();reject(Error('Sin respuesta del Service Worker.'));},10000);
   channel.port1.onmessage=e=>{clearTimeout(timeout);channel.port1.close();resolve(e.data);};
   worker.postMessage({type},[channel.port2]);
 });
 async function check(){
   const output=$('offline-health-status');if(!output)return;
   try{
     const worker=navigator.serviceWorker?.controller;
     const health=await send(worker,'AUDIT_WORKBENCH_HEALTH');
     const persistent=await navigator.storage?.persisted?.();
     const estimate=await navigator.storage?.estimate?.();
     const detail=health.ok?'Preparada para funcionar offline.':'Caché incompleta: '+(health.missingCount??'?')+' recursos pendientes.';
     const space=estimate?.quota?' · Espacio utilizado '+Math.round((estimate.usage||0)/1048576)+' MiB / cuota estimada '+Math.round(estimate.quota/1048576)+' MiB.':'';
     output.textContent=detail+' · Almacenamiento '+(persistent?'persistente':'sin protección de persistencia confirmada')+space;
     $('offline-health-repair').disabled=health.ok||!navigator.onLine;
   }catch(error){output.textContent='No se ha podido comprobar el modo offline: '+error.message;}
 }
 async function persist(){
   const output=$('offline-health-status');
   if(!navigator.storage?.persist){output.textContent='El navegador no admite solicitar almacenamiento persistente.';return;}
   try{
     const allowed=await navigator.storage.persist();
     output.textContent=allowed?'Persistencia concedida por el navegador.':'El navegador no concedió persistencia. Conserva backups JSON externos.';
     await check();
   }catch(error){output.textContent='No se pudo solicitar persistencia: '+error.message;}
 }
 async function repair(){
   const output=$('offline-health-status');
   if(!navigator.onLine){output.textContent='Reconecta al servidor original antes de reparar.';return;}
   if(!confirm('Reparar únicamente los archivos offline ausentes desde el servidor de origen. ¿Continuar?'))return;
   output.textContent='Comprobando y recuperando archivos ausentes…';
   try{
     const result=await send(navigator.serviceWorker?.controller,'AUDIT_WORKBENCH_REPAIR_SHELL');
     output.textContent=result.ok?'Archivos offline recuperados. Comprueba el arranque sin servidor.':'No se completó la reparación: '+(result.error||'Recursos ausentes.');
     await check();
   }catch(error){output.textContent='Error de reparación: '+error.message;}
 }
 function init(){
   const checkButton=$('offline-health-check'),persistButton=$('offline-health-persist'),repairButton=$('offline-health-repair');
   if(!checkButton||!persistButton||!repairButton)return;
   checkButton.addEventListener('click',()=>void check());
   persistButton.addEventListener('click',()=>void persist());
   repairButton.addEventListener('click',()=>void repair());
   if('serviceWorker' in navigator)navigator.serviceWorker.ready.then(check).catch(()=>{});
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
 globalThis.AuditOfflineHealth=Object.freeze({check});
})();