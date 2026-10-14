/* Opt-in PWA updates. No external services, audit data, or automatic reloads. */
'use strict';
(() => {
  const APPLY_MESSAGE='AUDIT_WORKBENCH_APPLY_UPDATE';
  const CHECK_INTERVAL_MS=60*60*1000;
  function supported(){
    return 'serviceWorker' in navigator && (
      location.protocol==='https:'||
      (location.protocol==='http:'&&['localhost','127.0.0.1'].includes(location.hostname))
    );
  }
  function init({saveBeforeReload,isSafeToReload}={}){
    const notice=document.getElementById('pwa-update-notice');
    const status=document.getElementById('pwa-update-status');
    const message=document.getElementById('pwa-update-message');
    const apply=document.getElementById('pwa-update-apply');
    const later=document.getElementById('pwa-update-later');
    const check=document.getElementById('pwa-update-check');
    if(!notice||!status||!message||!apply||!later||!check)return null;
    if(!supported()){
      check.hidden=true;
      status.textContent='Las actualizaciones automáticas requieren HTTPS o localhost.';
      return null;
    }
    let registration=null;
    let pendingWorker=null;
    let dismissedWorker=null;
    let checking=false;
    let applying=false;
    let reloadRequested=false;
    let lastCheck=0;

    function setStatus(text){status.textContent=text;}
    function renderPending(){
      const worker=registration?.waiting;
      if(!worker||!navigator.serviceWorker.controller){
        pendingWorker=null;
        notice.hidden=true;
        return;
      }
      if(worker!==pendingWorker){
        pendingWorker=worker;
        dismissedWorker=null;
      }
      notice.hidden=worker===dismissedWorker;
      if(!notice.hidden){
        message.textContent='Una nueva versión de Audit Workbench está preparada. Guarda los cambios y decide cuándo actualizar. Se reiniciará solo al confirmar.';
      }
      apply.disabled=applying;
      later.disabled=applying;
      setStatus('Nueva versión preparada para instalar.');
    }
    function watchInstalling(){
      const installing=registration?.installing;
      if(!installing||installing.__auditUpdateWatched)return;
      // Only a local marker on this worker wrapper, never persisted or transmitted.
      installing.__auditUpdateWatched=true;
      installing.addEventListener('statechange',()=>{
        if(installing.state==='installed')renderPending();
      });
    }
    async function checkUpdates(manual=false){
      if(!registration||checking||applying||!navigator.onLine)return;
      if(!manual&&Date.now()-lastCheck<30000)return;
      checking=true;check.disabled=true;
      if(manual)setStatus('Buscando una versión nueva…');
      try{
        lastCheck=Date.now();
        await registration.update();
        watchInstalling();
        renderPending();
        if(manual&&!registration.waiting)setStatus('No hay una nueva versión preparada. La instalación continúa funcionando offline.');
      }catch(error){
        if(manual)setStatus('No se pudo comprobar el servidor. La aplicación sigue disponible offline.');
        console.warn('No se pudo comprobar la actualización de Audit Workbench',error);
      }finally{checking=false;check.disabled=false;}
    }
    function sendActivation(worker){
      return new Promise((resolve,reject)=>{
        const channel=new MessageChannel();
        let finished=false;
        const timer=setTimeout(()=>{
          if(!finished){finished=true;channel.port1.close();reject(new Error('La actualización no respondió a tiempo.'));}
        },10000);
        channel.port1.onmessage=event=>{
          if(finished)return;
          finished=true;clearTimeout(timer);channel.port1.close();
          resolve(event.data);
        };
        try{worker.postMessage({type:APPLY_MESSAGE},[channel.port2]);}
        catch(error){if(!finished){finished=true;clearTimeout(timer);channel.port1.close();reject(error);}}
      });
    }
    async function applyUpdate(){
      if(applying||!registration?.waiting)return;
      if(!confirm('Se guardará el expediente y se reiniciará Audit Workbench para aplicar la nueva versión. Cierra otras ventanas de la aplicación antes de continuar. ¿Actualizar ahora?'))return;
      applying=true;apply.disabled=true;later.disabled=true;
      setStatus('Guardando antes de actualizar…');
      try{
        if(document.activeElement&&typeof document.activeElement.blur==='function')document.activeElement.blur();
        if(typeof saveBeforeReload!=='function'||typeof isSafeToReload!=='function')
          throw new Error('La comprobación de guardado no está disponible.');
        await saveBeforeReload();
        if(!isSafeToReload())throw new Error('Existen cambios sin guardar. Exporta el JSON antes de actualizar.');
        const worker=registration.waiting;
        if(!worker)throw new Error('La actualización ya no está pendiente. Vuelve a comprobarla.');
        reloadRequested=true;
        const reply=await sendActivation(worker);
        if(!reply?.ok){
          reloadRequested=false;
          throw new Error(reply?.reason||'No se ha podido activar la nueva versión.');
        }
        setStatus('Actualización aceptada. Preparando el reinicio…');
      }catch(error){
        reloadRequested=false;
        setStatus('Actualización aplazada: '+error.message);
        message.textContent='No se ha actualizado. Tus datos permanecen en la versión actual. '+error.message;
      }finally{
        applying=false;apply.disabled=false;later.disabled=false;
      }
    }
    apply.addEventListener('click',()=>void applyUpdate());
    later.addEventListener('click',()=>{
      dismissedWorker=registration?.waiting||null;
      notice.hidden=true;
      setStatus('Actualización aplazada. Puedes buscarla de nuevo cuando quieras.');
    });
    check.addEventListener('click',()=>{dismissedWorker=null;renderPending();void checkUpdates(true);});
    navigator.serviceWorker.addEventListener('controllerchange',()=>{
      if(reloadRequested){
        reloadRequested=false;
        location.reload();
      }else{
        renderPending();
      }
    });
    window.addEventListener('online',()=>{void checkUpdates();});
    document.addEventListener('visibilitychange',()=>{
      if(document.visibilityState==='visible')void checkUpdates();
    });
    async function setup(){
      try{
        registration=await navigator.serviceWorker.register('./sw.js',{scope:'./',updateViaCache:'none'});
        registration.addEventListener('updatefound',watchInstalling);
        watchInstalling();
        renderPending();
        if(navigator.onLine)await checkUpdates();
        // Long-running tablet sessions: check only while visible and online.
        setInterval(()=>{
          if(document.visibilityState==='visible'&&navigator.onLine)void checkUpdates();
        },CHECK_INTERVAL_MS);
      }catch(error){
        setStatus('No se pudo habilitar la búsqueda de actualizaciones.');
        console.warn('Service Worker de Audit Workbench no disponible',error);
      }
    }
    if(document.readyState==='complete')void setup();
    else window.addEventListener('load',()=>void setup(),{once:true});
    return {checkUpdates,applyUpdate,renderPending};
  }
  globalThis.AuditPwaUpdates=Object.freeze({init,supported});
})();
