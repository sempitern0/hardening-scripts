'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'../..');
function loadWorker(extra={}){
 const handlers={};
 const context=vm.createContext({URL,Request,Response,console,...extra,self:{registration:{scope:'https://audit.example/'},addEventListener:(type,handler)=>{handlers[type]=handler;},...extra.self}});
 vm.runInContext(fs.readFileSync(path.join(root,'sw.js'),'utf8'),context);
 return {context,handlers,name:vm.runInContext('CACHE_NAME',context),core:Array.from(vm.runInContext('CORE',context))};
}
function assertCached(...assets){
 const worker=loadWorker();
 assert.match(worker.name,/^audit-workbench-shell-v\d+-[a-z0-9-]+$/,'Expected a versioned app-shell cache');
 for(const asset of assets){
  assert(worker.core.includes('./'+asset),'Offline asset missing: '+asset);
  assert(fs.statSync(path.join(root,asset)).size>0,'Empty offline asset: '+asset);
 }
}
module.exports={loadWorker,assertCached};
