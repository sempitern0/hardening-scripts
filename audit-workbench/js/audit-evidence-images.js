/* Bounded multi-image evidence, compatible with legacy v3 records with one image. */
'use strict';
(() => {
  const MAX_IMAGES=10,MAX_INLINE=1399999,MAX_AUDIT_IMAGES=28*1024*1024;
  const validImage=value=>typeof value==='string'&&value.length>24&&value.length<=MAX_INLINE&&
    /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(value);
  function normalizedAttachment(item) {
    if(!item||typeof item!=='object'||Array.isArray(item)||!validImage(item.image))
      throw Error('Imagen adicional no válida en el expediente.');
    return {
      image:item.image,
      fileName:typeof item.fileName==='string'?item.fileName.slice(0,180):'',
      fileBytes:Number.isSafeInteger(item.fileBytes)&&item.fileBytes>=0?item.fileBytes:null,
      fileSha256:typeof item.fileSha256==='string'&&/^[a-f0-9]{64}$/i.test(item.fileSha256)?item.fileSha256.toLowerCase():''
    };
  }
  function normalize(value){
    if(value==null)return [];
    if(!Array.isArray(value)||value.length>MAX_IMAGES-1)throw Error('Máximo de '+MAX_IMAGES+' imágenes por evidencia.');
    return value.map(normalizedAttachment);
  }
  function list(record){
    const base=validImage(record?.image)?[{
      image:record.image,fileName:record.fileName||'',
      fileBytes:record.fileBytes??null,fileSha256:record.fileSha256||''
    }]:[];
    return [...base,...normalize(record?.attachments)];
  }
  function totalSize(rows){
    return (rows||[]).reduce((total,row)=>total+list(row).reduce((sum,item)=>sum+item.image.length,0),0);
  }
  function add(record,photos){
    if(!Array.isArray(photos)||!photos.length)throw Error('Selecciona al menos una imagen.');
    const initial=list(record);
    const normalized=photos.map(normalizedAttachment);
    if(initial.length+normalized.length>MAX_IMAGES)throw Error('Una evidencia puede contener hasta '+MAX_IMAGES+' imágenes.');
    const next=[...initial,...normalized];
    const first=next[0];
    record.image=first.image;
    record.fileName=first.fileName;
    record.fileBytes=first.fileBytes;
    record.fileSha256=first.fileSha256;
    record.sha256=first.fileSha256;
    record.attachments=next.slice(1);
    return record;
  }
  function remove(record,index){
    const all=list(record);
    if(!Number.isInteger(index)||index<0||index>=all.length)throw Error('Imagen no encontrada.');
    all.splice(index,1);
    if(!all.length){
      record.image='';record.fileName='';record.fileBytes=null;record.fileSha256='';record.sha256='';
      record.attachments=[];
    }else{
      const first=all[0];
      record.image=first.image;record.fileName=first.fileName;record.fileBytes=first.fileBytes;
      record.fileSha256=first.fileSha256;record.sha256=first.fileSha256;
      record.attachments=all.slice(1);
    }
    return record;
  }
  globalThis.AuditEvidenceImages=Object.freeze({
    MAX_IMAGES,MAX_AUDIT_IMAGES,validImage,normalize,list,totalSize,add,remove
  });
})();