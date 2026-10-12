/* Revisión editorial y plan de remediación local. No se realizan consultas de red. */
'use strict';
(() => {
  const clean = value => typeof value === 'string' ? value.trim() : '';
  const RANK = Object.freeze({'Crítica':0,'Alta':1,'Media':2,'Baja':3,'Informativa':4,'Sin evaluar':5});
  const CLOSED = new Set(['Cerrado','Mitigado']);
  const makeIssue = (severity, code, section, message, key = '') => ({severity,code,section,message,key});
  const notEmpty = value => clean(value).length > 0;
  const isRelated = (evidence, finding, relations) => {
    const key=clean(finding?._key), code=clean(finding?.id);
    if (key && relations?.normalizeLinks?.(evidence?.links)?.findings?.includes(key)) return true;
    const references = clean(finding?.evidenceIds).split(/[\s,;]+/).filter(Boolean);
    return references.some(ref => ref === clean(evidence?.id) || ref === clean(evidence?._key));
  };
  function plan(audit){
    return (audit?.findings||[]).map((item,index)=>({
      id: clean(item.id)||`Hallazgo ${index+1}`,
      key:clean(item._key),title:clean(item.title)||'Hallazgo sin título',
      severity:clean(item.severity)||'Sin evaluar',
      status:clean(item.status)||'Abierto',
      owner:clean(item.owner), deadline:clean(item.deadline),
      recommendation:clean(item.recommendation),
      verification:clean(item.verification),
      risk:clean(item.risk)
    })).sort((a,b)=>{
      const aClosed=CLOSED.has(a.status),bClosed=CLOSED.has(b.status);
      return Number(aClosed)-Number(bClosed) || (RANK[a.severity]??5)-(RANK[b.severity]??5) || a.id.localeCompare(b.id,'es',{numeric:true});
    });
  }
  function review(audit, relations){
    const issues=[];
    const add=(severity,code,section,message,key='')=>issues.push(makeIssue(severity,code,section,message,key));
    const meta=audit?.meta||{}, findings=audit?.findings||[],controls=audit?.controls||[],evidence=audit?.evidence||[];
    if(!notEmpty(meta.client)) add('blocker','CLIENTE','engagement','Indica la empresa u organización auditada.');
    if(!notEmpty(meta.project)) add('blocker','PROYECTO','engagement','Identifica el proyecto de auditoría.');
    if(!notEmpty(meta.scope)) add('blocker','ALCANCE','engagement','Describe qué activos, sedes y redes están autorizados para la revisión.');
    if(!Array.isArray(meta.auditTeam)||!meta.auditTeam.some(x=>notEmpty(x?.name)))add('warning','AUDITORES','engagement','Asigna el profesional o equipo responsable del informe.');
    if(!notEmpty(meta.limitations))add('warning','LIMITACIONES','engagement','Documenta las limitaciones reales de la evaluación, aunque sean «Ninguna».');
    if(!notEmpty(meta.rules))add('warning','AUTORIZACION','engagement','Documenta la autorización y reglas de compromiso acordadas.');
    if(meta.start&&meta.end&&meta.start>meta.end)add('blocker','FECHAS','engagement','La fecha de finalización es anterior a la de inicio.');
    if(!controls.length)add('warning','SIN_CONTROLES','controls','No hay controles registrados; explica la metodología y el alcance si es intencional.');
    const pending=controls.filter(c=>['Pendiente','No verificado',''].includes(clean(c.status)));
    if(pending.length)add('warning','CONTROLES_PENDIENTES','controls',`${pending.length} controles están pendientes o sin verificar. No deben figurar como conformes.`);
    for (const c of controls){
      if(c.status==='No conforme'&&!findings.some(f=>f.originControlKey&&f.originControlKey===c._key)){
        add('blocker','CONTROL_NO_CONFORME','controls',`${clean(c.id)||clean(c.name)||'Control'} no es conforme y no tiene hallazgo de seguimiento.`,clean(c._key));
      }
    }
    for(const f of findings){
      const name=clean(f.id)||clean(f.title)||'Hallazgo sin identificación';const key=clean(f._key);
      if(!notEmpty(f.title))add('blocker','TITULO_HALLAZGO','findings',`${name}: falta un título claro.`,key);
      if(!notEmpty(f.severity)||f.severity==='Sin evaluar')add('blocker','RIESGO_SIN_VALORAR','findings',`${name}: evalúa la severidad; no se asignará automáticamente.`,key);
      if(!notEmpty(f.recommendation))add('blocker','SIN_REMEDIACION','findings',`${name}: explica qué medida correctiva debe aplicarse.`,key);
      if(!notEmpty(f.risk))add('warning','SIN_IMPACTO','findings',`${name}: describe las consecuencias para el negocio o la seguridad.`,key);
      if(!notEmpty(f.owner)||f.owner==='Pendiente de asignar')add('warning','SIN_RESPONSABLE','findings',`${name}: asigna un responsable de remediación.`,key);
      if(!notEmpty(f.deadline))add('warning','SIN_FECHA','findings',`${name}: establece una fecha objetivo acordada con el cliente.`,key);
      if(!notEmpty(f.verification))add('warning','SIN_VERIFICACION','findings',`${name}: define cómo comprobar que la corrección funciona.`,key);
      if(!evidence.some(e=>isRelated(e,f,relations)))add('warning','SIN_EVIDENCIA','findings',`${name}: vincula evidencia o explica por qué no está disponible.`,key);
      if(CLOSED.has(f.status)&&!notEmpty(f.verification))add('blocker','CIERRE_NO_COMPROBADO','findings',`${name}: figura ${f.status.toLowerCase()} sin criterio documentado de verificación.`,key);
      const historical=Array.isArray(f.retests)?f.retests:[];
      const last=historical.at(-1);
      if(f.status==='Cerrado' && !historical.some(r=>r?.result==='verified'))add('warning','CIERRE_SIN_REEVALUACION','followup',`${name}: cerrado sin una corrección comprobada en el historial de seguimiento.`,key);
      if(last?.result==='verified' && f.status!=='Cerrado' && f.status!=='Riesgo aceptado')add('warning','ESTADO_DE_REEVALUACION','followup',`${name}: el seguimiento indica verificado, pero el estado administrativo es ${clean(f.status)||'vacío'}.`,key);
      if(last?.evidenceKey && !evidence.some(e=>e._key===last.evidenceKey))add('warning','EVIDENCIA_REEVALUACION_NO_DISPONIBLE','followup',`${name}: la evidencia de la última revisión ya no está disponible en el expediente.`,key);
      if(last?.result==='verified' && !last.evidenceKey)add('warning','VERIFICACION_SIN_EVIDENCIA','followup',`${name}: hay corrección verificada sin evidencia adicional vinculada.`,key);
      if(f.status==='Riesgo aceptado'&&!notEmpty(f.residual))add('warning','ACEPTACION_SIN_JUSTIFICAR','findings',`${name}: documenta justificación, responsable y condiciones de aceptación del riesgo.`,key);
    }
    if(!notEmpty(audit?.final?.executive))add('warning','SIN_RESUMEN','delivery','Completa el resumen ejecutivo para dirección.');
    if(!notEmpty(audit?.final?.signoff))add('warning','SIN_VALIDACION','delivery','Identifica quién revisa o autoriza la entrega.');
    for(const msg of relations?.referenceProblems?.(audit)||[])add('warning','REFERENCIA_INCORRECTA','evidence',String(msg).slice(0,300));
    return {issues, blockers:issues.filter(i=>i.severity==='blocker'),warnings:issues.filter(i=>i.severity==='warning'), ready:!issues.some(i=>i.severity==='blocker'), plan:plan(audit)};
  }
  globalThis.AuditQuality=Object.freeze({review,plan});
})();
