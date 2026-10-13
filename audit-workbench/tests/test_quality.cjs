'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.join(__dirname,'..');
const env={};env.globalThis=env;
vm.runInNewContext(fs.readFileSync(path.join(root,'js/audit-relations.js'),'utf8'),env);
vm.runInNewContext(fs.readFileSync(path.join(root,'js/audit-quality.js'),'utf8'),env);
const {review,plan}=env.AuditQuality;
const relations=env.AuditRelations;
const empty={meta:{},final:{},controls:[],findings:[],evidence:[]};
let v=review(empty,relations);
assert(!v.ready);
assert(v.blockers.some(x=>x.code==='ALCANCE'));
assert(v.warnings.some(x=>x.code==='SIN_CONTROLES'));
const audit={
 meta:{client:'Empresa Ejemplo',project:'Revisión de seguridad',scope:'LAN principal',rules:'Autorización firmada',limitations:'Sin pruebas destructivas',auditTeam:[{name:'Consultor'}]},
 final:{executive:'Se han detectado desviaciones',signoff:'Consultor'},
 controls:[{id:'CTRL-001',_key:'control-1',name:'MFA administradores',status:'No conforme'}],
 evidence:[{id:'EVD-001',_key:'ev-1',links:{assets:[],controls:['control-1'],findings:['finding-1']}}],
 findings:[{_key:'finding-1',id:'FND-001',originControlKey:'control-1',title:'MFA ausente',severity:'Alta',status:'Abierto',owner:'Infraestructura',deadline:'2026-11-01',risk:'Acceso no autorizado',recommendation:'Habilitar MFA',verification:'Comprobar inicio de sesión con MFA',evidenceIds:''}]
};
v=review(audit,relations);
assert(v.ready,JSON.stringify(v.blockers));
assert.equal(v.warnings.length,0,JSON.stringify(v.warnings));
assert.equal(v.plan.length,1);
assert.equal(v.plan[0].verification,'Comprobar inicio de sesión con MFA');
audit.findings.push({_key:'finding-2',id:'FND-002',title:'Sin valoración',severity:'Sin evaluar',status:'Abierto'});
v=review(audit,relations);
assert(!v.ready);
assert(v.blockers.some(x=>x.code==='RIESGO_SIN_VALORAR'));
assert(v.blockers.some(x=>x.code==='SIN_REMEDIACION'));
assert.equal(plan(audit)[0].id,'FND-001');
audit.findings[0].status='Cerrado';audit.findings[0].verification='';
v=review(audit,relations);
assert(v.blockers.some(x=>x.code==='CIERRE_NO_COMPROBADO'));
const hours={meta:{client:'Ejemplo',project:'Prueba',scope:'LAN',start:'2026-10-13',startTime:'17:30',end:'2026-10-13',endTime:'16:30'},final:{},controls:[],findings:[],evidence:[]};
assert(review(hours,relations).blockers.some(x=>x.code==='PERIODO_INVERTIDO'));
hours.meta.endTime='19:00';
assert(!review(hours,relations).blockers.some(x=>x.code==='PERIODO_INVERTIDO'));
hours.meta.startTime='25:20';
assert(review(hours,relations).blockers.some(x=>x.code==='HORA_INICIO'));
hours.meta.startTime='17:30';
hours.meta.endTime='';
assert(review(hours,relations).warnings.some(x=>x.code==='HORAS_NO_DOCUMENTADAS'));
const strict={...audit,controls:[{id:'CTRL-PENDIENTE',status:'Pendiente'}],findings:[{...audit.findings[0],status:'Abierto',verification:'Comprobar',evidenceIds:'EV-404'}]};
const preflight=review(strict,relations,{mode:'final'});
assert(preflight.blockers.some(x=>x.code==='CONTROLES_PENDIENTES'));
assert(preflight.blockers.some(x=>x.code==='EVIDENCIA_REFERENCIADA_INEXISTENTE'));
assert(preflight.blockers.some(x=>x.code==='SIN_VALIDACION')===false);
console.log('PASS audit quality checks, no false conformity, evidence links, plan priority and closure');
