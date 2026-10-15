/* Plan audit imports by immutable report reference; never match mutable client names. */
'use strict';
(() => {
  const reference=value=>typeof value==='string'?value.trim().toUpperCase():'';
  function plan(records,audits){
    if(!Array.isArray(records)||!Array.isArray(audits)||audits.length>250)
      throw Error('No se puede preparar la importación.');
    const existing=new Map();
    for(const item of records){
      const key=reference(item?.audit?.meta?.reportId);
      if(!key)continue;
      const matches=existing.get(key)||[];
      matches.push(item);
      existing.set(key,matches);
    }
    const seen=new Set();
    const entries=audits.map(audit=>{
      const key=reference(audit?.meta?.reportId);
      if(!key)throw Error('Hay un expediente sin referencia. Revisa el archivo antes de importarlo.');
      if(seen.has(key))throw Error('El archivo incluye la referencia repetida '+key+'. No se ha importado nada.');
      seen.add(key);
      const matches=existing.get(key)||[];
      if(matches.length>1)throw Error('La referencia '+key+' ya está repetida en la biblioteca. Resuelve el duplicado antes de importar.');
      return {audit,reference:key,existing:matches[0]||null};
    });
    return Object.freeze({
      entries,
      replaced:entries.filter(item=>item.existing),
      added:entries.filter(item=>!item.existing)
    });
  }
  globalThis.AuditImportPlan=Object.freeze({reference,plan});
})();
