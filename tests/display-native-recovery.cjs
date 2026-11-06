const assert=require('node:assert/strict'),{EventEmitter}=require('node:events');
const attach=require('../desktop/display/recovery.cjs');
let seq=0;const pending=new Map(),timers={setTimeout(fn,ms){pending.set(++seq,{fn,ms});return seq;},clearTimeout(id){pending.delete(id);}};
const win=new EventEmitter();win.webContents=new EventEmitter();let current='',loads=0,fallbacks=0;win.isDestroyed=()=>false;win.webContents.getURL=()=>current;win.loadURL=async url=>{current=url;loads++;};win.loadFile=async()=>{current='file:///recovery.html';fallbacks++;};
const player=attach(win,{url:'https://raiseroster.com/motivation/display/?desktop=1',fallback:'recovery.html',timers});
function advance(ms){const entry=[...pending].find(([,v])=>v.ms===ms);assert(entry,'Expected scheduled retry '+ms);pending.delete(entry[0]);entry[1].fn();}
player.load();win.webContents.emit('did-fail-load',{},-105,'NAME_NOT_RESOLVED',current,true);assert.equal(fallbacks,1);win.webContents.emit('did-fail-load',{},-105,'duplicate',current,true);assert.equal(fallbacks,1);advance(15000);assert.equal(loads,2);win.webContents.emit('did-finish-load');assert.equal(pending.size,0);
win.webContents.emit('did-fail-load',{},-105,'iframe','https://drive.google.com/',false);assert.equal(fallbacks,1);
win.webContents.emit('render-process-gone');assert.equal(fallbacks,2);advance(15000);advance(25000);assert.equal(fallbacks,3);advance(30000);win.webContents.emit('did-finish-load');assert.equal(pending.size,0);
win.webContents.emit('render-process-gone');win.emit('closed');assert.equal(pending.size,0);
console.log('PASS native navigation failure, bounded retries, load timeout, crash recovery, iframe isolation and cleanup');
