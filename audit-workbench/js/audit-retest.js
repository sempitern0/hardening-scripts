/* Reevaluación documentada de hallazgos. Sin peticiones de red ni mutación implícita. */
'use strict';
(() => {
  const RESULTS = Object.freeze({verified:'Corrección verificada',pending:'Debilidad persistente',unverified:'No se pudo verificar',reopened:'Hallazgo reabierto'});
  const MAX_HISTORY = 40;
  const clean = (v, max = 4000) => typeof v === 'string' ? v.trim().slice(0,max) : '';
  const dateValid = v => /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v+'T12:00:00Z')) && new Date(v+'T12:00:00Z').toISOString().slice(0,10)===v;
  const normalize = input => {
    if(!Array.isArray(input))return [];
    return input.slice(0,MAX_HISTORY).flatMap(entry=>{
      if(!entry||typeof entry!=='object'||Array.isArray(entry)||!Object.hasOwn(RESULTS,entry.result)||!dateValid(entry.date))return [];
      return [{id:clean(entry.id,100),date:entry.date,result:entry.result,by:clean(entry.by,160),notes:clean(entry.notes),evidenceKey:clean(entry.evidenceKey,120),evidenceId:clean(entry.evidenceId,100),evidenceSha256:/^[a-f0-9]{64}$/i.test(entry.evidenceSha256||'')?entry.evidenceSha256.toLowerCase():'',previousStatus:clean(entry.previousStatus,90)}];
    });
  };
  const latest = finding => normalize(finding?.retests).at(-1) || null;
  const outcome = finding => {
    if(finding?.status==='Riesgo aceptado')return 'accepted';
    const entry=latest(finding);
    if(!entry)return 'not-reviewed';
    if(entry.result==='verified' && finding.status!=='Cerrado')return 'inconsistent';
    if(['pending','reopened'].includes(entry.result) && finding.status==='Cerrado')return 'inconsistent';
    return entry.result;
  };
  const summary = audit => {
    const counts={total:0,verified:0,pending:0,unverified:0,reopened:0,accepted:0,inconsistent:0,'not-reviewed':0};
    for(const finding of audit?.findings||[]){counts.total++;counts[outcome(finding)]++;}
    return counts;
  };
  function record(finding, input, evidence, makeId){
    const history=normalize(finding.retests);
    if(history.length>=MAX_HISTORY)throw Error('Se ha alcanzado el límite de 40 revisiones por hallazgo.');
    const result=clean(input.result,20),date=clean(input.date,10),by=clean(input.by,160),notes=clean(input.notes);
    if(!Object.hasOwn(RESULTS,result))throw Error('Selecciona el resultado de la verificación.');
    if(!dateValid(date))throw Error('Introduce una fecha válida.');
    if(!by)throw Error('Identifica al auditor que realizó la verificación.');
    if(notes.length<12)throw Error('Describe el resultado y las comprobaciones realizadas (al menos 12 caracteres).');
    if(result==='verified'&&!clean(finding.verification))throw Error('Define primero en el hallazgo cómo verificar la corrección.');
    const evidenceKey=clean(input.evidenceKey,120);
    if(evidenceKey&&!evidence.some(item=>item._key===evidenceKey))throw Error('No se encuentra la evidencia seleccionada.');
    const source=evidence.find(item=>item._key===evidenceKey);
    const hash=source?.fileSha256||source?.sha256||'';
    const entry={id:makeId(),date,result,by,notes,evidenceKey,evidenceId:clean(source?.id,100),evidenceSha256:/^[a-f0-9]{64}$/i.test(hash)?hash.toLowerCase():'',previousStatus:clean(finding.status,90)};
    return entry;
  }
  function apply(finding,entry){
    // Only called after the auditor has explicitly recorded a revision.
    finding.retests=[...normalize(finding.retests),entry];
    if(entry.result==='verified')finding.status='Cerrado';
    if(entry.result==='pending')finding.status='Abierto';
    if(entry.result==='reopened')finding.status='Abierto';
    // A visit that could not verify the result must not change its existing status.
    return finding;
  }
  const evidenceFor = (entry,audit) => (audit?.evidence||[]).find(e=>e._key===entry?.evidenceKey)||null;
  globalThis.AuditRetest=Object.freeze({RESULTS,MAX_HISTORY,normalize,latest,outcome,summary,record,apply,evidenceFor});
})();
