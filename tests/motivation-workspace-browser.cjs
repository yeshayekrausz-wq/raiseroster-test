const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs/promises'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const base=path.resolve(__dirname,'..');
const mock=`
const settings={cards_enabled:true,weekly_cap:12,reveal_next_day:false,teacher_cards:true,phone_frozen:true,allow_home:true,allow_father:false,allow_mother:false,allow_other:false,blocked_students:[],display_enabled:true,timezone:'America/New_York',display_start:'00:00',display_end:'00:00',display_days:[0,1,2,3,4,5,6],show_birthdays:false,playlist:[{type:'totals',text:'',path:'',seconds:15},{type:'date',text:'',path:'',seconds:5}]};
window.state={mode:'ok',calls:[],students:[{id:'a',name:'Aaron Cohen',class_id:'class-a',phone:'3471234567'},{id:'b',name:'Binyomin Green',class_id:'class-a',phone:''},{id:'c',name:'Chaim Weiss',class_id:'class-b',phone:''}],classes:[{id:'class-a',name:'ז א'},{id:'class-b',name:'ז ב'}],programs:[{id:'program-a',config:{name:'Hatzlacha',term_name:'Winter',subjects:[{name:'Chumash',max_score:100,bands:[{minimum:90,points:10}]}]}}],workspace:{settings,revision:0,totals:{a:20,b:10,c:0},cards:[],birthdays:[]},events:[]};
const client={storage:{from(){return {upload:async()=>({data:{}}),createSignedUrl:async()=>({data:{signedUrl:'https://example.test/media.png'}})}}},auth:{getSession:async()=>({data:{session:{user:{id:'user'}}}})},from(){const q={select(){return q},eq(){return q},then(ok,bad){return Promise.resolve({data:[{organization_id:'school-a',role:'admin'}]}).then(ok,bad)}};return q;},async rpc(name,args){
 if(name==='rr_motivation_list')return {data:state.programs};
 if(name==='rr_motivation_roster')return {data:{classes:state.classes,students:state.students}};
 if(name==='rr_motivation_workspace')return {data:structuredClone(state.workspace)};
 if(name==='rr_motivation_report')return {data:state.events.filter(e=>!args.p_filters.student||e.student_id===args.p_filters.student)};
 if(name==='rr_motivation_command'){
 state.calls.push(args);if(state.mode==='error')return {error:{message:'Connection failed'}};const d=args.p_data;
 if(args.p_action==='points')state.workspace.totals[d.student]=(state.workspace.totals[d.student]||0)+d.points;
 if(args.p_action==='exam')state.workspace.totals[d.student]=(state.workspace.totals[d.student]||0)+10;
 if(args.p_action==='settings'){state.workspace.settings=d.settings;state.workspace.revision++;}
 if(args.p_action==='bulk_students')for(const r of d.rows){Object.assign(state.students.find(s=>s.id===r.id),{name:r.name,phone:r.phone,class_id:r.class_id});}
 if(args.p_action==='class_rename')state.classes.find(c=>c.id===d.class_id).name=d.name;
 if(args.p_action==='cards')state.workspace.cards.push({id:'card-a',code:'ABC123',batch_id:'batch-a',points:d.points,status:'available',class_id:d.class_id});
 state.events.unshift({id:state.events.length+1,student_id:d.student,student_name:state.students.find(s=>s.id===d.student)?.name||'',class_name:'ז א',kind:args.p_action,outcome:'accepted',created_at:new Date().toISOString(),detail:d});
 return {data:{outcome:'accepted',message:'Saved'}};
 }return {data:[]};
 }};export function createClient(){return client;}`;
