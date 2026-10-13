/* Audit Workbench: offline-first audits, explicit network connectors, no telemetry. */
'use strict';
(() => {
  const VERSION = 3;
  const storage = globalThis.AuditStorage;
  const relations = globalThis.AuditRelations;
  const templates = globalThis.AuditControlTemplates;
  const quality = globalThis.AuditQuality;
  const retest = globalThis.AuditRetest;
  const comparison = globalThis.AuditComparison;
  if (!storage) throw Error('No se ha cargado el módulo de almacenamiento offline.');
  if (!relations) throw Error('No se ha cargado el módulo de relaciones de auditoría.');
  if (!templates) throw Error('No se ha cargado el catálogo de controles offline.');
  if (!quality) throw Error('No se ha cargado la revisión de calidad offline.');
  if (!retest) throw Error('No se ha cargado el módulo de reevaluación.');
  if (!comparison) throw Error('No se ha cargado el resumen comparativo offline.');
  const SETTINGS_KEY = 'sysadmin-tools:audit-workbench:settings:v1';
  const CONNECTION_KEY = 'sysadmin-tools:audit-workbench:encrypted-nextcloud:v1';
  const LEGACY_STORE = 'sysadmin-tools:audit-workbench:v2';
  const ACTIVE_KEY = 'sysadmin-tools:audit-workbench:active:v3';
  const FALLBACK_KEY = 'sysadmin-tools:audit-workbench:records:v3';
  const PALETTE_KEY = 'sysadmin-tools:audit-workbench:palette:v1';
  const BACKUP_KEY = 'sysadmin-tools:audit-workbench:backup-settings:v1';
  const BACKUP_DB = 'audit-workbench-backup-directory';
  const palettes = ['ocean', 'forest', 'indigo', 'graphite', 'midnight', 'obsidian', 'pine-dark', 'amethyst-dark', 'crimson-dark'];
  const CVE_PATTERN = /^CVE-(?:1999|2\d{3})-\d{4,}$/i;
  const safeLogo = value => typeof value === 'string' && value.length <= 850000 && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(value) ? value : '';
  // The curated catalogue is offline and has no automatic compatibility claims.
  // Existing custom models remain editable even when absent from the catalogue.
  const vendorModels = window.AuditHardwareCatalog || Object.freeze({});
  const osCatalog = globalThis.AuditOSCatalog;
  const glossary = globalThis.AuditGlossary;
  const hardwareVendors = Object.keys(vendorModels);
  const hardwareModels = Object.values(vendorModels).flat();
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
    ['dashboard','▦','Resumen del expediente'],['engagement','◈','Cliente y alcance'],
    ['assets','▤','Hardware'],['networks','◇','Redes'],['software','▧','Software'],['cves','◉','Vulnerabilidades CVE'],
    ['controls','✓','Controles'],['findings','⚑','Hallazgos'],
    ['evidence','▣','Evidencias'],['legal','§','Cláusulas y privacidad'],['quality','☑','Revisión de calidad'],['followup','↺','Seguimiento'],['delivery','▥','Informe final']
  ];
  const metaFields = [
    ['client','Organización / cliente'],['project','Nombre del proyecto'],
    ['clientIdType','Documento fiscal del cliente','select',['No indicado','NIF entidad / CIF','DNI / NIF persona física','NIE','NIF intracomunitario / otro']],['clientTaxId','Número de identificación fiscal'],
    ['clientEmail','Correo electrónico del cliente'],['clientPhone','Teléfono del cliente'],['clientAddress','Domicilio fiscal / sede'],['clientPostal','Código postal (España)'],
    ['reportId','Identificador del informe'],['revision','Versión del informe'],
    ['contact','Contacto del cliente'],
    ['contactIdType','Documento identificativo del contacto','select',['No indicado','DNI / NIF persona física','NIE','Otro documento']],['contactId','DNI / NIE del contacto (opcional)'],
    ['start','Inicio de la auditoría','date'],['startTime','Hora de inicio (local)','time'],['end','Fin de la auditoría','date'],['endTime','Hora de fin (local)','time'],
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
      ['id','Identificador del activo'],['name','Activo / hostname'],['type','Categoría / rol','picker',presets.hardware],['vendor','Fabricante','picker',hardwareVendors],['model','Modelo','picker',hardwareModels],['serial','Número de serie'],
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
      ['id','Código del hallazgo'],['title','Título'],['severity','Severidad','select',['Sin evaluar','Crítica','Alta','Media','Baja','Informativa']],
      ['status','Seguimiento','select',['Abierto','En curso','Mitigado','Riesgo aceptado','Cerrado']],
      ['asset','Activos / alcance afectados','picker',[]],['cvss','CVSS (si corresponde)'],
      ['likelihood','Probabilidad','select',['No evaluada','Muy alta','Alta','Media','Baja','Muy baja']],
      ['impact','Impacto','select',['No evaluado','Muy alto','Alto','Medio','Bajo','Muy bajo']],
      ['description','Descripción / situación observada','textarea'],['risk','Consecuencia y escenario de riesgo','textarea'],
      ['method','Método o herramientas utilizadas','textarea'],['evidenceIds','ID(s) de evidencia'],
      ['references','CVE / CIS / NIST / referencias','textarea'],['recommendation','Remediación propuesta','textarea'],
      ['verification','Cómo comprobar que se ha solucionado','textarea'],
      ['owner','Responsable','picker',presets.owner],['deadline','Fecha objetivo','date'],['residual','Riesgo residual / notas','textarea']]},
    evidence:{title:'Cadena documental de evidencias',intro:'Las imágenes se incrustan opcionalmente en el expediente JSON y en el PDF; conserva los originales de manera separada y segura.',fields:[
      ['id','ID de evidencia'],['title','Título / descripción breve'],['asset','Activo / hallazgo relacionado','picker',[]],
      ['captured','Fecha de captura','date'],['source','Fuente / comando / ruta segura'],
      ['sha256','SHA-256 del original (opcional)'],['notes','Detalle, custodia y observaciones','textarea']]}
  };
  const severity = ['Crítica','Alta','Media','Baja','Informativa'];
  const fresh = () => ({schemaVersion:VERSION,meta:{classification:'Confidencial',type:'Auditoría de infraestructura',revision:'1.0',logo:'',reportAuto:'yes',auditTeam:[]},final:{disclaimer:'La evaluación refleja los sistemas y las evidencias examinados durante el período indicado. Las comprobaciones no ejecutadas y las exclusiones se detallan en el alcance.'},legal:legalDefaults(),assets:[],networks:[],software:[],cves:[],controls:[],findings:[],evidence:[],followupBaseline:null});
  const str = v => typeof v === 'string' ? v.slice(0,20000) : '';
  const html = v => String(v ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const uid = () => globalThis.crypto && crypto.randomUUID ? crypto.randomUUID() : 'id-'+Date.now()+'-'+Math.random().toString(36).slice(2);
  const plain = v => html(v || 'No documentado');
  const para = v => `<span class="report-text">${plain(v)}</span>`;
  const level = v => ({'Crítica':'critical','Alta':'high','Media':'medium','Baja':'low','Informativa':'info'})[v] || 'info';
  const slug = v => (v || 'cliente').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9_-]/gi,'-').slice(0,38);
  function validate(raw){
    if(!raw || Array.isArray(raw) || typeof raw!=='object' || raw.schemaVersion!==VERSION)throw Error('Versión de expediente incompatible (esperada: 3).');
    const out=fresh();
    for(const [block,fields] of [['meta',metaFields],['final',finalFields],['legal',legalFields]]){
      if(!raw[block]||Array.isArray(raw[block])||typeof raw[block]!=='object'){if(block==='legal')continue;throw Error('Bloque incorrecto: '+block)}
      for(const [name] of fields)out[block][name]=typeof raw[block][name]==='string'?str(raw[block][name]):out[block][name];
    }
    out.meta.logo=safeLogo(raw.meta.logo);
    out.meta.reportAuto=raw.meta.reportAuto==='no'?'no':'yes';
    out.meta.auditTeam=normalizeAuditTeam(raw.meta.auditTeam);
    out.followupBaseline=comparison.normalizeBaseline(raw.followupBaseline);
    for(const [block,definition] of Object.entries(groups)){
      if(block==='cves' && raw[block]===undefined)continue;
      if(!Array.isArray(raw[block])||raw[block].length>LIMIT_ROWS)throw Error('Datos no válidos en '+block);
      out[block]=raw[block].map(item=>{
        if(!item||typeof item!=='object'||Array.isArray(item))throw Error('Registro no válido en '+block);
        const record={_key:str(item._key)||uid()};
        for(const [name] of definition.fields)record[name]=str(item[name]);
        if(block==='controls'){
          record.templateKey=templates.safeKey(str(item.templateKey).split('/')[0]) && /^[A-Z0-9-]{2,64}$/.test(str(item.templateKey).split('/')[1]||'') ? str(item.templateKey).slice(0,130) : '';
          record.templateVersion=str(item.templateVersion).slice(0,12);
          record.expectedEvidence=str(item.expectedEvidence).slice(0,4000);
          record.recommendation=str(item.recommendation).slice(0,4000);
        }
        if(block==='findings'){record.originControlKey=str(item.originControlKey).slice(0,100);record.retests=retest.normalize(item.retests);}
        if(block==='evidence'){
          const pic=typeof item.image==='string' && item.image.length<1400000?item.image:'';
          record.image=/^data:image\/jpeg;base64,[a-z0-9+/=]+$/i.test(pic)&&pic.length<1400000?pic:'';
          record.links=relations.normalizeLinks(item.links);
          record.fileName=str(item.fileName).slice(0,180);
          record.fileBytes=Number.isSafeInteger(item.fileBytes) && item.fileBytes>=0 ? item.fileBytes : null;
          record.fileSha256=/^[a-f0-9]{64}$/i.test(item.fileSha256||'')?item.fileSha256.toLowerCase():'';
        }
        return record;
      });
    }
    return out;
  }
  const TEAM_MAX=60;
  const TEAM_ROLES=['Auditor/a de sistemas','Auditor/a de redes','Auditor/a de ciberseguridad','Responsable de auditoría','Especialista forense','Consultor/a técnico/a','Otro'];
  const MEMBER_DOCUMENT_TYPES=['DNI','NIE','Pasaporte / otro'];
  // Store immutable attribution snapshots in each audit. Global member updates must
  // not silently rewrite the author list of already issued reports.
  function normalizeMember(raw){
    if(!raw||typeof raw!=='object'||Array.isArray(raw))return null;
    const id=str(raw.id).slice(0,90),name=str(raw.name).trim().slice(0,160);
    if(!id||!name)return null;
    const idType=MEMBER_DOCUMENT_TYPES.includes(raw.idType)?raw.idType:'DNI';
    return {id,name,role:str(raw.role).slice(0,120),idType,documentId:normalizeId(raw.documentId).slice(0,32),email:str(raw.email).slice(0,254),phone:str(raw.phone).slice(0,40)};
  }
  function normalizeAuditTeam(raw){
    if(!Array.isArray(raw))return [];
    const seen=new Set();
    return raw.slice(0,TEAM_MAX).map(normalizeMember).filter(member=>{
      if(!member||seen.has(member.id))return false;
      seen.add(member.id);return true;
    });
  }
  function auditorNames(meta){return meta.auditTeam?.length?meta.auditTeam.map(x=>x.name).join(', '):str(meta.auditor).trim()}
  const DEFAULT_SETTINGS = () => ({
    company:'',taxType:'NIF entidad / CIF',taxId:'',email:'',phone:'',address:'',postal:'',
    prefix:'AUD',logo:'',sequences:{},members:[]
  });
  function loadSettings(){
    try{
      const raw=JSON.parse(localStorage.getItem(SETTINGS_KEY)||'{}');
      if(!raw||typeof raw!=='object'||Array.isArray(raw))return DEFAULT_SETTINGS();
      const cfg=DEFAULT_SETTINGS();
      for(const key of ['company','taxType','taxId','email','phone','address','postal','prefix'])if(typeof raw[key]==='string')cfg[key]=str(raw[key]);
      cfg.prefix=/^[A-Z0-9-]{2,12}$/.test(cfg.prefix)?cfg.prefix:'AUD';
      cfg.logo=safeLogo(raw.logo);
      cfg.members=normalizeAuditTeam(raw.members);
      if(raw.sequences&&typeof raw.sequences==='object'&&!Array.isArray(raw.sequences)){
        for(const [key,value] of Object.entries(raw.sequences)){
          if(key.length<160&&Number.isSafeInteger(value)&&value>=0&&value<1000000)cfg.sequences[key]=value;
        }
      }
      return cfg;
    }catch{return DEFAULT_SETTINGS()}
  }
  function loadSettingsFromImport(raw){
    if(!raw||typeof raw!=='object'||Array.isArray(raw))throw Error('Configuración no válida');
    const result=DEFAULT_SETTINGS();
    for(const key of ['company','taxType','taxId','email','phone','address','postal','prefix'])if(typeof raw[key]==='string')result[key]=str(raw[key]);
    result.logo=safeLogo(raw.logo);
    result.members=normalizeAuditTeam(raw.members);
    if(!/^[A-Z0-9-]{2,12}$/.test(result.prefix))result.prefix='AUD';
    if(raw.sequences&&typeof raw.sequences==='object'&&!Array.isArray(raw.sequences))for(const [key,num] of Object.entries(raw.sequences)){if(key.length<160&&Number.isSafeInteger(num)&&num>=0&&num<1000000)result.sequences[key]=num}
    return result;
  }
  let settings=loadSettings();
  function saveSettings(){
    try{localStorage.setItem(SETTINGS_KEY,JSON.stringify(settings));return true}
    catch(error){alert('No se pudo guardar la configuración local: '+error.message);return false}
  }
  function clientKey(client){return (client||'__pendiente__').trim().toLocaleLowerCase('es').slice(0,150)}
  function nextReportId(client){
    const key=clientKey(client),prefix=settings.prefix||'AUD';
    const prior=records.filter(r=>r.id!==currentId&&clientKey(r.audit?.meta?.client)===key).map(r=>r.audit?.meta?.reportId||'');
    const expression=new RegExp('^'+prefix+'-(\\d+)$','i');
    const highest=prior.reduce((max,id)=>Math.max(max,Number(id.match(expression)?.[1]||0)),0);
    const next=Math.max(settings.sequences[key]||0,highest)+1;
    settings.sequences[key]=next;saveSettings();
    return prefix+'-'+String(next).padStart(3,'0');
  }
  function normalizeId(v){return str(v).trim().toUpperCase().replace(/[.\s-]/g,'')}
  const DNI_LETTERS='TRWAGMYFPDXBNJZSQVHLCKE';
  function validDni(value){return /^\d{8}[A-Z]$/.test(value)&&DNI_LETTERS[Number(value.slice(0,8))%23]===value[8]}
  function validNie(value){return /^[XYZ]\d{7}[A-Z]$/.test(value)&&validDni('XYZ'.indexOf(value[0])+value.slice(1))}
  function validEntityNif(value){
    if(!/^[ABCDEFGHJKLMNPQRSUVW]\d{7}[0-9A-J]$/.test(value))return false;
    const digits=value.slice(1,8);
    const even=[1,3,5].reduce((acc,i)=>acc+Number(digits[i]),0);
    const odd=[0,2,4,6].reduce((acc,i)=>{const twice=Number(digits[i])*2;return acc+Math.floor(twice/10)+twice%10},0);
    const check=(10-(even+odd)%10)%10;
    const digit=String(check),letter='JABCDEFGHI'[check];
    const control=value[8];
    if('ABEH'.includes(value[0]))return control===digit;
    if('NPQRSW'.includes(value[0]))return control===letter;
    return control===digit||control===letter;
  }
  function validateIdentity(type,value){
    const v=normalizeId(value);
    if(!v||type==='No indicado')return '';
    if(type==='DNI / NIF persona física'&&!validDni(v))return 'DNI/NIF no válido: comprueba 8 dígitos y letra de control.';
    if(type==='NIE'&&!validNie(v))return 'NIE no válido: comprueba X/Y/Z, 7 cifras y letra de control.';
    if(type==='NIF entidad / CIF'&&!validEntityNif(v))return 'NIF de entidad no válido: comprueba la letra y el dígito/letra de control.';
    if(type==='NIF intracomunitario / otro'&&!/^[A-Z]{2}[A-Z0-9]{4,14}$/.test(v))return 'Comprueba país de dos letras y número fiscal; la verificación VIES no se realiza offline.';
    if(type==='Otro documento'&&v.length<4)return 'El documento parece demasiado corto.';
    return '';
  }
  // Validation checks syntax/control digits only; identity must still be verified by the auditor.
  function memberIdentityIssue(member){
    const type=member.idType||'DNI',number=normalizeId(member.documentId);
    if(!number)return 'El identificador personal es obligatorio para asignar al profesional.';
    if(type==='DNI')return validateIdentity('DNI / NIF persona física',number);
    if(type==='NIE')return validateIdentity('NIE',number);
    if(type==='Pasaporte / otro')return /^[A-Z0-9]{4,32}$/.test(number)?'':'El documento debe contener de 4 a 32 letras o números.';
    return 'Selecciona el tipo de identificación personal.';
  }
  function showMemberValidation(member){
    if(!member)return;
    const input=[...document.querySelectorAll('[data-member-field="documentId"]')].find(el=>el.dataset.memberId===member.id);
    if(!input)return;
    const issue=memberIdentityIssue(member),wrapper=input.closest('.field');
    let message=wrapper.querySelector('.field-error');
    if(!message){message=document.createElement('small');message.className='field-error';message.setAttribute('role','status');wrapper.append(message)}
    message.textContent=issue;
    input.setCustomValidity(issue);input.setAttribute('aria-invalid',issue?'true':'false');
    const kind=[...document.querySelectorAll('[data-member-field="idType"]')].find(el=>el.dataset.memberId===member.id);
    if(kind)kind.setAttribute('aria-invalid',issue?'true':'false');
  }
  function validationError(block,field,value,obj){
    const v=str(value).trim();if(!v)return '';
    if(field==='clientTaxId')return validateIdentity(obj.clientIdType||'No indicado',v);
    if(field==='contactId')return validateIdentity(obj.contactIdType||'No indicado',v);
    if(field==='taxId'&&block==='settings')return validateIdentity(obj.taxType||'No indicado',v);
    if(['email','clientEmail'].includes(field)&&!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v))return 'Introduce un correo electrónico válido.';
    if(['phone','clientPhone'].includes(field)&&!/^\+?[\d ()-]{9,23}$/.test(v))return 'Número telefónico no válido (9–15 dígitos, prefijo opcional).';
    if(['postal','clientPostal'].includes(field)&&!/^((0[1-9]|[1-4]\d|5[0-2])\d{3})$/.test(v))return 'Código postal español: 5 dígitos, provincia entre 01 y 52.';
    if(field==='id'&&block==='cves'&&!CVE_PATTERN.test(v))return 'Formato esperado: CVE-AAAA-NNNN.';
    if(field==='sha256'&& !/^[a-fA-F0-9]{64}$/.test(v))return 'La huella SHA-256 debe contener 64 caracteres hexadecimales.';
    if(field==='cvss'&& !(/^(?:10(?:\.0)?|[0-9](?:\.[0-9])?)$/.test(v)))return 'La puntuación CVSS debe estar entre 0.0 y 10.0.';
    if(field==='vlan'&&(!/^\d+$/.test(v)||Number(v)<1||Number(v)>4094))return 'VLAN válida: de 1 a 4094.';
    if(field==='cidr'&& !/^(?:\d{1,3}\.){3}\d{1,3}\/(?:[0-9]|[12][0-9]|3[0-2])$/.test(v))return 'Subred IPv4 CIDR no válida (ej. 192.168.1.0/24).';
    if(block==='meta'&&['start','startTime','end','endTime'].includes(field))return quality.periodProblems(obj)[0]?.message||'';
    return '';
  }
  function updateValidation(target){
    const block=target.dataset.block,field=target.dataset.field;
    const obj=block==='settings'?settings:fieldTarget(target);
    if(!obj||target.dataset.preset)return;
    const issue=validationError(block,field,target.value,obj);
    const wrapper=target.closest('.field');
    if(!wrapper)return;
    let node=wrapper.querySelector('.field-error');
    if(!node){node=document.createElement('small');node.className='field-error';node.setAttribute('role','status');wrapper.append(node)}
    node.textContent=issue;target.setAttribute('aria-invalid',issue?'true':'false');
    if(typeof target.setCustomValidity==='function')target.setCustomValidity(issue);
  }
  function invalidFields(){
    const problems=[];
    for(const member of state.meta.auditTeam||[]){
      const issue=memberIdentityIssue(member);
      if(issue)problems.push('Profesional '+(member.name||'sin nombre')+': '+issue);
    }
    for(const [name] of metaFields){const issue=validationError('meta',name,state.meta[name],state.meta);if(issue)problems.push(name+': '+issue)}
    for(const [block,def] of Object.entries(groups))for(const record of state[block])for(const [name] of def.fields){const issue=validationError(block,name,record[name],record);if(issue)problems.push(block+'/'+name+': '+issue)}
    return problems;
  }
  // Backup metadata contains timestamps and user preferences, never customer data.
  let backupPrefs = {lastExportAt:'',lastExportCount:0,lastFolderAt:'',lastFolderCount:0,folderName:'',automatic:false,lastError:''};
  try {backupPrefs={...backupPrefs,...JSON.parse(localStorage.getItem(BACKUP_KEY)||'{}')};} catch (_ignored) {}
  let autoBackupInProgress=false;
  const storeBackupPrefs=()=>{try{localStorage.setItem(BACKUP_KEY,JSON.stringify(backupPrefs))}catch(error){console.warn('No se pudo guardar la preferencia de backups',error)}};
  const changedSinceLastBackup=()=>{
    const latest = records.reduce((date,item)=>item.updatedAt>date?item.updatedAt:date,'');
    return dirty || !backupPrefs.lastFolderAt || latest>backupPrefs.lastFolderAt;
  };
  const canChooseFolder=()=>typeof window.showDirectoryPicker==='function' && typeof indexedDB!=='undefined';
  function directoryHandle(action){
    return new Promise((resolve,reject)=>{
      const request=indexedDB.open(BACKUP_DB,1);
      request.onupgradeneeded=()=>request.result.createObjectStore('handles');
      request.onerror=()=>reject(request.error||Error('No se pudo abrir el registro de carpetas'));
      request.onsuccess=()=>{
        const db=request.result,tx=db.transaction('handles',action==='get'?'readonly':'readwrite');
        const op=action==='get'?tx.objectStore('handles').get('backup'):action==='delete'?tx.objectStore('handles').delete('backup'):tx.objectStore('handles').put(action,'backup');
        op.onsuccess=()=>resolve(op.result);
        op.onerror=()=>reject(op.error||Error('No se pudo acceder a la carpeta'));
        tx.oncomplete=()=>db.close();
      };
    });
  }
  function backupPayload(){
    return {auditWorkbenchBackup:1,exportedAt:new Date().toISOString(),records:records.map(item=>({audit:item.id===currentId?state:item.audit}))};
  }
  function backupFilename(){return 'audit-workbench-copia-'+new Date().toISOString().replace(/[:.]/g,'-')+'.json'}
  async function backupToFolder({interactive=false}={}){
    if(autoBackupInProgress)return;
    autoBackupInProgress=true;
    try{
      if(!canChooseFolder())throw Error('Este navegador no admite escritura en carpetas mediante File System Access API. Utiliza «Descargar backup JSON».');
      const handle=await directoryHandle('get');
      if(!handle)throw Error('Primero selecciona una carpeta de destino.');
      let permission=await handle.queryPermission({mode:'readwrite'});
      if(permission!=='granted' && interactive)permission=await handle.requestPermission({mode:'readwrite'});
      if(permission!=='granted')throw Error('Permiso de escritura no disponible. Abre el gestor y autoriza la carpeta de nuevo.');
      await flush();
      const destination=await handle.getFileHandle(backupFilename(),{create:true});
      const writer=await destination.createWritable();
      try{await writer.write(JSON.stringify(backupPayload(),null,2));await writer.close()}
      catch(error){await writer.abort().catch(()=>{});throw error}
      backupPrefs.lastFolderAt=new Date().toISOString();backupPrefs.lastFolderCount=records.length;backupPrefs.lastError='';
      backupPrefs.folderName=handle.name;storeBackupPrefs();
      if(page==='backups')render();
    }catch(error){
      backupPrefs.lastError=String(error.message||error).slice(0,240);storeBackupPrefs();
      if(interactive)alert('No se pudo guardar en la carpeta: '+backupPrefs.lastError);
      else console.warn('Copia automática pendiente:',error.message);
      if(page==='backups')render();
    }finally{autoBackupInProgress=false}
  }
  async function selectBackupFolder(){
    try{
      if(!canChooseFolder())throw Error('El selector de carpetas no está disponible en este navegador.');
      const handle=await window.showDirectoryPicker({mode:'readwrite'});
      if((await handle.requestPermission({mode:'readwrite'}))!=='granted')throw Error('Permiso de escritura no concedido.');
      await directoryHandle(handle);backupPrefs.folderName=handle.name;backupPrefs.lastError='';storeBackupPrefs();render();
    }catch(error){if(error.name!=='AbortError')alert('No se pudo seleccionar la carpeta: '+error.message)}
  }
  async function forgetBackupFolder(){
    if(!confirm('¿Desvincular la carpeta de copias? Los archivos ya guardados NO se borrarán.'))return;
    try{await directoryHandle('delete')}catch(_ignored){}
    backupPrefs.automatic=false;backupPrefs.folderName='';backupPrefs.lastError='';storeBackupPrefs();render();
  }
  async function exportTabular(format){
    const engine=globalThis.AuditTabular;
    if(!engine){alert('El módulo de exportaciones no se ha cargado. Recarga la aplicación para actualizar la caché offline.');return}
    try{
      await flush();
      const prefix='auditoria-'+slug(state.meta.reportId||state.meta.client||'sin-referencia');
      if(format==='xlsx'){
        const file=engine.xlsx(state);downloadBlob(prefix+'.xlsx',file);
      }else{
        const key=byId('export-csv-section')?.value||'Hallazgos';
        const section=engine.sections(state).find(item=>item.name===key);
        if(!section)throw Error('Selecciona una sección de exportación.');
        download(prefix+'-'+slug(key)+'.csv',engine.csv(section),'text/csv;charset=utf-8');
      }
    }catch(error){alert('Error al preparar la exportación tabular: '+error.message)}
  }
  // The browser may suspend tabs. Periodic backups are attempted only while the
  // application is open, visible and the user has granted folder access.
  setInterval(()=>{
    if(!backupPrefs.automatic || document.hidden || !backupPrefs.folderName || autoBackupInProgress)return;
    const previous=Date.parse(backupPrefs.lastFolderAt||'');
    if((!Number.isFinite(previous)||Date.now()-previous>=30*60*1000) && changedSinceLastBackup())void backupToFolder();
  },60*1000);
  const repository=storage.createRepository({fallbackKey:FALLBACK_KEY});
  const byId=id=>document.getElementById(id);
  let state=fresh(),currentId='',page='records',records=[],storageError=false,dirty=false,saveTimer=null,writeQueue=Promise.resolve();
  let selectedPalette='ocean', deferredInstallPrompt=null;
  function updateStatus(message,warning=false){const node=byId('save-status');node.textContent=message;node.classList.toggle('warning',warning)}
  function enqueue(action){writeQueue=writeQueue.catch(()=>{}).then(action);return writeQueue}
  function selectPalette(value){
    selectedPalette=palettes.includes(value)?value:'ocean';
    document.documentElement.dataset.palette=selectedPalette;
    byId('palette').value=selectedPalette;
    byId('report').dataset.palette=selectedPalette;
    byId('pdf-theme').textContent=byId('palette').selectedOptions[0]?.textContent||selectedPalette;
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
        // No empty report is created implicitly. A new audit is an explicit action.
        let legacy=null;
        try{const input=localStorage.getItem(LEGACY_STORE);if(input)legacy=validate(JSON.parse(input))}catch(error){console.warn('No se pudo recuperar un expediente heredado',error)}
        if(legacy){const first=newRecord(legacy);await repository.put(first);records=[first]}
      }
      if(records.length){
        let lastId='';try{lastId=localStorage.getItem(ACTIVE_KEY)||''}catch(_ignored){}
        const active=records.find(r=>r.id===lastId)||[...records].sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt))[0];
        setActive(active);
      }
      updateStatus('● Biblioteca preparada · '+repository.mode);
    }catch(error){console.error('No se pudo inicializar la persistencia',error);storageError=true;currentId=uid();updateStatus('⚠ Sin almacenamiento · exporta JSON',true)}
    render();
  }
  async function createAudit(audit=fresh()){
    try{
      await flush();
      if(!audit.meta.reportId){audit.meta.reportId=nextReportId(audit.meta.client);audit.meta.reportAuto='yes'}
      // Auditors are selected explicitly per audit; never assign the company name as an individual.
      if(!audit.meta.logo)audit.meta.logo=settings.logo;
      const record=newRecord(audit);await enqueue(()=>repository.put(record));records.push(record);setActive(record);move('engagement')}
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
        if(records.length){setActive([...records].sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt))[0])}
        else{currentId='';state=fresh();try{localStorage.removeItem(ACTIVE_KEY)}catch(_ignored){}}
      }
      move('records');
    }catch(error){alert('No se pudo eliminar: '+error.message)}
  }
  async function duplicateAudit(id){
    const original=records.find(r=>r.id===id);if(!original)return;
    const copy=structuredCloneSafe(original.audit);copy.meta.project=(copy.meta.project||'Auditoría')+' · Copia';
    await createAudit(copy);
  }
  function downloadBlob(filename,blob){
    const url=URL.createObjectURL(blob);
    const anchor=document.createElement('a');
    anchor.href=url;anchor.download=filename;anchor.hidden=true;
    document.body.appendChild(anchor);
    try{anchor.click();}
    finally{anchor.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);}
  }
  function download(filename,content,type){downloadBlob(filename,new Blob([content],{type}))}
  function renderField(obj,block,def,index){
    const [name,label,type,choices]=def;
    const attrs=`data-block="${html(block)}" data-field="${html(name)}"`+(index===undefined?'':` data-index="${index}"`);
    const value=str(obj[name]),id='f-'+block+'-'+(index===undefined?'main':index)+'-'+name;
    const key=/^(vlan|cvss|serial)$/.test(name)?'decimal':'text';
    let control;
    if(type==='textarea')control=`<textarea id="${id}" ${attrs} maxlength="20000">${html(value)}</textarea>`;
    else if(type==='select')control=`<select id="${id}" ${attrs}>${choices.map(x=>`<option value="${html(x)}"${x===value?' selected':''}>${html(x)}</option>`).join('')}</select>`;
    else if(type==='picker' && ['os','cpu','ram','storage','site','name'].includes(name) && (name!=='name'||block==='software')){
      const options=name==='os'?(osCatalog?.ALL||choices):choices;
      const listId='suggest-'+block+'-'+(index===undefined?'main':index)+'-'+name;
      control=`<input id="${id}" ${attrs} list="${listId}" autocomplete="off" value="${html(value)}" maxlength="20000" placeholder="Escribe para buscar o introduce otro valor"><datalist id="${listId}">${options.map(x=>`<option value="${html(x)}"></option>`).join('')}</datalist>`;
    }
    else if(type==='picker'){
      // A native select is easier on touchscreens; unlisted values remain editable.
      const options=name==='asset'?[...new Set(['Todo el alcance',...state.assets.map(a=>str(a.name)).filter(Boolean)])]:block==='assets'&&name==='model'?(vendorModels[obj.vendor]||[]):choices;
      const custom=Boolean(value)&&!options.includes(value);
      control=`<select id="${id}" ${attrs} data-preset="true" aria-label="${html(label)}"><option value="">${block==='assets'&&name==='model'&&!obj.vendor?'Selecciona primero un fabricante…':'Seleccionar…'}</option>${options.map(x=>`<option value="${html(x)}"${x===value?' selected':''}>${html(x)}</option>`).join('')}<option value="__custom__"${custom?' selected':''}>Otro / escribir…</option></select><input ${attrs} data-custom="true" aria-label="${html(label)} personalizado" placeholder="Especifica el valor" value="${custom?html(value):''}" maxlength="20000" ${custom?'':'hidden'}>`;
    }else control=`<input id="${id}" type="${type==='date'?'date':type==='time'?'time':'text'}" ${attrs} value="${html(value)}" maxlength="20000"${key==='decimal'?' inputmode="decimal"':''}>`;
    const termId=glossary?.CONTEXT_HELP?.fields?.[block]?.[name];
    const term=termId?glossary.byId(termId):null;
    const help=term?`<button type="button" class="glossary-help" data-glossary-term="${html(term.id)}" data-glossary-field="${html(id)}" aria-label="Consultar ${html(term.title)} y volver a este campo"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><circle cx="12" cy="12" r="9"></circle><path d="M12 11v5"></path><circle cx="12" cy="7.5" r=".85" fill="currentColor" stroke="none"></circle></svg></button>`:'';
    return `<div class="field${type==='textarea'?' full':''}"><div class="field-heading"><label for="${id}">${html(label)}</label>${help}</div>${control}</div>`;
  }
  function pill(v){return `<span class="pill ${level(v)}">${html(v||'Sin clasificar')}</span>`}
  function metric(title,note,count){return `<div class="stat"><span class="metric">${count}</span><span class="metric-caption">${title}</span><span class="metric-foot">${note}</span></div>`}
  let glossaryQuery='', glossaryCategory='Todas', glossarySelected='';
  let glossaryReturn=null,lastAuditPage='engagement';
  function backToAudit(){const origin=glossaryReturn;glossaryReturn=null;const destination=origin?.page||lastAuditPage;move(destination);const target=origin?.field?byId(origin.field):null;if(target){target.scrollIntoView({block:'center'});target.focus({preventScroll:true});}else if(origin?.scrollY!==undefined)window.scrollTo(0,origin.scrollY);}
  function glossaryResults(){return glossary?.search(glossaryQuery,glossaryCategory)||[]}
  function glossaryEmphasis(value){
    const safe=html(value);
    const words=glossaryQuery.trim().split(/\s+/).filter(x=>x.length>1).slice(0,5);
    if(!words.length)return safe;
    const escaped=words.map(x=>x.replace(/[^\p{L}\p{N}]/gu, ch=>'\\'+ch));
    // Highlight only within plain escaped text; never interpret user input as HTML.
    const regex=new RegExp('('+escaped.join('|')+')','gi');
    return safe.split(/(&[^;]+;)/g).map(chunk=>chunk.startsWith('&')?chunk:chunk.replace(regex,'<mark>$1</mark>')).join('');
  }
  function renderGlossary(){
    const terms=glossaryResults();
    if(!terms.some(t=>t.id===glossarySelected))glossarySelected=terms[0]?.id||'';
    const selected=glossary?.byId(glossarySelected);
    const cats=['Todas',...(glossary?.CATEGORIES||[])];
    return `<span class="eyebrow">CONSULTA TÉCNICA · OFFLINE</span>${glossaryReturn||currentId?'<div class="glossary-return"><button class="button quiet" type="button" data-glossary-back="true">← Volver a la auditoría</button></div>':''}<h1 class="page-title">Diccionario técnico</h1>
      <p class="lead">Busca un concepto, selecciona una categoría y consulta una explicación práctica sin salir del asistente.</p>
      <section class="glossary-shell" aria-label="Diccionario técnico">
        <div class="glossary-toolbar"><label for="glossary-search">Buscar términos o sinónimos</label>
          <input id="glossary-search" type="search" autocomplete="off" placeholder="Ej.: red segmentada, 2FA, DNS…" value="${html(glossaryQuery)}" aria-controls="glossary-index">
          <span class="glossary-counter" id="glossary-count" aria-live="polite">${terms.length} de ${glossary.TERMS.length} conceptos</span>
        </div>
        <div class="glossary-categories" role="group" aria-label="Filtrar por temática">${cats.map(cat=>`<button type="button" class="glossary-category ${cat===glossaryCategory?'is-active':''}" data-glossary-category="${html(cat)}" aria-pressed="${cat===glossaryCategory}">${html(cat)}</button>`).join('')}</div>
        <div class="glossary-layout">
          <div class="glossary-index-panel"><h2>Índice de conceptos</h2><div id="glossary-index" class="glossary-index" role="group" aria-label="Conceptos disponibles">${renderGlossaryIndex(terms)}</div></div>
          <div id="glossary-detail" class="glossary-detail" aria-live="polite">${renderGlossaryDetail(selected)}</div>
        </div>
      </section>`;
  }
  function renderGlossaryIndex(terms){
    return terms.length?terms.map(t=>`<button type="button" class="glossary-entry ${t.id===glossarySelected?'is-active':''}" data-glossary-select="${html(t.id)}" aria-pressed="${t.id===glossarySelected}"><span class="glossary-entry-title">${glossaryEmphasis(t.title)}</span><span class="glossary-entry-category">${html(t.category)}</span></button>`).join(''):'<p class="glossary-empty">No hay coincidencias. Prueba otra palabra o categoría.</p>';
  }
  function glossaryPlatformIcon(platform){
    const p=String(platform||'').toLocaleLowerCase('es');
    const os=/macos|mac os|apple/.test(p)?'macos':/linux|debian|ubuntu|bash|chrony/.test(p)?'linux':/windows|powershell|cmd|defender|rsat|bitlocker|entra/.test(p)?'windows':'';
    return os?'<img class="glossary-os-icon" src="icons/os-'+os+'.svg" alt="" aria-hidden="true" loading="lazy">':'';
  }
  function glossaryTermPlatforms(t){
    const platforms=[...new Set((glossary?.GUIDES?.[t.id]?.commands||[]).map(c=>String(c.platform).toLowerCase()).flatMap(p=>/macos|mac os/.test(p)?['macos']:/linux|debian|ubuntu|bash|chrony/.test(p)?['linux']:/windows|powershell|cmd|defender|rsat|bitlocker|entra/.test(p)?['windows']:[]))];
    return platforms.length?'<div class="glossary-os-badges" aria-label="Plataformas con comandos disponibles">'+platforms.map(p=>'<span class="glossary-os-badge"><img class="glossary-os-icon" src="icons/os-'+p+'.svg" alt="" aria-hidden="true">'+(p==='macos'?'macOS':p==='linux'?'Linux':'Windows')+'</span>').join('')+'</div>':'';
  }
  function renderGlossaryGuide(t){
    const guide=glossary?.GUIDES?.[t.id];
    if(!guide)return '';
    return `<section class="glossary-section glossary-troubleshoot"><h3>Diagnóstico y troubleshooting</h3>
      <dl class="glossary-diagnostic"><dt>Patrón o síntoma</dt><dd>${html(guide.symptom)}</dd><dt>Cómo investigarlo</dt><dd>${html(guide.verify)}</dd><dt>Interpretación</dt><dd>${html(guide.interpret)}</dd></dl></section>
      <section class="glossary-section glossary-console"><h3>Alternativas por consola</h3>
        <p class="glossary-console-intro">Comandos de referencia; solo lectura salvo conexiones explícitamente indicadas. Sustituye rutas y destinos, verifica permisos y alcance. La aplicación no ejecuta nada.</p>
        ${guide.commands.map((item,i)=>`<div class="glossary-command"><div class="glossary-command-head"><span class="glossary-command-platform">${glossaryPlatformIcon(item.platform)}${html(item.platform)}</span><button type="button" class="glossary-copy" data-glossary-copy="${i}" data-glossary-id="${html(t.id)}" aria-label="Copiar comando ${html(item.platform)}">Copiar</button></div><pre><code>${html(item.command)}</code></pre><p><strong>Qué observar:</strong> ${html(item.lookFor)}</p></div>`).join('')}
      </section>`;
  }
  function renderGlossaryHelp(t){
    const help=t?.help;
    if(!help)return '';
    return `<details class="glossary-help-resource">
      <summary><span class="glossary-resource-mark" aria-hidden="true">☎</span><span>Ayuda ante ciberincidentes · ${html(help.region)}</span></summary>
      <div class="glossary-help-content">
        <p><strong>${html(help.organization)} · ${html(help.title)}</strong></p>
        <p>${html(help.guidance)}</p>
        <p class="glossary-help-phone"><a href="tel:017" aria-label="Llamar al 017, línea de ayuda en ciberseguridad de INCIBE">${html(help.phone)}</a><span>Orientación telefónica</span></p>
        <p><a href="${html(help.officialUrl)}" target="_blank" rel="noopener noreferrer external">Información oficial del servicio ↗</a></p>
        <p>${html(help.reporting)} <a href="${html(help.reportUrl)}" target="_blank" rel="noopener noreferrer external">Notificar un incidente empresarial ↗</a></p>
        <p class="glossary-help-privacy">${html(help.privacy)}</p>
      </div>
    </details>`;
  }
  function renderGlossaryDetail(t){
    if(!t)return '<div class="glossary-empty">Selecciona un concepto del índice.</div>';
    return `<article class="glossary-article">${glossaryReturn||currentId?'<button type="button" class="glossary-inline-back" data-glossary-back="true">← Volver al asistente</button>':''}<span class="glossary-kicker">${html(t.category)}</span><h2>${html(t.title)}</h2>${glossaryTermPlatforms(t)}${t.fullName?`<p class="glossary-fullname"><strong>Denominación completa:</strong> ${html(t.fullName)}</p>`:''}<div class="glossary-definition">${glossaryEmphasis(t.description)}</div>
      ${t.why?`<section class="glossary-section glossary-why"><h3>Por qué importa</h3><p>${glossaryEmphasis(t.why)}</p></section>`:''}
      <section class="glossary-section glossary-check"><h3>Qué comprobar en la auditoría</h3><p>${glossaryEmphasis(t.check)}</p></section>
      ${renderGlossaryGuide(t)}
      ${renderGlossaryHelp(t)}
      ${t.example?`<section class="glossary-section glossary-example"><h3>Ejemplo</h3><p>${html(t.example)}</p></section>`:''}
      ${t.references?.length?`<section class="glossary-section glossary-references"><h3>Referencias y recursos oficiales</h3><ul>${t.references.map(ref=>`<li><a href="${html(ref.url)}" target="_blank" rel="noopener noreferrer external">${html(ref.label)} <span aria-hidden="true">↗</span></a></li>`).join('')}</ul><p class="glossary-external-note">Estos recursos requieren conexión y se abren fuera de la aplicación.</p></section>` : ''}
      ${t.aliases?.length?`<p class="glossary-aliases"><strong>También se busca como:</strong> ${html(t.aliases.join(', '))}</p>`:''}
      <p class="glossary-disclaimer">Referencia orientativa. Documenta la prueba realizada y contrasta los criterios con el contexto del cliente.</p></article>`;
  }
  function openGlossary(term,origin){
    glossaryReturn=origin||{page:lastAuditPage,scrollY:window.scrollY};
    const selected=glossary?.byId(term)||glossary?.search(term)?.[0];
    glossaryQuery=selected?'':(term||'');glossaryCategory='Todas';glossarySelected=selected?.id||'';
    page='glossary';render();scrollTo(0,0);
  }
  function filterGlossary(q){
    glossaryQuery=q;
    const terms=glossaryResults();
    if(!terms.some(t=>t.id===glossarySelected))glossarySelected=terms[0]?.id||'';
    const index=byId('glossary-index'),detail=byId('glossary-detail'),counter=byId('glossary-count');
    if(index)index.innerHTML=renderGlossaryIndex(terms);
    if(detail)detail.innerHTML=renderGlossaryDetail(glossary?.byId(glossarySelected));
    if(counter)counter.textContent=terms.length+' de '+glossary.TERMS.length+' conceptos';
  }
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
  function renderBackups(){
    const pending=changedSinceLastBackup();
    const readable=iso=>iso?new Date(iso).toLocaleString('es-ES'):'Todavía no';
    const tables=globalThis.AuditTabular?.sections(state)||[];
    return `<span class="eyebrow">BIBLIOTECA / COPIAS Y ENTREGA</span><h1 class="page-title">Copias de seguridad y exportación</h1>
      <p class="lead">Los expedientes se guardan en <strong>${html(repository.mode)}</strong> dentro de este navegador. La carpeta de instalación contiene la aplicación, <strong>no</strong> los datos de los clientes.</p>
      <div class="grid-two">
        <section class="card"><h2>Copia completa · JSON</h2><p class="subtle">Único formato compatible con la restauración de todas las auditorías, incluidos textos, cláusulas y fotografías.</p>
          <p><strong>${records.length}</strong> auditorías en este perfil · Última descarga iniciada: <strong>${html(readable(backupPrefs.lastExportAt))}</strong></p>
          <div class="action-row"><button type="button" class="button accent" data-backup-all="true">Descargar backup completo (.json)</button><button type="button" class="button quiet" id="backup-restore">Importar / restaurar JSON</button></div>
          <p class="subtle">La descarga no prueba que el archivo se haya guardado correctamente. Verifica el archivo en la carpeta de destino antes de borrar datos del navegador.</p></section>
        <section class="card"><h2>Copias en carpeta local</h2><p class="subtle">${canChooseFolder()?'Disponible en este navegador.':'No disponible en este navegador. Puedes seguir descargando JSON manualmente.'}</p>
          <p>Destino: <strong>${html(backupPrefs.folderName||'Sin carpeta asociada')}</strong> · Última copia escrita: <strong>${html(readable(backupPrefs.lastFolderAt))}</strong></p>
          <p><strong>${pending?'Hay cambios pendientes de respaldar':'Sin cambios detectados desde la última copia guardada'}</strong></p>
          ${backupPrefs.lastError?`<p class="backup-error" role="alert">${html(backupPrefs.lastError)}</p>`:''}
          <div class="action-row"><button type="button" class="button quiet" id="backup-select-folder" ${canChooseFolder()?'':'disabled'}>Seleccionar carpeta</button><button type="button" class="button accent" id="backup-write-now" ${backupPrefs.folderName?'':'disabled'}>Guardar ahora</button><button type="button" class="button quiet" id="backup-forget" ${backupPrefs.folderName?'':'disabled'}>Desvincular</button></div>
          <label class="backup-opt"><input id="backup-auto" type="checkbox" ${backupPrefs.automatic?'checked':''} ${backupPrefs.folderName?'':'disabled'}> Realizar copias cada 30 minutos con cambios, mientras la aplicación esté abierta</label>
          <p class="subtle">Los permisos pueden caducar. No funciona cuando el navegador está cerrado y no sustituye un backup cifrado externo.</p></section>
      </div>
      <section class="card"><h2>Entregables editables · Excel / CSV</h2><p class="subtle">Úsalos para compartir inventarios y planes de actuación; <strong>no se pueden restaurar</strong> como auditorías. Las imágenes y cláusulas extensas permanecen en el JSON y en el PDF.</p>
        <div class="backup-exports"><div><label for="export-csv-section">Sección para CSV</label><select id="export-csv-section" aria-label="Seleccionar datos CSV">${tables.map(x=>`<option value="${html(x.name)}" ${x.name==='Hallazgos'?'selected':''}>${html(x.name)} (${x.rows.length})</option>`).join('')}</select></div>
          <button type="button" class="button quiet" id="backup-export-csv" ${currentId?'':'disabled'}>Exportar CSV</button>
          <button type="button" class="button accent" id="backup-export-xlsx" ${currentId?'':'disabled'}>Exportar Excel (.xlsx)</button></div>
        <p class="subtle">El XLSX incluye varias hojas con filtros; el CSV usa UTF-8 y separador de punto y coma para Excel en español. Comprueba los datos confidenciales antes de compartir.</p></section>
      <div class="notice warn">Algunos expedientes contienen datos personales, vulnerabilidades o evidencias sensibles. Guarda los backups en un volumen cifrado y controla quién puede acceder a ellos.</div>`;
  }
  function recordsMarkup(items){
    return items.length?items.map(r=>`<article class="audit-row${r.id===currentId?' current':''}"><div class="audit-description"><span class="eyebrow">${r.id===currentId?'ABIERTA · ':''}${html(r.audit.meta.reportId||'SIN REFERENCIA')}</span><h3>${html(r.audit.meta.project||'Auditoría sin título')}</h3><p>${html(r.audit.meta.client||'Cliente por identificar')} · Actualizada ${html(new Date(r.updatedAt).toLocaleString('es-ES'))}</p><small>${r.audit.assets.length} equipos · ${r.audit.findings.length} hallazgos · ${r.audit.controls.length} controles</small></div><div class="audit-actions"><button class="button accent" data-open="${html(r.id)}">Editar</button><button class="button quiet" data-copy="${html(r.id)}">Duplicar</button><button class="button quiet" data-export-record="${html(r.id)}">JSON</button><button class="button danger" data-delete-record="${html(r.id)}">Borrar</button></div></article>`).join(''):'<div class="empty"><b>Sin resultados</b>Prueba otro nombre o crea una auditoría.</div>';
  }
  function renderForm(block,fields,title,intro){return `<span class="eyebrow">AUDITORÍA / DOCUMENTACIÓN</span><h1 class="page-title">${title}</h1><p class="lead">${intro}</p><section class="card"><div class="fields">${fields.map(f=>renderField(state[block],block,f)).join('')}</div></section>`}
  function renderEngagement(){
    return renderForm('meta',metaFields,'Cliente y alcance','Contexto, autorización, alcance, metodología y limitaciones de la evaluación.')+renderAuditTeam()+
      `<section class="card"><h2>Logo específico del informe (opcional)</h2><p class="subtle">Adjunta tu logo o el de la consultora (PNG, JPEG o WebP; máximo 3 MiB). Se convierte a JPEG y se incluye en el JSON exportado y en la portada del PDF. No se sube a Internet.</p><input id="logo-upload" type="file" accept="image/png,image/jpeg,image/webp" aria-label="Seleccionar logotipo corporativo">${state.meta.logo?`<div class="logo-preview"><img src="${state.meta.logo}" alt="Logotipo corporativo incorporado"><button type="button" class="button danger small" id="logo-remove">Eliminar logotipo</button></div>`:''}</section>`;
  }
  const relationLabels = {assets:'Activos',controls:'Controles',findings:'Hallazgos'};
  function renderEvidenceRelations(evidence) {
    const links=relations.normalizeLinks(evidence.links);
    return `<div class="evidence-relations"><h3>Relacionar con el expediente</h3><p class="subtle">Selecciona los elementos afectados. No necesitas copiar identificadores manualmente.</p>
      ${relations.CATEGORIES.map(kind=>{
        const available=state[kind]||[];
        const selected=links[kind].map(key=>{
          const entry=available.find(item=>item._key===key);
          return `<button type="button" class="relation-chip" data-unlink-evidence="${html(evidence._key)}" data-relation-kind="${kind}" data-relation-target="${html(key)}" aria-label="Desvincular ${html(relations.itemLabel(entry,kind))}">${html(relations.itemLabel(entry,kind))} ×</button>`;
        }).join('');
        return `<div class="relation-line"><label for="rel-${kind}-${html(evidence._key)}">${relationLabels[kind]}</label><select id="rel-${kind}-${html(evidence._key)}" data-add-evidence-link="${html(evidence._key)}" data-relation-kind="${kind}"><option value="">+ Vincular ${relationLabels[kind].toLowerCase()}…</option>${available.filter(item=>!links[kind].includes(item._key)).map(item=>`<option value="${html(item._key)}">${html(relations.itemLabel(item,kind))}</option>`).join('')}</select><div class="relation-chips">${selected||'<small class="subtle">Sin elementos vinculados</small>'}</div></div>`;
      }).join('')}</div>`;
  }
  function renderLinkedEvidence(kind,item) {
    const related=relations.linkedEvidence(state,kind,item._key);
    return related.length?`<div class="related-evidence"><strong>${related.length} evidencia(s) vinculada(s)</strong><p>${related.map(e=>html(relations.itemLabel(e,'evidence'))).join(' · ')}</p></div>`:'';
  }
  let selectedTemplatePack = templates.PACKS[0].id;
  let templateMessage = '';
  function renderTemplateLibrary() {
    const pack=templates.getPack(selectedTemplatePack)||templates.PACKS[0];
    const installed=new Set(state.controls.map(control=>control.templateKey).filter(Boolean));
    const options=templates.PACKS.map(item=>`<option value="${html(item.id)}" ${pack.id===item.id?'selected':''}>${html(item.name)}</option>`).join('');
    const remaining=templates.countMissing(state.controls,pack.id);
    const checks=pack.controls.map(item=>{
      const exists=installed.has(templates.ref(pack.id,item.id));
      return `<label class="template-check"><input type="checkbox" data-template-choice="${html(item.id)}" ${exists?'disabled':'checked'}><span><strong>${html(item.name)}</strong><small>${html(item.method)}</small></span><span class="template-state">${exists?'Añadido':'Disponible'}</span></label>`;
    }).join('');
    return `<section class="card template-library"><div class="card-head"><div><h2>Plantillas de comprobaciones</h2><p class="subtle">Selecciona lo que necesitas. No se realiza ningún análisis automático y todos los resultados empiezan en «Pendiente».</p></div></div>
      <div class="template-pack-picker"><label for="template-pack">Área de revisión</label><select id="template-pack">${options}</select><p class="subtle">${html(pack.description)} · ${pack.controls.length} comprobaciones orientativas</p></div>
      <details class="template-details"><summary>Ver y seleccionar comprobaciones <strong>(${remaining} disponibles)</strong></summary><div class="template-checks">${checks}</div><div class="template-actions"><button type="button" class="button accent" data-apply-template="${html(pack.id)}" ${remaining?'':'disabled'}>Añadir controles seleccionados</button><span class="subtle">Sin duplicados. Puedes cambiar cada comprobación después.</span></div></details>
      ${templateMessage?`<p class="template-feedback" role="status">${html(templateMessage)}</p>`:''}</section>`;
  }
  function nextAvailableControlCode(used){let n=1;while(used.has('CTRL-'+String(n).padStart(3,'0')))n++;return 'CTRL-'+String(n).padStart(3,'0')}
  function renderControlExtras(control) {
    const linked=state.findings.filter(f=>f.originControlKey===control._key);
    const existing=linked.length?`<p class="subtle">Hallazgo relacionado: ${linked.map(f=>html(relations.itemLabel(f,'findings'))).join(' · ')}</p>`:'';
    const guide=control.templateKey?`<details class="control-check-guide"><summary>Guía rápida · evidencia y propuesta</summary><p><strong>Evidencia recomendable:</strong> ${html(control.expectedEvidence||'Definir según el alcance.')}</p><p><strong>Medida orientativa:</strong> ${html(control.recommendation||'Valorar con el responsable.')}</p><p class="subtle">Guía orientativa; el auditor debe verificar y documentar el resultado.</p></details>`:'';
    const button=control.status==='No conforme'&&!linked.length?`<button type="button" class="button quiet" data-finding-from-control="${html(control._key)}">+ Documentar hallazgo a partir de este control</button>`:'';
    return `<div class="control-extras">${guide}${existing}${button}</div>`;
  }
  function renderFindingOrigin(finding) {
    const options=state.controls.map(control=>`<option value="${html(control._key)}"${control._key===finding.originControlKey?' selected':''}>${html(relations.itemLabel(control,'controls'))}</option>`).join('');
    const deleted=finding.originControlKey&&!state.controls.some(control=>control._key===finding.originControlKey);
    return `<div class="finding-origin field full"><label for="origin-control-${html(finding._key)}">Control relacionado (opcional)</label><select id="origin-control-${html(finding._key)}" data-finding-control="${html(finding._key)}"><option value="">Sin control relacionado</option>${deleted?'<option value="__deleted__" selected>Control anterior eliminado — revisa el vínculo</option>':''}${options}</select><p class="subtle">Relaciona un hallazgo manual con el control que lo originó. Las evidencias del control pueden reutilizarse.</p></div>`;
  }
  function glossaryStageHint(block){
    const id=glossary?.CONTEXT_HELP?.stages?.[block];
    const term=id?glossary.byId(id):null;
    return term?`<p class="glossary-stage-hint">Referencia técnica: <button type="button" class="glossary-stage-link" data-glossary-term="${html(term.id)}" title="Consultar definición y comprobaciones de ${html(term.title)}">${html(term.title)} ↗</button></p>`:'';
  }
  let intakePreview=null,intakeSelected=new Set(),intakeError='',intakeBlock='assets',intakeReturn='assets';
  const intake=globalThis.AuditInventoryImport;
  function renderIntake(){
    const block=intakePreview?.block||intakeBlock;
    return `<span class="eyebrow">INVENTARIO / CAPTURA OPCIONAL</span><h1 class="page-title">Captura asistida de activos</h1>
      <p class="lead">Importa información obtenida mediante herramientas autorizadas. La vista previa no escribe en el expediente.</p>
      <div class="action-row"><button class="button quiet small" type="button" data-go="${html(intakeReturn)}">← Volver al inventario</button></div><section class="card"><h2>Seleccionar archivo</h2>
        <p class="subtle">Se admiten JSON de captura e inventarios CSV (UTF-8; comas o punto y coma). Máximo 2 MiB y 500 filas. Los datos se procesan localmente, sin conexiones a red.</p>
        <label for="intake-block">Destino en el inventario</label>
        <select id="intake-block"><option value="assets" ${block==='assets'?'selected':''}>Hardware</option><option value="networks" ${block==='networks'?'selected':''}>Redes</option><option value="software" ${block==='software'?'selected':''}>Software</option></select>
        <label for="intake-file">Archivo de captura</label><input id="intake-file" type="file" accept=".json,.csv,application/json,text/csv">
        <p class="subtle">Recopilación local opcional: <code>collect-local.sh --output captura.json</code> o <code>collect-local.ps1 -Output captura.json</code>. Ejecuta únicamente en equipos propios o autorizados.</p>
        <p id="intake-status" role="status" aria-live="polite">${html(intakeError)}</p></section>
        ${intakePreview?renderIntakePreview():''}`;
  }
  function renderIntakePreview(){
    if(!intakePreview)return '';
    const candidates=intake.reconcile(intakePreview,state[intakePreview.block]);
    const counts={nuevo:0,duplicado:0,conflicto:0};for(const c of candidates)counts[c.status]++;
    return `<section class="card"><h2>Vista previa · ${candidates.length} registros</h2>
      <p class="subtle">Origen: ${html(intakePreview.source)}${intakePreview.platform?' · '+html(intakePreview.platform):''}. Nuevos: ${counts.nuevo} · Duplicados: ${counts.duplicado} · Conflictos: ${counts.conflicto}. Nunca se sobrescriben registros.</p>
      <div class="intake-toolbar"><button class="button quiet small" type="button" data-intake-select="new">Seleccionar solo nuevos</button><button class="button quiet small" type="button" data-intake-select="none">Deseleccionar</button></div>
      <div class="intake-records">${candidates.map(c=>`<label class="intake-record"><input type="checkbox" data-intake-row="${c.index}" ${intakeSelected.has(c.index)?'checked':''} ${c.status!=='nuevo'?'disabled':''}><span><strong>${html(c.record.name||c.record.id||c.record.cidr||'Registro '+(c.index+1))}</strong><small>${html(c.status==='nuevo'?'Nuevo':c.status==='duplicado'?'Duplicado':'Conflicto: '+c.differences.slice(0,3).join(' · '))}</small><small>${html(Object.entries(c.record).filter(([,v])=>v).slice(0,8).map(([k,v])=>k+': '+v).join(' · '))}</small></span></label>`).join('')}</div>
      <div class="action-row"><button class="button accent" type="button" data-intake-apply="true" ${intakeSelected.size?'':'disabled'}>Incorporar ${intakeSelected.size} registros nuevos</button><button class="button quiet" type="button" data-intake-reset="true">Descartar vista previa</button></div>
      <p class="subtle">Los conflictos se muestran para revisión manual. Datos incompletos, credenciales y resultados no verificados nunca se convierten automáticamente en hallazgos.</p></section>`;
  }
  function renderGroup(block){const def=groups[block],rows=state[block];return `<span class="eyebrow">INVENTARIO / EVIDENCIAS</span><h1 class="page-title">${def.title}</h1><p class="lead">${def.intro}</p>${['assets','networks','software'].includes(block)?'<button type="button" class="button quiet small" data-go="intake">Captura asistida / Importar inventario ↗</button>':''}${glossaryStageHint(block)}${block==='controls'?renderTemplateLibrary():''}<section class="card"><div class="card-head"><div><h2>${rows.length} registros</h2><p class="subtle">Cada dato registrado podrá aparecer en el informe y en la copia JSON.</p></div>${block==='evidence'?'<button class="button quiet" data-export-manifest="true">Manifiesto SHA-256 (JSON)</button>':''}<button class="button accent" data-add="${block}">+ Añadir registro</button></div>${rows.length?rows.map((r,i)=>`<div class="entry" data-entry-key="${html(r._key||'')}" tabindex="-1"><div class="entry-head"><div><strong>${html(r.title||r.name||r.id||'Registro '+(i+1))}</strong> ${block==='findings'?pill(r.severity):''}</div><button class="button danger small" data-remove="${block}" data-index="${i}">Eliminar</button></div><div class="fields">${def.fields.map(f=>renderField(r,block,f,i)).join('')}</div>${['assets','controls','findings'].includes(block)?renderLinkedEvidence(block,r):''}${block==='controls'?renderControlExtras(r):''}${block==='findings'?renderFindingOrigin(r):''}${block==='evidence'?renderEvidenceRelations(r):''}${block==='cves'?`<div class="cve-tools"><button class="button quiet small" type="button" data-cve-check="${i}">Consultar CVE online (opcional)</button><button class="button small" type="button" data-cve-link="${i}">Ver en CVE.org ↗</button><span class="subtle">Solo se envía el identificador CVE, nunca los datos del cliente.</span></div>`:''}${block==='evidence'?`<div class="file-upload"><label for="evidence-upload-${i}"><strong>Adjuntar captura local</strong> (PNG, JPG, WebP hasta 5 MiB)</label><p class="subtle">Se guarda una copia optimizada. El SHA-256 identifica el archivo original, que debes conservar por separado.</p>${r.fileSha256?`<p class="evidence-digest">Archivo: ${html(r.fileName||'Sin nombre')} · ${(r.fileBytes||0).toLocaleString('es-ES')} bytes <span>SHA-256 ${html(r.fileSha256)}</span></p>`:''}<input type="file" accept="image/png,image/jpeg,image/webp" data-image-index="${i}" id="evidence-upload-${i}">${r.image?`<img class="evidence-preview" alt="Evidencia incrustada" src="${r.image}"><button class="button small danger" data-clear-image="${i}">Quitar imagen</button>`:''}</div>`:''}</div>`).join(''):`<div class="empty"><b>No hay registros todavía</b>Usa «Añadir registro» para empezar.</div>`}</section>`}
  const settingsFields=[
    ['company','Nombre legal de la consultora'],['taxType','Identificador fiscal','select',['No indicado','NIF entidad / CIF','DNI / NIF persona física','NIE','NIF intracomunitario / otro']],
    ['taxId','Identificación fiscal'],['email','Email corporativo'],['phone','Teléfono'],
    ['address','Domicilio profesional'],['postal','Código postal (España)'],['prefix','Prefijo de informes (ej. AUD)']
  ];
  function renderMemberDirectory(){
    const members=settings.members;
    return `<section class="card"><div class="card-head"><div><h2>Equipo de auditores</h2><p class="subtle">Registra nombre, función y documento identificativo de cada profesional. Estos datos se copian a los expedientes seleccionados y figuran en el PDF; custodia los backups como información personal.</p></div><button class="button accent" type="button" id="member-add" ${members.length>=TEAM_MAX?'disabled':''}>+ Añadir auditor/a</button></div>
    ${members.length?`<div class="member-directory">${members.map((member,i)=>`<section class="member-card" data-member-id="${html(member.id)}"><div class="member-card-head"><strong>Miembro ${i+1}${member.name?' · '+html(member.name):''}</strong><button type="button" class="button danger small" data-member-remove="${html(member.id)}">Eliminar</button></div><div class="fields">
    <div class="field"><label for="member-name-${i}">Nombre y apellidos</label><input id="member-name-${i}" data-member-id="${html(member.id)}" data-member-field="name" maxlength="160" autocomplete="off" value="${html(member.name)}" required></div>
    <div class="field"><label for="member-role-${i}">Función en las auditorías</label><select id="member-role-${i}" data-member-id="${html(member.id)}" data-member-field="role"><option value="">Seleccionar función…</option>${[...new Set([...TEAM_ROLES,member.role].filter(Boolean))].map(role=>`<option value="${html(role)}" ${role===member.role?'selected':''}>${html(role)}</option>`).join('')}</select></div>
    <div class="field"><label for="member-id-type-${i}">Tipo de identificador personal</label><select id="member-id-type-${i}" data-member-id="${html(member.id)}" data-member-field="idType">${MEMBER_DOCUMENT_TYPES.map(type=>`<option value="${html(type)}" ${type===(member.idType||'DNI')?'selected':''}>${html(type)}</option>`).join('')}</select></div>
    <div class="field"><label for="member-document-${i}">DNI / NIE / identificador personal <span class="required-mark">*</span></label><input id="member-document-${i}" data-member-id="${html(member.id)}" data-member-field="documentId" maxlength="32" autocomplete="off" autocapitalize="characters" spellcheck="false" value="${html(member.documentId||'')}" aria-describedby="member-help-${i}" required><small class="field-hint" id="member-help-${i}">Validación local de DNI/NIE. Para otro documento se comprueba el formato, no su autenticidad.</small></div>
    <div class="field"><label for="member-email-${i}">Correo profesional (opcional)</label><input id="member-email-${i}" type="email" data-member-id="${html(member.id)}" data-member-field="email" maxlength="254" value="${html(member.email)}"></div>
    <div class="field"><label for="member-phone-${i}">Teléfono profesional (opcional)</label><input id="member-phone-${i}" type="tel" data-member-id="${html(member.id)}" data-member-field="phone" maxlength="40" value="${html(member.phone)}"></div></div></section>`).join('')}</div>`:'<p class="empty">Todavía no hay auditores registrados. Añade un miembro para poder seleccionarlo en tus auditorías.</p>'}</section>`;
  }
  function renderAuditTeam(){
    const team=state.meta.auditTeam||[];
    const seen=new Set(settings.members.map(m=>m.id));
    return `<section class="card"><h2>Profesionales asignados a esta auditoría</h2><p class="subtle">Selecciona los auditores que realizan el trabajo. Se pueden elegir varios. El equipo seleccionado se guarda dentro del expediente y se incorpora al PDF.</p>
    ${settings.members.length?`<div class="auditor-choice-list">${settings.members.map(member=>`<label class="auditor-choice"><input type="checkbox" data-auditor-select="${html(member.id)}" ${team.some(x=>x.id===member.id)?'checked':''}><span><strong>${html(member.name)}</strong><small>${html(member.role||'Sin función definida')}${member.email?' · '+html(member.email):''} · ${memberIdentityIssue(member)?'Identificación pendiente':'Identidad documentada'}</small></span></label>`).join('')}</div>`:'<div class="notice warn">Configura primero los miembros de la consultora. <button type="button" class="button quiet small" data-go="settings">Añadir auditores</button></div>'}
    ${team.filter(member=>!seen.has(member.id)).map(member=>`<label class="auditor-choice archived"><input type="checkbox" data-auditor-select="${html(member.id)}" checked><span><strong>${html(member.name)}</strong><small>Profesional archivado en este informe; ya no figura en el directorio</small></span></label>`).join('')}
    <small class="subtle">Si actualizas el nombre o la función de un miembro del directorio, el expediente conserva sus datos anteriores hasta que lo desmarques y vuelvas a seleccionar.</small></section>`;
  }
  function renderSettings(){
    return `<span class="eyebrow">PREFERENCIAS / CONSULTORA</span><h1 class="page-title">Configuración de la consultora</h1>
      <p class="lead">Gestiona por separado los datos fiscales de la consultora y los profesionales que realizan las auditorías. La información se conserva en este dispositivo hasta que exportes el perfil.</p>
      ${currentId?'<button class="button quiet" type="button" data-go="engagement">← Volver al expediente abierto</button>':''}
      <section class="card"><h2>Datos de la empresa auditora</h2><div class="fields">${settingsFields.map(f=>renderField(settings,'settings',f)).join('')}</div></section>
      ${renderMemberDirectory()}
      <section class="card"><h2>Logotipo corporativo</h2><p class="subtle">Se copiará a cada expediente nuevo y al PDF. No se envía a ningún servidor.</p>
      <input type="file" id="settings-logo-upload" accept="image/jpeg,image/png,image/webp" aria-label="Logotipo de la consultora">${settings.logo?`<div class="logo-preview"><img src="${settings.logo}" alt="Logotipo configurado"><button type="button" class="button danger" id="settings-logo-remove">Eliminar logo</button></div>`:''}</section>
      <section class="card"><h2>Numeración y copia de seguridad</h2><p class="subtle">La numeración se asigna por cliente al completar su nombre. Cada cliente tiene su propia secuencia; un código usado no vuelve a asignarse aunque borres el expediente. Puedes corregir manualmente un identificador concreto.</p>
      <div class="action-row"><button class="button accent" id="settings-export">Exportar perfil JSON</button><button class="button quiet" id="settings-import">Importar perfil JSON</button><input type="file" id="settings-import-file" accept=".json,application/json" hidden></div></section>`;
  }
  function renderWizardTop(){const i=nav.findIndex(n=>n[0]===page);return i<0?'':`<div class="wizard-top"><span>Fase ${i+1} / ${nav.length}</span><progress max="${nav.length}" value="${i+1}"></progress><span>${html(nav[i][2])}</span></div>`}
  function renderWizard(){
    const current=nav.findIndex(n=>n[0]===page);
    if(current<0)return '';
    const previous=nav[current-1],next=nav[current+1];
    const options=nav.map(([id,,label],i)=>`<option value="${id}"${i===current?' selected':''}>${i+1}. ${html(label)}</option>`).join('');
    return `<div class="wizard-controls" aria-label="Asistente de auditoría"><div class="wizard-progress"><strong>Paso ${current+1} de ${nav.length}</strong><span>${html(nav[current][2])}</span><progress max="${nav.length}" value="${current+1}"></progress></div>
      <div class="wizard-buttons"><button type="button" class="button quiet" data-go="${previous?previous[0]:'records'}">← ${previous?'Anterior':'Biblioteca'}</button><label class="wizard-jump">Ir al paso <select id="wizard-step-select">${options}</select></label><button type="button" class="button accent" data-go="${next?next[0]:'records'}">${next?'Siguiente':'Finalizar'} →</button></div></div>`;
  }
  // Browser-side WebDAV session; credentials are encrypted at rest with a user passphrase.
  const utf8=new TextEncoder(),decoder=new TextDecoder();
  let unlockedConnection=null, connectionChannel='nextcloud';
  function bytesB64(bytes){return btoa(Array.from(bytes,b=>String.fromCharCode(b)).join(''))}
  function b64Bytes(value){return Uint8Array.from(atob(value),x=>x.charCodeAt(0))}
  async function deriveKey(passphrase,salt){
    const base=await crypto.subtle.importKey('raw',utf8.encode(passphrase),'PBKDF2',false,['deriveKey']);
    return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:310000,hash:'SHA-256'},base,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
  }
  async function encryptProfile(profile,passphrase){
    const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
    const key=await deriveKey(passphrase,salt);
    const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,utf8.encode(JSON.stringify(profile)));
    return {version:1,kdf:'PBKDF2-SHA256',rounds:310000,cipher:'AES-256-GCM',salt:bytesB64(salt),iv:bytesB64(iv),payload:bytesB64(new Uint8Array(ciphertext))};
  }
  async function decryptProfile(envelope,passphrase){
    if(envelope?.version!==1)throw Error('Formato cifrado no reconocido.');
    const key=await deriveKey(passphrase,b64Bytes(envelope.salt));
    return JSON.parse(decoder.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:b64Bytes(envelope.iv)},key,b64Bytes(envelope.payload))));
  }
  function validateWebdavProfile(url,user,password){
    const parsed=new URL(url);
    if(parsed.protocol!=='https:'||parsed.username||parsed.password||parsed.search||parsed.hash)throw Error('Usa una dirección HTTPS sin parámetros ni credenciales en URL.');
    if(!/\/remote\.php\/dav\/files\//.test(parsed.pathname)&&!/\/remote\.php\/webdav\/?$/.test(parsed.pathname))throw Error('Indica una URL WebDAV de Nextcloud, p. ej. https://nube.example/remote.php/dav/files/usuario/');
    if(!user.trim()||!password)throw Error('Indica usuario y contraseña de aplicación de Nextcloud.');
    return {url:parsed.href.replace(/\/*$/,'/') ,user:user.trim(),secret:password};
  }
  function connectionSettingsMarkup(){
    const exists=Boolean(localStorage.getItem(CONNECTION_KEY));
    return `<span class="eyebrow">CONECTORES / OPCIONAL</span><h1 class="page-title">Conexiones y entrega</h1>
      <p class="lead">La auditoría funciona offline. Las transferencias son opcionales y requieren confirmación explícita. Distingue exportación JSON sin cifrar, backup cifrado y entrega de PDF.</p>
      <section class="card"><h2>1 · Elige un canal</h2><div class="connection-methods"><label><input type="radio" name="channel" value="nextcloud" ${connectionChannel==='nextcloud'?'checked':''}> Nextcloud / WebDAV (subir JSON cifrando la conexión TLS)</label><label><input type="radio" name="channel" value="email" ${connectionChannel==='email'?'checked':''}> Email (abre tu cliente de correo)</label><label><input type="radio" name="channel" value="share" ${connectionChannel==='share'?'checked':''}> Compartir con el sistema</label></div></section>
      <section class="card" id="connection-nextcloud" ${connectionChannel==='nextcloud'?'':'hidden'}><h2>2 · Configura Nextcloud</h2><p class="subtle">Usa una contraseña de aplicación revocable, no la contraseña principal. El perfil queda cifrado localmente mediante AES-GCM y una frase de paso que no almacenamos. El navegador debe permitir CORS en el servidor WebDAV.</p>
      <div class="fields"><div class="field full"><label for="dav-url">URL WebDAV HTTPS</label><input id="dav-url" type="url" autocomplete="off" placeholder="https://nube.example/remote.php/dav/files/usuario/"></div>
      <div class="field"><label for="dav-user">Usuario</label><input id="dav-user" autocomplete="off"></div><div class="field"><label for="dav-secret">Contraseña de aplicación</label><input id="dav-secret" type="password" autocomplete="new-password"></div>
      <div class="field full"><label for="dav-passphrase">Frase de paso local (12 caracteres mínimo)</label><input id="dav-passphrase" type="password" autocomplete="new-password"></div></div>
      <div class="action-row"><button class="button accent" id="dav-save">Guardar conexión cifrada</button><button class="button quiet" id="dav-unlock" ${exists?'':'disabled'}>Desbloquear conexión</button><button class="button danger" id="dav-forget" ${exists?'':'disabled'}>Borrar conexión</button></div>
      <p class="subtle" id="dav-status" role="status">${unlockedConnection?'Conexión desbloqueada en esta sesión.':exists?'Hay un perfil cifrado. Introduce la frase de paso para desbloquearlo.':'Todavía no hay una conexión guardada.'}</p></section>
      <section class="card" id="connection-upload" ${connectionChannel==='nextcloud'?'':'hidden'}><h2>3 · Entrega bajo consentimiento</h2><p class="subtle">Subida JSON original SIN CIFRAR, solo mediante HTTPS. Para backups remotos, prefiere la nueva opción «Subir copia cifrada» de abajo. Puede contener información confidencial y evidencias incrustadas. No se sincroniza automáticamente.</p>
      <div class="action-row"><button class="button accent" id="dav-upload" ${unlockedConnection&&currentId?'':'disabled'}>Subir expediente JSON</button><button class="button quiet" id="open-email" ${currentId?'':'disabled'}>Preparar correo</button><button class="button quiet" id="native-share-json" ${currentId?'':'disabled'}>Compartir JSON</button></div><p class="subtle" id="dav-upload-status" role="status"></p></section>
      <section class="card" id="connection-email" ${connectionChannel==='email'?'':'hidden'}><h2>2 · Envío por correo</h2><p class="subtle">Abre un correo con asunto y texto preparados. Los navegadores no pueden adjuntar automáticamente un PDF a un enlace mailto. Genera y revisa el PDF, adjúntalo en tu cliente y verifica destinatarios antes de enviar.</p><button type="button" class="button accent" id="open-email" ${currentId?'':'disabled'}>Redactar correo</button></section>
      <section class="card" id="connection-share" ${connectionChannel==='share'?'':'hidden'}><h2>2 · Compartir mediante el dispositivo</h2><p class="subtle">Utiliza Web Share API si el dispositivo la ofrece; elige manualmente la aplicación de destino. También puedes exportar JSON y compartir el PDF ya generado desde el gestor de archivos.</p><button type="button" class="button accent" id="native-share-json" ${currentId?'':'disabled'}>Compartir expediente JSON</button></section>
      ${globalThis.AuditSecureTransferUI.view(Boolean(currentId),Boolean(unlockedConnection))}<section class="card"><h2>Otros proveedores</h2><p class="subtle">Drive, OneDrive y Microsoft 365 requieren OAuth mediante PKCE, registro de aplicación y políticas CORS. No guardes <em>client secrets</em> de OAuth en una aplicación JavaScript distribuida: no pueden mantenerse secretos en un cliente público. Se añadirán integraciones específicas cuando tengan un flujo seguro verificado.</p></section>`;
  }
  function renderConnections(){return connectionSettingsMarkup()}
  async function uploadDav(){
    if(!currentId||!unlockedConnection)throw Error('Abre un expediente y desbloquea la conexión primero.');
    const filename='auditoria-'+slug(state.meta.client)+'-'+slug(state.meta.reportId||'informe')+'.json';
    const body=JSON.stringify(state,null,2);
    if(!confirm(`¿Enviar el expediente ${state.meta.reportId||''} (${Math.ceil(body.length/1024)} KiB) a ${new URL(unlockedConnection.url).origin}? Puede incluir datos personales y evidencias.`))return;
    const target=new URL(encodeURIComponent(filename),unlockedConnection.url).href;
    const authorization='Basic '+btoa(Array.from(utf8.encode(unlockedConnection.user+':'+unlockedConnection.secret),v=>String.fromCharCode(v)).join(''));
    const reply=await fetch(target,{method:'PUT',mode:'cors',credentials:'omit',headers:{'Authorization':authorization,'Content-Type':'application/json;charset=utf-8'},body,redirect:'error',referrerPolicy:'no-referrer'});
    if(!reply.ok)throw Error('WebDAV devolvió HTTP '+reply.status+'. Revisa permisos y CORS.');
    byId('dav-upload-status').textContent='Expediente enviado por HTTPS. Conserva igualmente una copia offline.';
  }
  // Connectivity is advisory: navigator.onLine never establishes Internet reachability.
  let serverVerified=false,networkBusy=false;
  function refreshNetworkStatus(){
    const panel=byId('network-panel'),title=byId('network-status'),detail=byId('network-description'),button=byId('network-check');
    if(!panel||!title||!detail)return;
    const connected=navigator.onLine;
    const state=networkBusy?'checking':!connected?'offline':serverVerified?'reachable':'unverified';
    panel.dataset.state=state;
    const copy={
      offline:['Sin conexión detectada','El expediente sigue disponible offline.'],
      unverified:['Red detectada · sin verificar','No implica acceso a Internet.'],
      reachable:['Servidor de la PWA accesible','No certifica acceso a Internet.'],
      checking:['Comprobando servidor…','Sin enviar datos del expediente.']
    }[state];
    title.textContent=copy[0];detail.textContent=copy[1];if(button)button.disabled=networkBusy;
    const status=byId('online-status');if(status)status.textContent=copy.join(' · ');
  }
  async function checkNetworkServer(){
    if(networkBusy)return;
    serverVerified=false;
    if(!navigator.onLine){refreshNetworkStatus();return;}
    if(!['http:','https:'].includes(location.protocol)){refreshNetworkStatus();return;}
    networkBusy=true;refreshNetworkStatus();
    const controller=new AbortController();
    // No cross-origin requests, credentials, telemetry or audit data.
    try{
      const url=new URL('./manifest.webmanifest',location.href);
      const response=await fetch(url.href,{method:'GET',cache:'no-store',credentials:'omit',redirect:'error',signal:controller.signal});
      serverVerified=response.ok&&response.type!=='opaque';
    }catch(_error){serverVerified=false;}
    finally{networkBusy=false;refreshNetworkStatus();}
  }
  function renderOnline(){
    const status=navigator.onLine?'Red detectada por el navegador; disponibilidad de servicios externos no comprobada.':'Sin conexión detectada. El expediente sigue siendo editable.';
    return `<span class="eyebrow">CONECTIVIDAD / ENTREGA OPCIONAL</span><h1 class="page-title">Herramientas conectadas</h1>
      <p class="lead">La auditoría no necesita Internet. Estas operaciones solo se ejecutan tras pulsar y confirmar, sin credenciales guardadas.</p>
      <section class="card"><h2>Estado de conexión e instalación</h2><p id="online-status" role="status">${html(status)}</p><div class="action-row"><button class="button quiet" id="check-connectivity">Comprobar conectividad</button><button class="button accent" id="install-pwa" ${deferredInstallPrompt?'':'hidden'}>Instalar aplicación en este dispositivo</button><button class="button quiet" data-go="cves">Consultar CVE por identificador</button></div><p class="subtle online-install-note">Para tablets: primero abre el sitio mediante HTTPS. Si el navegador no ofrece instalación directa, usa «Añadir a pantalla de inicio» desde su menú. Tras abrirla online, prueba la aplicación en modo avión.</p></section>
      <section class="card"><h2>Entrega bajo control del auditor</h2><p class="subtle">No se realiza ningún envío automático. El PDF se adjunta manualmente después de revisarlo.</p><div class="action-row"><button class="button accent" id="open-email">Preparar correo</button><button class="button quiet" id="native-share-json">Compartir JSON con el sistema</button><button class="button quiet" id="delivery-pdf">Generar PDF</button></div></section>
      <section class="card"><h2>Sincronización con nube</h2><p class="subtle">Google Drive, OneDrive, S3, Nextcloud y correo API requieren autorización, cifrado, autenticación y mecanismos de revocación. Todavía no están conectados. Exporta JSON y utiliza un cliente autorizado.</p></section>`;
  }
  const reviewState = (mode='draft') => quality.review(state,relations,{mode});
  function renderPlanSummary(rows,limit=6){
    if(!rows.length)return '<p class="subtle">No hay hallazgos documentados. Si no se han encontrado debilidades, explica la cobertura y las limitaciones.</p>';
    const selected=rows.slice(0,limit);
    return `<div class="remediation-list">${selected.map(item=>`<article class="remediation-item"><div class="remediation-heading"><strong>${html(item.id)} · ${html(item.title)}</strong>${pill(item.severity)}</div><p class="subtle">${html(item.status)} · Responsable: ${html(item.owner||'Por asignar')} · Fecha objetivo: ${html(item.deadline||'Sin acordar')}</p><p><strong>Acción:</strong> ${html(item.recommendation||'Pendiente de definir')}</p><p><strong>Verificación:</strong> ${html(item.verification||'Pendiente de definir')}</p></article>`).join('')}</div>${rows.length>limit?`<p class="subtle">Se muestran ${limit} de ${rows.length}; el PDF incluirá todos los hallazgos.</p>`:''}`;
  }
  function renderQuality(){
    const audit=reviewState();
    return `<span class="eyebrow">REVISIÓN ANTES DE ENTREGAR</span><h1 class="page-title">Control de calidad</h1><p class="lead">Solo los puntos que necesitan tu atención. Pulsa «Revisar» para ir directamente al apartado correspondiente. Los avisos no se corrigen automáticamente.</p>
      ${glossaryStageHint('quality')}<section class="card quality-overview"><div class="quality-counts"><div><strong>${audit.blockers.length}</strong><span>Imprescindibles</span></div><div><strong>${audit.warnings.length}</strong><span>Avisos</span></div><div><strong>${state.findings.length}</strong><span>Hallazgos</span></div></div>
      <div class="notice ${audit.ready?'':'warn'}">${audit.ready?'No se han detectado impedimentos de entrega. Revisa los avisos antes de emitir el informe final.':'Hay datos esenciales pendientes. Si imprimes ahora, el documento se identificará claramente como BORRADOR.'}</div></section>
      <section class="card"><h2>Aspectos que conviene revisar</h2>${audit.issues.length?`${[['blockers','Imprescindibles'],['warnings','Avisos y recomendaciones']].map(([key,title])=>audit[key].length?`<details class="quality-review-section" ${key==='blockers'||!audit.blockers.length?'open':''}><summary>${title} (${audit[key].length})</summary><div class="quality-issues">${audit[key].map(issue=>`<div class="quality-issue"><span class="quality-severity ${issue.severity}">${issue.severity==='blocker'?'Imprescindible':'Aviso'}</span><p>${html(issue.message)}</p><button type="button" class="button quiet small" data-quality-section="${html(issue.section)}" data-quality-key="${html(issue.key)}">Revisar →</button></div>`).join('')}</div></details>`:'').join('')}`:'<p class="notice">Todos los puntos comprobados están resueltos. La revisión profesional del contenido sigue siendo necesaria.</p>'}</section>
      <section class="card"><h2>Plan de remediación automático</h2><p class="subtle">Se ordena por severidad técnica y deja al final los casos cerrados o mitigados. No asigna plazos ni prioridades inventadas.</p>${renderPlanSummary(audit.plan)}<div class="action-row"><button class="button accent" type="button" data-go="delivery">Ir al informe final →</button><button class="button quiet" type="button" data-go="findings">Editar hallazgos</button></div></section>`;
  }
  function renderComparison(){
    const result=comparison.compare(state,retest);
    const n=result.counts,has=result.hasBaseline;
    const metrics=[
      [has?result.initialTotal:'—','Hallazgos de referencia'],
      [has?result.verifiedPercent+' %':'—','Correcciones verificadas sobre la referencia'],
      [has?result.priorityNotVerified:'—','Alta/crítica sin verificación de cierre'],
      [n.accepted+(result.addedCounts.accepted||0),'Riesgos aceptados (no corregidos)']
    ];
    const text=result.decisions.slice(0,5).map(row=>`<tr><td>${html(row.id||'Sin código')} · ${html(row.title||'Sin título')}</td><td>${html(row.severity)}</td><td>${html(row.owner||'Sin asignar')}</td><td>${html(row.deadline||'Por acordar')}</td></tr>`).join('');
    return `<section class="card" aria-label="Resumen ejecutivo del seguimiento"><div class="card-head"><div><h2>¿Estamos reduciendo la exposición?</h2><p class="subtle">Indicadores verificados para dirección. No equivalen a un cálculo automático del riesgo empresarial.</p></div></div>
      <div class="comparison-summary">${metrics.map(([num,label])=>`<div class="comparison-metric"><strong>${html(num)}</strong><span>${html(label)}</span></div>`).join('')}</div>
      <p class="comparison-note">${html(result.limitations)}</p>
      ${has?`<p class="comparison-note">Referencia: ${html(result.baseline.capturedAt.slice(0,10))} · Aún sin cierre verificado: ${result.initialTotal-result.counts.verified} de ${result.initialTotal} · Nuevos hallazgos desde la referencia: ${result.added} · Eliminados del expediente: ${result.counts.missing}${result.severityChanged?' · Severidades modificadas: '+result.severityChanged:''}.</p>`:`<p class="comparison-note">Para futuros seguimientos se fijará automáticamente una referencia antes de la primera verificación. Si el expediente ya tiene revisiones, puedes fijar una referencia actual para próximas comparaciones.</p>`}
      ${result.decisions.length?`<h3>Decisiones prioritarias pendientes (${result.decisions.length})</h3><table class="comparison-table"><thead><tr><th>Hallazgo</th><th>Severidad</th><th>Responsable</th><th>Fecha objetivo</th></tr></thead><tbody>${text}</tbody></table>`:'<p class="subtle">No hay hallazgos abiertos de severidad Alta o Crítica identificados en el expediente actual.</p>'}
      <div class="comparison-actions">${!has&&state.findings.length?'<button type="button" class="button quiet" id="comparison-capture">Fijar referencia actual para próximos seguimientos</button>':''}<button type="button" class="button quiet" data-go="quality">Revisar calidad y evidencias →</button></div>
    </section>`;
  }
  function renderFollowup(){
    const counts=retest.summary(state);
    const tiles=[['verified','Correcciones verificadas'],['pending','Persistentes'],['reopened','Reabiertos'],['accepted','Riesgos aceptados'],['unverified','No comprobables'],['inconsistent','Estado por aclarar'],['not-reviewed','Sin reevaluar']];
    const now=new Date();const today=new Date(now.getTime()-now.getTimezoneOffset()*60000).toISOString().slice(0,10);
    return `<span class="eyebrow">SEGUIMIENTO / REEVALUACIÓN</span><h1 class="page-title">¿Qué ha corregido el cliente?</h1><p class="lead">Documenta cada revisión en su hallazgo. Solo marca como corregido lo que has comprobado: una promesa de corrección no es una verificación.</p>
      ${glossaryStageHint('followup')}<section class="card"><h2>Estado de las correcciones</h2><div class="retest-summary">${tiles.map(([key,label])=>`<div><strong>${counts[key]}</strong><span>${label}</span></div>`).join('')}</div><p class="subtle">Se muestra el último resultado de cada hallazgo. Los históricos permanecen conservados en el expediente.</p>
      <div class="action-row"><button type="button" class="button accent" id="retest-pdf" ${!state.findings.length?'disabled':''}>Informe de reevaluación PDF ↗</button><button type="button" class="button quiet" data-go="findings">Editar hallazgos</button></div></section>
      ${renderComparison()}
      ${state.findings.length?state.findings.map((finding,index)=>{
        const latest=retest.latest(finding),status=retest.outcome(finding);
        const label=status==='accepted'?'Riesgo aceptado':status==='not-reviewed'?'Sin reevaluar':status==='inconsistent'?'Estado por aclarar':retest.RESULTS[status];
        const history=retest.normalize(finding.retests);
        const auditorOptions=(state.meta.auditTeam||[]).map(m=>html(m.name)).filter(Boolean);
        const evidenceOptions=state.evidence.map(e=>`<option value="${html(e._key)}">${html(e.id||'Evidencia')} · ${html(e.title||e.asset||'Sin título')}</option>`).join('');
        return `<article class="retest-item" data-retest-key="${html(finding._key)}"><div class="retest-item-head"><h3>${html(finding.id||'FND-'+(index+1))} · ${html(finding.title||'Hallazgo sin título')}</h3><span class="retest-status">${html(label)}</span></div>
          <p class="subtle">Severidad: ${html(finding.severity||'Sin evaluar')} · Seguimiento: ${html(finding.status||'Abierto')} · ${history.length} revisiones registradas</p>
          <p><strong>Comprobación de cierre:</strong> ${html(finding.verification||'Pendiente de definir en la ficha del hallazgo.')}</p>
          <details><summary>Registrar una nueva verificación</summary>
            <div class="retest-fields">
              <label>Resultado<select data-retest-field="result" required><option value="">Selecciona un resultado</option>${Object.entries(retest.RESULTS).map(([key,title])=>`<option value="${key}">${html(title)}</option>`).join('')}</select></label>
              <label>Fecha de comprobación<input type="date" data-retest-field="date" value="${today}" required></label>
              <label>Auditor responsable<input data-retest-field="by" list="audit-retest-auditors-${index}" maxlength="160" placeholder="Nombre del profesional" required><datalist id="audit-retest-auditors-${index}">${auditorOptions.map(name=>`<option value="${name}"></option>`).join('')}</datalist></label>
              <label>Evidencia de reevaluación<select data-retest-field="evidenceKey"><option value="">Sin evidencia adjunta</option>${evidenceOptions}</select></label>
              <label class="wide">Qué comprobaste y cuál fue el resultado<textarea data-retest-field="notes" maxlength="4000" required placeholder="Prueba realizada, resultado observado y limitaciones..."></textarea></label>
            </div><button type="button" class="button accent" data-save-retest="${html(finding._key)}">Guardar comprobación</button><p class="subtle">El registro se incorpora al historial. Para una corrección verificada se requiere un criterio de cierre definido; adjuntar una nueva evidencia es recomendable.</p></details>
          ${history.length?`<h4>Historial de verificaciones</h4><ol class="retest-history">${[...history].reverse().map(entry=>{const ev=retest.evidenceFor(entry,state);return `<li><strong>${html(entry.date)} · ${html(retest.RESULTS[entry.result])}</strong><div class="retest-meta">${html(entry.by)} · Estado previo: ${html(entry.previousStatus||'No registrado')}${entry.evidenceId||ev?' · Evidencia: '+html(entry.evidenceId||ev?.id||ev?.title):''}${entry.evidenceSha256?' · SHA-256 original: '+html(entry.evidenceSha256):''}</div><p>${html(entry.notes)}</p></li>`}).join('')}</ol>`:'<p class="subtle">Todavía no se ha documentado ninguna comprobación posterior.</p>'}
        </article>`;}).join(''):'<section class="card"><p class="subtle">No existen hallazgos. Registra primero las desviaciones detectadas durante la auditoría.</p></section>'}`;
  }
  function renderDelivery(){
    const audit=reviewState('final');
    return `<span class="eyebrow">ENTREGA / REPORTING</span><h1 class="page-title">Informe final</h1><p class="lead">Resumen para dirección, plan de remediación y anexo técnico verificable.</p>
      <div class="notice ${audit.ready?'':'warn'}">${audit.ready?'Revisión básica superada.':'Pendientes '+audit.blockers.length+' datos imprescindibles: el documento se emitirá como BORRADOR si decides continuar.'} ${audit.warnings.length} avisos adicionales. <button class="button quiet small" data-go="quality">Revisar calidad →</button></div>
      <section class="card"><div class="card-head"><div><h2>Conclusiones y cierre</h2><p class="subtle">Explica los riesgos en lenguaje comprensible y las decisiones necesarias.</p></div></div><div class="fields">${finalFields.map(f=>renderField(state.final,'final',f)).join('')}</div></section>
      <section class="card"><h2>Plan de remediación generado</h2><p class="subtle">Se utilizarán los hallazgos ya documentados. Para completar una acción, edita su ficha.</p>${renderPlanSummary(audit.plan)}<button type="button" class="button quiet" data-go="findings">Revisar responsables, fechas y verificación</button></section>
      <section class="card"><h2>Preparar entrega</h2><p class="subtle">El PDF contiene el informe y el plan de remediación; el JSON permite continuar la auditoría.</p><div class="action-row"><button class="button accent" id="delivery-pdf">Generar borrador PDF ↗</button><button class="button accent" id="delivery-pdf-final">Informe definitivo PDF ↗</button><button class="button quiet" id="retest-pdf">Informe de reevaluación PDF ↗</button><button class="button quiet" id="delivery-json">Descargar expediente JSON ↓</button><button class="button quiet" data-go="backups">Copias / Excel / CSV</button><button class="button danger" id="delivery-reset">Nuevo expediente</button><button class="button quiet" id="native-share-json">Compartir JSON (opcional)</button><button class="button quiet" id="open-email">Preparar correo (sin adjuntos)</button></div><p id="delivery-export-status" class="export-inline-status" role="status" aria-live="polite">La copia JSON se guarda mediante una descarga del navegador, no dentro de la carpeta de la PWA.</p></section>`;
  }

  function render(){
    const inLibrary=['records','backups','online','settings','connections','glossary'].includes(page)||!currentId;
    byId('navigation').hidden=true;
    byId('audit-context').hidden=true;
    byId('workspace-label').textContent='MENÚ PRINCIPAL';
    // Keep the global menu in sync with the current view, including the glossary.
    for(const button of byId('global-navigation').querySelectorAll('[data-go]')){
      const active=button.dataset.go===(page==='online'?'connections':page);
      button.classList.toggle('active',active);
      if(active)button.setAttribute('aria-current','page');
      else button.removeAttribute('aria-current');
    }
    byId('main-audit-context').hidden=inLibrary;
    byId('main-audit-context').textContent=(state.meta.reportId||'Sin referencia')+' · '+(state.meta.client||'Cliente pendiente')+' · '+(state.meta.project||'Sin título');
    byId('audit-context-title').textContent=state.meta.project||state.meta.client||'Auditoría sin título';
    byId('audit-context-ref').textContent=[state.meta.reportId||'SIN REFERENCIA',state.meta.client||'Cliente pendiente'].join(' · ');
    byId('navigation').innerHTML=nav.map(([id,symbol,name])=>`<button type="button" data-go="${id}" class="${page===id?'active':''}" ${page===id?'aria-current="page"':''}><span class="nav-mark">${symbol}</span>${name}</button>`).join('');
    byId('current-section').textContent=page==='records'?'Biblioteca de auditorías':page==='backups'?'Copias de seguridad':page==='settings'?'Configuración de consultora':page==='connections'||page==='online'?'Conexiones online':page==='glossary'?'Diccionario técnico':page==='intake'?'Captura asistida':nav.find(n=>n[0]===page)?.[2]||'Expediente';
    byId('active-audit-label').textContent=inLibrary?'Selecciona una auditoría':(state.meta.reportId||'Sin referencia')+' · '+(state.meta.project||state.meta.client||'Sin título');
    byId('btn-export').disabled=inLibrary;
    byId('btn-pdf').disabled=inLibrary;

    byId('workspace').innerHTML=(inLibrary?'':renderWizardTop())+(page==='dashboard'?renderOverview():page==='records'?renderRecords():page==='backups'?renderBackups():page==='settings'?renderSettings():page==='connections'||page==='online'?renderConnections():page==='glossary'?renderGlossary():page==='intake'?renderIntake():page==='engagement'?renderEngagement():page==='legal'?renderForm('legal',legalFields,'Cláusulas y privacidad','Modelos editables para auditorías en España. Revisa el contrato y solicita asesoramiento jurídico cuando corresponda.'):page==='quality'?renderQuality():page==='followup'?renderFollowup():page==='delivery'?renderDelivery():renderGroup(page))+(inLibrary?'':renderWizard());
    byId('wizard-step-select')?.addEventListener('change',event=>move(event.target.value));
    for(const target of workspace.querySelectorAll('.field [data-field]:not([data-preset])'))updateValidation(target);
  }
  function move(section){if(nav.some(n=>n[0]===section))lastAuditPage=section;if(section==='glossary'&&page!=='glossary')glossaryReturn={page:page==='records'?lastAuditPage:page,scrollY:window.scrollY};if(!['records','backups','online','settings','connections','glossary'].includes(section)&&!currentId){alert('Primero crea o abre una auditoría desde la biblioteca.');return}if(['records','backups','online','settings','connections','glossary'].includes(section)||section==='intake'||nav.some(n=>n[0]===section)){page=section;render();scrollTo(0,0)}}
  function fieldTarget(target){const {block,field,index}=target.dataset;if(!block||!field)return null;if(block==='meta'||block==='final'||block==='legal')return state[block];if(groups[block]&&index!==undefined)return state[block][Number(index)];return null}
  const workspace=byId('workspace');
  byId('global-navigation').addEventListener('click',e=>{const b=e.target.closest('[data-go]');if(b)move(b.dataset.go)});
  byId('navigation').addEventListener('click',e=>{const b=e.target.closest('[data-go]');if(b)move(b.dataset.go)});
  workspace.addEventListener('focusin',event=>{if(event.target.dataset.block==='meta'&&event.target.dataset.field==='client')event.target.dataset.originalClient=event.target.value});
  workspace.addEventListener('input',e=>{
    const t=e.target;
    if(t.id==='glossary-search'){filterGlossary(t.value);return;}
    if(t.dataset.memberField){
      const member=settings.members.find(m=>m.id===t.dataset.memberId);if(!member)return;
      const field=t.dataset.memberField,limit=field==='name'?160:field==='email'?254:field==='role'?120:field==='documentId'?32:40;
      member[field]=field==='documentId'?normalizeId(t.value).slice(0,32):t.value.slice(0,limit);
      if(field==='idType'||field==='documentId')showMemberValidation(member);
      if(field==='email'){const bad=Boolean(member.email)&&!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(member.email);t.setCustomValidity(bad?'Introduce un correo electrónico válido.':'');t.setAttribute('aria-invalid',String(bad));}
      const title=t.closest('.member-card')?.querySelector('.member-card-head strong');if(title&&field==='name')title.textContent='Auditor/a · '+(member.name||'Sin nombre');
      saveSettings();return;
    }
    if(t.id==='record-filter'){
      const term=t.value.toLocaleLowerCase('es');
      const matches=[...records].sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt)).filter(r=>[r.audit.meta.client,r.audit.meta.project,r.audit.meta.reportId].some(v=>(v||'').toLocaleLowerCase('es').includes(term)));
      byId('record-list').innerHTML=recordsMarkup(matches);return;
    }
    if(t.dataset.preset)return;
    if(t.dataset.block==='settings'){settings[t.dataset.field]=t.value;updateValidation(t);saveSettings();return}
    const obj=fieldTarget(t);if(obj){obj[t.dataset.field]=t.value;if(t.dataset.block==='meta'&&t.dataset.field==='reportId')state.meta.reportAuto='no';if(t.dataset.block==='meta'&&['project','client','reportId'].includes(t.dataset.field)){byId('audit-context-title').textContent=state.meta.project||state.meta.client||'Auditoría sin título';byId('audit-context-ref').textContent=(state.meta.reportId||'SIN REFERENCIA')+' · '+(state.meta.client||'Cliente pendiente');byId('active-audit-label').textContent=(state.meta.reportId||'Sin referencia')+' · '+(state.meta.project||state.meta.client||'Sin título')}if(['title','name','id'].includes(t.dataset.field)){const heading=t.closest('.entry')?.querySelector('.entry-head strong');if(heading)heading.textContent=obj.title||obj.name||obj.id||'Registro'}persist();updateValidation(t)}
  });
  workspace.addEventListener('change',async e=>{
    const t=e.target;
    if(t.id==='intake-file'&&t.files?.length){
      try{
        const file=t.files[0];
        if(file.size>intake.LIMIT_BYTES)throw Error('Archivo superior a 2 MiB.');
        const block=byId('intake-block')?.value||intakeBlock;intakeBlock=block;
        const result=intake.parse(await file.text(),{block,filename:file.name,size:file.size});
        intakePreview=result;
        intakeSelected=new Set(intake.reconcile(result,state[block]).filter(x=>x.status==='nuevo').map(x=>x.index));
        intakeError='';
      }catch(error){intakePreview=null;intakeSelected.clear();intakeError='No se pudo importar: '+error.message;}
      render();return;
    }
    if(t.id==='intake-block'){intakeBlock=t.value;intakePreview=null;intakeSelected.clear();intakeError='Selecciona un nuevo archivo para la sección elegida.';render();return;}
    if(t.dataset.intakeRow!==undefined){const n=Number(t.dataset.intakeRow);if(t.checked)intakeSelected.add(n);else intakeSelected.delete(n);render();return;}
    if(t.dataset.findingControl!==undefined){
      const finding=state.findings.find(f=>f._key===t.dataset.findingControl);
      if(!finding)return;
      const control=state.controls.find(c=>c._key===t.value);
      finding.originControlKey=control?control._key:'';
      if(control){for(const evidence of state.evidence){const links=relations.normalizeLinks(evidence.links);if(links.controls.includes(control._key)&&!links.findings.includes(finding._key)){links.findings.push(finding._key);evidence.links=links;}}}
      persist();render();return;
    }
    if(t.id==='template-pack'){selectedTemplatePack=t.value;templateMessage='';render();return}
    if(t.dataset.auditorSelect!==undefined){
      const id=t.dataset.auditorSelect;
      if(t.checked){const member=settings.members.find(x=>x.id===id);if(!member||!member.name.trim()){alert('Define primero un nombre para este auditor.');t.checked=false;return;}
        const issue=memberIdentityIssue(member);if(issue){alert('Completa la identificación de '+member.name+' en Configuración: '+issue);t.checked=false;return;}
        if(!state.meta.auditTeam.some(x=>x.id===id))state.meta.auditTeam.push({...member});
      }else state.meta.auditTeam=state.meta.auditTeam.filter(x=>x.id!==id);
      state.meta.auditor=auditorNames({...state.meta,auditor:''});persist();return;
    }
    if(t.id==='backup-auto'){
      if(!backupPrefs.folderName){t.checked=false;alert('Primero selecciona una carpeta para las copias periódicas.');return}
      backupPrefs.automatic=t.checked;backupPrefs.lastError='';storeBackupPrefs();
      if(t.checked)void backupToFolder({interactive:true});
      return;
    }
    if(t.name==='channel'){connectionChannel=t.value;for(const key of ['nextcloud','upload','email','share'])byId('connection-'+key).hidden=(key==='upload'||key==='nextcloud'?connectionChannel!=='nextcloud':connectionChannel!==key);return}
    if(t.id==='settings-import-file'&&t.files?.length){
      try{const raw=JSON.parse(await t.files[0].text());if(!['audit-workbench-consultancy-v1','audit-workbench-consultancy-v2'].includes(raw?.kind))throw Error('No es un perfil de consultora.');settings=loadSettingsFromImport(raw.settings);saveSettings();render()}
      catch(error){alert('Perfil no importado: '+error.message)}return;
    }
    if(t.id==='settings-logo-upload'&&t.files?.length){
      try{settings.logo=await resizeImage(t.files[0],640,.84,850000,3);saveSettings();render()}catch(error){alert('No se pudo cargar el logo: '+error.message)}return;
    }
    if(t.id==='logo-upload'&&t.files?.length){
      const auditId=currentId;
      try{
        const image=await resizeImage(t.files[0],640,0.84,850000,3);
        if(auditId!==currentId)throw Error('Ha cambiado el expediente; selecciona el logo de nuevo.');
        state.meta.logo=image;persist();render();
      }catch(error){alert('No se pudo incorporar el logo: '+error.message);t.value=''}
      return;
    }
    if(t.dataset.imageIndex!==undefined&&t.files?.length){
      const id=currentId,recordKey=state.evidence[Number(t.dataset.imageIndex)]?._key;
      try{const file=t.files[0];if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>5*1024*1024)throw Error('Selecciona una imagen PNG, JPEG o WebP de hasta 5 MiB.');const digest=globalThis.crypto?.subtle ? Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await file.arrayBuffer())),b=>b.toString(16).padStart(2,'0')).join('') : '';const image=await resizeImage(file);if(id!==currentId)throw Error('Ha cambiado el expediente.');const record=state.evidence.find(x=>x._key===recordKey);if(!record)throw Error('No se encontró la evidencia.');record.image=image;record.fileName=file.name.slice(0,180);record.fileBytes=file.size;record.fileSha256=digest;record.sha256=digest;persist();render()}
      catch(err){alert('No se pudo incorporar la imagen: '+err.message);t.value=''}return;
    }
    if(t.dataset.addEvidenceLink!==undefined){
      const evidence=state.evidence.find(row=>row._key===t.dataset.addEvidenceLink);
      const kind=t.dataset.relationKind;
      const target=state[kind]?.find(row=>row._key===t.value);
      if(evidence&&relations.CATEGORIES.includes(kind)&&target){
        evidence.links=relations.normalizeLinks(evidence.links);
        if(!evidence.links[kind].includes(target._key))evidence.links[kind].push(target._key);
        persist();render();
      }
      return;
    }
    if(t.dataset.block==='settings'){
      settings[t.dataset.field]=t.value;
      if(t.dataset.field==='taxType'){const id=byId('f-settings-main-taxId');if(id)updateValidation(id)}
      if(t.dataset.field==='prefix'){settings.prefix=settings.prefix.trim().toUpperCase();if(!/^[A-Z0-9-]{2,12}$/.test(settings.prefix)){alert('Prefijo válido: de 2 a 12 caracteres A-Z, 0-9 o guion.');return}}
      saveSettings();updateValidation(t);return;
    }
    const obj=fieldTarget(t);if(!obj)return;
    if(t.dataset.block==='meta'&&t.dataset.field==='client'&&state.meta.reportAuto!=='no'){
      const newClient=clientKey(t.value);
      if(newClient!==clientKey(t.dataset.originalClient||'')){
        state.meta.reportId=nextReportId(t.value);persist();
        const idInput=byId('f-meta-main-reportId');if(idInput)idInput.value=state.meta.reportId;
      }
    }
    if(t.dataset.block==='meta'&&t.dataset.field==='reportId'&&t.value!==state.meta.reportId){state.meta.reportAuto='no'}

    if(t.dataset.block==='meta'&&t.dataset.field==='client'){
      const context=byId('main-audit-context');context.textContent=(state.meta.reportId||'Sin referencia')+' · '+(t.value||'Cliente pendiente')+' · '+(state.meta.project||'Sin título');
    }
    if(t.dataset.preset){
      const custom=t.closest('.field').querySelector('[data-custom]');
      const isOther=t.value==='__custom__';custom.hidden=!isOther;
      obj[t.dataset.field]=isOther?custom.value:t.value;
      if(t.dataset.block==='assets'&&t.dataset.field==='vendor'){
        obj.model='';
        const sibling=workspace.querySelector(`#f-assets-${t.dataset.index}-model`)?.closest('.field');
        if(sibling)sibling.outerHTML=renderField(obj,'assets',groups.assets.fields.find(f=>f[0]==='model'),Number(t.dataset.index));
      }
      if(isOther)custom.focus();persist();return;
    }
    obj[t.dataset.field]=t.value;
    if(t.dataset.block==='meta'&&['clientIdType','contactIdType'].includes(t.dataset.field)){const name=t.dataset.field==='clientIdType'?'clientTaxId':'contactId';const target=byId('f-meta-main-'+name);if(target)updateValidation(target)}
    if(t.dataset.block==='assets'&&t.dataset.field==='vendor'){
      obj.model='';
      const sibling=workspace.querySelector(`#f-assets-${t.dataset.index}-model`)?.closest('.field');
      if(sibling)sibling.outerHTML=renderField(obj,'assets',groups.assets.fields.find(f=>f[0]==='model'),Number(t.dataset.index));
    }
    if(t.dataset.block==='controls'&&t.dataset.field==='status'){obj.status=t.value;persist();render();return}
    if(t.dataset.block==='findings'&&t.dataset.field==='severity'){
      const badge=t.closest('.entry')?.querySelector('.entry-head .pill');
      if(badge)badge.outerHTML=pill(obj.severity);
    }
    persist();updateValidation(t);
  });
  workspace.addEventListener('click',async e=>{
    const b=e.target.closest('button');if(!b)return;
    if(b.dataset.intakeSelect){
      if(!intakePreview)return;
      const choices=intake.reconcile(intakePreview,state[intakePreview.block]);
      intakeSelected=new Set(b.dataset.intakeSelect==='new'?choices.filter(x=>x.status==='nuevo').map(x=>x.index):[]);
      render();return;
    }
    if(b.dataset.intakeReset!==undefined){intakePreview=null;intakeSelected.clear();intakeError='';render();return;}
    if(b.dataset.intakeApply!==undefined){
      if(!currentId||!intakePreview||!intakeSelected.size)return;
      const block=intakePreview.block;
      const items=intake.reconcile(intakePreview,state[block]).filter(x=>x.status==='nuevo'&&intakeSelected.has(x.index));
      if(!items.length||state[block].length+items.length>LIMIT_ROWS){alert('No hay registros válidos o se supera el límite de inventario.');return;}
      if(!confirm('Incorporar '+items.length+' registros NUEVOS a '+groups[block].title+'? No se actualizarán registros existentes.'))return;
      for(const {record} of items){
        const row={_key:uid()};for(const [field] of groups[block].fields)row[field]=record[field]||'';
        if(block==='assets'){row.criticality='Sin valorar';row.state='Por revisar';}
        if(block==='software'){row.license='Pendiente de revisar';row.support='Pendiente de verificar';row.exposure=row.exposure||'Pendiente de revisar';}
        row.notes=[row.notes,'Captura importada ('+intakePreview.source+(intakePreview.platform?' · '+intakePreview.platform:'')+(intakePreview.capturedAt?' · '+intakePreview.capturedAt:'')+'); pendiente de verificación por el auditor.'].filter(Boolean).join(' · ').slice(0,20000);
        state[block].push(row);
      }
      intakePreview=null;intakeSelected.clear();intakeError='';
      persist();move(block);return;
    }
    if(b.dataset.glossaryCopy!==undefined){
      const term=glossary?.byId(b.dataset.glossaryId);
      const command=glossary?.GUIDES?.[term?.id]?.commands?.[Number(b.dataset.glossaryCopy)]?.command;
      if(!command)return;
      try{
        if(!navigator.clipboard?.writeText)throw Error('Clipboard API no disponible');
        await navigator.clipboard.writeText(command);
        b.textContent='Copiado';
      }catch(_error){
        const previous=document.getElementById('glossary-copy-fallback');
        previous?.remove();
        const textarea=document.createElement('textarea');
        textarea.id='glossary-copy-fallback';
        textarea.value=command;textarea.setAttribute('readonly','');textarea.style.position='fixed';textarea.style.left='-9999px';
        document.body.appendChild(textarea);textarea.select();
        const copied=typeof document.execCommand==='function'&&document.execCommand('copy');
        textarea.remove();
        b.textContent=copied?'Copiado':'Selecciona el comando para copiarlo';
      }
      return;
    }
    if(b.dataset.glossaryBack!==undefined){
      backToAudit();
      return;
    }
    if(b.dataset.glossaryTerm){openGlossary(b.dataset.glossaryTerm,{page,field:b.dataset.glossaryField||'',scrollY:window.scrollY});return;}
    if(b.dataset.glossarySelect){glossarySelected=b.dataset.glossarySelect;filterGlossary(glossaryQuery);return;}
    if(b.dataset.glossaryCategory){glossaryCategory=b.dataset.glossaryCategory;glossarySelected='';render();return;}
    if(b.id==='comparison-capture'){
      if(state.followupBaseline)return;
      if(!state.findings.length){alert('Registra primero los hallazgos de la auditoría.');return;}
      const alreadyReviewed=state.findings.some(f=>retest.normalize(f.retests).length);
      if(!confirm(alreadyReviewed?'Esta referencia describe el estado ACTUAL, no el informe inicial. ¿Fijarla para comparar revisiones posteriores?':'Se fijará una fotografía de los hallazgos actuales para futuras comparativas. No será editable. ¿Continuar?'))return;
      try{state.followupBaseline=comparison.capture(state,'manual-current');persist();render();}catch(error){alert(error.message)}
      return;
    }
    if(b.dataset.saveRetest!==undefined){
      const finding=state.findings.find(f=>f._key===b.dataset.saveRetest);
      const card=b.closest('[data-retest-key]');
      if(!finding||!card)return;
      const read=name=>card.querySelector(`[data-retest-field="${name}"]`)?.value||'';
      try{
        const data={result:read('result'),date:read('date'),by:read('by'),notes:read('notes'),evidenceKey:read('evidenceKey')};
        if(data.result==='verified'&&!data.evidenceKey&&!confirm('No has vinculado evidencia de la corrección. ¿Guardar igualmente la comprobación documentada?'))return;
        const entry=retest.record(finding,data,state.evidence,uid);
        // Congelar una línea de referencia antes de la PRIMERA reevaluación,
        // nunca reconstruir el pasado a partir de estados actuales.
        if(!state.followupBaseline&&!state.findings.some(f=>retest.normalize(f.retests).length)){
          state.followupBaseline=comparison.capture(state,'before-first-retest');
        }
        retest.apply(finding,entry);persist();render();
      }catch(error){alert('No se pudo registrar la reevaluación: '+error.message)}
      return;
    }
    if(b.id==='retest-pdf'){printRetestReport();return;}
    if(b.dataset.qualitySection){
      const section=b.dataset.qualitySection, key=b.dataset.qualityKey;
      move(section);
      if(key){const row=[...workspace.querySelectorAll('[data-entry-key]')].find(el=>el.dataset.entryKey===key);if(row){row.classList.add('quality-target');row.scrollIntoView({block:'center',behavior:'smooth'});row.focus({preventScroll:true})}}
      return;
    }
    if(b.dataset.go){if(b.dataset.go==='intake'&&['assets','networks','software'].includes(page)){intakeReturn=page;intakeBlock=page;intakePreview=null;intakeSelected.clear();intakeError='';}move(b.dataset.go);return}
    if(b.id==='install-pwa'){alert('Instala desde el menú del navegador: Instalar aplicación / Añadir a pantalla de inicio. Requiere HTTPS o localhost y compatibilidad PWA.');return;}
    if(b.id==='check-connectivity'){await checkNetworkServer();return}
    if(b.id==='member-add'){
      if(settings.members.length>=TEAM_MAX){alert('Máximo de 60 profesionales por perfil.');return;}
      const member={id:uid(),name:'',role:'',idType:'DNI',documentId:'',email:'',phone:''};settings.members.push(member);saveSettings();render();
      const last=byId('member-name-'+(settings.members.length-1));last?.focus();return;
    }
    if(b.dataset.memberRemove){
      const member=settings.members.find(m=>m.id===b.dataset.memberRemove);if(!member)return;
      if(!confirm('¿Eliminar del directorio a '+(member.name||'este profesional')+'? Las auditorías en las que participó conservarán su ficha.'))return;
      settings.members=settings.members.filter(m=>m.id!==b.dataset.memberRemove);saveSettings();render();return;
    }
    if(b.id==='settings-export'){download('perfil-consultora.json',JSON.stringify({kind:'audit-workbench-consultancy-v2',settings},null,2),'application/json;charset=utf-8');return}
    if(b.id==='settings-import'){byId('settings-import-file').click();return}
    if(b.id==='settings-logo-remove'){if(confirm('¿Eliminar el logo global de la consultora?')){settings.logo='';saveSettings();render()}return}
    if(b.id==='dav-save'){
      try{
        if(!crypto?.subtle||!globalThis.isSecureContext)throw Error('El cifrado requiere HTTPS o localhost.');
        const pass=byId('dav-passphrase').value;
        if(pass.length<12)throw Error('Usa al menos 12 caracteres de frase de paso local.');
        const profile=validateWebdavProfile(byId('dav-url').value,byId('dav-user').value,byId('dav-secret').value);
        const envelope=await encryptProfile(profile,pass);
        localStorage.setItem(CONNECTION_KEY,JSON.stringify(envelope));unlockedConnection=profile;
        render();alert('Conexión guardada cifrada. Necesitarás la frase de paso para desbloquearla de nuevo.');
      }catch(error){alert('No se pudo guardar la conexión: '+error.message)}return;
    }
    if(b.id==='dav-unlock'){
      try{
        const envelope=JSON.parse(localStorage.getItem(CONNECTION_KEY)||'null');
        const pass=byId('dav-passphrase').value;
        unlockedConnection=await decryptProfile(envelope,pass);
        validateWebdavProfile(unlockedConnection.url,unlockedConnection.user,unlockedConnection.secret);
        render();alert('Conexión desbloqueada para esta sesión.');
      }catch(error){unlockedConnection=null;alert('No se pudo desbloquear: contraseña incorrecta o perfil dañado.')}return;
    }
    if(b.id==='dav-forget'){if(confirm('¿Eliminar el perfil cifrado y cerrar la sesión Nextcloud?')){localStorage.removeItem(CONNECTION_KEY);unlockedConnection=null;render()}return}
    if(b.id==='dav-upload'){try{await flush();await uploadDav()}catch(error){byId('dav-upload-status').textContent='Error de subida: '+error.message}return}
    if(b.id==='backup-select-folder'){await selectBackupFolder();return}
    if(b.id==='backup-write-now'){await backupToFolder({interactive:true});return}
    if(b.id==='backup-forget'){await forgetBackupFolder();return}
    if(b.id==='backup-restore'){byId('input-import').click();return}
    if(b.id==='backup-export-xlsx'){await exportTabular('xlsx');return}
    if(b.id==='backup-export-csv'){await exportTabular('csv');return}
    if(b.dataset.unlinkEvidence!==undefined){
      const evidence=state.evidence.find(row=>row._key===b.dataset.unlinkEvidence);
      const kind=b.dataset.relationKind;
      if(evidence&&relations.CATEGORIES.includes(kind)){
        evidence.links=relations.normalizeLinks(evidence.links);
        evidence.links[kind]=evidence.links[kind].filter(key=>key!==b.dataset.relationTarget);
        persist();render();
      }
      return;
    }
    if(b.dataset.exportManifest!==undefined){
      download('manifiesto-evidencias-'+slug(state.meta.reportId)+'.json',JSON.stringify(relations.evidenceManifest(state),null,2),'application/json;charset=utf-8');return;
    }
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
    if(b.dataset.applyTemplate!==undefined){
      const choices=[...workspace.querySelectorAll('[data-template-choice]:checked')].map(input=>input.dataset.templateChoice);
      if(!choices.length){alert('Selecciona al menos una comprobación disponible.');return}
      const remaining=LIMIT_ROWS-state.controls.length;
      if(choices.length>remaining){alert(`Límite de controles: quedan ${remaining} espacios.`);return}
      try{
        const batch=templates.prepare(state.controls,b.dataset.applyTemplate,choices,uid,()=>relations.nextCode([...state.controls], 'controls'));
        // Assign unique IDs across existing controls and the entire imported batch.
        const used=new Set(state.controls.map(row=>row.id));
        for(const row of batch){while(used.has(row.id))row.id=nextAvailableControlCode(used);used.add(row.id)}
        if(!batch.length){templateMessage='Los controles seleccionados ya están incluidos.';render();return}
        state.controls.push(...batch);templateMessage=`${batch.length} comprobaciones añadidas. Están pendientes de evaluación.`;
        persist();render();
      }catch(error){alert('No se pudo aplicar la plantilla: '+error.message)}
      return;
    }
    if(b.dataset.findingFromControl!==undefined){
      const control=state.controls.find(x=>x._key===b.dataset.findingFromControl);
      if(!control||control.status!=='No conforme'){alert('Marca primero el control como «No conforme».');return}
      const prior=state.findings.find(x=>x.originControlKey===control._key);
      if(prior){move('findings');return}
      if(state.findings.length>=LIMIT_ROWS){alert('Se ha alcanzado el límite de hallazgos.');return}
      const finding={_key:uid(),id:relations.nextCode(state.findings,'findings'),originControlKey:control._key,
        title:control.name||'Incumplimiento por documentar',severity:'Sin evaluar',status:'Abierto',asset:control.asset||'',
        method:control.method||'',description:control.notes||'',references:control.reference||'',
        recommendation:control.recommendation||'',risk:'',evidenceIds:control.evidenceIds||''};
      state.findings.push(finding);
      for(const evidence of state.evidence){
        evidence.links=relations.normalizeLinks(evidence.links);
        if(evidence.links.controls.includes(control._key)&&!evidence.links.findings.includes(finding._key))evidence.links.findings.push(finding._key);
      }
      persist();move('findings');return;
    }
    if(b.dataset.add){if(state[b.dataset.add].length>=LIMIT_ROWS)return alert('Límite de registros alcanzado.');const type=b.dataset.add;let row={_key:uid()};if(['assets','controls','findings','evidence'].includes(type))row.id=relations.nextCode(state[type],type);if(type==='findings')row={...row,severity:'Media',status:'Abierto'};if(type==='cves')row={...row,id:'',severity:'Sin evaluar',status:'Sin verificar'};if(type==='controls')row.status='Pendiente';if(type==='evidence')row.links=relations.normalizeLinks(null);state[type].push(row);persist();render();return}
    if(b.dataset.remove){const k=b.dataset.remove,i=Number(b.dataset.index);if(confirm('¿Eliminar este registro y su contenido?')){state[k].splice(i,1);persist();render()}return}
    if(b.dataset.clearImage!==undefined){if(confirm('¿Eliminar la imagen incrustada?')){state.evidence[Number(b.dataset.clearImage)].image='';persist();render()}return}
    if(b.id==='delivery-pdf'){printReport('draft');return}
    if(b.id==='delivery-pdf-final'){printReport('final');return}
    if(b.id==='delivery-json'){exportJson();return}
    if(b.id==='delivery-reset'){await createAudit();return}
  });
  /** Convert a user image to a bounded JPEG data URL without uploading or executing it.
   *  FileReader data URLs avoid blob: restrictions under restrictive browser CSPs.
   */
  async function resizeImage(file,maxSize=1300,quality=.78,maxLength=1390000,maxMegabytes=5){
    if(!['image/png','image/jpeg','image/webp'].includes(file.type))throw Error('Usa PNG, JPEG o WebP. SVG no se admite como contenido de cliente por seguridad.');
    if(file.size>maxMegabytes*1024*1024)throw Error(`La imagen supera ${maxMegabytes} MiB.`);
    const source=await new Promise((resolve,reject)=>{
      const reader=new FileReader();
      reader.onload=()=>resolve(reader.result);
      reader.onerror=()=>reject(Error('No se pudo leer el archivo local.'));
      reader.readAsDataURL(file);
    });
    const image=await new Promise((resolve,reject)=>{
      const picture=new Image();
      picture.onload=()=>resolve(picture);
      picture.onerror=()=>reject(Error('El navegador no ha podido decodificar la imagen.'));
      picture.src=source;
    });
    if(!image.naturalWidth||!image.naturalHeight||image.naturalWidth*image.naturalHeight>40000000)throw Error('Dimensiones no válidas o imagen excesivamente grande.');
    let side=maxSize;
    for(let attempt=0;attempt<5;attempt++,side=Math.round(side*.75)){
      const ratio=Math.min(1,side/Math.max(image.naturalWidth,image.naturalHeight));
      const canvas=document.createElement('canvas');
      canvas.width=Math.max(1,Math.round(image.naturalWidth*ratio));
      canvas.height=Math.max(1,Math.round(image.naturalHeight*ratio));
      const context=canvas.getContext('2d');
      if(!context)throw Error('El dispositivo no admite conversión de imágenes.');
      context.fillStyle='#fff';context.fillRect(0,0,canvas.width,canvas.height);
      context.drawImage(image,0,0,canvas.width,canvas.height);
      const encoded=canvas.toDataURL('image/jpeg',quality);
      if(encoded.length<=maxLength)return encoded;
    }
    throw Error('No se pudo reducir el tamaño; prueba con otra imagen.');
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
    if(!currentId){alert('Primero crea o selecciona una auditoría.');return;}
    const filename='auditoria-'+slug(state.meta.client)+'.json';
    const body=JSON.stringify(state,null,2);
    if(!navigator.share||!navigator.canShare){
      if(confirm('Compartir archivos no está disponible en este navegador. ¿Descargar el expediente JSON para enviarlo mediante un canal autorizado?'))download(filename,body,'application/json;charset=utf-8');
      return;
    }
    if(!confirm('Compartirás el expediente completo, con posibles datos personales. Comprueba autorización y destinatario. ¿Continuar?'))return;
    const file=new File([body],filename,{type:'application/json'});
    if(!navigator.canShare({files:[file]})){
      if(confirm('El sistema no admite compartir este archivo directamente. ¿Descargarlo en su lugar?'))download(filename,body,'application/json;charset=utf-8');
      return;
    }
    try{await navigator.share({files:[file],title:'Expediente de auditoría'});}
    catch(error){
      if(error.name==='AbortError')return;
      const detail=['NotAllowedError','SecurityError'].includes(error.name)?'El navegador o sistema ha denegado el permiso de compartir. Esta función requiere activación del usuario y una aplicación de destino compatible.':error.message;
      if(confirm(detail+' ¿Descargar el JSON para compartirlo manualmente?'))download(filename,body,'application/json;charset=utf-8');
    }
  }
  function draftEmail(){
    if(!currentId){alert('Primero crea o selecciona una auditoría.');return;}
    if(!confirm('Se abrirá tu cliente de correo con un asunto y mensaje de entrega, SIN adjuntos. Exporta el PDF y adjúntalo manualmente tras comprobar destinatario, confidencialidad y autorización. ¿Continuar?'))return;
    const subject='Entrega de auditoría '+(state.meta.reportId||state.meta.project||'');
    const body='Se adjunta el informe de auditoría revisado correspondiente a '+(state.meta.client||'la organización')+'.\n\nPor favor confirma su recepción por un canal autorizado.\n\n[Adjuntar manualmente el PDF final]';
    location.href='mailto:?subject='+encodeURIComponent(subject.slice(0,180))+'&body='+encodeURIComponent(body.slice(0,700));
  }
  async function backupAll(){
    try{
      await flush();
      download('audit-workbench-backup-'+new Date().toISOString().slice(0,10)+'.json',JSON.stringify(backupPayload(),null,2),'application/json;charset=utf-8');
      backupPrefs.lastExportAt=new Date().toISOString();backupPrefs.lastExportCount=records.length;
      storeBackupPrefs();if(page==='backups')render();
    }catch(error){alert('No se pudo exportar el backup: '+error.message)}
  }
  let exportFeedbackTimer=null;
  function showExportFeedback(message,isError=false){
    let notice=byId('export-feedback-toast');
    if(!notice){
      notice=document.createElement('div');
      notice.id='export-feedback-toast';
      notice.className='export-feedback-toast';
      notice.setAttribute('role','status');
      notice.setAttribute('aria-live','polite');
      document.body.appendChild(notice);
    }
    notice.textContent=message;
    notice.classList.toggle('error',isError);
    notice.hidden=false;
    const inline=byId('delivery-export-status');
    if(inline)inline.textContent=message;
    clearTimeout(exportFeedbackTimer);
    exportFeedbackTimer=setTimeout(()=>{notice.hidden=true},9000);
  }
  function exportJson(audit=state){
    try{
      if(!audit||typeof audit!=='object'||!audit.meta||typeof audit.meta!=='object')
        throw Error('No se ha identificado un expediente válido. Selecciona una auditoría antes de exportar.');
      const filename='auditoria-'+slug(audit.meta.client)+'-'+new Date().toISOString().slice(0,10)+'.json';
      const payload=JSON.stringify(audit,null,2);
      if(!payload)throw Error('No ha sido posible serializar el expediente.');
      download(filename,payload,'application/json;charset=utf-8');
      const message='Descarga solicitada: '+filename+'. Verifica el archivo en las descargas del navegador.';
      showExportFeedback(message);
      return filename;
    }catch(error){
      showExportFeedback('No se pudo preparar el JSON: '+error.message,true);
      console.error('Error al exportar JSON',error);
      return null;
    }
  }
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
  byId('btn-export').addEventListener('click',()=>exportJson());
  byId('btn-pdf').addEventListener('click',printReport);
  const table = (fields,row) => `<table class="report-table"><tbody>${fields.map(([name,label])=>`<tr><th class="report-field-label">${html(label)}</th><td>${para(row[name])}</td></tr>`).join('')}</tbody></table>`;
  const section = (num,title,content) => `<section class="report-section"><h2>${num}. ${html(title)}</h2>${content}</section>`;
  function reportRows(k){const rows=state[k];return rows.length?rows.map((row,i)=>`<h3>${i+1}. ${html(row.title||row.name||row.id||'Registro')}</h3>${table(groups[k].fields,row)}${k==='evidence'?`<p class="report-note"><strong>Integridad y vínculos:</strong> ${html(row.fileSha256?'SHA-256 original: '+row.fileSha256:'Archivo original sin huella calculada')} ${html(row.fileName?' · Archivo: '+row.fileName:'')} · ${html(relations.CATEGORIES.map(kind=>{const names=relations.normalizeLinks(row.links)[kind].map(key=>state[kind].find(x=>x._key===key)).filter(Boolean).map(x=>relations.itemLabel(x,kind));return names.length?relationLabels[kind]+': '+names.join(', '):''}).filter(Boolean).join(' · ')||'Sin relaciones explícitas')}</p>`:''}${k==='evidence'&&row.image?`<figure><img class="report-evidence" alt="Evidencia ${html(row.id)}" src="${row.image}"><figcaption class="report-note">${html(row.id||'Evidencia')}: ${html(row.title||'Captura adjunta')}</figcaption></figure>`:''}`).join(''):'<p class="report-empty">Sin registros incluidos en esta categoría.</p>'}
  let printMode='audit',reportDeliveryMode='draft';
  function buildReport(){
    byId('report').dataset.palette=selectedPalette;
    const today=new Date().toLocaleDateString('es-ES');
    const count=Object.fromEntries(severity.map(s=>[s,state.findings.filter(x=>x.severity===s).length]));
    const meta=state.meta,ending=state.final;
    const cover=`<div class="report-cover"><div class="sup">SYSADMIN / SECURITY · AUDIT REPORT <span class="report-theme-name">${html(selectedPalette)}</span></div>${meta.logo?`<img class="report-logo" src="${meta.logo}" alt="Logo corporativo">`:''}<h1>Informe de auditoría<br>informática</h1><h2>${html(meta.project||'Infraestructura, sistemas y ciberseguridad')}</h2><p class="classify">${html(meta.classification||'Confidencial')}</p><div class="cover-meta"><div><span class="report-number">CLIENTE</span><h3>${html(meta.client||'No indicado')}</h3><p>${html(meta.contact||'')}</p></div><div><span class="report-number">ENTREGA</span><h3>${html(today)}</h3><p>Ref. ${html(meta.reportId||'Sin referencia')} · Rev. ${html(meta.revision||'1.0')}</p><p>${html(auditorNames(meta)||'Equipo auditor pendiente de asignar')}</p><p>${html(settings.company||'')}</p><p>${html(settings.taxId||'')}</p></div></div></div>`;
    const legal=section(1,'Confidencialidad, alcance legal y custodia',`<p class="report-note">Cláusulas modelo que deben adaptarse al contrato específico y validarse antes de la entrega. RGPD (UE) 2016/679 y LOPDGDD 3/2018, según resulte aplicable.</p>${legalFields.map(([key,label])=>`<h3>${html(label)}</h3><p>${para(state.legal[key])}</p>`).join('')}`);
    const teamTable=meta.auditTeam?.length?`<table class="report-table"><thead><tr><th>Profesional</th><th>Documento</th><th>Función</th><th>Contacto</th></tr></thead><tbody>${meta.auditTeam.map(m=>`<tr><td>${html(m.name)}</td><td>${html(m.documentId?(m.idType||'DNI')+' · '+m.documentId:'No documentado')}</td><td>${html(m.role||'No indicada')}</td><td>${html(m.email||'No indicado')}</td></tr>`).join('')}</tbody></table>`:`<p>${html(auditorNames(meta)||'No se han asignado profesionales.')}</p>`;
    const identity=section(2,'Identificación, alcance y metodología',table(metaFields,meta)+`<h3>Equipo responsable de la auditoría</h3>${teamTable}`);
    const summaryCounts={assets:state.assets.length,controls:state.controls.length,verified:state.controls.filter(c=>!['Pendiente','No verificado',''].includes(str(c.status).trim())).length,findings:state.findings.length};
    const executive=section(3,'Resumen ejecutivo',`<p>${para(ending.executive)}</p><div class="report-summary-metrics"><div><strong>${summaryCounts.assets}</strong><span>Activos inventariados</span></div><div><strong>${summaryCounts.verified}/${summaryCounts.controls}</strong><span>Controles con resultado</span></div><div><strong>${summaryCounts.findings}</strong><span>Hallazgos registrados</span></div></div><h3>Valoración del riesgo</h3><p>${para(ending.assessment)}</p><div class="report-stat-grid">${severity.map(s=>`<div><strong>${count[s]}</strong><small>${s}</small></div>`).join('')}</div><h3>Puntos fuertes</h3><p>${para(ending.strengths)}</p><h3>Debilidades principales</h3><p>${para(ending.weaknesses)}</p>`);
    const controls=section(8,'Controles y verificaciones',reportRows('controls'));
    const findings=section(9,'Resumen de hallazgos y ficha técnica',`${state.findings.length?`<table class="report-table"><thead><tr><th>ID</th><th>Hallazgo</th><th>Severidad</th><th>Remediación</th></tr></thead><tbody>${state.findings.map(f=>`<tr><td>${html(f.id)}</td><td>${html(f.title)}</td><td>${html(f.severity)}</td><td>${para(f.recommendation)}</td></tr>`).join('')}</tbody></table>`:'<p class="report-empty">No hay hallazgos registrados.</p>'}${state.findings.map(f=>`<div class="report-finding"><h3>${html(f.id||'Hallazgo')} — ${html(f.title||'Sin título')} <span class="report-badge ${level(f.severity)}">${html(f.severity)}</span></h3>${table(groups.findings.fields,f)}${f.originControlKey?`<p class="report-note"><strong>Control de origen:</strong> ${html(relations.itemLabel(state.controls.find(c=>c._key===f.originControlKey),'controls'))}</p>`:''}${state.evidence.filter(e=>e.image&&((f.evidenceIds||'').split(/[,;\s]+/).includes(e.id)||relations.normalizeLinks(e.links).findings.includes(f._key))).map(e=>`<figure><img class="report-evidence" src="${e.image}" alt="Evidencia ${html(e.id)}"><figcaption class="report-note">${html(e.id)} — ${html(e.title)}</figcaption></figure>`).join('')}</div>`).join('')}`);
    const reviewed=reviewState('final'); // El borrador debe mostrar también los impedimentos para una entrega definitiva.
    const actionPlan=section(11,'Plan de remediación y comprobación',reviewed.plan.length?reviewed.plan.map(item=>`<div class="report-action"><h3>${html(item.id)} · ${html(item.title)} <span class="report-badge ${level(item.severity)}">${html(item.severity)}</span></h3><p><strong>Estado:</strong> ${html(item.status)} · <strong>Responsable:</strong> ${html(item.owner||'Pendiente de asignar')} · <strong>Fecha objetivo:</strong> ${html(item.deadline||'Por acordar')}</p><p><strong>Acción correctiva:</strong> ${para(item.recommendation||'Sin definir')}</p><p><strong>Criterio de verificación:</strong> ${para(item.verification||'Sin definir')}</p></div>`).join(''):'<p class="report-empty">No se registraron hallazgos que requieran remediación. Esta observación no implica ausencia de riesgos fuera del alcance revisado.</p>');
    const draftMarker=reportDeliveryMode==='final'&&reviewed.ready?'':`<aside class="report-draft"><strong>BORRADOR · NO VALIDADO PARA ENTREGA</strong><p>${reviewed.blockers.length} impedimentos para entregar y ${reviewed.warnings.length} advertencias. Documento de trabajo, no constituye informe definitivo.</p></aside>`;
    const closing=section(12,'Conclusiones y plan de acción',table(finalFields.filter(f=>f[0]!=='executive'&&f[0]!=='strengths'&&f[0]!=='weaknesses'&&f[0]!=='assessment'),ending)+`<div class="report-signature">Generado localmente con Audit Workbench. Validación y autorización de entrega: ${html(ending.signoff||'Pendiente de firma')}.</div>`);
    const toc=section(0,'Contenido del informe',`<nav class="report-toc" aria-label="Índice del informe">${[
      [3,'Resumen ejecutivo'],[2,'Identificación, alcance y metodología'],[9,'Hallazgos y ficha técnica'],
      [11,'Plan de remediación'],[4,'Inventario de hardware'],[5,'Infraestructura de redes'],
      [6,'Software y servicios'],[7,'Vulnerabilidades CVE'],[8,'Controles y verificaciones'],
      [10,'Registro de evidencias'],[12,'Conclusiones y plan de acción'],[1,'Confidencialidad y custodia']
    ].map(([number,title])=>`<a href="#report-section-${number}">${html(title)} <span aria-hidden="true">↗</span></a>`).join('')}</nav>`);
    const chapters=[
      [3,executive],[2,identity],[9,findings],[11,actionPlan],[4,section(4,'Inventario de hardware',reportRows('assets'))],
      [5,section(5,'Infraestructura de redes',reportRows('networks'))],[6,section(6,'Software y servicios',reportRows('software'))],
      [7,section(7,'Vulnerabilidades CVE registradas',reportRows('cves'))],[8,controls],
      [10,section(10,'Registro de evidencias',reportRows('evidence'))],[12,closing],[1,legal]
    ];
    byId('report').innerHTML=cover.replace('<div class="report-cover">','<div class="report-cover">'+draftMarker)+toc+
      chapters.map(([num,part],index)=>part.replace('class="report-section"','class="report-section" id="report-section-'+num+'"').replace(/(<h2>)\d+\. /,(_,tag)=>tag+(index+1)+'. ')).join('');
  }
  function buildRetestReport(){
    byId('report').dataset.palette=selectedPalette;
    const meta=state.meta,counts=retest.summary(state),comparisonState=comparison.compare(state,retest),today=new Date().toLocaleDateString('es-ES');
    const title='Informe de reevaluación de seguridad';
    const cover=`<div class="report-cover"><div class="sup">SYSADMIN / SECURITY · SEGUIMIENTO DE CORRECCIONES</div>${meta.logo?`<img class="report-logo" src="${meta.logo}" alt="Logo corporativo">`:''}<h1>Informe de<br>reevaluación</h1><h2>${html(meta.project||'Auditoría técnica')}</h2><p class="classify">${html(meta.classification||'Confidencial')}</p><div class="cover-meta"><div><span class="report-number">CLIENTE</span><h3>${html(meta.client||'No indicado')}</h3><p>Referencia: ${html(meta.reportId||'No indicada')}</p></div><div><span class="report-number">FECHA DE EMISIÓN</span><h3>${html(today)}</h3><p>Documento de seguimiento · Rev. ${html(meta.revision||'1.0')}</p></div></div></div>`;
    const summary=section(1,'Alcance de la reevaluación',`<p>Este documento recoge exclusivamente los resultados de verificaciones posteriores registrados en el expediente ${html(meta.reportId||'')}. No equivale a una nueva auditoría integral ni garantiza ausencia de riesgos.</p><p><strong>Auditoría de referencia:</strong> ${html(meta.project||'No documentada')} · <strong>Cliente:</strong> ${html(meta.client||'No documentado')}</p><p><strong>Total de hallazgos:</strong> ${counts.total} · <strong>Correcciones verificadas:</strong> ${counts.verified} · <strong>Persistentes:</strong> ${counts.pending} · <strong>Reabiertos:</strong> ${counts.reopened} · <strong>No comprobables:</strong> ${counts.unverified} · <strong>Sin reevaluar:</strong> ${counts['not-reviewed']} · <strong>Estados por aclarar:</strong> ${counts.inconsistent} · <strong>Riesgos aceptados:</strong> ${counts.accepted}.</p>`);
    const entries=state.findings.map((finding,i)=>{
      const history=retest.normalize(finding.retests),last=retest.latest(finding);
      const status=retest.outcome(finding),label=status==='accepted'?'Riesgo aceptado':status==='not-reviewed'?'Sin reevaluar':status==='inconsistent'?'Estado por aclarar':retest.RESULTS[status];
      const e=last?retest.evidenceFor(last,state):null;
      return `<div class="retest-print-item"><h3>${html(finding.id||'Hallazgo '+(i+1))} · ${html(finding.title||'Sin título')}</h3><p><strong>Última clasificación:</strong> ${html(label)} · <strong>Severidad:</strong> ${html(finding.severity||'Sin evaluar')} · <strong>Estado administrativo:</strong> ${html(finding.status||'No indicado')}</p><p><strong>Remediación propuesta:</strong> ${para(finding.recommendation)}</p><p><strong>Criterio de verificación:</strong> ${para(finding.verification)}</p>${last?`<p><strong>Última comprobación:</strong> ${html(last.date)} · ${html(last.by)}</p><p>${para(last.notes)}</p>${e||last.evidenceId?`<p class="retest-meta"><strong>Evidencia referenciada:</strong> ${html(last.evidenceId||e?.id||'Sin código')} · ${html(e?.title||'Conservar original y expediente de referencia')}${last.evidenceSha256?' · SHA-256: '+html(last.evidenceSha256):''}${!e?' · Original no disponible en este expediente':''}</p>`:''}`:'<p>Este hallazgo todavía no cuenta con una reevaluación documentada.</p>'}${history.length>1?`<p class="retest-meta">Historial: ${history.map(h=>html(h.date)+' ('+html(retest.RESULTS[h.result])+')').join(' → ')}</p>`:''}</div>`;
    }).join('');
    const cmp=comparisonState,c=cmp.counts;
    const metricRows=[
      ['Hallazgos en referencia',cmp.hasBaseline?cmp.initialTotal:'Sin referencia histórica'],
      ['Correcciones verificadas (referencia)',cmp.hasBaseline?c.verified+' de '+cmp.initialTotal+' ('+cmp.verifiedPercent+' %)':'No calculable'],
      ['Alta/crítica sin cierre verificado (referencia)',cmp.hasBaseline?cmp.priorityNotVerified+' de '+cmp.priorityInitial:'No calculable'],
      ['Riesgos aceptados (no corregidos)',c.accepted+(cmp.addedCounts.accepted||0)],
      ['Hallazgos nuevos respecto a referencia',cmp.hasBaseline?cmp.added:'No calculable'],
      ['Referencias eliminadas del expediente',cmp.hasBaseline?c.missing:'No calculable']
    ];
    const keyRows=cmp.decisions.slice(0,10).map(row=>`<tr><td>${html(row.id||'Sin código')} · ${html(row.title||'Sin título')}</td><td>${html(row.severity)}</td><td>${html(row.owner||'Sin asignar')}</td><td>${html(row.deadline||'Por acordar')}</td></tr>`).join('');
    const comparisonSection=section(2,'Evolución y decisiones para dirección',`<p>${html(cmp.limitations)}</p><div class="comparison-summary">${metricRows.slice(0,4).map(([label,value],index)=>`<div class="comparison-metric"><strong>${html(index===1&&cmp.hasBaseline?cmp.verifiedPercent+' %':value)}</strong><span>${html(label)}</span></div>`).join('')}</div><table class="report-table"><thead><tr><th>Indicador</th><th>Resultado</th></tr></thead><tbody>${metricRows.map(([label,value])=>`<tr><td>${html(label)}</td><td>${html(value)}</td></tr>`).join('')}</tbody></table><h3>Prioridades técnicas pendientes</h3>${keyRows?`<table class="report-table"><thead><tr><th>Hallazgo</th><th>Severidad</th><th>Responsable</th><th>Fecha objetivo</th></tr></thead><tbody>${keyRows}</tbody></table>`:'<p>Sin hallazgos de severidad alta o crítica pendientes en el inventario actual.</p>'}<p class="report-note">Una aceptación de riesgo no es una corrección. Los hallazgos no comprobables, sin reevaluar o con estados contradictorios permanecen sin verificación de cierre. Los indicadores son recuentos documentales, no mediciones de pérdidas económicas evitadas.</p>`);
    const details=section(3,'Resultado por hallazgo',entries||'<p>Sin hallazgos registrados.</p>');
    const closing=section(4,'Consideraciones y entrega',`<p>Una corrección se considera verificada solo cuando existe una comprobación documentada con su resultado. Los riesgos aceptados no se computan como corregidos. Los activos y sistemas no revisados en esta visita permanecen fuera de este documento.</p><p>Responsable de revisión: ${html(auditorNames(meta)||'Pendiente de identificar')}. Documento generado localmente: ${html(today)}.</p>`);
    byId('report').innerHTML=cover+summary+comparisonSection+details+closing;
  }
  function printRetestReport(){
    if(!state.findings.length){alert('Registra al menos un hallazgo para preparar una reevaluación.');return;}
    if(!state.findings.some(f=>retest.normalize(f.retests).length)&&!confirm('No hay verificaciones posteriores registradas. El informe mostrará todos los hallazgos como sin reevaluar. ¿Continuar?'))return;
    printMode='retest';buildRetestReport();window.print();
  }
  function printReport(mode='draft'){
    printMode='audit';
    reportDeliveryMode=mode==='final'?'final':'draft';
    const review=reviewState(reportDeliveryMode),invalid=invalidFields();
    if(reportDeliveryMode==='final'&&(review.blockers.length||invalid.length)){
      alert('No se puede emitir un informe definitivo. Existen '+(review.blockers.length+invalid.length)+' problemas que requieren revisión. Consulta «Revisión de calidad» o genera un borrador.');
      move('quality');return;
    }
    if(reportDeliveryMode==='final'&&review.warnings.length&&!confirm('El informe definitivo contiene '+review.warnings.length+' avisos documentales. Revisa su justificación antes de entregar. ¿Continuar?'))return;
    buildReport();window.print();
  }

  window.addEventListener('beforeprint',()=>{if(printMode==='retest')buildRetestReport();else buildReport()});
  window.addEventListener('afterprint',()=>{printMode='audit'});
  byId('palette').addEventListener('change',event=>selectPalette(event.target.value));
  byId('open-library').addEventListener('click',async()=>{try{await flush();move('records')}catch(error){alert(error.message)}});
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')void saveCurrent()});
  window.addEventListener('pagehide',()=>void saveCurrent());
  byId('network-check')?.addEventListener('click',()=>void checkNetworkServer());
  window.addEventListener('online',()=>{serverVerified=false;refreshNetworkStatus()});
  window.addEventListener('offline',()=>{serverVerified=false;refreshNetworkStatus()});
  refreshNetworkStatus();
  byId('local-date').textContent=new Date().toLocaleDateString('es-ES');
  try{selectPalette(localStorage.getItem(PALETTE_KEY)||'ocean')}catch(_ignored){selectPalette('ocean')}
  globalThis.AuditSecureTransferUI.bind({getProfile:()=>unlockedConnection,getAudit:()=>currentId?state:null,download,flush});
  void initialLoad();
  // Leave beforeinstallprompt to the browser: suppressing its default UI caused warning banners.
  window.addEventListener('appinstalled',()=>{
    deferredInstallPrompt=null;
    if(page==='online')render();
  });
  if('serviceWorker' in navigator && ['https:','http:'].includes(location.protocol) && (location.protocol==='https:'||['localhost','127.0.0.1'].includes(location.hostname))){
    window.addEventListener('load',()=>navigator.serviceWorker.register('./sw.js',{scope:'./'}).catch(error=>console.warn('PWA no disponible:',error)));
  }
})();
