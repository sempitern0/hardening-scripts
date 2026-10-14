/* Immutable visible identifiers: separate audit references from external CVE IDs.
 * Uses browser CSPRNG; never derives identity from a client name or mutable form field.
 */
'use strict';
(() => {
  const clean=value=>typeof value==='string'?value.trim().toUpperCase():'';
  const isLockedField=(block,field)=>
    (block==='meta'&&field==='reportId') ||
    (['assets','controls','findings','evidence'].includes(block)&&field==='id');
  const existingSet=(records)=>new Set((records||[]).map(item=>
    clean(item?.audit?.meta?.reportId||item?.meta?.reportId||item?.reportId)).filter(Boolean));
  function generate(existing=[],prefix='AUD',options={}){
    const normalized=clean(prefix);
    if(!/^[A-Z0-9-]{2,12}$/.test(normalized))throw Error('El prefijo del informe debe tener entre 2 y 12 caracteres A-Z, 0-9 o guion.');
    const engine=options.crypto||globalThis.crypto;
    if(!engine?.getRandomValues)throw Error('No se dispone de generación criptográfica de identificadores. Usa un navegador actualizado en un origen seguro.');
    const date=options.date||new Date();
    if(!(date instanceof Date)||!Number.isFinite(date.getTime()))throw Error('Fecha de creación incorrecta.');
    const stamp=[date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('');
    const used=existingSet(existing);
    for(let attempt=0;attempt<12;attempt++){
      const bytes=new Uint8Array(12);
      engine.getRandomValues(bytes);
      const random=[...bytes].map(x=>x.toString(16).padStart(2,'0')).join('').toUpperCase();
      const id=normalized+'-'+stamp+'-'+random;
      if(!used.has(id))return id;
    }
    throw Error('No ha sido posible generar una referencia libre de colisiones. Reintenta la operación.');
  }
  function collides(value,records,excludeRecordId=''){
    const id=clean(value);
    return Boolean(id)&&records.some(r=>r?.id!==excludeRecordId&&clean(r?.audit?.meta?.reportId)===id);
  }
  globalThis.AuditIdentifiers=Object.freeze({generate,isLockedField,collides});
})();