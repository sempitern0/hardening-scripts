/* Audit Workbench — local, deterministic relationships and document checks.
 * No network access, storage, or DOM access. The current JSON schema remains v3.
 */
'use strict';
(() => {
  const CATEGORIES = Object.freeze(['assets', 'controls', 'findings']);
  const PREFIXES = Object.freeze({assets:'ACT',controls:'CTRL',findings:'FND',evidence:'EVD'});
  const validKey = value => typeof value === 'string' && value.length > 0 && value.length <= 100;
  const str = value => typeof value === 'string' ? value : '';
  function normalizeLinks(raw) {
    const out = {};
    for (const category of CATEGORIES) {
      const source = Array.isArray(raw?.[category]) ? raw[category] : [];
      out[category] = [...new Set(source.slice(0,500).filter(validKey))].slice(0, 500);
    }
    return out;
  }
  function nextCode(records, type) {
    const prefix = PREFIXES[type];
    if (!prefix) throw new TypeError('Categoría desconocida');
    const used = new Set((records || []).map(item => str(item.id).toUpperCase()));
    let number = 1;
    while (used.has(`${prefix}-${String(number).padStart(3,'0')}`)) number++;
    return `${prefix}-${String(number).padStart(3,'0')}`;
  }
  const itemLabel = (item, kind) => {
    if (!item) return 'Registro eliminado';
    const description = str(item.title || item.name).trim();
    const code = str(item.id).trim();
    return [code, description].filter(Boolean).join(' · ') || `${kind} sin nombre`;
  };
  function linkedEvidence(audit, kind, key) {
    return (audit.evidence || []).filter(e => normalizeLinks(e.links)[kind]?.includes(key));
  }
  function referenceProblems(audit) {
    const messages = [];
    const lookup = Object.fromEntries(CATEGORIES.map(category => [category, new Set((audit[category] || []).map(item => item._key))]));
    const seen = new Set();
    for (const category of [...CATEGORIES, 'evidence']) {
      for (const item of audit[category] || []) {
        const id = str(item.id).trim().toUpperCase();
        if (id) {
          const scoped = `${category}:${id}`;
          if (seen.has(scoped)) messages.push(`Identificador repetido en ${category}: ${id}`);
          seen.add(scoped);
        }
      }
    }
    for (const evidence of audit.evidence || []) {
      const name = itemLabel(evidence, 'evidence');
      for (const category of CATEGORIES) {
        for (const key of normalizeLinks(evidence.links)[category]) {
          if (!lookup[category].has(key)) messages.push(`Referencia ausente: ${name} → ${category}`);
        }
      }
      if (evidence.fileSha256 && !/^[a-f0-9]{64}$/i.test(evidence.fileSha256)) messages.push(`SHA-256 del archivo no válido: ${name}`);
    }
    return messages;
  }
  function evidenceManifest(audit) {
    return {
      kind: 'audit-workbench-evidence-manifest-v1',
      reportId: str(audit.meta?.reportId),
      evidence: (audit.evidence || []).map(row => ({
        id:str(row.id), title:str(row.title), fileName:str(row.fileName),
        fileBytes:Number.isSafeInteger(row.fileBytes) ? row.fileBytes : null,
        originalSha256:str(row.fileSha256), captured:str(row.captured),
        links:normalizeLinks(row.links)
      })),
      notes:'Las huellas SHA-256 se calculan sobre el archivo original seleccionado. Las imágenes incrustadas se optimizan y no tienen necesariamente la misma huella. Conserve el archivo original por separado.'
    };
  }
  globalThis.AuditRelations = Object.freeze({CATEGORIES, normalizeLinks, nextCode, itemLabel, linkedEvidence, referenceProblems, evidenceManifest});
})();
