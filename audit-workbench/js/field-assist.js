/* Data-aware form aids. All values come from the active audit; never infer compliance or rewrite existing fields. */
'use strict';
(()=>{
  const text=value=>typeof value==='string'?value.trim():'';
  const unique=(values,limit=120)=>{
    const seen=new Set(),result=[];
    for(const value of values){
      const item=text(value),key=item.toLocaleLowerCase('es');
      if(!item||seen.has(key))continue;
      seen.add(key);result.push(item);
      if(result.length>=limit)break;
    }
    return result;
  };
  const assets=audit=>(audit?.assets||[]).filter(x=>text(x?.name)||text(x?.id));
  function assetChoices(audit){
    const rows=assets(audit),counts=new Map();
    for(const row of rows){
      const name=text(row.name).toLocaleLowerCase('es');
      if(name)counts.set(name,(counts.get(name)||0)+1);
    }
    const options=[];
    for(const item of rows){
      const name=text(item.name),id=text(item.id);
      // Ambiguous hostnames are represented by their unique inventory code where possible.
      const duplicate=name&&counts.get(name.toLocaleLowerCase('es'))>1;
      const value=duplicate&&id?id:(name||id);
      const label=[name||id,id&&id!==value?id:'',text(item.site)].filter(Boolean).join(' · ');
      if(!value)continue;
      options.push({value,label:label||value});
    }
    const seen=new Set();
    return options.filter(option=>{
      const key=option.value.toLocaleLowerCase('es');
      if(seen.has(key))return false;
      seen.add(key);return true;
    }).slice(0,250);
  }
  function suggestions(audit,block,field,base=[]){
    const rows=block==='software'?(audit?.software||[]):block==='networks'?(audit?.networks||[]):[];
    let learned=[];
    if(field==='site'&&block==='assets')learned=(audit?.assets||[]).map(x=>x.site);
    else if(field==='owner'&&['assets','findings'].includes(block))
      learned=[...(audit?.assets||[]).map(x=>x.owner),...(audit?.findings||[]).map(x=>x.owner)];
    else if(field==='vendor'&&block==='software')learned=rows.map(x=>x.vendor);
    else if(block==='networks'&&['gateway','dns','firewall'].includes(field))learned=rows.map(x=>x[field]);
    return unique([...learned,...base]);
  }
  function refs(value){
    return unique(text(value).split(/[\s,;]+/).filter(Boolean),500);
  }
  function appendRef(current,code){
    const token=text(code);
    if(!token||/[\s,;]/.test(token))return text(current);
    const present=refs(current);
    if(present.some(x=>x.toUpperCase()===token.toUpperCase()))return text(current);
    return [...present,token].join(', ');
  }
  function candidates(audit,kind,current){
    const collection=kind==='evidence'?(audit?.evidence||[]):kind==='cve'?(audit?.cves||[]):[];
    const used=new Set(refs(current).map(x=>x.toUpperCase()));
    const seen=new Set();
    const rows=[];
    for(const row of collection){
      const id=text(row?.id),normalized=id.toUpperCase();
      if(!id||used.has(normalized)||seen.has(normalized))continue;
      // References are selected, not asserted. CVEs retain their verification status.
      seen.add(normalized);
      rows.push({id,title:text(row.title||row.name),status:text(row.status)});
    }
    return rows.slice(0,60);
  }
  function ipv4(value){
    const s=text(value),parts=s.split('.');
    if(parts.length!==4||parts.some(p=>!/^\d{1,3}$/.test(p)||Number(p)>255))return null;
    return parts.reduce((n,p)=>((n<<8)>>>0)+Number(p),0)>>>0;
  }
  function subnet(value){
    const m=/^(.+)\/(\d{1,2})$/.exec(text(value));
    if(!m)return null;
    const ip=ipv4(m[1]),bits=Number(m[2]);
    if(ip===null||bits>32)return null;
    const mask=bits===0?0:(0xffffffff<<(32-bits))>>>0;
    return {address:ip&mask,mask,bits};
  }
  function inSubnet(ip,cidr){
    const address=ipv4(ip),prefix=subnet(cidr);
    if(address===null||!prefix)return null;
    return ((address&prefix.mask)>>>0)===prefix.address;
  }
  function crossChecks(audit){
    const issues=[];
    const add=(code,section,message,key='')=>issues.push({code,section,message,key});
    const assetByIp=new Map(),assetByName=new Map();
    for(const row of audit?.assets||[]){
      const ip=text(row.ip),name=text(row.name),key=text(row._key);
      if(ipv4(ip)!==null){
        if(assetByIp.has(ip))add('IP_ACTIVO_REPETIDA','assets','Dos activos comparten la dirección IP '+ip+'; confirma si son interfaces compartidas o un duplicado.',key);
        else assetByIp.set(ip,key);
      }
      if(name){
        const normalized=name.toLocaleLowerCase('es');
        if(assetByName.has(normalized))add('NOMBRE_ACTIVO_REPETIDO','assets','Nombre de activo repetido: '+name+'. Las referencias por nombre pueden ser ambiguas.',key);
        else assetByName.set(normalized,key);
      }
    }
    const cidrs=new Set();
    for(const row of audit?.networks||[]){
      const cidr=text(row.cidr),gateway=text(row.gateway),key=text(row._key);
      if(cidr&&subnet(cidr)){
        const canonical=subnet(cidr),signature=canonical.address+'/'+canonical.bits;
        if(cidrs.has(signature))add('RED_REPETIDA','networks','La red '+cidr+' aparece más de una vez; verifica si es intencionado.',key);
        cidrs.add(signature);
      }
      const belongs=inSubnet(gateway,cidr);
      if(gateway&&cidr&&belongs===false)add('GATEWAY_FUERA_DE_SUBRED','networks',
        'La puerta de enlace '+gateway+' no pertenece a '+cidr+'. Comprueba máscara, interfaz y diseño de enrutamiento.',key);
    }
    return issues;
  }
  globalThis.AuditFieldAssist=Object.freeze({assetChoices,suggestions,appendRef,candidates,refs,ipv4,subnet,inSubnet,crossChecks});
})();