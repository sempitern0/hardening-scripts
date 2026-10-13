/* Offline inventory intake: parses untrusted CSV/JSON, never touches audit state. */
'use strict';
(() => {
  const KIND='audit-workbench-discovery-v1';
  const BLOCKS=['assets','networks','software'];
  const LIMIT_BYTES=2*1024*1024, LIMIT_ROWS=500, LIMIT_COLUMNS=48;
  const FIELDS=Object.freeze({
    assets:['id','name','type','vendor','model','serial','ip','os','cpu','ram','storage','site','owner','notes'],
    networks:['name','cidr','vlan','gateway','dns','purpose','firewall','exposure','notes'],
    software:['name','version','vendor','asset','license','support','exposure','notes']
  });
  const ALIASES={
    assets:{
      id:['assetid','identifier','identificador','deviceid'],
      name:['hostname','host','computername','device','device_name','nombre','activo','equipo'],
      type:['category','role','tipo','categoria'],vendor:['manufacturer','fabricante','marca'],
      model:['modelo'],serial:['serialnumber','serial_number','serie','numero_de_serie'],
      ip:['ipaddress','ipv4','direccionip','direccion_ip','ip_address'],
      os:['operatingsystem','operating_system','sistemaoperativo','sistema_operativo','platform'],
      cpu:['processor','procesador'],ram:['memory','memoria','memoryram'],storage:['disk','disks','almacenamiento'],
      site:['location','ubicacion','sede'],owner:['responsable','propietario'],notes:['observaciones','description']
    },
    networks:{
      name:['segment','segmento','network','red','interface','interfaz'],
      cidr:['subnet','subred','prefix','networkcidr'],vlan:['vlanid','vlan_id'],
      gateway:['router','defaultgateway','puertadeenlace','gatewayip'],
      dns:['nameservers','resolvers','dnsservers','servidoresdns'],
      purpose:['function','funcion','servicio'],firewall:['acl','reglas'],
      exposure:['exposicion','accessibility'],notes:['observaciones','description']
    },
    software:{
      name:['product','producto','application','aplicacion','software','package','paquete','servicio'],
      version:['release','versioninstalada','version_instalada'],
      vendor:['publisher','fabricante','manufacturer'],asset:['host','hostname','equipo','activo'],
      license:['licencia'],support:['eol','soporte'],exposure:['exposicion'],notes:['observaciones','description']
    }
  };
  const normalize=s=>String(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
  const str=v=>typeof v==='string'?v.trim().slice(0,2000):typeof v==='number'&&Number.isFinite(v)?String(v):'';
  const isObject=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
  const labels=Object.fromEntries(BLOCKS.map(block=>{
    const mapping={};
    for(const field of FIELDS[block])for(const alias of [field,...(ALIASES[block][field]||[])])mapping[normalize(alias)]=field;
    return [block,mapping];
  }));
  function parseCSV(text){
    const source=String(text||'').replace(/^\uFEFF/,'');
    if(!source.trim())throw Error('El CSV está vacío.');
    const first=source.split(/\r?\n/,1)[0];
    const score=ch=>{let quoted=false,n=0;for(let i=0;i<first.length;i++){if(first[i]==='"'){if(quoted&&first[i+1]==='"')i++;else quoted=!quoted;}else if(!quoted&&first[i]===ch)n++;}return n;};
    const delimiter=score(';')>score(',')?';':',';
    const rows=[];let row=[],cell='',quoted=false;
    for(let i=0;i<source.length;i++){
      const ch=source[i];
      if(ch==='"'){if(quoted&&source[i+1]==='"'){cell+='"';i++;}else quoted=!quoted;}
      else if(ch===delimiter&&!quoted){row.push(cell);cell='';}
      else if((ch==='\r'||ch==='\n')&&!quoted){if(ch==='\r'&&source[i+1]==='\n')i++;row.push(cell);cell='';if(row.some(v=>v.trim()!==''))rows.push(row);row=[];if(rows.length>LIMIT_ROWS+1)throw Error('El CSV supera 500 registros. Divide el archivo.');}
      else cell+=ch;
      if(cell.length>8192)throw Error('Una celda CSV supera el tamaño permitido.');
    }
    if(quoted)throw Error('CSV inválido: comillas sin cerrar.');
    row.push(cell);if(row.some(v=>v.trim()!==''))rows.push(row);
    if(rows.length<2)throw Error('El CSV necesita encabezados y al menos un registro.');
    if(rows[0].length>LIMIT_COLUMNS)throw Error('Demasiadas columnas CSV.');
    const header=rows.shift().map(s=>s.trim());
    if(new Set(header.map(normalize)).size!==header.length)throw Error('Cabeceras duplicadas.');
    return rows.map((cells,index)=>{
      if(cells.length!==header.length)throw Error('CSV: número de columnas incorrecto en fila '+(index+2)+'.');
      return Object.fromEntries(header.map((name,i)=>[name,cells[i]]));
    });
  }
  function selectRows(payload,block){
    if(Array.isArray(payload))return payload;
    if(!isObject(payload))throw Error('Estructura JSON no admitida.');
    if(payload.schemaVersion===3&&!payload.kind)throw Error('Este archivo parece un expediente completo: usa Importar expediente, no Captura asistida.');
    if(payload.kind&&payload.kind!==KIND)throw Error('Formato de captura no reconocido.');
    if(payload.kind&&payload.schemaVersion!==1)throw Error('Versión de captura incompatible.');
    if(payload.kind){
      if(!isObject(payload.items))throw Error('La captura no contiene el objeto items.');
      return payload.items[block]||[];
    }
    if(Array.isArray(payload[block]))return payload[block];
    if(Array.isArray(payload.records))return payload.records;
    throw Error('No encuentro registros para '+block+'. Selecciona la sección correcta.');
  }
  function normalizeRows(rows,block){
    if(!BLOCKS.includes(block))throw Error('Sección de inventario desconocida.');
    if(!Array.isArray(rows)||rows.length===0)throw Error('No hay registros en la sección seleccionada.');
    if(rows.length>LIMIT_ROWS)throw Error('Máximo 500 registros por archivo.');
    const map=labels[block],out=[];
    for(let i=0;i<rows.length;i++){
      if(!isObject(rows[i]))throw Error('Registro '+(i+1)+' no es un objeto.');
      const entry={},keys=Object.keys(rows[i]);
      if(keys.length>LIMIT_COLUMNS)throw Error('Registro con demasiados campos.');
      for(const key of keys){const field=map[normalize(key)];if(field&&!Object.prototype.hasOwnProperty.call(entry,field)){entry[field]=str(rows[i][key]);}}
      if(block==='assets'&&!entry.name&&!entry.serial&&!entry.id)throw Error('Activo '+(i+1)+' sin hostname, serie ni identificador.');
      if(block==='networks'&&!entry.name&&!entry.cidr)throw Error('Red '+(i+1)+' sin nombre ni CIDR.');
      if(block==='software'&&!entry.name)throw Error('Software '+(i+1)+' sin nombre.');
      out.push(entry);
    }
    return out;
  }
  function parse(text,{block,filename='',size}={}){
    if(!BLOCKS.includes(block))throw Error('Selecciona Hardware, Redes o Software.');
    if(typeof text!=='string')throw Error('El archivo no contiene texto.');
    if((size??new TextEncoder().encode(text).length)>LIMIT_BYTES)throw Error('El límite por archivo es 2 MiB.');
    const isCSV=/\.csv$/i.test(filename);
    const payload=isCSV?null:JSON.parse(text.replace(/^\uFEFF/,''));
    const rows=isCSV?parseCSV(text):selectRows(payload,block);
    return Object.freeze({block,rows:normalizeRows(rows,block),source:isCSV?'CSV':payload?.kind===KIND?'Recopilador local':'JSON',
      capturedAt:typeof payload?.capturedAt==='string'?payload.capturedAt.slice(0,40):'',
      platform:typeof payload?.source?.platform==='string'?payload.source.platform.slice(0,60):''});
  }
  const same=(a,b)=>normalize(a)===normalize(b);
  function identityMatches(block,row,existing){
    if(block==='assets')return Boolean((row.serial&&existing.serial&&same(row.serial,existing.serial))||
      (row.name&&existing.name&&same(row.name,existing.name))||(row.id&&existing.id&&same(row.id,existing.id)));
    if(block==='networks')return Boolean((row.cidr&&existing.cidr&&same(row.cidr,existing.cidr))||(row.name&&existing.name&&same(row.name,existing.name)));
    return Boolean(row.name&&existing.name&&same(row.name,existing.name)&&same(row.asset,existing.asset));
  }
  function reconcile(parsed,existing=[]){
    const known=Array.isArray(existing)?existing:[];
    const taken=[];
    return parsed.rows.map((record,index)=>{
      const previous=known.find(row=>identityMatches(parsed.block,record,row))||taken.find(row=>identityMatches(parsed.block,record,row));
      const differences=previous?Object.keys(record).filter(key=>record[key]&&!same(record[key],previous[key])).map(key=>key+': '+str(previous[key]).slice(0,70)+' → '+record[key].slice(0,70)):[];
      if(!previous)taken.push(record);
      return {index,record,status:previous?(differences.length?'conflicto':'duplicado'):'nuevo',differences};
    });
  }
  globalThis.AuditInventoryImport=Object.freeze({KIND,BLOCKS,LIMIT_BYTES,LIMIT_ROWS,FIELDS,parse,parseCSV,reconcile});
})();