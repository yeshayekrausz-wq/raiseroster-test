// PLAYWRIGHT_MODULE and CHROMIUM_MODULE can point to externally installed dependencies.
const {chromium:pw}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const chromiumImport=require(process.env.CHROMIUM_MODULE||'@sparticuz/chromium');
const chromium=chromiumImport.default||chromiumImport;
const fs=require('node:fs/promises'), http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const base=path.resolve(__dirname,'..');
const mock=`
const state=window.testState={mode:window.testMode||'ok',revision:0,programs:{campaigns:true,motivation:true,library:false},history:[],calls:[]};
const orgs=[{id:'school-a',name:'Alpha School',status:'ACTIVE',created_at:'2026-01-01'},{id:'school-b',name:'Beta School',status:'SUSPENDED',created_at:'2026-01-02'}];
const members=[{organization_id:'school-a',user_id:'platform',role:'super_admin'},{organization_id:'school-a',user_id:'school-user',role:'admin'},{organization_id:'school-b',user_id:'platform',role:'admin'}];
const users=[{id:'platform',name:'Platform Owner',email:'owner@example.test'},{id:'school-user',name:'School User',email:'school@example.test'}];
const client={auth:{getSession:async()=>({data:{session:{user:{id:'platform',email:'owner@example.test'}}}}),onAuthStateChange:()=>{},signOut:async()=>({}),signInWithPassword:async()=>({})},
 functions:{invoke:async(name,{body})=>{state.calls.push(body);return {data:body.action==='list_users'?{users}:{}};}},
 from(table){let data=table==='organizations'?orgs:table==='organization_members'?members:[];const q={select(){return q},eq(k,v){data=data.filter(r=>r[k]===v);return q},in(k,v){data=data.filter(r=>v.includes(r[k]));return q},order(){return q},limit(){return q},then(ok,bad){return Promise.resolve({data}).then(ok,bad)}};return q;},
 async rpc(name,args){
   if(name.startsWith('rr_')&&state.mode==='missing')return {error:{code:'PGRST202',message:'Function missing'}};
   if(name.startsWith('rr_')&&state.mode==='denied')return {error:{code:'42501',message:'Permission denied'}};
   if(name==='rr_sa_get_program_settings')return {data:{programs:state.programs,revision:state.revision,history:state.history}};
   if(name==='rr_sa_set_program_settings'){
     if(state.mode==='conflict')return {error:{code:'40001',message:'Changed'}};
     state.history.unshift({actor_label:'owner@example.test',reason:args.p_reason,before:state.programs,after:args.p_programs,created_at:new Date().toISOString()});state.programs=args.p_programs;state.revision++;return {data:{changed:true}};
   }
   if(name==='rr_school_program_menu')return {data:state.programs};
   if(name==='sa_org_overview')return {data:{campaigns:[],user_count:2,student_count:0,active_campaign_total:0}};
   return {data:[]};
 }};
export function createClient(){return client;}`;
(async()=>{
 const server=http.createServer(async(req,res)=>{try{let p=decodeURIComponent(new URL(req.url,'http://local').pathname);if(p.endsWith('/'))p+='index.html';const file=path.join(base,p);if(!file.startsWith(base+path.sep))throw Error();res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(await fs.readFile(file));}catch{res.statusCode=404;res.end('Not found');}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await pw.launch({executablePath:process.env.CHROMIUM_PATH||await chromium.executablePath(),args:['--no-sandbox','--disable-gpu','--no-zygote','--single-process'],headless:true});
 try{
 const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1365,height:900}});
 await context.route('https://**/*',route=>route.request().url().includes('supabase-js')?route.fulfill({contentType:'text/javascript',body:mock}):route.abort());
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const url='http://127.0.0.1:'+server.address().port;
 await page.goto(url+'/superadmin/#accounts');await page.locator('#accountsBody tr').first().waitFor();
 assert.equal(await page.locator('#accountsBody tr').count(),2);
 await page.selectOption('#accountFilter','SUSPENDED');assert.match(await page.locator('#accountsBody').innerText(),/Beta School/);assert.doesNotMatch(await page.locator('#accountsBody').innerText(),/Alpha School/);
 await page.click('.nav [data-page="users"]');await page.fill('#userSearch','school@example.test');assert.equal(await page.locator('#usersBody tr').count(),1);
 await page.click('#usersBody .uMng');await page.click('#detailTabs [data-tab="programs"]');await page.locator('#programReason').waitFor();
 await page.uncheck('[name="motivation"]');await page.fill('#programReason','School requested fewer menus');await page.click('[data-program-form] button[type="submit"]');
 await page.waitForFunction(()=>document.querySelector('[data-status]')?.textContent.includes('saved'));
 assert.match(await page.locator('#dPrograms').innerText(),/School requested fewer menus/);assert.equal(await page.isChecked('[name="motivation"]'),false);
 // Failed save keeps edits; stale-version feedback is explicit.
 await page.evaluate(()=>testState.mode='conflict');await page.check('[name="library"]');await page.fill('#programReason','Add library');await page.click('[data-program-form] button[type="submit"]');await page.waitForFunction(()=>document.querySelector('[data-status]')?.textContent.includes('Another administrator'));
 assert.equal(await page.isChecked('[name="library"]'),true);
 page.once('dialog',d=>d.dismiss());await page.click('.nav [data-page="accounts"]');await page.waitForTimeout(100);assert.match(page.url(),/#detail/);
 page.once('dialog',d=>d.accept());await page.click('.nav [data-page="accounts"]');await page.waitForURL('**/#accounts');
 await page.selectOption('#accountFilter','');await page.locator('#accountsBody .acctManage').first().click();await page.click('#detailTabs [data-tab="users"]');
 await page.locator('[data-uid="school-user"].uRole').click();assert.equal(await page.inputValue('#selectedRole'),'admin');
 await page.selectOption('#selectedRole','super_admin');page.once('dialog',d=>d.dismiss());await page.click('#saveRole');assert.equal(await page.evaluate(()=>testState.calls.filter(c=>c.action==='set_role').length),0);
 await page.click('#closeModalBtn');
 await page.click('#detailTabs [data-tab="programs"]');
 if(process.env.SCREENSHOT_PATH)await page.screenshot({path:process.env.SCREENSHOT_PATH,fullPage:true});
 // Hub uses live settings on subsequent hash navigation in this test client.
 await page.goto(url+'/');await page.locator('#workspace:not([hidden])').waitFor();await page.waitForFunction(()=>document.querySelector('#programs').textContent.includes('Campaigns'));
 await page.evaluate(()=>{testState.programs.motivation=false;document.querySelector('#schoolSelect').dispatchEvent(new Event('change'));});
 await page.waitForFunction(()=>!document.querySelector('#programs').textContent.includes('Motivation'));
 await page.evaluate(()=>location.hash='motivation');await page.waitForFunction(()=>document.querySelector('#workspaceStatus').textContent.includes('not shown'));
 // Permission errors do not silently fall back to enabled menus.
 await page.evaluate(()=>{testState.mode='denied';document.querySelector('#schoolSelect').dispatchEvent(new Event('change'));});await page.waitForFunction(()=>document.querySelector('#workspaceStatus').textContent.includes('Permission denied'));
 assert.equal(await page.locator('#programs a').count(),0);
 // Only missing RPC keeps legacy defaults, and setup is clear in Super Admin.
 await page.addInitScript(()=>window.testMode='missing');await page.goto(url+'/');await page.waitForFunction(()=>document.querySelector('#programs').textContent.includes('Campaigns'));
 await page.goto(url+'/superadmin/#detail/school-a');await page.click('#detailTabs [data-tab="programs"]');await page.waitForFunction(()=>document.querySelector('#dPrograms').textContent.includes('not activated'));
 assert.equal(await page.locator('#dPrograms button[type="submit"]').count(),0);
 assert.deepEqual(errors,[]);
 console.log('PASS: browser account filter, user search, program save/history, conflict retention, unsaved navigation, role elevation cancellation, hub visibility, fail-closed errors, missing-backend setup.');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exit(1)});
