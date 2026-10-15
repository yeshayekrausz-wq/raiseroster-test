const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs/promises'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const base=path.resolve(__dirname,'..');
const mock=`
window.state={mode:window.testMode||'ok',calls:[],students:[{id:'a',name:'Aaron Cohen',class_id:'class-a',phone:'3471234567'},{id:'b',name:'Binyomin Green',class_id:'class-a',phone:''},{id:'c',name:'Chaim Weiss',class_id:'class-b',phone:''}]};
const client={auth:{getSession:async()=>({data:{session:{user:{id:'user'}}}})},from(){const q={select(){return q},eq(){return q},then(ok,bad){return Promise.resolve({data:[{organization_id:'school-a',role:'admin'}]}).then(ok,bad)}};return q;},async rpc(name,args){
 if(name==='rr_motivation_list')return {data:[]};
 if(name==='rr_motivation_roster'){if(state.mode==='missing')return {error:{code:'PGRST202'}};if(state.mode==='denied')return {error:{code:'42501',message:'Access denied'}};return {data:{classes:[{id:'class-a',name:'ז א'},{id:'class-b',name:'ז ב'}],students:state.students}};}
 if(name==='rr_motivation_add_student'){state.calls.push(args);if(state.mode==='network')return {error:{message:'Network request failed'}};if(state.mode==='duplicate')return {error:{code:'23505'}};state.students.push({id:'new',name:args.p_name,phone:args.p_phone,class_id:args.p_class});return {data:{student_id:'new',created:true}};}
 return {data:{}};
 }};export function createClient(){return client;}`;
(async()=>{
 const server=http.createServer(async(req,res)=>{try{let p=decodeURIComponent(new URL(req.url,'http://local').pathname);if(p.endsWith('/'))p+='index.html';const file=path.join(base,p);if(!file.startsWith(base+path.sep))throw Error();res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(await fs.readFile(file));}catch{res.statusCode=404;res.end('Missing');}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-gpu','--no-zygote','--single-process'],headless:true});
 try{
 const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1440,height:1000}});
 await context.route('https://**/*',r=>r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:mock}):r.abort());
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));const url='http://127.0.0.1:'+server.address().port+'/motivation/admin/?org=school-a';
 await page.goto(url);await page.locator('#rosterContent:not([hidden])').waitFor();assert.equal(await page.locator('#studentCount').innerText(),'3');
 await page.fill('#studentSearch','347123');await page.press('#studentSearch','ArrowDown');await page.press('#studentSearch','Enter');assert.equal(await page.locator('#profileName').innerText(),'Aaron Cohen');assert.equal(await page.inputValue('#studentSearch'),'');
 await page.keyboard.down('Shift');await page.locator('#profileNavigator:not([hidden])').waitFor();await page.keyboard.press('ArrowDown');await page.keyboard.up('Shift');assert.equal(await page.locator('#profileName').innerText(),'Binyomin Green');
 await page.keyboard.down('Shift');await page.keyboard.press('ArrowRight');await page.keyboard.up('Shift');assert.equal(await page.locator('#profileName').innerText(),'Chaim Weiss');
 await page.keyboard.down('Shift');await page.keyboard.press('ArrowLeft');await page.keyboard.press('Escape');await page.keyboard.up('Shift');assert.equal(await page.locator('#profileName').innerText(),'Chaim Weiss');assert.equal(await page.locator('#studentProfile').isVisible(),true);
 await page.keyboard.press('Escape');assert.equal(await page.locator('#studentProfile').isVisible(),false);
 await page.locator('[data-class="class-a"]').click();assert.equal(await page.locator('#classStudents button').count(),2);
 await page.screenshot({path:'/tmp/motivation-dashboard.png',fullPage:true});
 await page.click('#showAddStudent');await page.fill('#newStudentName','New Student');await page.fill('#newStudentPhone','3475551234');assert.equal(await page.inputValue('#newStudentClass'),'class-a');
 await page.evaluate(()=>state.mode='network');await page.click('#saveStudent');await page.waitForFunction(()=>document.querySelector('#addStatus').textContent.includes('Network'));assert.equal(await page.inputValue('#newStudentName'),'New Student');const key=await page.evaluate(()=>state.calls[0].p_request);
 await page.evaluate(()=>state.mode='ok');await page.click('#saveStudent');await page.waitForFunction(()=>document.querySelector('#profileName').textContent==='New Student');assert.equal(await page.evaluate(()=>state.calls[1].p_request),key);assert.equal(await page.locator('#studentCount').innerText(),'4');
 await page.keyboard.down('Shift');await page.screenshot({path:'/tmp/motivation-shift.png',fullPage:true});await page.keyboard.up('Shift');await page.click('#closeProfile');
 await page.click('#showAddStudent');await page.fill('#newStudentName','Aaron Cohen');await page.selectOption('#newStudentClass','class-a');await page.evaluate(()=>state.mode='duplicate');await page.click('#saveStudent');await page.waitForFunction(()=>document.querySelector('#addStatus').textContent.includes('already exists'));assert.equal(await page.inputValue('#newStudentName'),'Aaron Cohen');page.once('dialog',d=>d.accept());await page.click('#cancelAdd');
 await page.click('#navSettings');await page.waitForFunction(()=>!document.querySelector('#settingsView').hidden);await page.click('#newProgram');await page.fill('#termName','Unsaved');page.once('dialog',d=>d.dismiss());await page.click('#navDashboard');await page.waitForTimeout(100);assert.match(page.url(),/#settings/);assert.equal(await page.locator('#settingsView').isHidden(),false);
 page.once('dialog',d=>d.accept());await page.click('#navDashboard');await page.waitForFunction(()=>!document.querySelector('#rosterView').hidden);
 await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);await page.screenshot({path:'/tmp/motivation-mobile.png',fullPage:true});
 await page.addInitScript(()=>window.testMode='missing');await page.goto(url);await page.waitForFunction(()=>document.querySelector('#rosterStatus').textContent.includes('not activated'));assert.equal(await page.locator('#rosterContent').isHidden(),true);
 await page.addInitScript(()=>window.testMode='denied');await page.goto(url);await page.waitForFunction(()=>document.querySelector('#rosterStatus').textContent.includes('Access denied'));assert.equal(await page.locator('#rosterContent').isHidden(),true);
 assert.deepEqual(errors,[]);console.log('PASS roster browser: name/phone search, Enter, classes, Shift student/class navigation, Esc cancel, shared add, same-request retry, duplicate retention, settings discard guard, mobile fit, backend failure states.');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exit(1);});
