/* Audit Workbench - local-only audit records. No network APIs are used. */
'use strict';
(() => {
  const VERSION = 2;
  const LEGACY_STORE = 'sysadmin-tools:audit-workbench:v2';
  const ACTIVE_KEY = 'sysadmin-tools:audit-workbench:active:v3';
  const FALLBACK_KEY = 'sysadmin-tools:audit-workbench:records:v3';
  const PALETTE_KEY = 'sysadmin-tools:audit-workbench:palette:v1';
  const palettes = ['ocean', 'forest', 'indigo', 'graphite', 'midnight', 'obsidian', 'pine-dark', 'amethyst-dark', 'crimson-dark'];
  const CVE_PATTERN = /^CVE-(?:1999|2\d{3})-\d{4,}$/i;
  const safeLogo = value => typeof value === 'string' && value.length <= 650000 && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(value) ? value : '';
  const hardwareVendors = ['Dell', 'HPE / Hewlett Packard Enterprise', 'HP', 'Lenovo', 'Cisco', 'Fortinet', 'Palo Alto Networks', 'Juniper', 'Ubiquiti', 'MikroTik', 'Aruba / HPE', 'Netgear', 'TP-Link', 'Synology', 'QNAP', 'Supermicro', 'IBM', 'Fujitsu', 'Huawei', 'ASUS', 'Acer', 'Apple', 'Samsung', 'Intel', 'AMD', 'VMware', 'Proxmox', 'Nutanix', 'APC / Schneider Electric', 'Eaton', 'Zyxel', 'Sophos', 'SonicWall', 'WatchGuard', 'Brother', 'Epson', 'Canon'];
  const hardwareModels = ['PowerEdge R350', 'PowerEdge R450', 'PowerEdge R550', 'PowerEdge R650', 'PowerEdge R750', 'PowerEdge R760', 'ProLiant DL360 Gen10', 'ProLiant DL380 Gen10', 'ProLiant DL360 Gen11', 'ProLiant DL380 Gen11', 'ThinkSystem SR630', 'ThinkSystem SR650', 'Catalyst 9200', 'Catalyst 9300', 'Catalyst 9500', 'FortiGate 40F', 'FortiGate 60F', 'FortiGate 80F', 'FortiGate 100F', 'FortiGate 200F', 'PA-440', 'PA-820', 'UniFi Dream Machine', 'UniFi Dream Machine Pro', 'UniFi Switch Pro', 'UniFi U6 Pro', 'UniFi U7 Pro', 'MikroTik CCR2004', 'MikroTik RB5009', 'Synology DS923+', 'Synology DS1522+', 'QNAP TS-464', 'QNAP TS-873A', 'Proxmox VE (VM)', 'VMware ESXi (VM)', 'Hyper-V (VM)', 'APC Smart-UPS', 'Eaton 9PX'];
  const presets = {
    hardware: ['Servidor físico', 'Servidor virtual', 'Estación de trabajo', 'Portátil', 'Tablet', 'Firewall', 'Switch', 'Router', 'Access point', 'NAS / SAN', 'Impresora', 'Hypervisor', 'UPS / SAI', 'IoT / OT'],
    operating: ['Windows 11 Pro', 'Windows 11 Enterprise', 'Windows 10 (EOL)', 'Windows Server 2025', 'Windows Server 2022', 'Windows Server 2019', 'Windows Server 2016', 'Windows Server 2012 R2 (EOL)', 'Debian 13', 'Debian 12', 'Debian 11', 'Ubuntu Server 26.04 LTS', 'Ubuntu Server 24.04 LTS', 'Ubuntu Server 22.04 LTS', 'Ubuntu Desktop 24.04 LTS', 'RHEL 10', 'RHEL 9', 'RHEL 8', 'Rocky Linux 10', 'Rocky Linux 9', 'AlmaLinux 10', 'AlmaLinux 9', 'Fedora Server', 'CentOS Stream 10', 'SUSE Linux Enterprise 15', 'openSUSE Leap', 'Arch Linux', 'Alpine Linux', 'Proxmox VE 9', 'Proxmox VE 8', 'VMware ESXi 8', 'VMware ESXi 7', 'Hyper-V Server / Windows Hyper-V', 'TrueNAS SCALE', 'pfSense Plus', 'pfSense CE', 'OPNsense', 'FortiOS', 'Cisco IOS / IOS XE', 'Cisco NX-OS', 'RouterOS', 'UniFi OS', 'Synology DSM 7', 'QTS / QuTS hero', 'macOS Sequoia', 'macOS Tahoe', 'iOS', 'iPadOS', 'Android', 'ChromeOS', 'FreeBSD', 'OpenBSD', 'Firmware propietario', 'SO no identificado'],
    function: ['Usuarios', 'Administración', 'Servidores', 'DMZ', 'Wi-Fi corporativa', 'Wi-Fi invitados', 'Voz / VoIP', 'Backups', 'IoT / OT', 'Almacenamiento', 'Interconexión', 'Gestión de hipervisores'],
    support: ['Vigente', 'EOL / Fuera de soporte', 'Soporte extendido', 'Pendiente de verificar', 'No aplica'],
    license: ['Libre / Open source', 'Propietaria', 'Suscripción', 'OEM', 'Sin licencia acreditada', 'No aplica', 'Pendiente de revisar'],
    exposure: ['Interno', 'Perimetral', 'Internet / Pública', 'VPN', 'Segmentada', 'Sin exposición', 'Pendiente de revisar'],
    risk: ['Crítico', 'Alto', 'Medio', 'Bajo', 'Sin evaluar'],
    owner: ['Infraestructura', 'Seguridad / SOC', 'Sistemas', 'Redes', 'Desarrollo', 'Proveedor externo', 'Negocio', 'Pendiente de asignar'],
    cpu: ['Intel Xeon Silver', 'Intel Xeon Gold', 'Intel Xeon Platinum', 'AMD EPYC', 'Intel Core i3', 'Intel Core i5', 'Intel Core i7', 'Intel Core i9', 'AMD Ryzen 5', 'AMD Ryzen 7', 'AMD Ryzen 9', 'Apple Silicon M1', 'Apple Silicon M2', 'Apple Silicon M3', 'Apple Silicon M4', 'ARM / SoC', 'Procesador virtual (vCPU)', 'No identificado'],
    ram: ['2 GiB', '4 GiB', '8 GiB', '16 GiB', '32 GiB', '48 GiB', '64 GiB', '96 GiB', '128 GiB', '192 GiB', '256 GiB', '384 GiB', '512 GiB', '1 TiB', '2 TiB', 'No identificado'],
    storage: ['SSD NVMe', 'SSD SATA', 'HDD SATA', 'SAS / RAID', 'RAID 1', 'RAID 5', 'RAID 6', 'RAID 10', 'SAN Fibre Channel', 'iSCSI', 'NFS', 'Ceph / almacenamiento distribuido', 'Almacenamiento virtual', 'No identificado'],
    site: ['CPD principal', 'CPD secundario', 'Rack de comunicaciones', 'Oficina central', 'Delegación', 'Sucursal', 'Teletrabajo / remoto', 'Cloud / IaaS', 'Laboratorio', 'Otro edificio', 'Pendiente de identificar']
  };
  const LIMIT_ROWS = 500;
  const nav = [
    ['dashboard','▦','Vista general'],['records','▤','Auditorías guardadas'],['engagement','◈','Cliente y alcance'],
    ['assets','▤','Hardware'],['networks','◇','Redes'],['software','▧','Software'],['cves','◉','Vulnerabilidades CVE'],
    ['controls','✓','Controles'],['findings','⚑','Hallazgos'],
    ['evidence','▣','Evidencias'],['legal','§','Cláusulas y privacidad'],['delivery','▥','Informe final']
  ];
  const metaFields = [
    ['client','Organización / cliente'],['project','Nombre del proyecto'],
    ['reportId','Identificador del informe'],['revision','Versión del informe'],
    ['auditor','Auditor / consultora'],['contact','Contacto del cliente'],
    ['start','Inicio de la auditoría','date'],['end','Fin de la auditoría','date'],
    ['classification','Clasificación','select',['Confidencial','Uso interno','Público']],
    ['type','Modalidad','select',['Auditoría de sistemas','Auditoría de infraestructura','Revisión de ciberseguridad','Pentesting autorizado','Mixta']],
    ['objectives','Objetivos y contexto','textarea'],['scope','Alcance autorizado (activos, redes y sedes)','textarea'],
    ['exclusions','Exclusiones y pruebas prohibidas','textarea'],['rules','Reglas de compromiso y autorizaciones','textarea'],
    ['methodology','Metodología y referencias','textarea'],['limitations','Limitaciones y cobertura real','textarea']
  ];
  const finalFields = [
    ['executive','Resumen ejecutivo','textarea'],['strengths','Puntos fuertes','textarea'],
    ['weaknesses','Principales debilidades','textarea'],['assessment','Valoración general del riesgo','textarea'],
    ['roadmap','Plan de mejora priorizado','textarea'],['cleanup','Limpieza y acciones posteriores a las pruebas','textarea'],
    ['nextSteps','Próximos pasos y reevaluación','textarea'],['disclaimer','Consideraciones de responsabilidad','textarea'],
    ['signoff','Firma / responsable del informe']
  ];
  const legalFields = [
    ['confidentiality','Confidencialidad y destinatarios autorizados','textarea'],
    ['authorization','Autorización y reglas de compromiso','textarea'],
    ['scopeNotice','Naturaleza temporal, pruebas no ejecutadas y limitaciones','textarea'],
    ['dataProtection','Protección de datos personales y custodia','textarea'],
    ['retention','Conservación, devolución y eliminación de evidencias','textarea'],
    ['thirdParties','Transferencia a terceros y canales de entrega','textarea'],
    ['responsibility','Responsabilidades, validación y firma','textarea']
  ];
  const legalDefaults = () => ({
    confidentiality:'Documento de uso confidencial destinado exclusivamente al cliente y a las personas que este autorice expresamente. Se prohíbe su difusión no autorizada; las copias deben protegerse conforme a su clasificación.',
    authorization:'La evaluación se ha realizado únicamente sobre los activos y las pruebas autorizados por el cliente. Las condiciones, ventanas de ejecución, exclusiones y autorizaciones se recogerán en el acuerdo o documento de alcance firmado. Este informe no sustituye dicho acuerdo.',
    scopeNotice:'Los resultados reflejan una observación limitada al periodo, la muestra, los métodos y las evidencias descritos. La ausencia de hallazgos no implica ausencia de vulnerabilidades ni garantiza la seguridad futura de la infraestructura. Los controles no revisados se identifican como tales.',
    dataProtection:'Cuando las actividades impliquen tratamiento de datos personales, las partes determinarán sus roles y las bases de legitimación conforme al RGPD y la LOPDGDD. Si procede un encargo de tratamiento, se formalizará el correspondiente acuerdo conforme al artículo 28 del RGPD. Se aplicarán medidas adecuadas de confidencialidad, minimización y seguridad.',
    retention:'Las evidencias, notas y copias se conservarán únicamente durante el plazo acordado por las partes y el exigible legalmente, con acceso restringido. Al finalizar la prestación se aplicarán las instrucciones pactadas de devolución, eliminación segura o conservación obligatoria, dejando constancia cuando corresponda.',
    thirdParties:'La entrega de este informe y de sus evidencias a proveedores, plataformas cloud, repositorios o terceros requiere autorización previa del cliente y revisión de las garantías jurídicas y técnicas aplicables. Se priorizarán medios cifrados y destinatarios verificados.',
    responsibility:'Las recomendaciones deben ser priorizadas y validadas por los responsables designados antes de su aplicación en producción. El auditor describe el alcance y los resultados efectivamente contrastados; la asignación contractual de responsabilidades no queda modificada por este modelo de texto.'
  });
  const groups = {
    assets:{title:'Inventario de hardware',intro:'Hosts, servidores, dispositivos de red, periféricos e infraestructura física.',fields:[
      ['name','Activo / hostname'],['type','Categoría / rol','picker',presets.hardware],['vendor','Fabricante','picker',hardwareVendors],['model','Modelo','picker',hardwareModels],['serial','Número de serie'],
      ['ip','IP / identificador'],['os','Sistema operativo / firmware','picker',presets.operating],['cpu','Procesador','picker',presets.cpu],['ram','Memoria RAM','picker',presets.ram],['storage','Tipo de almacenamiento','picker',presets.storage],['site','Ubicación / sede','picker',presets.site],
      ['owner','Responsable','picker',presets.owner],['criticality','Criticidad','select',['Sin valorar','Crítica','Alta','Media','Baja']],
      ['state','Estado / ciclo de vida','select',['Por revisar','En servicio','Obsoleto','Fuera de servicio']],['notes','Observaciones','textarea']]},
    networks:{title:'Infraestructura de red',intro:'Segmentos, VLAN, equipamiento, servicios y exposición de red.',fields:[
      ['name','Segmento / equipo'],['cidr','Subred CIDR'],['vlan','VLAN'],['gateway','Gateway'],
      ['dns','DNS / DHCP'],['purpose','Función / servicios','picker',presets.function],['firewall','Firewall / controles'],
      ['exposure','Accesibilidad y segmentación','picker',presets.exposure],['notes','Observaciones','textarea']]},
    software:{title:'Inventario de software y servicios',intro:'Aplicaciones instaladas, licencias, versiones, criticidad y mantenimiento.',fields:[
      ['name','Software / servicio','picker',['Microsoft 365','Microsoft Office','Microsoft SQL Server','PostgreSQL','MySQL','MariaDB','Oracle Database','Apache HTTP Server','Nginx','IIS','Docker Engine','Kubernetes','Proxmox VE','VMware vCenter','Zabbix','Wazuh','Grafana','Prometheus','Elastic / OpenSearch','Suricata','pfSense','Fortinet FortiOS','Veeam Backup & Replication','Acronis Cyber Protect','Active Directory DS','Samba AD','Microsoft Entra ID','Microsoft Defender for Endpoint','CrowdStrike Falcon','Sophos Endpoint','Google Workspace','Nextcloud','GitLab','Jenkins','GitHub Actions','OpenVPN','WireGuard']],['version','Versión'],['vendor','Fabricante','picker',hardwareVendors],['asset','Activo asociado'],
      ['license','Licencia','picker',presets.license],['support','Soporte / EOL','picker',presets.support],['exposure','Exposición / función','picker',presets.exposure],['notes','Observaciones','textarea']]},
    cves:{title:'Catálogo de vulnerabilidades CVE',intro:'Asocia CVE verificados con activos y hallazgos. El expediente funciona offline; las consultas externas son opcionales y explícitas.',fields:[
      ['id','Identificador CVE (CVE-AAAA-NNNN)'],['title','Descripción breve'],['asset','Activo afectado','picker',[]],
      ['status','Estado de verificación','select',['Sin verificar','Pendiente de contrastar','Confirmada','Descartada','No aplicable']],
      ['severity','Severidad evaluada','select',['Sin evaluar','Crítica','Alta','Media','Baja','Informativa']],
      ['cvss','CVSS oficial / referencia (si se conoce)'],['published','Fecha de publicación','date'],['source','Fuente consultada'],
      ['consulted','Última consulta','date'],['references','Referencias / avisos','textarea'],['notes','Notas, impacto y mitigación','textarea']]},
    controls:{title:'Controles de seguridad',intro:'Registrar solo verificaciones realizadas. «No verificado» no equivale a «Conforme».',fields:[
      ['id','Identificador'],['category','Área','select',['Inventario','Identidad','Red','Sistemas','Parcheado','Backups','Monitorización','Continuidad','Protección de datos','Otro']],
      ['name','Control / criterio'],['asset','Activo o alcance','picker',[]],['status','Resultado','select',['Pendiente','Conforme','No conforme','No aplica','No verificado']],
      ['method','Método de verificación','textarea'],['reference','Marco / referencia'],
      ['evidenceIds','ID(s) de evidencia'],['notes','Observaciones','textarea']]},
    findings:{title:'Hallazgos y recomendaciones',intro:'Una ficha por debilidad. La puntuación CVSS, si se indica, es manual y no implica cálculo ni validación automática.',fields:[
      ['id','Código del hallazgo'],['title','Título'],['severity','Severidad','select',['Crítica','Alta','Media','Baja','Informativa']],
      ['status','Seguimiento','select',['Abierto','En curso','Mitigado','Riesgo aceptado','Cerrado']],
      ['asset','Activos / alcance afectados','picker',[]],['cvss','CVSS (si corresponde)'],
      ['likelihood','Probabilidad','select',['No evaluada','Muy alta','Alta','Media','Baja','Muy baja']],
      ['impact','Impacto','select',['No evaluado','Muy alto','Alto','Medio','Bajo','Muy bajo']],
      ['description','Descripción / situación observada','textarea'],['risk','Consecuencia y escenario de riesgo','textarea'],
      ['method','Método o herramientas utilizadas','textarea'],['evidenceIds','ID(s) de evidencia'],
      ['references','CVE / CIS / NIST / referencias','textarea'],['recommendation','Remediación propuesta','textarea'],
      ['owner','Responsable','picker',presets.owner],['deadline','Fecha objetivo','date'],['residual','Riesgo residual / notas','textarea']]},
    evidence:{title:'Cadena documental de evidencias',intro:'Las imágenes se incrustan opcionalmente en el expediente JSON y en el PDF; conserva los originales de manera separada y segura.',fields:[
      ['id','ID de evidencia'],['title','Título / descripción breve'],['asset','Activo / hallazgo relacionado','picker',[]],
      ['captured','Fecha de captura','date'],['source','Fuente / comando / ruta segura'],
      ['sha256','SHA-256 del original (opcional)'],['notes','Detalle, custodia y observaciones','textarea']]}
  };
  const severity = ['Crítica','Alta','Media','Baja','Informativa'];
  const fresh = () => ({schemaVersion:VERSION,meta:{classification:'Confidencial',type:'Auditoría de infraestructura',revision:'1.0',logo:''},final:{disclaimer:'La evaluación refleja los sistemas y las evidencias examinados durante el período indicado. Las comprobaciones no ejecutadas y las exclusiones se detallan en el alcance.'},legal:legalDefaults(),assets:[],networks:[],software:[],cves:[],controls:[],findings:[],evidence:[]});
  const str = v => typeof v === 'string' ? v.slice(0,20000) : '';
  const html = v => String(v ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const uid = () => globalThis.crypto && crypto.randomUUID ? crypto.randomUUID() : 'id-'+Date.now()+'-'+Math.random().toString(36).slice(2);
  const plain = v => html(v || 'No documentado');
  const para = v => `<span class="report-text">${plain(v)}</span>`;
  const level = v => ({'Crítica':'critical','Alta':'high','Media':'medium','Baja':'low','Informativa':'info'})[v] || 'info';
  const slug = v => (v || 'cliente').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9_-]/gi,'-').slice(0,38);
  function validate(raw){
    if(!raw || Array.isArray(raw) || typeof raw!=='object' || raw.schemaVersion!==VERSION)throw Error('Versión de expediente incompatible (esperada: 2).');
    const out=fresh();
    for(const [block,fields] of [['meta',metaFields],['final',finalFields],['legal',legalFields]]){
      if(!raw[block]||Array.isArray(raw[block])||typeof raw[block]!=='object'){if(block==='legal')continue;throw Error('Bloque incorrecto: '+block)}
      for(const [name] of fields)out[block][name]=typeof raw[block][name]==='string'?str(raw[block][name]):out[block][name];
    }
    out.meta.logo=safeLogo(raw.meta.logo);
    for(const [block,definition] of Object.entries(groups)){
      if(block==='cves' && raw[block]===undefined)continue;
      if(!Array.isArray(raw[block])||raw[block].length>LIMIT_ROWS)throw Error('Datos no válidos en '+block);
      out[block]=raw[block].map(item=>{
        if(!item||typeof item!=='object'||Array.isArray(item))throw Error('Registro no válido en '+block);
        const record={_key:str(item._key)||uid()};
        for(const [name] of definition.fields)record[name]=str(item[name]);
        if(block==='evidence'){
          const pic=typeof item.image==='string' && item.image.length<1400000?item.image:'';
          record.image=/^data:image\/jpeg;base64,[a-z0-9+/=]+$/i.test(pic)&&pic.length<1400000?pic:'';
        }
        return record;
      });
    }
    return out;
  }
  // Persistent multi-audit repository. IndexedDB is preferred for larger evidence images;
  // localStorage fallback retains functionality in browsers where IDB is unavailable.
  function openDatabase(){
    return new Promise((resolve,reject)=>{
      if(!('indexedDB' in globalThis))return reject(Error('IndexedDB no disponible'));
      const request=indexedDB.open('audit-workbench-offline',1);
      request.onupgradeneeded=()=>request.result.createObjectStore('audits',{keyPath:'id'});
      request.onsuccess=()=>resolve(request.result);
      request.onerror=()=>reject(request.error||Error('No se pudo abrir IndexedDB'));
      request.onblocked=()=>reject(Error('Cierra las otras pestañas de la aplicación y reintenta.'));
    });
  }
  function createRepository(){
    let database=null;
    const transaction=(kind,action)=>new Promise((resolve,reject)=>{
      const tx=database.transaction('audits',kind),store=tx.objectStore('audits');
      let result;
      tx.oncomplete=()=>resolve(result);
      tx.onerror=()=>reject(tx.error||Error('Error de almacenamiento'));
      tx.onabort=()=>reject(tx.error||Error('Transacción cancelada'));
      const req=action(store);
      if(req)req.onsuccess=()=>{result=req.result};
    });
    const fallback=()=>JSON.parse(localStorage.getItem(FALLBACK_KEY)||'[]');
    return {
      get mode(){return database?'IndexedDB':'almacenamiento local'},
      async init(){try{database=await openDatabase();return}catch(error){console.warn('IndexedDB no disponible; almacenamiento local alternativo:',error);localStorage.getItem(FALLBACK_KEY)}},
      async list(){return database?transaction('readonly',s=>s.getAll()):fallback()},
      async put(record){if(database)return transaction('readwrite',s=>s.put(record));const records=fallback().filter(r=>r.id!==record.id);records.push(record);localStorage.setItem(FALLBACK_KEY,JSON.stringify(records))},
      async remove(id){if(database)return transaction('readwrite',s=>s.delete(id));localStorage.setItem(FALLBACK_KEY,JSON.stringify(fallback().filter(r=>r.id!==id)))}
    };
  }
  const repository=createRepository();
  const byId=id=>document.getElementById(id);
  let state=fresh(),currentId='',page='dashboard',records=[],storageError=false,dirty=false,saveTimer=null,writeQueue=Promise.resolve();
  let selectedPalette='ocean';
  function updateStatus(message,warning=false){const node=byId('save-status');node.textContent=message;node.classList.toggle('warning',warning)}
  function enqueue(action){writeQueue=writeQueue.catch(()=>{}).then(action);return writeQueue}
  function selectPalette(value){
    selectedPalette=palettes.includes(value)?value:'ocean';
    document.documentElement.dataset.palette=selectedPalette;
    byId('palette').value=selectedPalette;
    try{localStorage.setItem(PALETTE_KEY,selectedPalette)}catch(_ignored){}
  }
  const newRecord=(audit=fresh())=>({id:uid(),createdAt:new Date().toISOString(),updatedAt:new Date().toISOString(),audit});
  function setActive(record){
    currentId=record.id;
    state=validate(record.audit);
    try{localStorage.setItem(ACTIVE_KEY,currentId)}catch(_ignored){}
  }
  function saveCurrent(){
    clearTimeout(saveTimer);saveTimer=null;
    if(!dirty)return writeQueue;
    dirty=false;
    const now=new Date().toISOString();
    const existing=records.find(r=>r.id===currentId);
    if(!existing)return writeQueue;
    const snapshot={...existing,updatedAt:now,audit:structuredCloneSafe(state)};
    updateStatus('Guardando…');
    return enqueue(async()=>{
      try{
        await repository.put(snapshot);
        const idx=records.findIndex(r=>r.id===snapshot.id);
        if(idx>=0&&records[idx].updatedAt<=snapshot.updatedAt)records[idx]=snapshot;
        storageError=false;
        if(!dirty)updateStatus('● Guardado · '+repository.mode);
      }catch(error){
        console.error('No se pudo guardar el expediente',error);
        dirty=true;storageError=true;
        updateStatus('⚠ Sin guardar: exporta JSON',true);
      }
    });
  }
  function structuredCloneSafe(value){return JSON.parse(JSON.stringify(value))}
  function persist(){dirty=true;updateStatus('Cambios pendientes…');clearTimeout(saveTimer);saveTimer=setTimeout(()=>void saveCurrent(),250)}
  async function flush(){if(saveTimer){clearTimeout(saveTimer);saveTimer=null}await saveCurrent();await writeQueue;if(storageError)throw Error('El expediente no se pudo guardar. Exporta el JSON antes de cambiar de auditoría.')}
  async function initialLoad(){
    try{
      await repository.init();
      records=(await repository.list()).filter(r=>r&&typeof r.id==='string'&&r.audit&&r.audit.schemaVersion===VERSION);
      if(records.length===0){
        let audit=fresh();
        try{const legacy=localStorage.getItem(LEGACY_STORE);if(legacy)audit=validate(JSON.parse(legacy))}catch(error){console.warn('No se pudo migrar el expediente antiguo',error)}
        const first=newRecord(audit);await repository.put(first);records=[first];
      }
      let lastId='';try{lastId=localStorage.getItem(ACTIVE_KEY)||''}catch(_ignored){}
      const active=records.find(r=>r.id===lastId)||[...records].sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt))[0];
      setActive(active);updateStatus('● Guardado · '+repository.mode);
    }catch(error){console.error('No se pudo inicializar la persistencia',error);storageError=true;currentId=uid();updateStatus('⚠ Sin almacenamiento · exporta JSON',true)}
    render();
  }
  async function createAudit(audit=fresh()){
    try{await flush();const record=newRecord(audit);await enqueue(()=>repository.put(record));records.push(record);setActive(record);move('engagement')}
    catch(error){alert('No se ha creado la auditoría: '+error.message)}
  }
  async function switchAudit(id){
    const record=records.find(r=>r.id===id);if(!record)return;
    try{await flush();setActive(record);move('dashboard')}
    catch(error){alert(error.message)}
  }
  async function deleteAudit(id){
    const record=records.find(r=>r.id===id);if(!record||!confirm(`¿Eliminar definitivamente la auditoría "${record.audit?.meta?.project||record.audit?.meta?.client||'Sin título'}" de este navegador? Exporta el JSON antes de continuar.`))return;
    try{
      await flush();await enqueue(()=>repository.remove(id));records=records.filter(r=>r.id!==id);
      if(currentId===id){
        if(records.length===0){const freshRecord=newRecord();await enqueue(()=>repository.put(freshRecord));records.push(freshRecord)}
        setActive([...records].sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt))[0]);
      }
      move('records');
    }catch(error){alert('No se pudo eliminar: '+error.message)}
  }
  async function duplicateAudit(id){
    const original=records.find(r=>r.id===id);if(!original)return;
    const copy=structuredCloneSafe(original.audit);copy.meta.project=(copy.meta.project||'Auditoría')+' · Copia';
    await createAudit(copy);
  }
  function download(filename,content,type){const url=URL.createObjectURL(new Blob([content],{type}));const a=document.createElement('a');a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000)}
  function renderField(obj,block,def,index){
    const [name,label,type,choices]=def;
    const attrs=`data-block="${html(block)}" data-field="${html(name)}"`+(index===undefined?'':` data-index="${index}"`);
    const value=str(obj[name]),id='f-'+block+'-'+(index===undefined?'main':index)+'-'+name;
    const key=/^(vlan|cvss|serial)$/.test(name)?'decimal':'text';
    let control;
    if(type==='textarea')control=`<textarea id="${id}" ${attrs} maxlength="20000">${html(value)}</textarea>`;
    else if(type==='select')control=`<select id="${id}" ${attrs}>${choices.map(x=>`<option value="${html(x)}"${x===value?' selected':''}>${html(x)}</option>`).join('')}</select>`;
    else if(type==='picker'){
      // A native select is easier on touchscreens; unlisted values remain editable.
      const options=name==='asset'?[...new Set(['Todo el alcance',...state.assets.map(a=>str(a.name)).filter(Boolean)])]:choices;
      const custom=Boolean(value)&&!options.includes(value);
      control=`<select id="${id}" ${attrs} data-preset="true" aria-label="${html(label)}"><option value="">Seleccionar…</option>${options.map(x=>`<option value="${html(x)}"${x===value?' selected':''}>${html(x)}</option>`).join('')}<option value="__custom__"${custom?' selected':''}>Otro / escribir…</option></select><input ${attrs} data-custom="true" aria-label="${html(label)} personalizado" placeholder="Especifica el valor" value="${custom?html(value):''}" maxlength="20000" ${custom?'':'hidden'}>`;
    }else control=`<input id="${id}" type="${type==='date'?'date':'text'}" ${attrs} value="${html(value)}" maxlength="20000"${key==='decimal'?' inputmode="decimal"':''}>`;
    return `<div class="field${type==='textarea'?' full':''}"><label for="${id}">${html(label)}</label>${control}</div>`;
  }
  function pill(v){return `<span class="pill ${level(v)}">${html(v||'Sin clasificar')}</span>`}
  function metric(title,note,count){return `<div class="stat"><span class="metric">${count}</span><span class="metric-caption">${title}</span><span class="metric-foot">${note}</span></div>`}
  function renderOverview(){
    const counts=Object.fromEntries(severity.map(s=>[s,state.findings.filter(x=>x.severity===s).length]));
    return `<section class="hero"><span class="eyebrow">AUDIT / WORKSPACE</span><h2>${html(state.meta.project||'Tu próxima auditoría, bien documentada.')}</h2><p>Inventario técnico, evaluación de controles, gestión de hallazgos y un informe final coherente. Toda la información permanece en este navegador hasta que tú la exportes.</p><button class="button" data-go="engagement">Comenzar auditoría &rarr;</button></section>
      <section class="stats">${metric('Equipos inventariados','Hardware',state.assets.length)}${metric('Segmentos registrados','Infraestructura',state.networks.length)}${metric('Controles evaluados','Seguridad',state.controls.length)}${metric('Hallazgos','Gestión de riesgos',state.findings.length)}</section>
      <div class="grid-two"><section class="card"><h2>Distribución de severidades</h2><p class="subtle">Se calcula únicamente a partir de los hallazgos documentados.</p><div class="severity-line">${severity.map(s=>`<span class="sev-bar ${level(s)} ${counts[s]?'with-count':''}" title="${html(s)}: ${counts[s]}"></span>`).join('')}</div><div class="severity-legend">${severity.map(s=>`<span><strong>${counts[s]}</strong> ${s}</span>`).join('')}</div></section>
      <section class="card"><h2>Flujo recomendado</h2><div class="timeline"><div><b>01</b><span>Delimita objetivos, exclusiones y autorización<small>Cliente y alcance</small></span></div><div><b>02</b><span>Inventaría sistemas, aplicaciones y redes<small>Hardware · Redes · Software</small></span></div><div><b>03</b><span>Registra controles, evidencias y hallazgos<small>Pruebas verificadas y remediación</small></span></div><div><b>04</b><span>Revisa y entrega el informe final<small>Guardar JSON · Generar PDF</small></span></div></div></section></div>
      <div class="notice warn"><strong>Confidencialidad operativa.</strong> No introduzcas contraseñas, tokens ni hashes de autenticación sin tratar. Almacena el expediente JSON y los PDF en un disco cifrado. Exporta frecuentemente una copia: el autoguardado del navegador no constituye una copia de seguridad.</div>`;
  }
  function renderRecords(){
    const search=(byId('record-filter')?.value||'').toLocaleLowerCase('es');
    const items=[...records].sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt)).filter(r=>[r.audit.meta.client,r.audit.meta.project,r.audit.meta.reportId].some(v=>(v||'').toLocaleLowerCase('es').includes(search)));
    return `<span class="eyebrow">BIBLIOTECA / EXPEDIENTES LOCALES</span><h1 class="page-title">Auditorías guardadas</h1><p class="lead">Cada expediente se guarda por separado en este navegador. Puedes abrirlo, duplicarlo, exportarlo o borrarlo.</p><section class="card"><div class="card-head"><div><h2>${records.length} auditorías</h2><p class="subtle">Almacenamiento ${html(repository.mode)} · No sincronizado entre dispositivos.</p></div><div class="audit-actions"><button class="button quiet" data-backup-all="true">Respaldar todas (JSON)</button><button class="button accent" data-new="true">+ Nueva auditoría</button></div></div><div class="library-toolbar"><label for="record-filter">Buscar por cliente, proyecto o referencia</label><input id="record-filter" type="search" value="${html(search)}" placeholder="Buscar auditorías…" autocomplete="off"></div><div id="record-list">${recordsMarkup(items)}</div></section><div class="notice warn">Una auditoría guardada en el navegador no equivale a una copia de seguridad. Exporta el JSON a un directorio cifrado antes de entregar el equipo o borrar los datos del navegador.</div>`;
  }
  function recordsMarkup(items){
    return items.length?items.map(r=>`<article class="audit-row${r.id===currentId?' current':''}"><div class="audit-description"><span class="eyebrow">${r.id===currentId?'ABIERTA · ':''}${html(r.audit.meta.reportId||'SIN REFERENCIA')}</span><h3>${html(r.audit.meta.project||'Auditoría sin título')}</h3><p>${html(r.audit.meta.client||'Cliente por identificar')} · Actualizada ${html(new Date(r.updatedAt).toLocaleString('es-ES'))}</p><small>${r.audit.assets.length} equipos · ${r.audit.findings.length} hallazgos · ${r.audit.controls.length} controles</small></div><div class="audit-actions"><button class="button accent" data-open="${html(r.id)}">Editar</button><button class="button quiet" data-copy="${html(r.id)}">Duplicar</button><button class="button quiet" data-export-record="${html(r.id)}">JSON</button><button class="button danger" data-delete-record="${html(r.id)}">Borrar</button></div></article>`).join(''):'<div class="empty"><b>Sin resultados</b>Prueba otro nombre o crea una auditoría.</div>';
  }
  function renderForm(block,fields,title,intro){return `<span class="eyebrow">AUDITORÍA / DOCUMENTACIÓN</span><h1 class="page-title">${title}</h1><p class="lead">${intro}</p><section class="card"><div class="fields">${fields.map(f=>renderField(state[block],block,f)).join('')}</div></section>`}
  function renderEngagement(){
    return renderForm('meta',metaFields,'Cliente y alcance','Contexto, autorización, alcance, metodología y limitaciones de la evaluación.')+
      `<section class="card"><h2>Identidad corporativa del informe</h2><p class="subtle">Adjunta tu logo o el de la consultora (PNG, JPEG o WebP; máximo 3 MiB). Se convierte a JPEG y se incluye en el JSON exportado y en la portada del PDF. No se sube a Internet.</p><input id="logo-upload" type="file" accept="image/png,image/jpeg,image/webp" aria-label="Seleccionar logotipo corporativo">${state.meta.logo?`<div class="logo-preview"><img src="${state.meta.logo}" alt="Logotipo corporativo incorporado"><button type="button" class="button danger small" id="logo-remove">Eliminar logotipo</button></div>`:''}</section>`;
  }
  function renderGroup(block){const def=groups[block],rows=state[block];return `<span class="eyebrow">INVENTARIO / EVIDENCIAS</span><h1 class="page-title">${def.title}</h1><p class="lead">${def.intro}</p><section class="card"><div class="card-head"><div><h2>${rows.length} registros</h2><p class="subtle">Cada dato registrado podrá aparecer en el informe y en la copia JSON.</p></div><button class="button accent" data-add="${block}">+ Añadir registro</button></div>${rows.length?rows.map((r,i)=>`<div class="entry"><div class="entry-head"><div><strong>${html(r.title||r.name||r.id||'Registro '+(i+1))}</strong> ${block==='findings'?pill(r.severity):''}</div><button class="button danger small" data-remove="${block}" data-index="${i}">Eliminar</button></div><div class="fields">${def.fields.map(f=>renderField(r,block,f,i)).join('')}</div>${block==='cves'?`<div class="cve-tools"><button class="button quiet small" type="button" data-cve-check="${i}">Consultar CVE online (opcional)</button><button class="button small" type="button" data-cve-link="${i}">Ver en CVE.org ↗</button><span class="subtle">Solo se envía el identificador CVE, nunca los datos del cliente.</span></div>`:''}${block==='evidence'?`<div class="file-upload"><label for="evidence-upload-${i}"><strong>Captura opcional</strong> (PNG, JPG, WebP hasta 5 MiB; se optimiza localmente)</label><input type="file" accept="image/png,image/jpeg,image/webp" data-image-index="${i}" id="evidence-upload-${i}">${r.image?`<img class="evidence-preview" alt="Evidencia incrustada" src="${r.image}"><button class="button small danger" data-clear-image="${i}">Quitar imagen</button>`:''}</div>`:''}</div>`).join(''):`<div class="empty"><b>No hay registros todavía</b>Usa «Añadir registro» para empezar.</div>`}</section>`}
  function renderDelivery(){const unresolved=state.controls.filter(x=>x.status==='Pendiente'||x.status==='No verificado').length;return `<span class="eyebrow">ENTREGA / REPORTING</span><h1 class="page-title">Informe final</h1><p class="lead">Última revisión editorial antes de entregar el resultado al cliente.</p><div class="notice">El PDF se crea con <strong>Imprimir → Guardar como PDF</strong> en tu navegador. No se necesita conexión, servidor ni librerías adicionales. Activa los gráficos de fondo si quieres conservar la composición visual.</div>${unresolved?`<div class="notice warn">Atención: hay ${unresolved} controles pendientes o no verificados. Se mostrarán así en el informe, no como conformes.</div>`:''}<section class="card"><div class="card-head"><div><h2>Conclusiones y cierre</h2><p class="subtle">Incluye un resumen ejecutivo entendible y un plan técnico accionable.</p></div></div><div class="fields">${finalFields.map(f=>renderField(state.final,'final',f)).join('')}</div></section><section class="card"><h2>Preparar entrega</h2><p class="subtle">El informe incorpora portada, confidencialidad, alcance, inventarios, controles, hallazgos, evidencias y recomendaciones.</p><div class="action-row"><button class="button accent" id="delivery-pdf">Generar informe PDF ↗</button><button class="button quiet" id="delivery-json">Guardar expediente JSON</button><button class="button danger" id="delivery-reset">Nuevo expediente</button><button class="button quiet" id="native-share-json">Compartir JSON (opcional)</button><button class="button quiet" id="open-email">Preparar correo (sin adjuntos)</button></div></section>`}
  function render(){
    byId('navigation').innerHTML=nav.map(([id,symbol,name])=>`<button type="button" data-go="${id}" class="${page===id?'active':''}" ${page===id?'aria-current="page"':''}><span class="nav-mark">${symbol}</span>${name}</button>`).join('');
    byId('current-section').textContent=nav.find(n=>n[0]===page)[2];
    byId('workspace').innerHTML=page==='dashboard'?renderOverview():page==='records'?renderRecords():page==='engagement'?renderEngagement():page==='legal'?renderForm('legal',legalFields,'Cláusulas y privacidad','Modelos editables para auditorías en España. Revisa el contrato y solicita asesoramiento jurídico cuando corresponda.'):page==='delivery'?renderDelivery():renderGroup(page);
  }
  function move(section){if(nav.some(n=>n[0]===section)){page=section;render();scrollTo(0,0)}}
  function fieldTarget(target){const {block,field,index}=target.dataset;if(!block||!field)return null;if(block==='meta'||block==='final'||block==='legal')return state[block];if(groups[block]&&index!==undefined)return state[block][Number(index)];return null}
  const workspace=byId('workspace');
  byId('navigation').addEventListener('click',e=>{const b=e.target.closest('[data-go]');if(b)move(b.dataset.go)});
  workspace.addEventListener('input',e=>{
    const t=e.target;
    if(t.id==='record-filter'){
      const term=t.value.toLocaleLowerCase('es');
      const matches=[...records].sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt)).filter(r=>[r.audit.meta.client,r.audit.meta.project,r.audit.meta.reportId].some(v=>(v||'').toLocaleLowerCase('es').includes(term)));
      byId('record-list').innerHTML=recordsMarkup(matches);return;
    }
    if(t.dataset.preset)return;
    const obj=fieldTarget(t);if(obj){obj[t.dataset.field]=t.value;persist()}
  });
  workspace.addEventListener('change',async e=>{
    const t=e.target;
    if(t.id==='logo-upload'&&t.files?.length){try{const image=await resizeImage(t.files[0],500,0.86);if(image.length>650000)throw Error('Logo demasiado grande para el expediente.');state.meta.logo=image;persist();render()}catch(error){alert('Logo no válido: '+error.message)}return}
    if(t.dataset.imageIndex!==undefined&&t.files?.length){
      const id=currentId,recordKey=state.evidence[Number(t.dataset.imageIndex)]?._key;
      try{const image=await resizeImage(t.files[0]);if(id!==currentId)throw Error('Ha cambiado el expediente.');const record=state.evidence.find(x=>x._key===recordKey);if(!record)throw Error('No se encontró la evidencia.');record.image=image;persist();render()}
      catch(err){alert('No se pudo incorporar la imagen: '+err.message);t.value=''}return;
    }
    const obj=fieldTarget(t);if(!obj)return;
    if(t.dataset.preset){
      const custom=t.closest('.field').querySelector('[data-custom]');
      const isOther=t.value==='__custom__';custom.hidden=!isOther;
      obj[t.dataset.field]=isOther?custom.value:t.value;
      if(isOther)custom.focus();persist();return;
    }
    obj[t.dataset.field]=t.value;persist();
  });
  workspace.addEventListener('click',async e=>{
    const b=e.target.closest('button');if(!b)return;
    if(b.dataset.go){move(b.dataset.go);return}
    if(b.dataset.new){await createAudit();return}
    if(b.dataset.backupAll){await backupAll();return}
    if(b.dataset.open){await switchAudit(b.dataset.open);return}
    if(b.dataset.copy){await duplicateAudit(b.dataset.copy);return}
    if(b.dataset.deleteRecord){await deleteAudit(b.dataset.deleteRecord);return}
    if(b.dataset.exportRecord){const r=records.find(r=>r.id===b.dataset.exportRecord);if(r)exportJson(r.id===currentId?state:r.audit);return}
    if(b.id==='logo-remove'){if(confirm('¿Quitar el logotipo de este expediente?')){state.meta.logo='';persist();render()}return}
    if(b.dataset.cveLink!==undefined){const id=str(state.cves[Number(b.dataset.cveLink)]?.id).trim().toUpperCase();if(!CVE_PATTERN.test(id)){alert('Introduce un identificador CVE válido.');return}window.open('https://www.cve.org/CVERecord?id='+encodeURIComponent(id),'_blank','noopener,noreferrer');return}
    if(b.dataset.cveCheck!==undefined){await lookupCve(Number(b.dataset.cveCheck),b);return}
    if(b.id==='native-share-json'){await shareAudit();return}
    if(b.id==='open-email'){draftEmail();return}
    if(b.dataset.add){if(state[b.dataset.add].length>=LIMIT_ROWS)return alert('Límite de registros alcanzado.');const type=b.dataset.add;let row={_key:uid()};if(type==='findings')row={...row,id:'AUD-'+String(state.findings.length+1).padStart(3,'0'),severity:'Media',status:'Abierto'};if(type==='cves')row={...row,id:'',severity:'Sin evaluar',status:'Sin verificar'};if(type==='controls')row.status='Pendiente';if(type==='evidence')row.id='EVI-'+String(state.evidence.length+1).padStart(3,'0');state[type].push(row);persist();render();return}
    if(b.dataset.remove){const k=b.dataset.remove,i=Number(b.dataset.index);if(confirm('¿Eliminar este registro y su contenido?')){state[k].splice(i,1);persist();render()}return}
    if(b.dataset.clearImage!==undefined){if(confirm('¿Eliminar la imagen incrustada?')){state.evidence[Number(b.dataset.clearImage)].image='';persist();render()}return}
    if(b.id==='delivery-pdf'){printReport();return}
    if(b.id==='delivery-json'){exportJson();return}
    if(b.id==='delivery-reset'){await createAudit();return}
  });
  function resizeImage(file,maxSize=1300,quality=.78){
    if(!['image/png','image/jpeg','image/webp'].includes(file.type))return Promise.reject(Error('Formato no permitido.'));
    if(file.size>(maxSize===500?3:5)*1024*1024)return Promise.reject(Error('El archivo supera el límite de tamaño.'));
    return new Promise((resolve,reject)=>{
      const url=URL.createObjectURL(file);const img=new Image();
      img.onload=()=>{URL.revokeObjectURL(url);try{const ratio=Math.min(1,maxSize/Math.max(img.width,img.height));const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.width*ratio));canvas.height=Math.max(1,Math.round(img.height*ratio));const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(img,0,0,canvas.width,canvas.height);const out=canvas.toDataURL('image/jpeg',quality);if(out.length>1390000)throw Error('La imagen resultante es demasiado grande.');resolve(out)}catch(e){reject(e)}};
      img.onerror=()=>{URL.revokeObjectURL(url);reject(Error('No se pudo abrir el archivo.'))};img.src=url;
    });
  }
  async function lookupCve(index,button){
    const row=state.cves[index];if(!row)return;
    const id=str(row.id).trim().toUpperCase();
    if(!CVE_PATTERN.test(id)){alert('Identificador inválido. Usa CVE-AAAA-NNNN (o más dígitos).');return}
    if(!navigator.onLine){alert('Sin conexión. Puedes registrar la CVE manualmente y consultarla más tarde.');return}
    if(!confirm('La consulta enviará únicamente '+id+' a cveawg.mitre.org mediante HTTPS. No se envían datos de la auditoría. ¿Consultar?'))return;
    button.disabled=true;button.textContent='Consultando…';
    const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),10000);
    try{
      const response=await fetch('https://cveawg.mitre.org/api/cve/'+encodeURIComponent(id),{method:'GET',credentials:'omit',cache:'no-store',mode:'cors',signal:controller.signal,referrerPolicy:'no-referrer'});
      if(!response.ok)throw Error('HTTP '+response.status+' (la CVE puede no estar publicada)');
      const result=await response.json();
      const metadata=result.cveMetadata||{};
      if(metadata.cveId?.toUpperCase()!==id)throw Error('El registro recibido no coincide con el identificador solicitado.');
      const record=result.containers?.cna||{};
      const description=record.descriptions?.find(x=>x.lang==='es')?.value||record.descriptions?.find(x=>x.lang==='en')?.value||'';
      if(description && !row.title)row.title=description.slice(0,2000);
      row.source='CVE Program / CVE Services (cveawg.mitre.org)';
      row.consulted=new Date().toISOString().slice(0,10);
      if(metadata.datePublished)row.published=metadata.datePublished.slice(0,10);
      row.references=[row.references,'https://www.cve.org/CVERecord?id='+id].filter(Boolean).join('\n').slice(0,20000);
      persist();render();alert('Ficha '+id+' consultada. Comprueba manualmente los sistemas afectados y el estado de explotación: consultar una CVE no equivale a confirmar vulnerabilidad.');
    }catch(error){alert('No se pudo completar la consulta: '+error.message+'\nPuedes usar «Ver en CVE.org» o registrar la información manualmente. Algunos navegadores y redes restringen consultas CORS.')}
    finally{clearTimeout(timeout);button.disabled=false;button.textContent='Consultar CVE online (opcional)'}
  }
  async function shareAudit(){
    if(!navigator.share||!navigator.canShare){alert('Tu navegador no permite compartir archivos de forma nativa. Exporta el JSON y envíalo con el canal autorizado por el cliente.');return}
    if(!confirm('Vas a abrir el panel nativo para compartir una copia del expediente completo. Podría enviarse fuera del dispositivo. Revisa el destinatario, la clasificación y la autorización del cliente. ¿Continuar?'))return;
    const file=new File([JSON.stringify(state,null,2)],'auditoria-'+slug(state.meta.client)+'.json',{type:'application/json'});
    if(!navigator.canShare({files:[file]})){alert('Este sistema no admite compartir archivos JSON. Exporta el expediente manualmente.');return}
    try{await navigator.share({files:[file],title:'Expediente de auditoría'})}catch(error){if(error.name!=='AbortError')alert('No se pudo abrir el panel: '+error.message)}
  }
  function draftEmail(){
    if(!confirm('Se abrirá tu cliente de correo con un asunto y mensaje de entrega, SIN adjuntos. Exporta el PDF y adjúntalo manualmente tras comprobar destinatario, confidencialidad y autorización. ¿Continuar?'))return;
    const subject='Entrega de auditoría '+(state.meta.reportId||state.meta.project||'');
    const body='Se adjunta el informe de auditoría revisado correspondiente a '+(state.meta.client||'la organización')+'.\n\nPor favor confirma su recepción por un canal autorizado.\n\n[Adjuntar manualmente el PDF final]';
    location.href='mailto:?subject='+encodeURIComponent(subject.slice(0,180))+'&body='+encodeURIComponent(body.slice(0,700));
  }
  async function backupAll(){
    try{
      await flush();
      const payload={auditWorkbenchBackup:1,exportedAt:new Date().toISOString(),records:records.map(item=>({audit:item.id===currentId?state:item.audit}))};
      download('audit-workbench-backup-'+new Date().toISOString().slice(0,10)+'.json',JSON.stringify(payload,null,2),'application/json;charset=utf-8');
    }catch(error){alert('No se pudo exportar el backup: '+error.message)}
  }
  function exportJson(audit=state){const name='auditoria-'+slug(audit.meta.client)+'-'+new Date().toISOString().slice(0,10)+'.json';download(name,JSON.stringify(audit,null,2),'application/json;charset=utf-8')}
  async function importJson(file){
    try{
      if(file.size>40*1024*1024)throw Error('El archivo supera 40 MiB. Exporta los expedientes individualmente o separa los backups.');
      const input=JSON.parse(await file.text());
      if(input?.auditWorkbenchBackup===1){
        if(!Array.isArray(input.records)||input.records.length>250)throw Error('El backup es inválido o supera 250 auditorías.');
        const all=input.records.map(item=>validate(item.audit));
        if(!confirm('Se restaurarán '+all.length+' auditorías como copias nuevas. No se sustituirán los expedientes existentes. ¿Continuar?'))return;
        await flush();
        for(const audit of all){const record=newRecord(audit);await enqueue(()=>repository.put(record));records.push(record)}
        if(all.length)setActive(records[records.length-1]);
        move('records');
        return;
      }
      const loaded=validate(input);
      if(!confirm('Se importará como una nueva auditoría sin sustituir los expedientes guardados. ¿Continuar?'))return;
      await createAudit(loaded);
    }catch(error){alert('No se pudo importar el JSON: '+error.message)}
  }
  byId('btn-import').addEventListener('click',()=>byId('input-import').click());
  byId('input-import').addEventListener('change',async e=>{if(e.target.files?.[0])await importJson(e.target.files[0]);e.target.value=''});
  byId('btn-export').addEventListener('click',exportJson);
  byId('btn-pdf').addEventListener('click',printReport);
  const table = (fields,row) => `<table class="report-table"><tbody>${fields.map(([name,label])=>`<tr><th class="report-field-label">${html(label)}</th><td>${para(row[name])}</td></tr>`).join('')}</tbody></table>`;
  const section = (num,title,content) => `<section class="report-section"><h2>${num}. ${html(title)}</h2>${content}</section>`;
  function reportRows(k){const rows=state[k];return rows.length?rows.map((row,i)=>`<h3>${i+1}. ${html(row.title||row.name||row.id||'Registro')}</h3>${table(groups[k].fields,row)}${k==='evidence'&&row.image?`<figure><img class="report-evidence" alt="Evidencia ${html(row.id)}" src="${row.image}"><figcaption class="report-note">${html(row.id||'Evidencia')}: ${html(row.title||'Captura adjunta')}</figcaption></figure>`:''}`).join(''):'<p class="report-empty">Sin registros incluidos en esta categoría.</p>'}
  function buildReport(){
    const today=new Date().toLocaleDateString('es-ES');
    const count=Object.fromEntries(severity.map(s=>[s,state.findings.filter(x=>x.severity===s).length]));
    const meta=state.meta,ending=state.final;
    const cover=`<div class="report-cover"><div class="sup">SYSADMIN / SECURITY · AUDIT REPORT</div>${meta.logo?`<img class="report-logo" src="${meta.logo}" alt="Logo corporativo">`:''}<h1>Informe de auditoría<br>informática</h1><h2>${html(meta.project||'Infraestructura, sistemas y ciberseguridad')}</h2><p class="classify">${html(meta.classification||'Confidencial')}</p><div class="cover-meta"><div><span class="report-number">CLIENTE</span><h3>${html(meta.client||'No indicado')}</h3><p>${html(meta.contact||'')}</p></div><div><span class="report-number">ENTREGA</span><h3>${html(today)}</h3><p>Ref. ${html(meta.reportId||'Sin referencia')} · Rev. ${html(meta.revision||'1.0')}</p><p>${html(meta.auditor||'')}</p></div></div></div>`;
    const legal=section(1,'Confidencialidad, alcance legal y custodia',`<p class="report-note">Cláusulas modelo que deben adaptarse al contrato específico y validarse antes de la entrega. RGPD (UE) 2016/679 y LOPDGDD 3/2018, según resulte aplicable.</p>${legalFields.map(([key,label])=>`<h3>${html(label)}</h3><p>${para(state.legal[key])}</p>`).join('')}<h3>Nota adicional del auditor</h3><p>${para(ending.disclaimer)}</p>`);
    const identity=section(2,'Identificación, alcance y metodología',table(metaFields,meta));
    const executive=section(3,'Resumen ejecutivo',`<p>${para(ending.executive)}</p><h3>Valoración del riesgo</h3><p>${para(ending.assessment)}</p><div class="report-stat-grid">${severity.map(s=>`<div><strong>${count[s]}</strong><small>${s}</small></div>`).join('')}</div><h3>Puntos fuertes</h3><p>${para(ending.strengths)}</p><h3>Debilidades principales</h3><p>${para(ending.weaknesses)}</p>`);
    const controls=section(8,'Controles y verificaciones',reportRows('controls'));
    const findings=section(9,'Resumen de hallazgos y ficha técnica',`${state.findings.length?`<table class="report-table"><thead><tr><th>ID</th><th>Hallazgo</th><th>Severidad</th><th>Remediación</th></tr></thead><tbody>${state.findings.map(f=>`<tr><td>${html(f.id)}</td><td>${html(f.title)}</td><td>${html(f.severity)}</td><td>${para(f.recommendation)}</td></tr>`).join('')}</tbody></table>`:'<p class="report-empty">No hay hallazgos registrados.</p>'}${state.findings.map(f=>`<div class="report-finding"><h3>${html(f.id||'Hallazgo')} — ${html(f.title||'Sin título')} <span class="report-badge ${level(f.severity)}">${html(f.severity)}</span></h3>${table(groups.findings.fields,f)}${state.evidence.filter(e=>(f.evidenceIds||'').split(/[,;\s]+/).includes(e.id)&&e.image).map(e=>`<figure><img class="report-evidence" src="${e.image}" alt="Evidencia ${html(e.id)}"><figcaption class="report-note">${html(e.id)} — ${html(e.title)}</figcaption></figure>`).join('')}</div>`).join('')}`);
    const closing=section(11,'Conclusiones y plan de acción',table(finalFields.filter(f=>f[0]!=='executive'&&f[0]!=='strengths'&&f[0]!=='weaknesses'&&f[0]!=='assessment'),ending)+`<div class="report-signature">Generado localmente con Audit Workbench. Validación y autorización de entrega: ${html(ending.signoff||'Pendiente de firma')}.</div>`);
    byId('report').innerHTML=cover+legal+identity+executive+section(4,'Inventario de hardware',reportRows('assets'))+section(5,'Infraestructura de redes',reportRows('networks'))+section(6,'Software y servicios',reportRows('software'))+section(7,'Vulnerabilidades CVE registradas',reportRows('cves'))+controls+findings+section(10,'Registro de evidencias',reportRows('evidence'))+closing;
  }
  function printReport(){buildReport();window.print()}
  window.addEventListener('beforeprint',buildReport);
  byId('palette').addEventListener('change',event=>selectPalette(event.target.value));
  byId('open-library').addEventListener('click',async()=>{try{await flush();move('records')}catch(error){alert(error.message)}});
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')void saveCurrent()});
  window.addEventListener('pagehide',()=>void saveCurrent());
  byId('local-date').textContent=new Date().toLocaleDateString('es-ES');
  try{selectPalette(localStorage.getItem(PALETTE_KEY)||'ocean')}catch(_ignored){selectPalette('ocean')}
  void initialLoad();
  if('serviceWorker' in navigator && ['https:','http:'].includes(location.protocol) && (location.protocol==='https:'||['localhost','127.0.0.1'].includes(location.hostname))){
    window.addEventListener('load',()=>navigator.serviceWorker.register('./sw.js',{scope:'./'}).catch(error=>console.warn('PWA no disponible:',error)));
  }
})();
