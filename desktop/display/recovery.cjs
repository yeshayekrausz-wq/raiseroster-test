// Recover the kiosk when navigation fails, stalls, or its renderer crashes.
module.exports=function attachRecovery(win,{url,fallback,onError=()=>{},timers=globalThis}){
 let retry=null,watchdog=null,stopped=false,attempts=0;
 const clearWatchdog=()=>{timers.clearTimeout(watchdog);watchdog=null;};
 function failed(message){
  if(stopped||retry)return;
  clearWatchdog();onError(message);
  const delay=Math.min(60000,15000*2**Math.min(attempts++,2));
  retry=timers.setTimeout(()=>{retry=null;load();},delay);
  win.loadFile(fallback).catch(()=>{});
 }
 function load(){
  if(stopped||win.isDestroyed())return;
  clearWatchdog();
  watchdog=timers.setTimeout(()=>failed('Display loading timed out.'),25000);
  win.loadURL(url).catch(()=>failed('Unable to load the display website.'));
 }
 win.webContents.on('did-fail-load',(_e,code,description,_url,isMainFrame)=>{
  if(isMainFrame&&code!==-3)failed('Display connection: '+description);
 });
 win.webContents.on('did-finish-load',()=>{
  if(win.webContents.getURL().startsWith(url.split('?')[0])){clearWatchdog();timers.clearTimeout(retry);retry=null;attempts=0;}
 });
 win.webContents.on('render-process-gone',()=>failed('Display renderer stopped.'));
 win.on('closed',()=>{stopped=true;clearWatchdog();timers.clearTimeout(retry);});
 return {load};
};
