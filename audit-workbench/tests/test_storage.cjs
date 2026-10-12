'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'audit-storage.js'), 'utf8');
const context = {console};
context.globalThis = context;
vm.runInNewContext(source, context, {filename:'audit-storage.js'});
const createRepository = context.AuditStorage.createRepository;

function localStorageFixture() {
  const data = new Map();
  let writes = 0;
  return {
    getItem: key => data.has(key) ? data.get(key) : null,
    setItem: (key, value) => {writes++; data.set(key, String(value));},
    removeItem: key => data.delete(key),
    get writes() {return writes;}
  };
}

function mockIndexedDB() {
  const data = new Map();
  let version = 0;
  let created = 0;
  const database = {
    createObjectStore(name, props) {
      assert.equal(name,'audits');assert.equal(props.keyPath,'id');created++;
    },
    transaction(name, kind) {
      assert.equal(name, 'audits');assert(['readonly','readwrite'].includes(kind));
      const tx = {error:null};
      tx.objectStore = () => {
        function requestFor(resultFn) {
          const req = {result:undefined};
          queueMicrotask(() => {
            try {req.result = resultFn();req.onsuccess?.();tx.oncomplete?.();}
            catch (error) {tx.error=error;tx.onerror?.();}
          });
          return req;
        }
        return {
          getAll:()=>requestFor(()=>[...data.values()]),
          put:r=>requestFor(()=>{data.set(r.id,r);return r.id;}),
          delete:id=>requestFor(()=>{data.delete(id);return undefined;})
        };
      };
      return tx;
    }
  };
  return {
    open(name, versionNumber) {
      assert.equal(name, 'audit-workbench-offline');
      const req={result:database,error:null};
      queueMicrotask(()=>{
        if (!version) {version=versionNumber;req.onupgradeneeded?.();}
        req.onsuccess?.();
      });
      return req;
    },
    get created() {return created;}
  };
}

async function main() {
  const key='sysadmin-tools:audit-workbench:records:v3';
  const local=localStorageFixture();
  const logger={warn:()=>{}};
  const fallback=createRepository({storage:local,indexed:null,logger});
  await fallback.init();
  assert.equal(fallback.mode,'almacenamiento local');
  assert.equal((await fallback.list()).length,0);
  const original={id:'a-1',audit:{schemaVersion:3,meta:{client:'Cliente'},evidence:[{sha256:'abc'}]}};
  await fallback.put(original);
  assert.equal(JSON.parse(local.getItem(key))[0].audit.meta.client,'Cliente');
  await fallback.put({...original,audit:{schemaVersion:3,meta:{client:'Cliente actualizado'}}});
  assert.equal((await fallback.list()).length,1,'replace same ID, not duplicate');
  assert.equal((await fallback.list())[0].audit.meta.client,'Cliente actualizado');
  await fallback.put({id:'a-2',audit:{schemaVersion:3}});
  const secondSession=createRepository({storage:local,indexed:null,logger});
  await secondSession.init();
  assert.equal((await secondSession.list()).length,2,'same storage key across browser sessions');
  await secondSession.remove('a-1');
  assert.equal((await fallback.list()).length,1);
  await secondSession.remove('missing');
  assert.equal((await fallback.list()).length,1);

  const invalid=localStorageFixture();
  invalid.setItem(key,'{"unexpected":"object"}');
  const blocked=createRepository({storage:invalid,indexed:null,logger});
  await blocked.init();
  const before=invalid.writes;
  await assert.rejects(blocked.list(),/formato incorrecto/);
  await assert.rejects(blocked.put({id:'overwrite'}),/formato incorrecto/);
  await assert.rejects(blocked.remove('a-1'),/formato incorrecto/);
  assert.equal(invalid.writes,before,'invalid data must never be erased or replaced');

  const indexed=mockIndexedDB(), separateLocal=localStorageFixture();
  const repo=createRepository({storage:separateLocal,indexed,logger});
  await repo.init();
  assert.equal(indexed.created,1);
  assert.equal(repo.mode,'IndexedDB');
  await repo.put(original);
  assert.equal((await repo.list()).length,1);
  await repo.put({id:'a-2',audit:{schemaVersion:3}});
  assert.equal((await repo.list()).length,2);
  await repo.remove('a-1');
  assert.equal((await repo.list())[0].id,'a-2');
  assert.equal(separateLocal.writes,0,'IndexedDB does not write the localStorage fallback');
  console.log('PASS storage: unchanged keys, IndexedDB lifecycle, fallback, safe corrupt-data behavior');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
