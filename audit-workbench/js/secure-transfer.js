/* Offline-first secure transfer primitives: opt-in, no automatic network calls. */
'use strict';
(() => {
  const KIND='audit-workbench-encrypted-backup-v1';
  const MAX_FILE=45*1024*1024;
  const encoder=new TextEncoder(),decoder=new TextDecoder();
  const crypt=()=>globalThis.crypto?.subtle?globalThis.crypto:null;
  const b64=bytes=>{
    let output='';
    for(let i=0;i<bytes.length;i+=8192)output+=String.fromCharCode(...bytes.subarray(i,i+8192));
    return btoa(output);
  };
  const unb64=encoded=>Uint8Array.from(atob(encoded),ch=>ch.charCodeAt(0));
  function validatePassphrase(secret){
    if(typeof secret!=='string'||secret.length<16||secret.length>512)throw Error('La frase de cifrado debe contener entre 16 y 512 caracteres.');
  }
  async function key(secret,salt,rounds=310000){
    const crypto=crypt();
    if(!crypto)throw Error('Web Crypto requiere HTTPS o localhost y un navegador compatible.');
    const material=await crypto.subtle.importKey('raw',encoder.encode(secret),'PBKDF2',false,['deriveKey']);
    return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:rounds,hash:'SHA-256'},material,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
  }
  async function encryptBackup(data,passphrase){
    validatePassphrase(passphrase);
    const c=crypt(),raw=encoder.encode(JSON.stringify(data));
    if(raw.byteLength>MAX_FILE)throw Error('El expediente excede el límite de 45 MiB.');
    const salt=c.getRandomValues(new Uint8Array(16)),iv=c.getRandomValues(new Uint8Array(12));
    const aad=encoder.encode(KIND);
    const cipher=new Uint8Array(await c.subtle.encrypt({name:'AES-GCM',iv,additionalData:aad},await key(passphrase,salt),raw));
    return JSON.stringify({kind:KIND,version:1,algorithm:'AES-256-GCM',kdf:'PBKDF2-SHA256',iterations:310000,
      salt:b64(salt),iv:b64(iv),ciphertext:b64(cipher),createdAt:new Date().toISOString()});
  }
  async function decryptBackup(text,passphrase){
    validatePassphrase(passphrase);
    if(typeof text!=='string'||text.length>MAX_FILE*1.5)throw Error('Archivo de backup demasiado grande.');
    const payload=JSON.parse(text);
    if(payload?.kind!==KIND||payload.version!==1||payload.algorithm!=='AES-256-GCM'||payload.kdf!=='PBKDF2-SHA256'||payload.iterations!==310000)throw Error('Formato de backup cifrado desconocido.');
    const salt=unb64(payload.salt),iv=unb64(payload.iv),cipher=unb64(payload.ciphertext);
    if(salt.length!==16||iv.length!==12||cipher.length>MAX_FILE+16)throw Error('Parámetros de cifrado no válidos.');
    try{
      const decrypted=await crypt().subtle.decrypt({name:'AES-GCM',iv,additionalData:encoder.encode(KIND)},await key(passphrase,salt),cipher);
      return decoder.decode(decrypted);
    }catch(_err){throw Error('No se pudo descifrar: frase incorrecta o archivo alterado.');}
  }
  function validateDavUrl(value){
    const url=new URL(value);
    if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash)throw Error('Se requiere WebDAV HTTPS sin credenciales ni parámetros en la URL.');
    if(!/\/remote\.php\/(dav\/files\/[^/]+\/|webdav\/)/.test(url.pathname))throw Error('URL de Nextcloud WebDAV no reconocida.');
    return url;
  }
  function target(profile,filename){
    const base=validateDavUrl(profile.url);
    if(!/^[a-zA-Z0-9_.-]{1,160}$/.test(filename)||filename==='.'||filename==='..')throw Error('Nombre de archivo no permitido.');
    const pathname=base.pathname.endsWith('/')?base.pathname:base.pathname+'/';
    const url=new URL(base.href);url.pathname=pathname+encodeURIComponent(filename);
    return url.href;
  }
  function shareApiInfo(profile,filename){
    const url=validateDavUrl(profile.url);
    const index=url.pathname.indexOf('/remote.php/');
    if(index<0)throw Error('Ruta Nextcloud no válida.');
    const localPath=url.pathname.slice(index).replace(/^\/remote\.php\/(?:dav\/files\/[^/]+|webdav)\/?/,'');
    const segments=localPath.split('/').filter(Boolean).map(x=>decodeURIComponent(x));
    if(segments.some(x=>!x||x==='.'||x==='..'||x.includes('/')||x.includes('\\')))throw Error('Ruta de carpeta no permitida.');
    const folder='/'+[...segments,filename].join('/');
    const api=url.origin+url.pathname.slice(0,index)+'/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json';
    return {api,path:folder};
  }
  function auth(profile){
    // Encodes UTF-8 usernames/app passwords, does not persist or log them.
    return 'Basic '+btoa(Array.from(encoder.encode(profile.user+':'+profile.secret),b=>String.fromCharCode(b)).join(''));
  }
  function safeFilename(type){
    const token=Array.from(crypt().getRandomValues(new Uint8Array(6)),b=>b.toString(16).padStart(2,'0')).join('');
    const date=new Date().toISOString().replace(/[-:]/g,'').replace(/\..+$/,'').replace('T','-');
    return 'audit-'+date+'-'+token+'.'+(type==='pdf'?'pdf':'awenc');
  }
  async function upload(profile,filename,body,type){
    const url=target(profile,filename);
    const result=await fetch(url,{method:'PUT',mode:'cors',credentials:'omit',redirect:'error',referrerPolicy:'no-referrer',
      headers:{Authorization:auth(profile),'Content-Type':type,'If-None-Match':'*'},body});
    if(result.status===412)throw Error('El archivo ya existe: no se sobrescribe.');
    if(!result.ok)throw Error('WebDAV devolvió HTTP '+result.status+'. Comprueba permisos, CORS y espacio.');
    return {filename,url,sharePath:shareApiInfo(profile,filename).path};
  }
  function expiryDate(days){
    const d=Number(days);
    if(!Number.isInteger(d)||d<1||d>7)throw Error('La caducidad debe ser de 1 a 7 días.');
    const today=new Date();
    const utcDate=new Date(Date.UTC(today.getFullYear(),today.getMonth(),today.getDate()+d));
    return utcDate.toISOString().slice(0,10);
  }
  async function ocs(profile,method,path,data){
    const info=shareApiInfo(profile,'file.pdf');
    const parsed=new URL(info.api);
    parsed.pathname=parsed.pathname.replace(/\/shares$/,'/shares'+(path?'/'+encodeURIComponent(String(path)):''));
    const result=await fetch(parsed.href,{method,mode:'cors',credentials:'omit',redirect:'error',referrerPolicy:'no-referrer',
      headers:{Authorization:auth(profile),'OCS-APIRequest':'true','Accept':'application/json',...(data?{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'}:{})},
      ...(data?{body:new URLSearchParams(data).toString()}:{})});
    if(!result.ok)throw Error('Nextcloud Share API respondió HTTP '+result.status+'. Comprueba CORS/permisos.');
    if(method==='DELETE')return true;
    const payload=await result.json();
    const code=Number(payload?.ocs?.meta?.statuscode);
    if(![100,200].includes(code))throw Error('Nextcloud rechazó compartir: '+String(payload?.ocs?.meta?.message||code).slice(0,160));
    return payload.ocs.data;
  }
  async function createExpiringShare(profile,filename,days,password){
    if(typeof password!=='string'||password.length<16)throw Error('El enlace requiere una contraseña de al menos 16 caracteres.');
    const expiration=expiryDate(days),path=shareApiInfo(profile,filename).path;
    const data=await ocs(profile,'POST','',{path,shareType:'3',permissions:'1',password,expireDate:expiration,publicUpload:'false'});
    if(!data?.id)throw Error('El servidor no devolvió un identificador de compartición.');
    const id=String(data.id);
    const returned=String(data.expiration||'').slice(0,10);
    if(returned!==expiration){
      try{await ocs(profile,'DELETE',id)}catch(_e){}
      throw Error('No se confirmó la caducidad en el servidor. Comprueba y elimina el enlace en Nextcloud.');
    }
    let url;
    try{url=new URL(data.url)}catch(_e){url=null;}
    if(!url||url.protocol!=='https:'||url.username||url.password){
      try{await ocs(profile,'DELETE',id)}catch(_e){}
      throw Error('Nextcloud devolvió un enlace no seguro. Revisa las comparticiones.');
    }
    return {id,url:url.href,expiration,filename};
  }
  async function revokeShare(profile,share){return ocs(profile,'DELETE',share.id)}
  async function isPdf(file){
    if(!file||file.size<5||file.size>40*1024*1024)return false;
    const bytes=new Uint8Array(await file.slice(0,5).arrayBuffer());
    return String.fromCharCode(...bytes)==='%PDF-';
  }
  globalThis.AuditSecureTransfer=Object.freeze({KIND,encryptBackup,decryptBackup,validateDavUrl,target,shareApiInfo,safeFilename,upload,expiryDate,createExpiringShare,revokeShare,isPdf});
})();
