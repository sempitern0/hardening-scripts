/* Local document release control. SHA-256 flags accidental changes; it is NOT a signature or immutable audit log. */
'use strict';
(() => {
  const VERSION=1, MAX_HISTORY=40, MAX_BASELINE=3000000;
  const clone=value=>JSON.parse(JSON.stringify(value));
  const clean=value=>typeof value==='string'?value.trim():'';
  const noControl=audit=>{
    const content=clone(audit);
    delete content.documentControl;
    return content;
  };
  function normalize(value){
    if(value==null)return {version:VERSION,status:'draft',revision:0,confirmed:null,history:[],pending:null};
    if(!value||typeof value!=='object'||Array.isArray(value)||value.version!==VERSION||
       !['draft','confirmed','amending'].includes(value.status)||
       !Number.isInteger(value.revision)||value.revision<0||value.revision>MAX_HISTORY+1||
       !Array.isArray(value.history)||value.history.length>MAX_HISTORY)throw Error('Control documental no válido. Restaura un JSON verificado.');
    const event=item=>{
      if(!item||typeof item!=='object'||Array.isArray(item))throw Error('Historial documental incorrecto.');
      for(const key of ['at','author','digest']){
        if(typeof item[key]!=='string'||item[key].length>220)throw Error('Historial documental incorrecto.');
      }
      if(item.digest&&!/^[a-f0-9]{64}$/.test(item.digest))throw Error('Huella documental inválida.');
      return item;
    };
    for(const entry of value.history)event(entry);
    if(value.confirmed)event(value.confirmed);
    if(value.status==='confirmed'&&!value.confirmed)throw Error('Confirmación documental incompleta.');
    if(value.status==='amending'&&(!value.pending||typeof value.pending!=='object'||
       !value.pending.before||typeof value.pending.before!=='object'||!value.confirmed))
       throw Error('Rectificación pendiente sin información de referencia.');
    if(value.pending&&JSON.stringify(value.pending).length>MAX_BASELINE+2000)throw Error('Rectificación demasiado grande.');
    return clone(value);
  }
  function baseline(audit){
    const result={};
    function flatten(value,path,level){
      if(level>6)return;
      if(Array.isArray(value)){
        if(value.length>501)throw Error('Demasiados registros para esta rectificación.');
        value.forEach((row,index)=>flatten(row,path+'['+index+']',level+1));return;
      }
      if(value&&typeof value==='object'){
        for(const [key,item] of Object.entries(value)){
          if(key==='documentControl'||(path.startsWith('evidence[')&&key==='image'))continue;
          flatten(item,path?(path+'.'+key):key,level+1);
        }
        return;
      }
      if(typeof value==='string'&&value.length>20000)throw Error('Campo demasiado extenso para registrar la rectificación.');
      result[path]=JSON.stringify(value??null);
    }
    flatten(noControl(audit),'',0);
    if(JSON.stringify(result).length>MAX_BASELINE)throw Error('El expediente supera el límite de rectificación local. Conserva un backup externo.');
    return result;
  }
  function changes(before,audit){
    const after=baseline(audit);
    const keys=new Set([...Object.keys(before),...Object.keys(after)]);
    const list=[];
    for(const key of keys){
      if(before[key]!==after[key]){
        list.push({field:key.slice(0,200),operation:!(key in before)?'added':!(key in after)?'removed':'modified'});
      }
    }
    if(list.length>1000)throw Error('Demasiados cambios para una sola rectificación. Divide el trabajo en varias correcciones.');
    return list;
  }
  async function digest(audit){
    if(!globalThis.crypto?.subtle)throw Error('La huella SHA-256 requiere HTTPS o localhost.');
    const bytes=new TextEncoder().encode(JSON.stringify(noControl(audit)));
    const hash=new Uint8Array(await crypto.subtle.digest('SHA-256',bytes));
    return Array.from(hash,x=>x.toString(16).padStart(2,'0')).join('');
  }
  function text(value,label,max=240){
    const v=clean(value);
    if(v.length<3||v.length>max)throw Error(label+' debe contener entre 3 y '+max+' caracteres.');
    return v;
  }
  async function confirm(audit,author){
    const doc=normalize(audit.documentControl);
    if(doc.status!=='draft')throw Error('Solo se puede confirmar un expediente en borrador.');
    const digestValue=await digest(audit);
    const at=new Date().toISOString();
    const actor=text(author,'El responsable');
    audit.documentControl={
      version:VERSION,status:'confirmed',revision:1,
      confirmed:{at,author:actor,digest:digestValue},
      history:[{at,author:actor,digest:digestValue,type:'confirmation',revision:1}],
      pending:null
    };
    return audit.documentControl;
  }
  async function beginAmendment(audit,author,reason){
    const doc=normalize(audit.documentControl);
    if(doc.status!=='confirmed')throw Error('Solo se puede rectificar un expediente confirmado.');
    const current=await digest(audit);
    if(current!==doc.confirmed.digest)throw Error('El contenido no coincide con la última confirmación. Restaura y revisa el expediente antes de rectificar.');
    if(doc.history.length>=MAX_HISTORY)throw Error('Límite de revisiones alcanzado: archiva y crea un nuevo expediente.');
    const before=baseline(audit),actor=text(author,'El responsable',160),why=text(reason,'El motivo',1200);
    audit.documentControl={
      ...doc,status:'amending',
      pending:{author:actor,reason:why,at:new Date().toISOString(),beforeDigest:current,before}
    };
    return audit.documentControl;
  }
  async function finalizeAmendment(audit){
    const doc=normalize(audit.documentControl);
    if(doc.status!=='amending')throw Error('No hay una rectificación abierta.');
    const edits=changes(doc.pending.before,audit);
    if(!edits.length)throw Error('No hay modificaciones para registrar; vuelve a la auditoría y edita los campos necesarios.');
    const at=new Date().toISOString(),newDigest=await digest(audit);
    const revision=doc.revision+1;
    const event={
      type:'emergency-amendment',revision,at,author:doc.pending.author,
      reason:doc.pending.reason,beforeDigest:doc.pending.beforeDigest,
      digest:newDigest,changes:edits
    };
    audit.documentControl={
      version:VERSION,status:'confirmed',revision,
      confirmed:{at,author:doc.pending.author,digest:newDigest},
      history:[...doc.history,event],pending:null
    };
    return event;
  }
  async function verify(audit){
    const doc=normalize(audit.documentControl);
    if(doc.status!=='confirmed')return false;
    return await digest(audit)===doc.confirmed.digest;
  }
  globalThis.AuditDocumentControl=Object.freeze({
    VERSION,normalize,baseline,changes,digest,confirm,beginAmendment,finalizeAmendment,verify
  });
})();
