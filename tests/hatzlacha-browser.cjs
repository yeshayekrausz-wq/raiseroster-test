const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs/promises'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const base=path.resolve(__dirname,'..');
const mock=`
window.state={programs:[],mode:window.testMode||'ok',saves:0};
const client={auth:{getSession:async()=>({data:{session:{user:{id:'user'}}}})},from(){const q={select(){return q},eq(){return q},then(ok,bad){return Promise.resolve({data:[{organization_id:'school-a',role:'admin'}]}).then(ok,bad)}};return q;},async rpc(name,args){
 if(state.mode==='missing')return {error:{code:'PGRST202'}};
 if(state.mode==='denied')return {error:{code:'42501',message:'School administrator access required'}};
 if(name==='rr_motivation_list')return {data:state.programs};
 if(state.mode==='conflict')return {error:{code:'40001'}};
 if(state.mode==='network')return {error:{message:'Network request failed'}};
 state.saves++;const id=args.p_id||'program-'+state.saves;const revision=args.p_expected_revision+1;
 state.programs=[{id,config:args.p_config,revision},...state.programs.filter(p=>p.id!==id)];return {data:{id,revision}};
 }};export function createClient(){return client;}`;
(async()=>{
 const server=http.createServer(async(req,res)=>{try{let p=decodeURIComponent(new URL(req.url,'http://local').pathname);if(p.endsWith('/'))p+='index.html';const file=path.join(base,p);if(!file.startsWith(base+path.sep))throw Error();res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(await fs.readFile(file));}catch{res.statusCode=404;res.end('Missing');}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-gpu','--no-zygote','--single-process'],headless:true});
 try{
 const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1365,height:1000}});
 await context.route('https://**/*',r=>r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:mock}):r.abort());
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const url='http://127.0.0.1:'+server.address().port+'/motivation/admin/?org=school-a';await page.goto(url);await page.locator('#workspace:not([hidden])').waitFor();
 await page.click('#newProgram');await page.fill('#termName','Winter');await page.fill('#startDate','2026-10-15');await page.fill('#endDate','2027-01-01');await page.fill('#targetPoints','1000');await page.click('#addSubject');
 await page.fill('.subject-name','חומש');await page.fill('.minimum','70');await page.fill('.points','5');await page.click('.add-band');await page.locator('.minimum').nth(1).fill('90');await page.locator('.points').nth(1).fill('10');
 for(const [score,points] of [['69','0'],['70','5'],['89.5','5'],['90','10'],['100','10']]){await page.fill('.try-score',score);assert.equal(await page.locator('output').innerText(),points+' points');}
 await page.fill('.try-score','101');assert.match(await page.locator('output').innerText(),/from 0 to 100/);
 await page.click('#save');await page.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('Program saved'));assert.equal(await page.locator('.program-choice').count(),1);assert.match(await page.locator('#revision').innerText(),/1/);
 await page.fill('.try-score','95');assert.equal(await page.locator('#dirtyLabel').innerText(),'');
 await page.fill('#programName','<img src=x onerror=alert(1)>');await page.click('#save');await page.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('Program saved'));assert.equal(await page.locator('.program-choice img').count(),0);
 await page.evaluate(()=>state.mode='conflict');await page.fill('#termName','Changed term');await page.click('#save');await page.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('Another administrator'));assert.equal(await page.inputValue('#termName'),'Changed term');
 page.once('dialog',d=>d.dismiss());await page.click('#newProgram');assert.equal(await page.inputValue('#termName'),'Changed term');
 await page.evaluate(()=>state.mode='network');await page.click('#save');await page.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('Network'));assert.equal(await page.inputValue('#termName'),'Changed term');
 await page.evaluate(()=>state.mode='ok');page.once('dialog',d=>d.accept());await page.click('#reload');await page.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('loaded'));assert.equal(await page.inputValue('#termName'),'Winter');
 await page.fill('#programName','הצלחה');await page.click('#save');await page.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('Program saved'));
 await page.screenshot({path:process.env.SCREENSHOT_PATH||'/tmp/hatzlacha-desktop.png',fullPage:true});
 await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);await page.screenshot({path:'/tmp/hatzlacha-mobile.png',fullPage:true});
 await page.addInitScript(()=>window.testMode='missing');await page.goto(url);await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('not activated'));assert.equal(await page.locator('#newProgram').isDisabled(),true);
 await page.addInitScript(()=>window.testMode='denied');await page.goto(url);await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('access required'));assert.equal(await page.locator('#workspace').isHidden(),true);
 assert.deepEqual(errors,[]);console.log('PASS Hatzlacha browser: rules/boundaries, save/reopen, safe text rendering, conflict/network edit retention, discard guard, preview without dirtying, mobile fit, missing/denied backend.');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exit(1);});
