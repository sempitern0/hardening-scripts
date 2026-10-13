'use strict';
(() => {
  const sec=globalThis.AuditSecureTransfer;
  let state={file:null,previewUrl:null,share:null,uploaded:''};
  const el=id=>document.getElementById(id);
  const msg=(id,value)=>{const node=el(id);if(node)node.textContent=value;};
  const safeName=()=>sec.safeFilename('backup');
  function view(available,unlocked){
    const noAudit=available?'':' disabled',noRemote=available&&unlocked?'':' disabled';
    return [
      '<section class="card secure-transfer" aria-labelledby="transfer-title">',
      '<div class="transfer-heading"><h2 id="transfer-title">Distribución segura · copias y PDF</h2>',
      '<p class="subtle">Cada transferencia requiere una acción del auditor. El expediente se procesa localmente y solo se envía cuando autorizas expresamente una subida.</p></div>',
      !available?'<div class="notice warn" role="status">No hay expediente abierto. Crea o selecciona una auditoría para exportar, compartir o subir información. <button class="button quiet small" type="button" data-go="records">Ir a mis auditorías</button></div>':'',
      '<div class="transfer-section" aria-labelledby="transfer-backup-title">',
      '<div class="transfer-section-header"><span class="transfer-step" aria-hidden="true">01</span><div><h3 id="transfer-backup-title">Copia de seguridad cifrada</h3><p class="subtle">AES-256-GCM antes de salir del dispositivo. La frase de cifrado no se envía al servidor.</p></div></div>',
      '<div class="transfer-field"><label for="transfer-key">Frase para cifrar y recuperar el backup</label>',
      '<input id="transfer-key" type="password" autocomplete="new-password" minlength="16" maxlength="512" placeholder="Mínimo 16 caracteres" aria-describedby="transfer-key-hint">',
      '<small id="transfer-key-hint">Utiliza una frase distinta de la contraseña de Nextcloud. Consérvala por separado.</small></div>',
      '<div class="action-row transfer-actions"><button type="button" class="button quiet" data-transfer="download"'+noAudit+'>Descargar copia cifrada</button>',
      '<button type="button" class="button accent" data-transfer="backup"'+noRemote+'>Subir copia cifrada</button></div>',
      '<div class="transfer-field"><label for="transfer-recover">Recuperar una copia cifrada</label>',
      '<input id="transfer-recover" type="file" accept=".awenc,.json">',
      '<small>Descifra y descarga un JSON para importarlo manualmente. Nunca sobrescribe el expediente actual.</small></div>',
      '<p id="transfer-backup-status" class="transfer-feedback" role="status" aria-live="polite"></p>',
      '</div>',
      '<div class="transfer-section" aria-labelledby="transfer-pdf-title">',
      '<div class="transfer-section-header"><span class="transfer-step" aria-hidden="true">02</span><div><h3 id="transfer-pdf-title">Previsualizar y subir un informe PDF</h3><p class="subtle">Genera el PDF con «Generar PDF», guárdalo y revísalo antes de seleccionarlo. La vista previa no envía archivos.</p></div></div>',
      '<div class="transfer-field"><label for="transfer-pdf">Seleccionar PDF revisado</label>',
      '<input id="transfer-pdf" type="file" accept=".pdf,application/pdf">',
      '<small>PDF hasta 40 MiB. Previsualización local, sin túneles ni servicios externos.</small></div>',
      '<div id="transfer-preview" class="transfer-preview" hidden></div>',
      '<div class="action-row transfer-actions"><button type="button" class="button quiet" data-transfer="close">Cerrar vista previa</button>',
      '<button type="button" class="button accent" data-transfer="pdf"'+noRemote+'>Subir PDF a Nextcloud</button></div>',
      '</div>',
      '<div class="transfer-section" aria-labelledby="transfer-share-title">',
      '<div class="transfer-section-header"><span class="transfer-step" aria-hidden="true">03</span><div><h3 id="transfer-share-title">Crear un enlace temporal protegido</h3><p class="subtle">Solo para un PDF ya subido. Nextcloud gestiona el acceso de lectura, la contraseña y la caducidad.</p></div></div>',
      '<div class="transfer-grid"><div class="transfer-field"><label for="transfer-expiry">Caducidad del enlace</label>',
      '<select id="transfer-expiry"><option value="1">1 día</option><option value="2">2 días</option><option value="3">3 días</option><option value="7">7 días</option></select></div>',
      '<div class="transfer-field"><label for="transfer-share-key">Contraseña para el destinatario</label>',
      '<input id="transfer-share-key" type="password" autocomplete="new-password" minlength="16" placeholder="Mínimo 16 caracteres">',
      '<small>Entrega la contraseña por un canal diferente al del enlace.</small></div></div>',
      '<div class="action-row transfer-actions"><button type="button" class="button accent" data-transfer="share"'+noRemote+'>Crear enlace protegido</button>',
      '<button type="button" class="button danger" data-transfer="revoke"'+(unlocked?'':' disabled')+'>Revocar último enlace</button></div>',
      '<p id="transfer-pdf-status" class="transfer-feedback" role="status" aria-live="polite"></p>',
      '<div id="transfer-share-link" class="transfer-share-link"></div>',
      '<p class="subtle">Gestiona los enlaces de sesiones anteriores desde Nextcloud. La aplicación no guarda contraseñas ni tokens de compartición.</p>',
      '</div></section>'
    ].join('');
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
