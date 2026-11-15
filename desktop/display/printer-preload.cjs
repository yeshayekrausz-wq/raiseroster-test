const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('receiptPrinter',Object.freeze({state:()=>ipcRenderer.invoke('printer-state'),save:s=>ipcRenderer.invoke('printer-save',s),test:()=>ipcRenderer.invoke('printer-test'),retry:()=>ipcRenderer.invoke('printer-retry'),onStatus:fn=>ipcRenderer.on('printer-status',(_e,s)=>fn(s))}));
