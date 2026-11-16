const {spawn}=require('child_process');
const fs=require('fs');
const path=require('path');
const chrome=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',[
 '--headless','--allow-file-access-from-files','--disable-gpu','--no-first-run','--no-default-browser-check',
 '--disable-background-networking','--remote-debugging-pipe',
 '--user-data-dir=/private/tmp/pinshutter-logo-render-profile'
],{stdio:['ignore','ignore','pipe','pipe','pipe']});
let next=0,buffer='';const pending=new Map();
chrome.stdio[4].on('data',chunk=>{buffer+=chunk.toString();let at;while((at=buffer.indexOf('\0'))>=0){const data=buffer.slice(0,at);buffer=buffer.slice(at+1);if(!data)continue;const msg=JSON.parse(data);const item=pending.get(msg.id);if(item){pending.delete(msg.id);msg.error?item.reject(msg.error):item.resolve(msg.result);}}});
function call(method,params={},sessionId){return new Promise((resolve,reject)=>{const id=++next;pending.set(id,{resolve,reject});chrome.stdio[3].write(JSON.stringify({id,method,params,...(sessionId?{sessionId}: {})})+'\0');});}
const timer=setTimeout(()=>{chrome.kill();process.exit(1)},30000);
(async()=>{
 try{
 const {targetId}=await call('Target.createTarget',{url:'about:blank'});
 const {sessionId}=await call('Target.attachToTarget',{targetId,flatten:true});
 await call('Page.enable',{},sessionId);
 for(const file of process.argv.slice(2)){
  await call('Page.navigate',{url:'file://'+path.resolve(file)},sessionId);
  // Wait for the new file's renderer rather than the previous document.
  let ready=false;
  for(let n=0;n<100;n++){
   const r=await call('Runtime.evaluate',{expression:'location.href === '+JSON.stringify('file://'+path.resolve(file))+' && !!window.iconReady',returnByValue:true},sessionId);
   if(r.result.value){ready=true;break;}
   await new Promise(r=>setTimeout(r,25));
  }
  if(!ready)throw Error('Renderer did not load: '+file);
  const result=await call('Runtime.evaluate',{expression:'window.iconReady.then(() => window.exportAssets ? window.exportAssets() : document.querySelector("canvas").toDataURL("image/png"))',awaitPromise:true,returnByValue:true},sessionId);
  if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));
  if(typeof result.result.value === 'string') {
   const dest=file.replace(/\.html$/,'.png');
   fs.writeFileSync(dest,Buffer.from(result.result.value.split(',')[1],'base64'));
   console.log(dest);
  } else {
   const root=path.resolve(__dirname,'../../..');
   for (const [name,data] of Object.entries(result.result.value)) {
    const dest=path.resolve(root,name);
    if(!dest.startsWith(root+path.sep))throw Error('Export outside app root');
    fs.mkdirSync(path.dirname(dest),{recursive:true});
    fs.writeFileSync(dest,Buffer.from(data.split(',')[1],'base64'));
   }
   console.log(Object.keys(result.result.value).length+' PS assets exported');
  }
 }
 }finally{clearTimeout(timer);chrome.kill();}
})().catch(e=>{console.error(e);process.exitCode=1});
