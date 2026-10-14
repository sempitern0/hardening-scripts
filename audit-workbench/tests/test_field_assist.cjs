'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),ctx={};ctx.globalThis=ctx;
vm.runInNewContext(fs.readFileSync(path.join(root,'js/field-assist.js'),'utf8'),ctx);
const a=ctx.AuditFieldAssist;
const audit={assets:[{_key:'1',id:'ACT-001',name:'server-a',ip:'192.168.1.20',site:'Madrid',owner:'Sistemas'},{_key:'2',id:'ACT-002',name:'server-b',ip:'192.168.1.20',site:'Madrid'}],networks:[{cidr:'192.168.1.0/24',gateway:'192.168.2.1'}],evidence:[{id:'EVD-001',title:'Captura'}],findings:[{owner:'SOC'}]};
assert.deepEqual([...a.suggestions(audit,'assets','site',['Barcelona'])],['Madrid','Barcelona']);
assert(a.assetChoices(audit).some(x=>x.value==='server-a'));
assert.equal(a.appendRef('EVD-001','EVD-001'),'EVD-001');
assert.equal(a.appendRef('EVD-001','EVD-002'),'EVD-001, EVD-002');
assert(a.candidates(audit,'evidence','').some(x=>x.id==='EVD-001'));
assert.equal(a.inSubnet('192.168.1.1','192.168.1.0/24'),true);
for(const [ip,cidr,expected] of [
 ['10.0.0.1','10.0.0.0/8',true],
 ['172.16.255.254','172.16.0.0/16',true],
 ['192.168.1.255','192.168.1.0/24',true],
 ['255.255.255.255','0.0.0.0/0',true],
 ['192.168.1.1','192.168.1.1/32',true],
 ['192.168.1.2','192.168.1.1/32',false],
 ['192.168.1.1','192.168.1.0/33',null]
])assert.equal(a.inSubnet(ip,cidr),expected,ip+' in '+cidr);
assert.equal(a.inSubnet('192.168.2.1','192.168.1.0/24'),false);
assert.equal(a.inSubnet('300.0.0.1','192.168.1.0/24'),null);
assert(a.crossChecks(audit).some(x=>x.code==='IP_ACTIVO_REPETIDA'));
assert(a.crossChecks(audit).some(x=>x.code==='GATEWAY_FUERA_DE_SUBRED'));
const html=fs.readFileSync(path.join(root,'index.html'),'utf8'),sw=fs.readFileSync(path.join(root,'sw.js'),'utf8');
assert(html.indexOf('js/field-assist.js')<html.indexOf('js/audit-quality.js'));
require('./support/sw-contract.js').assertCached('js/field-assist.js');
const app=fs.readFileSync(path.join(root,'js/app.js'),'utf8');
assert(app.includes('data-assist-ref="evidence"')&&app.includes('assist.assetChoices(state)'));
console.log('PASS contextual field suggestions and reversible cross-checks');