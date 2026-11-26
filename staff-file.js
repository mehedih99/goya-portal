/* Offline staff package: reads authorized documents; never changes Drive sharing. */
(() => {'use strict';
 const encoder=new TextEncoder(),active=new Set();
 const crcTable=Uint32Array.from({length:256},(_,n)=>{for(let k=0;k<8;k++)n=(n&1)?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
 function crc32(bytes){let n=0xffffffff;for(const b of bytes)n=crcTable[(n^b)&255]^(n>>>8);return (n^0xffffffff)>>>0;}
 function header(size){const bytes=new Uint8Array(size),view=new DataView(bytes.buffer);return {bytes,u16:(p,n)=>view.setUint16(p,n,true),u32:(p,n)=>view.setUint32(p,n,true)};}
 function zip(entries){
  const parts=[],central=[];let offset=0,centralSize=0;
  for(const entry of entries){
   const directory=entry.name.endsWith('/'),segments=(directory?entry.name.slice(0,-1):entry.name).split('/');
   if(!/^[A-Za-z0-9_./-]+$/.test(entry.name)||segments.some(s=>!s||s==='.'||s==='..'))throw Error('Invalid package filename.');
   const name=encoder.encode(entry.name),bytes=entry.bytes instanceof Uint8Array?entry.bytes:new Uint8Array(entry.bytes),crc=crc32(bytes),local=header(30),record=header(46);
   local.u32(0,0x04034b50);local.u16(4,20);local.u16(6,0x800);local.u16(12,33);local.u32(14,crc);local.u32(18,bytes.length);local.u32(22,bytes.length);local.u16(26,name.length);
   record.u32(0,0x02014b50);record.u16(4,20);record.u16(6,20);record.u16(8,0x800);record.u16(14,33);record.u32(16,crc);record.u32(20,bytes.length);record.u32(24,bytes.length);record.u16(28,name.length);record.u32(38,directory?16:0);record.u32(42,offset);
   parts.push(local.bytes,name,bytes);central.push(record.bytes,name);offset+=30+name.length+bytes.length;centralSize+=46+name.length;
  }
  const end=header(22);end.u32(0,0x06054b50);end.u16(8,entries.length);end.u16(10,entries.length);end.u32(12,centralSize);end.u32(16,offset);
  return new Blob([...parts,...central,end.bytes],{type:'application/zip'});
 }
 function localLink(pdf,x,y,w,h,path){
  if(!/^Documents\/[A-Za-z0-9_-]+\.(pdf|jpg|png)$/.test(path))throw Error('Invalid local document link.');
  const api=pdf.internal,rect=[api.getCoordinateString(x),api.getVerticalCoordinateString(y+h),api.getCoordinateString(x+w),api.getVerticalCoordinateString(y)].join(' ');
  if(!pdf.__goyaLocalLinks){pdf.__goyaLocalLinks=true;api.events.subscribe('putPage',function(page){const links=page.pageContext.goyaLocalLinks;if(!links?.length)return;const refs=links.map(content=>{const obj=this.internal.newAdditionalObject();obj.content=content;return obj.objId+' 0 R';});this.internal.write('/Annots ['+refs.join(' ')+']');});}
  (api.getCurrentPageInfo().pageContext.goyaLocalLinks||=[]).push('<< /Type /Annot /Subtype /Link /Rect ['+rect+'] /Border [0 0 0] /A << /S /Launch /F ('+path+') /NewWindow true >> >>');
 }
 const slug=v=>String(v||'Staff').normalize('NFKD').replace(/[^a-z0-9_-]+/gi,'-').replace(/^-|-$/g,'').slice(0,70)||'Staff';
 async function download(member,status=()=>{}){
  if(active.has(member.id))return;active.add(member.id);
  try{
   const all=await GoyaManagement.rpc('goya_hr_documents',{p_staff:member.id});
   const docs=all.filter(d=>Number(d.version_rank)===1&&d.category!=='profile-photo').sort((a,b)=>String(a.category).localeCompare(String(b.category))||String(a.id).localeCompare(String(b.id)));
   if(docs.length>200)throw Error('Too many documents for one offline package.');
   const entries=[],files=[];let total=0;
   const root='GOYA-'+slug(member.profile?.employee_code||member.id)+'-'+slug(member.name);
   entries.push({name:root+'/Documents/',bytes:new Uint8Array()});
   for(const [i,d] of docs.entries()){
    status('Preparing Staff File: document '+(i+1)+' of '+docs.length+'…');
    const blob=await GoyaHR.documentBlob(d,member.id),ext=({'application/pdf':'pdf','image/jpeg':'jpg','image/png':'png'})[blob.type];
    if(!ext||!blob.size||blob.size>5000000)throw Error('A document has an unsupported format or size. Please check the staff documents.');
    total+=blob.size;if(total>200000000)throw Error('This staff package exceeds the download size limit.');
    const path='Documents/'+String(i+1).padStart(3,'0')+'-'+slug(d.custom_title||d.category)+'.'+ext;
    files.push({...d,local_path:path,title:d.custom_title||d.category});entries.push({name:root+'/'+path,bytes:await blob.arrayBuffer()});
   }
   status('Preparing Staff File PDF…');
   const pdf=await GoyaManagement.staffPDF(member,{documents:files,returnPDF:true});
   entries.unshift({name:root+'/Staff-Details.pdf',bytes:pdf.output('arraybuffer')});
   entries.push({name:root+'/Read-Me.txt',bytes:encoder.encode('GOYA Staff File\r\n\r\nExtract the entire ZIP before opening Staff-Details.pdf. Keep the PDF and Documents folder together. Open File links use local files. If your PDF viewer blocks a link, open the filename shown in the Documents folder. No internet or Google Drive login is required after extraction.\r\n\r\n'+(files.length?'Included documents:\r\n'+files.map(d=>d.local_path).join('\r\n'):'No documents were uploaded at the time of this export.')+'\r\n')});
   const url=URL.createObjectURL(zip(entries)),link=document.createElement('a');link.href=url;link.download=root+'.zip';link.click();setTimeout(()=>URL.revokeObjectURL(url),60000);
  }finally{active.delete(member.id);}
 }
 window.GoyaStaffFile={download,localLink,zip};
})();
