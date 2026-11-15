const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const escape = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const formats = ['auto','receipt58','receipt80','Letter','A4'];
function paperFormat(settings, printer={}) {
  if (settings.format && settings.format !== 'auto') return settings.format;
  const description=[printer.name,printer.displayName,...Object.entries(printer.options||{}).flat()].join(' ');
  if (/58\s*mm|pos[- _]?58|receipt58/i.test(description)) return 'receipt58';
  if (/80\s*mm|pos[- _]?80|thermal|receipt|epson.*tm-|star.*tsp/i.test(description)) return 'receipt80';
  return /\bA4\b/i.test(description) ? 'A4' : 'Letter';
}
function receiptHTML(value, width, totals) {
  const points = value.rows.reduce((n,v) => n + (Number(v)||0), 0);
  return `<!doctype html><html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><style>@page{margin:0}*{box-sizing:border-box}html,body{margin:0;padding:0}body{width:${width}mm;padding:${width>100?18:3}mm;font:14px Arial;text-align:center;overflow-wrap:anywhere}h2{font-size:20px;margin:2mm 0}p{margin:2mm 0}</style><body><h2 dir="auto">${escape(value.name)}</h2><p dir="auto">${escape(value.className)}</p><p>${escape(value.date || new Date().toLocaleString())}</p><p>Cards accepted: ${value.rows.length}</p>${totals?`<p>Card points entered: ${escape(points)}</p>`:''}<p>Powered by YKonnect</p></body></html>`;
}
function setupReceiptPrinter({app, BrowserWindow, ipcMain, Notification}) {
  const file = () => path.join(app.getPath('userData'), 'receipt-printer.json');
  let settingsWindow, busy = false, failed = null, status = '';
  function settings() { try { const s=JSON.parse(fs.readFileSync(file(),'utf8'));return {deviceName:typeof s.deviceName==='string'?s.deviceName:'',width:s.width===58?58:80,format:formats.includes(s.format)?s.format:(s.width===58?'receipt58':s.width===80?'receipt80':'auto')}; } catch { return {deviceName:'',width:80,format:'auto'}; } }
  function report(message, error=false) {
    status=message;
    if(settingsWindow&&!settingsWindow.isDestroyed())settingsWindow.webContents.send('printer-status',{message,error});
    if(error&&Notification.isSupported())new Notification({title:'YKonnect receipt printer',body:message}).show();
  }
  async function print(value, totals) {
    const s=settings();
    const win=new BrowserWindow({show:false,webPreferences:{nodeIntegration:false,contextIsolation:true,sandbox:true}});
    try {
      const printers=await win.webContents.getPrintersAsync();
      const printer=s.deviceName?printers.find(p=>p.name===s.deviceName):printers.find(p=>p.isDefault);
      if(!printer)throw Error(s.deviceName?'The selected receipt printer is unavailable. Open Receipt printer from the tray.':'No default printer. Select a receipt printer from the tray.');
      const format=paperFormat(s,printer),width=format==='receipt58'?58:format==='receipt80'?80:format==='A4'?210:215.9;
      await win.loadURL('data:text/html;charset=utf-8,'+encodeURIComponent(receiptHTML(value,width,totals)));
      const px=await win.webContents.executeJavaScript('Math.max(document.body.scrollHeight,document.body.getBoundingClientRect().height)');
      const height=Math.max(50000,Math.ceil(px*25400/96)+3000);
      await new Promise((resolve,reject)=>win.webContents.print({silent:true,deviceName:printer.name,printBackground:true,margins:{marginType:'none'},pageSize:format==='Letter'||format==='A4'?format:{width:width*1000,height},copies:1},(ok,reason)=>ok?resolve():reject(Error(reason||'Print job failed'))));
      report('Receipt sent to '+(printer.displayName||printer.name)+'.');
    } finally {win.destroy();}
  }
  // Serialize jobs: each student's receipt keeps its own immutable values.
  let queue=Promise.resolve();
  function enqueue(value, totals, test=false) {
    const copy={...value,rows:[...value.rows],date:value.date||new Date().toLocaleString()};
    const job=queue.then(async()=>{busy=true;try{await print(copy,totals);return {ok:true};}catch(e){if(!test)failed={value:copy,totals};report('Receipt not printed: '+e.message,true);return {ok:false,error:e.message};}finally{busy=false;}});
    queue=job.catch(()=>{});return job;
  }
  function show() {
    if(settingsWindow&&!settingsWindow.isDestroyed()){settingsWindow.show();settingsWindow.focus();return;}
    settingsWindow=new BrowserWindow({width:560,height:600,resizable:true,autoHideMenuBar:true,title:'Receipt printer',webPreferences:{preload:path.join(__dirname,'printer-preload.cjs'),nodeIntegration:false,contextIsolation:true,sandbox:true}});
    settingsWindow.webContents.setWindowOpenHandler(()=>({action:'deny'}));
    settingsWindow.webContents.on('will-navigate',e=>e.preventDefault());
    settingsWindow.loadFile(path.join(__dirname,'printer.html'));
  }
  function authorized(event) {
    if(!settingsWindow||settingsWindow.isDestroyed()||event.sender!==settingsWindow.webContents||event.senderFrame?.url!==pathToFileURL(path.join(__dirname,'printer.html')).href)throw Error('Not allowed');
  }
  ipcMain.handle('printer-state',async e=>{authorized(e);return {settings:settings(),printers:(await settingsWindow.webContents.getPrintersAsync()).map(p=>({name:p.name,label:p.displayName||p.name,isDefault:p.isDefault})),status,failed:!!failed};});
  ipcMain.handle('printer-save',async(e,s)=>{authorized(e);if(!s||!formats.includes(s.format||('receipt'+s.width))||typeof s.deviceName!=='string')throw Error('Invalid printer settings');const printers=await settingsWindow.webContents.getPrintersAsync();if(s.deviceName&&!printers.some(p=>p.name===s.deviceName))throw Error('Printer unavailable');fs.writeFileSync(file(),JSON.stringify({deviceName:s.deviceName,format:s.format||('receipt'+s.width)}),{mode:0o600});report('Printer settings saved.');return {ok:true};});
  ipcMain.handle('printer-test',e=>{authorized(e);return enqueue({name:'YKonnect test receipt',className:'Receipt printer setup',rows:[10,20]},true,true);});
  ipcMain.handle('printer-retry',e=>{authorized(e);if(!failed)return {ok:false,error:'No failed receipt available.'};const job=failed;failed=null;return enqueue(job.value,job.totals);});
  return {show,enqueue,isBusy:()=>busy};
}
module.exports={setupReceiptPrinter,receiptHTML,paperFormat};

