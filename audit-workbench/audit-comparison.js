/* Comparación ejecutiva offline: solo hechos verificables, sin puntajes de riesgo inventados. */
'use strict';
(() => {
  const MAX_FINDINGS = 500;
  const MAX_TEXT = 200;
  const PRIORITY = Object.freeze({'Crítica':0,'Alta':1,'Media':2,'Baja':3,'Informativa':4,'Sin evaluar':5});
  const clean = (value,limit=MAX_TEXT) => typeof value==='string'?value.trim().slice(0,limit):'';
  const validDate = value => typeof value==='string' && /^\d{4}-\d{2}-\d{2}T/.test(value) && !Number.isNaN(Date.parse(value));
  function normalizeBaseline(input){
    if(!input || typeof input!=='object' || Array.isArray(input) || input.version!==1 || !validDate(input.capturedAt) || !Array.isArray(input.findings) || input.findings.length>MAX_FINDINGS)return null;
    const seen=new Set(),findings=[];
    for(const row of input.findings){
      if(!row || typeof row!=='object'||Array.isArray(row))return null;
      const key=clean(row.key,100);
      if(!key||seen.has(key))return null;
      seen.add(key);
      findings.push({key,id:clean(row.id,100),title:clean(row.title),severity:Object.hasOwn(PRIORITY,row.severity)?row.severity:'Sin evaluar',status:clean(row.status,60)});
    }
    const source=['before-first-retest','manual-current'].includes(input.source)?input.source:'manual-current';
    return {version:1,capturedAt:new Date(input.capturedAt).toISOString(),source,findings};
  }
  function capture(audit,source='manual-current',now=new Date().toISOString()){
    if(!validDate(now))throw Error('Fecha de referencia no válida.');
    if(!['before-first-retest','manual-current'].includes(source))throw Error('Origen de referencia no válido.');
    const rows=(audit?.findings||[]);
    if(rows.length>MAX_FINDINGS)throw Error('Demasiados hallazgos para fijar la referencia.');
    const snapshot={version:1,capturedAt:new Date(now).toISOString(),source,
      findings:rows.map(row=>({key:clean(row._key,100),id:clean(row.id,100),title:clean(row.title),severity:Object.hasOwn(PRIORITY,row.severity)?row.severity:'Sin evaluar',status:clean(row.status,60)}))};
    const safe=normalizeBaseline(snapshot);
    if(!safe)throw Error('Los hallazgos necesitan identificadores internos únicos antes de comparar.');
    return safe;
  }
  function compare(audit,retest){
    const current=Array.isArray(audit?.findings)?audit.findings:[];
    const baseline=normalizeBaseline(audit?.followupBaseline);
    const statusOf=f=>retest.outcome(f);
    const empty={verified:0,pending:0,reopened:0,unverified:0,accepted:0,inconsistent:0,'not-reviewed':0,missing:0};
    const currentByKey=new Map(current.filter(f=>typeof f?._key==='string').map(f=>[f._key,f]));
    const keys=baseline?new Set(baseline.findings.map(f=>f.key)):null;
    const initial=baseline?baseline.findings:current.map(f=>({key:f._key,id:f.id,title:f.title,severity:f.severity,status:f.status}));
    const counts={...empty};let priorityInitial=0,priorityOpen=0,severityChanged=0;
    for(const row of initial){
      const currentRow=currentByKey.get(row.key);
      const status=currentRow?statusOf(currentRow):'missing';
      counts[Object.hasOwn(counts,status)?status:'inconsistent']++;
      if(['Crítica','Alta'].includes(row.severity)){
        priorityInitial++;
        // Aceptar un riesgo NO significa eliminar la exposición técnica.
        if(status!=='verified')priorityOpen++;
      }
      if(currentRow && baseline && clean(currentRow.severity)!==row.severity)severityChanged++;
    }
    const added=baseline?current.filter(f=>!keys.has(f._key)):[];
    const addedCounts={...empty};
    for(const row of added){const s=statusOf(row);addedCounts[Object.hasOwn(addedCounts,s)?s:'inconsistent']++;}
    const decisions=current.filter(f=>statusOf(f)!=='verified'&&statusOf(f)!=='accepted'&&['Crítica','Alta'].includes(f.severity))
      .map(f=>({id:clean(f.id,100),key:clean(f._key,100),title:clean(f.title),severity:clean(f.severity,50),owner:clean(f.owner,120),deadline:clean(f.deadline,30),status:statusOf(f)}))
      .sort((a,b)=>(PRIORITY[a.severity]??5)-(PRIORITY[b.severity]??5)||a.id.localeCompare(b.id,'es',{numeric:true}));
    const dates=current.flatMap(f=>Array.isArray(f.retests)?f.retests.map(r=>r?.date).filter(x=>/^\d{4}-\d{2}-\d{2}$/.test(x)):[]).sort();
    const total=initial.length;
    return {
      hasBaseline:Boolean(baseline),baseline,
      initialTotal:total,currentTotal:current.length,
      counts,added:added.length,addedCounts,
      verifiedPercent:baseline&&total>0?Math.round(100*counts.verified/total):null,
      priorityInitial:baseline?priorityInitial:null,
      priorityNotVerified:baseline?priorityOpen:null,
      severityChanged,decisions,
      firstReview:dates[0]||'',lastReview:dates.at(-1)||'',
      limitations: baseline ? (baseline.source==='manual-current'?'Referencia fijada manualmente; no demuestra por sí sola el estado de la auditoría inicial.':'Referencia fijada inmediatamente antes de la primera reevaluación documentada; no equivale a una medición de riesgo económico.') : 'No hay una referencia histórica congelada. Solo se muestran estados actuales; no es posible calcular una evolución comparable.',
    };
  }
  globalThis.AuditComparison=Object.freeze({normalizeBaseline,capture,compare});
})();
