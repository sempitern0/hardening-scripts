/* Audit Workbench offline persistence. Keeps the existing IndexedDB and fallback keys. */
'use strict';
(() => {
  const DATABASE_NAME = 'audit-workbench-offline';
  const OBJECT_STORE = 'audits';
  const DEFAULT_FALLBACK_KEY = 'sysadmin-tools:audit-workbench:records:v3';

  function createRepository({
    fallbackKey = DEFAULT_FALLBACK_KEY,
    storage = globalThis.localStorage,
    indexed = globalThis.indexedDB,
    logger = console
  } = {}) {
    let database = null;

    function openDatabase() {
      return new Promise((resolve, reject) => {
        if (!indexed) return reject(Error('IndexedDB no disponible'));
        const request = indexed.open(DATABASE_NAME, 1);
        request.onupgradeneeded = () => request.result.createObjectStore(OBJECT_STORE, {keyPath: 'id'});
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error || Error('No se pudo abrir IndexedDB'));
        request.onblocked = () => reject(Error('Cierra las otras pestañas de la aplicación y reintenta.'));
      });
    }

    function transaction(kind, action) {
      return new Promise((resolve, reject) => {
        const tx = database.transaction(OBJECT_STORE, kind);
        const objectStore = tx.objectStore(OBJECT_STORE);
        let result;
        tx.oncomplete = () => resolve(result);
        tx.onerror = () => reject(tx.error || Error('Error de almacenamiento'));
        tx.onabort = () => reject(tx.error || Error('Transacción cancelada'));
        const request = action(objectStore);
        if (request) request.onsuccess = () => { result = request.result; };
      });
    }

    // Invalid cached data must never be silently replaced by an empty list.
    function fallback() {
      const raw = storage.getItem(fallbackKey);
      if (raw === null) return [];
      const data = JSON.parse(raw);
      if (!Array.isArray(data)) throw Error('Los expedientes locales tienen un formato incorrecto. Exporta o recupera una copia antes de continuar.');
      return data;
    }

    return Object.freeze({
      get mode() { return database ? 'IndexedDB' : 'almacenamiento local'; },
      async init() {
        try { database = await openDatabase(); }
        catch (error) {
          logger.warn('IndexedDB no disponible; almacenamiento local alternativo:', error);
          // Force access check while preparing the UI, as in earlier versions.
          storage.getItem(fallbackKey);
        }
      },
      async list() { return database ? transaction('readonly', store => store.getAll()) : fallback(); },
      async putMany(items) {
        if(!Array.isArray(items)||items.some(item=>!item||typeof item.id!=='string'||!item.id)||
           new Set(items.map(item=>item.id)).size!==items.length)
          throw Error('Lote de auditorías inválido o con identificadores repetidos.');
        if(!items.length)return;
        if(database)return transaction('readwrite',store=>{
          for(const item of items)store.put(item);
          return null;
        });
        const saved=fallback(), byId=new Map(items.map(item=>[item.id,item]));
        const known=new Set(saved.map(item=>item.id));
        const merged=saved.map(item=>byId.get(item.id)||item);
        for(const item of items)if(!known.has(item.id))merged.push(item);
        // Build the full next library and write once; failed writes leave the original intact.
        storage.setItem(fallbackKey,JSON.stringify(merged));
      },
      async put(record) {
        if (database) return transaction('readwrite', store => store.put(record));
        const records = fallback().filter(item => item.id !== record.id);
        records.push(record);
        storage.setItem(fallbackKey, JSON.stringify(records));
      },
      async remove(id) {
        if (database) return transaction('readwrite', store => store.delete(id));
        storage.setItem(fallbackKey, JSON.stringify(fallback().filter(item => item.id !== id)));
      }
    });
  }

  globalThis.AuditStorage = Object.freeze({createRepository});
})();