(async()=>{
 const server=http.createServer(async(req,res)=>{try{let p=decodeURIComponent(new URL(req.url,'http://local').pathname);if(p.endsWith('/'))p+='index.html';const file=path.join(base,p);if(!file.startsWith(base+path.sep))throw Error();res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(await fs.readFile(file));}catch{res.statusCode=404;res.end('Missing');}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-gpu','--no-zygote','--single-process'],headless:true});
 try{
 const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1440,height:1000}});
 await context.route('https://**/*',r=>r.request().url().includes('supabase-js')?r.fulfill({contentType:'text/javascript',body:mock}):r.abort());
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));const url='http://127.0.0.1:'+server.address().port+'/motivation/admin/?org=school-a';

 await page.addInitScript(()=>window.print=()=>{window.printed=true;});
 await page.goto(url);await page.waitForFunction(()=>document.querySelector('#workspaceMessage').textContent==='Program ready',null,{timeout:5000}).catch(async e=>{console.log(await page.locator('body').innerText(),errors);throw e;});
 assert.match(await page.locator('#allStudents').innerText(),/20 pts/);
 await page.locator('#allStudents [data-student="a"]').click();await page.click('#studentPoints');await page.fill('#awardPoints','5');await page.fill('#awardReason','Participation');await page.click('#taskSave');await page.waitForFunction(()=>document.querySelector('#profilePoints').textContent==='25 points');
 await page.click('#studentExam');await page.fill('#examScore','95');await page.fill('#examReason','Week 1');await page.click('#taskSave');await page.waitForFunction(()=>document.querySelector('#profilePoints').textContent==='35 points');
 await page.click('#studentLog');await page.waitForFunction(()=>document.querySelector('#personalLog').textContent.includes('Week 1'));assert.match(await page.locator('#personalLog').innerText(),/Participation/);
 await page.click('#studentEdit');await page.fill('.edit-name','Aaron Edited');await page.click('#taskSave');await page.waitForFunction(()=>document.querySelector('#profileName').textContent==='Aaron Edited');await page.click('#closeProfile');
 await page.locator('[data-class="class-a"]').click();await page.click('#bulkEdit');assert.equal(await page.locator('[data-edit-id]').count(),2);await page.locator('.edit-phone').nth(1).fill('3475551111');await page.click('#taskSave');await page.waitForFunction(()=>!document.querySelector('#taskDialog').open);
 await page.click('#renameClass');await page.fill('#classNewName','ז חדש');await page.click('#taskSave');await page.waitForFunction(()=>document.querySelector('#classTitle').textContent==='ז חדש');
 await page.screenshot({path:'/tmp/stage4-dashboard.png',fullPage:true});
 await page.locator('a[href="#documents"]').click();await page.click('#generateCards');await page.fill('#cardCount','2');await page.fill('#cardPoints','7');await page.click('#taskSave');await page.waitForFunction(()=>document.querySelector('#cardList').textContent.includes('ABC123'));
 await page.click('#printCards');assert.match(await page.locator('#printArea').textContent(),/ABC123/);assert.doesNotMatch(await page.locator('#printArea').textContent(),/7 points/);
 await page.click('#printIDs');assert.match(await page.locator('#printArea').textContent(),/Aaron Edited/);await page.emulateMedia({media:'print'});await page.pdf({path:'/tmp/stage4-id-cards.pdf',format:'A4',printBackground:true});await page.emulateMedia({media:'screen'});
 await page.locator('a[href="#reports"]').click();await page.click('#loadLog');await page.waitForFunction(()=>document.querySelector('#logTable').textContent.includes('Participation'));const dl=page.waitForEvent('download');await page.click('#exportLog');assert.equal((await dl).suggestedFilename(),'motivation-log.csv');
 await page.locator('a[href="#display"]').click();await page.fill('#schoolTimezone','America/New_York');await page.click('#addSlide');await page.locator('.slide-text').last().fill('School message');await page.locator('#displayPanel [data-save-settings]').click();await page.waitForFunction(()=>document.querySelector('#workspaceMessage').textContent==='Settings saved.');
 const display=await context.newPage();await display.goto(url.replace('/admin/','/projector/')+'&program=program-a');await display.waitForFunction(()=>document.querySelector('#screen').textContent.includes('Aaron Cohen'));await display.screenshot({path:'/tmp/stage4-projector.png',fullPage:true});await display.close();
 await page.locator('a[href="#phone"]').click();assert.match(await page.locator('#phoneView').innerText(),/not connected/);await page.check('[data-setting="allow_father"]');await page.locator('#phonePanel [data-save-settings]').click();await page.waitForFunction(()=>document.querySelector('#workspaceMessage').textContent==='Settings saved.');assert.equal(await page.evaluate(()=>state.workspace.settings.allow_father),true);
 await page.setViewportSize({width:390,height:844});await page.locator('#navDashboard').click();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);await page.screenshot({path:'/tmp/stage4-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS Stage 4 browser: points/exams, student log/edit, bulk edit, class rename, cards/print, report export, display playlist/projector, phone preferences, mobile layout.');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exit(1);});
