/* Audit Workbench — offline, dependency-free tabular exports. */
'use strict';
(() => {
  const enc = new TextEncoder();
  const xmlEscape = value => String(value ?? '').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  const display = value => {
    if (value == null) return '';
    if (Array.isArray(value)) return value.map(display).join('; ');
    if (typeof value === 'object') return '[Datos estructurados: consultar expediente JSON]';
    return String(value).slice(0, 32767);
  };
  const sections = audit => {
    const basic = audit.meta || {};
    const tables = [{
      name: 'Resumen',
      headers: ['Campo', 'Valor'],
      rows: [['Cliente', basic.client], ['Referencia', basic.reportId], ['Proyecto', basic.project],
        ['Tipo', basic.type], ['Clasificación', basic.classification], ['Fecha de inicio', basic.start],
        ['Fecha de fin', basic.end], ['Versión del informe', basic.revision],
        ['Auditores', (basic.auditTeam || []).map(m => m.name).join('; ')],
        ['Alcance', basic.scope], ['Exclusiones', basic.exclusions]]
    }];
    const defs = [
      ['Hardware', ['name','type','vendor','model','serial','ip','os','cpu','ram','storage','site','owner','criticality','state','notes','osLicense','osUpdates','avProduct','avRealtime','avUpdated','cpuSpeed','ramMax','ramSlots','diskCapacity','diskType','gpuType','gpuMemory','ethernetPort','cableCategory','ethernetSpeed','wifiAdapter','wifiSignal','processReview','localAccounts','adminAccounts'],
        ['Activo','Tipo','Fabricante','Modelo','Serie','IP','Sistema operativo','CPU','RAM','Almacenamiento','Ubicación','Responsable','Criticidad','Estado','Observaciones','Licencia SO','Actualizaciones SO','Antivirus / EDR','Protección en tiempo real','Firmas / motor','CPU GHz','RAM máxima GB','Ranuras RAM','Disco GB','Tipo de disco','Tipo de GPU','Memoria GPU GB','Ethernet','Categoría cable','Enlace Mbps','Wi-Fi','Señal dBm','Procesos revisados','Usuarios revisados','Privilegios revisados']],
      ['Redes', ['name','cidr','vlan','gateway','dns','purpose','firewall','exposure','notes','ssid','wifiSecurity','wifiSignal','wifiChannel','wifiStandard','wifiBand','contractedRate','measuredRate'],
        ['Red / dispositivo','CIDR','VLAN','Gateway','DNS / DHCP','Función','Firewall','Exposición','Observaciones','SSID','Seguridad Wi-Fi','Señal dBm','Canal Wi-Fi','Estándar 802.11','Banda Wi-Fi','Velocidad contratada Mbps','Velocidad medida Mbps']],
      ['Software', ['name','version','vendor','asset','license','support','exposure','notes','licenseType','licenseStatus','installedAt','updateStatus','updatedAt'],
        ['Producto','Versión','Fabricante','Activo','Licencia','Soporte','Exposición','Observaciones','Tipo de licencia','Cumplimiento licencia','Fecha instalación','Estado de actualización','Fecha actualización']],
      ['CVE', ['id','title','asset','status','severity','cvss','published','source','references','notes'],
        ['CVE','Descripción','Activo','Estado','Severidad','CVSS','Publicación','Fuente','Referencias','Notas']],
      ['Controles', ['id','category','name','asset','status','method','reference','evidenceIds','notes'],
        ['ID','Área','Control','Activo','Resultado','Método','Marco','Evidencias','Observaciones']],
      ['Hallazgos', ['id','title','severity','status','asset','cvss','likelihood','impact','description','risk','evidenceIds','references','recommendation','owner','deadline','verification','residual'],
        ['ID','Hallazgo','Severidad','Estado','Activo','CVSS','Probabilidad','Impacto','Descripción','Riesgo','Evidencias','Referencias','Remediación','Responsable','Fecha objetivo','Verificación de cierre','Riesgo residual']],
      ['Evidencias', ['id','title','asset','captured','source','sha256','notes'],
        ['ID','Título','Activo / hallazgo','Fecha','Origen','SHA-256','Notas']]
    ];
    for (const [name, fields, headers] of defs) {
      const key = ({Hardware:'assets', Redes:'networks', Software:'software', CVE:'cves', Controles:'controls', Hallazgos:'findings', Evidencias:'evidence'})[name];
      tables.push({name, headers, rows:(Array.isArray(audit[key]) ? audit[key] : []).map(record => fields.map(field => record?.[field]))});
    }
    return tables;
  };
  const safeCell = value => {
    const s = display(value);
    // Guard against spreadsheet formula injection in programs that auto-evaluate CSV cells.
    return /^[\s\u0000-\u001f]*[=+@\-\t\r]/.test(s) ? "'" + s : s;
  };
  const csv = table => {
    const quote = value => '"' + safeCell(value).replace(/"/g, '""') + '"';
    return '\ufeff' + [table.headers, ...table.rows].map(row => row.map(quote).join(';')).join('\r\n') + '\r\n';
  };
  const crcTable = (() => {
    const table = [];
    for (let i = 0; i < 256; i++) {
      let c = i;
      for (let j = 0; j < 8; j++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
      table.push(c >>> 0);
    }
    return table;
  })();
  const crc32 = bytes => {
    let crc = 0xffffffff;
    for (const b of bytes) crc = crcTable[(crc ^ b) & 255] ^ (crc >>> 8);
    return (crc ^ 0xffffffff) >>> 0;
  };
  const u16 = (view, pos, val) => view.setUint16(pos, val, true);
  const u32 = (view, pos, val) => view.setUint32(pos, val, true);
  function makeZip(entries) {
    // Stored ZIP entries, compatible with XLSX and fully offline; no compression dependencies.
    const local = [], central = [];
    let offset = 0;
    for (const [name, content] of entries) {
      const filename = enc.encode(name), bytes = enc.encode(content), checksum = crc32(bytes);
      const header = new Uint8Array(30 + filename.length), view = new DataView(header.buffer);
      u32(view, 0, 0x04034b50); u16(view, 4, 20); u16(view, 6, 0x0800);
      u32(view, 14, checksum); u32(view, 18, bytes.length); u32(view, 22, bytes.length);
      u16(view, 26, filename.length); header.set(filename, 30);
      local.push(header, bytes);
      const dir = new Uint8Array(46 + filename.length), dv = new DataView(dir.buffer);
      u32(dv, 0, 0x02014b50); u16(dv, 4, 20); u16(dv, 6, 20); u16(dv, 8, 0x0800);
      u32(dv, 16, checksum); u32(dv, 20, bytes.length); u32(dv, 24, bytes.length);
      u16(dv, 28, filename.length); u32(dv, 42, offset); dir.set(filename, 46);
      central.push(dir);
      offset += header.length + bytes.length;
    }
    const dirSize = central.reduce((size, part) => size + part.length, 0);
    const end = new Uint8Array(22), endView = new DataView(end.buffer);
    u32(endView, 0, 0x06054b50); u16(endView, 8, entries.length); u16(endView, 10, entries.length);
    u32(endView, 12, dirSize); u32(endView, 16, offset);
    return new Blob([...local, ...central, end], {type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
  }
  const cellRef = (column, row) => {
    let label = '';
    while (column > 0) {column--; label = String.fromCharCode(65 + (column % 26)) + label; column = Math.floor(column / 26);}
    return label + row;
  };
  const inlineCell = (column, row, value, style = 0) => `<c r="${cellRef(column,row)}" s="${style}" t="inlineStr"><is><t xml:space="preserve">${xmlEscape(display(value))}</t></is></c>`;
  const makeSheet = table => {
    const columns = table.headers.length;
    const title = `<row r="1" ht="34" customHeight="1">${inlineCell(1,1,'AUDIT WORKBENCH · '+table.name,2)}</row>`;
    const sub = `<row r="2" ht="23" customHeight="1">${inlineCell(1,2,'Exportación tabular · No sustituye al expediente JSON ni al informe PDF.',3)}</row>`;
    const headers = `<row r="4" ht="29" customHeight="1">${table.headers.map((h,i) => inlineCell(i+1,4,h,1)).join('')}</row>`;
    const rows = table.rows.map((data,i) => `<row r="${i+5}" ht="21" customHeight="1">${data.map((v,j) => inlineCell(j+1,i+5,v,i%2===0?4:0)).join('')}</row>`).join('');
    const widths = table.headers.map((h,i)=>`<col min="${i+1}" max="${i+1}" width="${Math.min(44,Math.max(14,h.length+5))}" customWidth="1"/>`).join('');
    const merged = columns>1?`<mergeCells count="2"><mergeCell ref="A1:${cellRef(columns,1)}"/><mergeCell ref="A2:${cellRef(columns,2)}"/></mergeCells>`:'';
    const filter = table.rows.length?`<autoFilter ref="A4:${cellRef(columns,Math.max(5,table.rows.length+4))}"/>`:'';
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="19"/><cols>${widths}</cols><sheetData>${title}${sub}${headers}${rows}</sheetData>${merged}${filter}<pageMargins left="0.55" right="0.55" top="0.7" bottom="0.7" header="0.2" footer="0.2"/></worksheet>`;
  };
  function xlsx(audit) {
    const sheets = sections(audit);
    const types = sheets.map((_,i)=>`<Override PartName="/xl/worksheets/sheet${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('');
    const contentTypes = `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${types}</Types>`;
    const workbook = `<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.map((s,i)=>`<sheet name="${xmlEscape(s.name)}" sheetId="${i+1}" r:id="rId${i+1}"/>`).join('')}</sheets></workbook>`;
    const relations = `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${sheets.map((_,i)=>`<Relationship Id="rId${i+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i+1}.xml"/>`).join('')}<Relationship Id="rId${sheets.length+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`;
    const styles = `<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="11"/><name val="Aptos"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Aptos"/></font><font><b/><color rgb="FF123A50"/><sz val="17"/><name val="Aptos"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF174558"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF0F5F7"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="5"><xf fontId="0" fillId="0" borderId="0" xfId="0"/><xf fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf fontId="0" fillId="0" borderId="0" xfId="0"/><xf fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1"/></cellXfs></styleSheet>`;
    const baseRel = `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`;
    const entries = [
      ['[Content_Types].xml',contentTypes], ['_rels/.rels',baseRel],
      ['xl/workbook.xml',workbook], ['xl/_rels/workbook.xml.rels',relations],
      ['xl/styles.xml',styles], ...sheets.map((s,i)=>[`xl/worksheets/sheet${i+1}.xml`,makeSheet(s)])
    ];
    return makeZip(entries);
  }
  globalThis.AuditTabular = Object.freeze({sections, csv, xlsx});
})();
