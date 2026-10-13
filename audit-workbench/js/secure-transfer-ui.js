'use strict';
(() => {
  const sec=globalThis.AuditSecureTransfer;
  let state={file:null,previewUrl:null,share:null,uploaded:''};
  const el=id=>document.getElementById(id);
  const msg=(id,value)=>{const node=el(id);if(node)node.textContent=value;};
  const safeName=()=>sec.safeFilename('backup');
  function view(available,unlocked){
    return '<section class="card secure-transfer"><h2>Distribución segura · copias y PDF</h2>'+
      '<p class="subtle">Los documentos se procesan localmente. Nada se sube sin confirmación. El almacenamiento remoto usa Nextcloud WebDAV HTTPS; para compartir se requiere su API OCS con CORS habilitado.</p>'+
      '<h3>Copia del expediente cifrada</h3><label for="transfer-key">Frase de cifrado (mínimo 16 caracteres)</label><input id="transfer-key" type="password" autocomplete="new-password" placeholder="Contraseña independiente de la cuenta Nextcloud">'+
      '<div class="action-row"><button type="button" class="button quiet" data-transfer="download" '+(!available?'disabled':'')+'>Descargar copia cifrada</button><button type="button" class="button accent" data-transfer="backup" '+(!available||!unlocked?'disabled':'')+'>Subir copia cifrada</button></div>'+
      '<label for="transfer-recover">Recuperar JSON de copia cifrada</label><input id="transfer-recover" type="file" accept=".awenc,.json"><p class="subtle">Se descarga el JSON descifrado; impórtalo por el procedimiento normal. No sobrescribe el expediente actual.</p><p id="transfer-backup-status" role="status"></p>'+
      '<hr><h3>Informe PDF · vista local y enlace temporal</h3><p class="subtle">Genera y guarda primero el PDF con la función de impresión de la aplicación. Selecciona el archivo revisado para verlo localmente o subirlo. No se abren túneles ni puertos del ordenador.</p>'+
      '<label for="transfer-pdf">PDF revisado (máximo 40 MiB)</label><input id="transfer-pdf" type="file" accept=".pdf,application/pdf"><div id="transfer-preview" class="transfer-preview" hidden></div>'+
      '<div class="action-row"><button type="button" class="button quiet" data-transfer="close">Cerrar vista previa</button><button type="button" class="button accent" data-transfer="pdf" '+(!unlocked?'disabled':'')+'>Subir PDF</button></div>'+
      '<h3>Compartir archivo subido</h3><p class="subtle">Enlace Nextcloud con contraseña, lectura y caducidad confirmada por el servidor. La contraseña debe compartirse por otro canal.</p>'+
      '<div class="fields"><div class="field"><label for="transfer-expiry">Caducidad</label><select id="transfer-expiry"><option value="1">1 día</option><option value="2">2 días</option><option value="3">3 días</option><option value="7">7 días</option></select></div><div class="field"><label for="transfer-share-key">Contraseña del enlace (mín. 16 caracteres)</label><input id="transfer-share-key" type="password" autocomplete="new-password"></div></div>'+
      '<div class="action-row"><button type="button" class="button accent" data-transfer="share" '+(!unlocked?'disabled':'')+'>Crear enlace temporal</button><button type="button" class="button danger" data-transfer="revoke" '+(!unlocked?'disabled':'')+'>Revocar último enlace</button></div>'+
      '<p id="transfer-pdf-status" role="status"></p><div id="transfer-share-link"></div><p class="subtle">Enlaces de sesiones anteriores: revócalos desde Nextcloud. La aplicación no guarda tokens públicos ni contraseñas de enlace.</p></section>';
  }
  function clearPreview(){
    if(state.previewUrl){URL.revokeObjectURL(state.previewUrl);state.previewUrl=null;}
    const target=el('transfer-preview');if(target){target.replaceChildren();target.hidden=true;}
  }
  function bind({getProfile,getAudit,download,flush}){
    const workspace=el('workspace');
    if(!workspace||workspace.dataset.transferBound)return;
    workspace.dataset.transferBound='true';
    workspace.addEventListener('change',async event=>{
      const t=event.target;
      if(t.id==='transfer-pdf'&&t.files?.length){
        clearPreview();state.file=null;state.uploaded='';
        try{
          if(!await sec.isPdf(t.files[0]))throw Error('PDF no válido o superior a 40 MiB.');
          state.file=t.files[0];state.previewUrl=URL.createObjectURL(state.file);
          const container=el('transfer-preview');
          const frame=document.createElement('iframe');
          frame.title='Previsualización local del PDF';frame.src=state.previewUrl;frame.setAttribute('sandbox','allow-same-origin');
          container.appendChild(frame);container.hidden=false;
          msg('transfer-pdf-status','PDF listo para revisión local. No se ha subido.');
        }catch(error){msg('transfer-pdf-status',error.message)}
      }
      if(t.id==='transfer-recover'&&t.files?.length){
        try{
          if(t.files[0].size>60*1024*1024)throw Error('Archivo demasiado grande.');
          const json=await sec.decryptBackup(await t.files[0].text(),el('transfer-key')?.value||'');
          download('auditoria-recuperada.json',json,'application/json;charset=utf-8');
          msg('transfer-backup-status','JSON descifrado: descarga iniciada, revisa el archivo.');
        }catch(error){msg('transfer-backup-status','Error: '+error.message)}
      }
    });
    workspace.addEventListener('click',async event=>{
      const button=event.target.closest('button[data-transfer]');
      if(!button)return;
      const action=button.dataset.transfer,profile=getProfile();
      if(action==='close'){clearPreview();return;}
      try{
        button.disabled=true;
        if(action==='download'||action==='backup'){
          const audit=getAudit();if(!audit)throw Error('Abre primero un expediente.');
          await flush();
          const ciphertext=await sec.encryptBackup(getAudit(),el('transfer-key')?.value||'');
          const filename=safeName();
          if(action==='download'){download(filename,ciphertext,'application/json;charset=utf-8');msg('transfer-backup-status','Descarga iniciada. Protege el archivo y la frase de cifrado por separado.');}
          else{
            if(!profile)throw Error('Desbloquea Nextcloud primero.');
            if(!confirm('¿Subir el backup CIFRADO a '+new URL(profile.url).origin+'?'))return;
            await sec.upload(profile,filename,ciphertext,'application/json;charset=utf-8');
            msg('transfer-backup-status','Subido: '+filename+'. El servidor solo recibe datos cifrados.');
          }
        }else if(action==='pdf'){
          if(!profile)throw Error('Desbloquea Nextcloud primero.');
          if(!state.file||!await sec.isPdf(state.file))throw Error('Selecciona un PDF válido.');
          if(!confirm('¿Subir el PDF revisado a '+new URL(profile.url).origin+'?'))return;
          const filename=sec.safeFilename('pdf');
          await sec.upload(profile,filename,state.file,'application/pdf');state.uploaded=filename;
          msg('transfer-pdf-status','PDF subido ('+filename+'). Todavía no hay enlace público.');
        }else if(action==='share'){
          if(!profile||!state.uploaded)throw Error('Desbloquea Nextcloud y sube primero el PDF en esta sesión.');
          const expiration=el('transfer-expiry').value,pass=el('transfer-share-key').value;
          if(!confirm('¿Crear enlace público protegido con caducidad de '+expiration+' día(s)?'))return;
          const share=await sec.createExpiringShare(profile,state.uploaded,Number(expiration),pass);
          state.share=share;el('transfer-share-key').value='';
          const target=el('transfer-share-link');target.replaceChildren();
          const link=document.createElement('a');link.href=share.url;link.target='_blank';link.rel='noopener noreferrer';link.textContent='Abrir enlace temporal ↗';target.appendChild(link);
          msg('transfer-pdf-status','Enlace vigente hasta '+share.expiration+'. Comparte la contraseña por otro canal.');
        }else if(action==='revoke'){
          if(!profile||!state.share)throw Error('No hay enlace de esta sesión; revisa Nextcloud.');
          if(!confirm('¿Revocar el último enlace?'))return;
          await sec.revokeShare(profile,state.share);state.share=null;el('transfer-share-link')?.replaceChildren();
          msg('transfer-pdf-status','Enlace revocado.');
        }
      }catch(error){msg(action==='download'||action==='backup'?'transfer-backup-status':'transfer-pdf-status','Error: '+error.message)}
      finally{if(button.isConnected)button.disabled=false;}
    });
    window.addEventListener('pagehide',clearPreview);
  }
  globalThis.AuditSecureTransferUI=Object.freeze({view,bind,clearPreview});
})();
