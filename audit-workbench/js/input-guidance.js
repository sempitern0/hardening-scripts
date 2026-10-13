/* Local-only form guidance and telephone presentation; no external lookups. */
'use strict';
(() => {
  const COUNTRIES=Object.freeze([
    {id:'ES',name:'España',dial:'34',example:'612 345 678',min:9,max:9,groups:[3,3,3]},
    {id:'PT',name:'Portugal',dial:'351',example:'912 345 678',min:9,max:9,groups:[3,3,3]},
    {id:'FR',name:'Francia',dial:'33',example:'6 12 34 56 78',min:9,max:9,groups:[1,2,2,2,2]},
    {id:'DE',name:'Alemania',dial:'49',example:'151 2345 6789',min:7,max:13,groups:[3,4,4,2]},
    {id:'IT',name:'Italia',dial:'39',example:'312 345 6789',min:6,max:12,groups:[3,3,4,2]},
    {id:'GB',name:'Reino Unido',dial:'44',example:'7700 900 123',min:9,max:10,groups:[4,3,3]},
    {id:'US',name:'Estados Unidos',dial:'1',example:'202 555 0123',min:10,max:10,groups:[3,3,4]},
    {id:'MX',name:'México',dial:'52',example:'55 1234 5678',min:10,max:10,groups:[2,4,4]},
    {id:'AR',name:'Argentina',dial:'54',example:'11 2345 6789',min:10,max:11,groups:[2,4,4,1]},
    {id:'CO',name:'Colombia',dial:'57',example:'310 123 4567',min:10,max:10,groups:[3,3,4]},
    {id:'BR',name:'Brasil',dial:'55',example:'11 91234 5678',min:10,max:11,groups:[2,5,4]},
    {id:'CL',name:'Chile',dial:'56',example:'9 1234 5678',min:9,max:9,groups:[1,4,4]},
    {id:'PE',name:'Perú',dial:'51',example:'987 654 321',min:9,max:9,groups:[3,3,3]}
  ].map(c=>Object.freeze(c)));
  const OTHER=Object.freeze({id:'OTHER',name:'Otro país',dial:'',example:'+prefijo y número',min:7,max:15,groups:[3,3,3,3,3]});
  const byId=id=>COUNTRIES.find(c=>c.id===id)||OTHER;
  const onlyDigits=s=>String(s||'').replace(/\D/g,'');
  const detect=value=>{
    const raw=String(value||'').trim();
    if(!raw)return byId('ES');
    if(raw.startsWith('+')){
      const normalized=onlyDigits(raw);
      return [...COUNTRIES].sort((a,b)=>b.dial.length-a.dial.length).find(c=>normalized.startsWith(c.dial))||OTHER;
    }
    return onlyDigits(raw).length===9?byId('ES'):OTHER;
  };
  const national=(value,country)=>{
    const raw=String(value||'').trim(),c=byId(country);
    if(c.id==='OTHER')return raw;
    const d=onlyDigits(raw);
    return raw.startsWith('+')&&d.startsWith(c.dial)?d.slice(c.dial.length):d;
  };
  const format=(value,country)=>{
    const c=byId(country);
    if(c.id==='OTHER')return String(value||'');
    const d=onlyDigits(value).slice(0,c.max);
    const segments=[];let n=0;
    for(const size of c.groups){if(n>=d.length)break;segments.push(d.slice(n,n+size));n+=size;}
    if(n<d.length)segments.push(d.slice(n));
    return segments.join(' ');
  };
  const international=(value,country)=>{
    const c=byId(country);
    if(c.id==='OTHER'){
      const raw=String(value||'').trim();
      return raw? (raw.startsWith('+')?'+':'')+onlyDigits(raw):'';
    }
    const digits=onlyDigits(value).slice(0,c.max);
    return digits?'+'+c.dial+' '+format(digits,c.id):'';
  };
  function validate(value){
    const raw=String(value||'').trim();
    if(!raw)return '';
    if(!/^\+?[\d ()-]+$/.test(raw))return 'El teléfono solo admite dígitos, espacios y separadores habituales.';
    const digits=onlyDigits(raw);
    if(digits.length<7||digits.length>15)return 'Comprueba el teléfono: deben existir entre 7 y 15 dígitos en total.';
    if(raw.startsWith('+')){
      if(digits.startsWith('0'))return 'El prefijo internacional no puede empezar por cero.';
      const c=detect(raw);
      if(c.id!=='OTHER'){
        const local=digits.slice(c.dial.length);
        if(local.length<c.min||local.length>c.max)return 'Comprueba el número para '+c.name+': '+c.min+(c.min===c.max?' dígitos nacionales.':'–'+c.max+' dígitos nacionales.');
      }
    }
    return '';
  }
  const ID_EXAMPLES=Object.freeze({
    'DNI / NIF persona física':'12345678Z',
    'DNI':'12345678Z',
    'NIE':'X1234567L',
    'NIF entidad / CIF':'B12345678',
    'NIF intracomunitario / otro':'ESB12345678',
    'Pasaporte / otro':'PA1234567',
    'Otro documento':'Número del documento',
    'No indicado':'Selecciona el tipo de documento'
  });
  const documentPlaceholder=type=>ID_EXAMPLES[type]||'Número de identificación';
  const EXAMPLES=Object.freeze({
    meta:{clientEmail:'contacto@empresa.es',clientPostal:'28013',clientAddress:'Calle Mayor 12, Madrid',reportId:'AUD-001',revision:'1.0',contact:'Nombre y apellidos'},
    settings:{email:'auditoria@consultora.es',postal:'28013',prefix:'AUD',address:'Calle Mayor 12, Madrid'},
    assets:{id:'ACT-001',name:'SRV-DC-01',serial:'SN123456789',ip:'192.168.10.25',cpu:'Intel Xeon / AMD EPYC',ram:'32 GiB',storage:'SSD 1 TiB',owner:'Departamento de sistemas'},
    networks:{name:'VLAN de servidores',cidr:'192.168.10.0/24',vlan:'20',gateway:'192.168.10.1',dns:'192.168.10.53, 192.168.10.54',firewall:'FW-001 / regla 120'},
    software:{version:'16.2.0',asset:'SRV-DC-01',vendor:'Fabricante o editor'},
    cves:{id:'CVE-2025-12345',cvss:'7.5',asset:'SRV-DC-01'},
    controls:{id:'CTRL-001',evidenceIds:'EV-001, EV-002',reference:'ISO/IEC 27001 / CIS Controls'},
    findings:{id:'FND-001',cvss:'7.5',asset:'SRV-DC-01',evidenceIds:'EV-001',references:'CVE-2025-12345 · CIS Control 7'},
    evidence:{id:'EV-001',sha256:'SHA-256 de 64 caracteres hexadecimales',asset:'SRV-DC-01'}
  });
  function placeholder(block,field,obj){
    if(field==='clientTaxId')return documentPlaceholder(obj?.clientIdType);
    if(field==='contactId')return documentPlaceholder(obj?.contactIdType);
    if(block==='settings'&&field==='taxId')return documentPlaceholder(obj?.taxType);
    if(block==='member')return {name:'Nombre y apellidos',email:'auditor@consultora.es',role:'Auditor técnico / responsable'}[field]||'';
    return EXAMPLES[block]?.[field]||'';
  }

  // Enhance fields after each SPA render, without changing the audit data schema.
  const flags={ES:'🇪🇸',PT:'🇵🇹',FR:'🇫🇷',DE:'🇩🇪',IT:'🇮🇹',GB:'🇬🇧',US:'🇺🇸',MX:'🇲🇽',AR:'🇦🇷',CO:'🇨🇴',BR:'🇧🇷',CL:'🇨🇱',PE:'🇵🇪'};
  function enhance(root){
    if(!root)return;
  }
  function apply(root){
    if(!root)return;
    for(const input of root.querySelectorAll('input[data-field],input[data-member-field]')){
      if(input.dataset.guidanceReady)continue;
      const field=input.dataset.field||input.dataset.memberField;
      const block=input.dataset.block||'member';
      if(field==='phone'||field==='clientPhone'){
        const saved=input.value,country=detect(saved);let activeCountry=country.id;
        const wrap=document.createElement('div');wrap.className='phone-widget';
        const select=document.createElement('select');select.className='phone-country';select.setAttribute('aria-label','País y prefijo telefónico');
        for(const c of [...COUNTRIES,OTHER]){
          const option=document.createElement('option');option.value=c.id;option.textContent=(flags[c.id]||'🌐')+' '+c.name+(c.dial?' (+'+c.dial+')':'');
          if(c.id===country.id)option.selected=true;
          select.appendChild(option);
        }
        input.parentNode.insertBefore(wrap,input);wrap.appendChild(select);wrap.appendChild(input);
        input.type='tel';input.setAttribute('inputmode','tel');input.setAttribute('autocomplete','tel');
        input.dataset.guidanceReady='phone';
        input.placeholder=country.example;
        input.value=country.id==='OTHER'?saved:format(national(saved,country.id),country.id);
        select.addEventListener('change',()=>{
          const old=input.value,next=byId(select.value);
          input.value=old&&activeCountry!==next.id?'':format(old,next.id);
          input.placeholder=next.example;
          activeCountry=next.id;
          input.dispatchEvent(new Event('input',{bubbles:true}));
          input.focus();
        });
        input.addEventListener('input',()=>{
          const c=byId(select.value);
          const display=c.id==='OTHER'?input.value:format(input.value,c.id);
          const stored=international(display,c.id);
          input.value=stored;
          queueMicrotask(()=>{if(input.isConnected){input.value=display;}});
        },true);
      }else{
        const type=field==='clientTaxId'?'clientIdType':field==='contactId'?'contactIdType':field==='taxId'?'taxType':field==='documentId'?'idType':null;
        const owner=input.closest('.member-card');
        const select=type?(owner?owner.querySelector('[data-member-field="idType"]'):root.querySelector('[data-block="'+block+'"][data-field="'+type+'"]')):null;
        const update=()=>{input.placeholder=type?documentPlaceholder(select?.value):placeholder(block,field,{});};
        update();
        if(select)select.addEventListener('change',update);
        input.dataset.guidanceReady='hint';
      }
    }
  }
  function start(){
    const root=document.getElementById('workspace');if(!root)return;
    apply(root);
    new MutationObserver(()=>apply(root)).observe(root,{childList:true,subtree:true});
  }
  if(typeof document!=='undefined'){
    if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});
    else start();
  }

  globalThis.AuditInputGuidance=Object.freeze({
    COUNTRIES,OTHER,byId,detect,national,format,international,validate,placeholder,documentPlaceholder,onlyDigits
  });
})();