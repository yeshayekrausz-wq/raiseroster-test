import {initAccountProfile} from './account.js';
import {initNavigation} from './navigation.js';
import {initWorkspace} from './workspace.js';
import {initRoster} from './roster.js';
import {SUPABASE_URL,SUPABASE_KEY} from '../../shared/config.js';
import {resolveMembership} from '../../shared/membership.js';
const $=id=>document.getElementById(id);
let authBlocked=false,authUser=null;
function lockAuth(message){authBlocked=true;document.body.setAttribute('data-auth-locked','');for(const d of document.querySelectorAll('dialog[open]'))d.close();for(const el of document.querySelectorAll('[popover]')){if(el.matches(':popover-open'))el.hidePopover();}$('authGateMessage').textContent=message;}
let db,org,programs=[],selected=null,dirty=false,busy=false;
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function status(text,error=false){$('status').textContent=text;$('status').className=error?'error':'';}
function feedback(text,kind=''){$('saveStatus').textContent=text;$('saveStatus').className=kind;}
function changed(){dirty=true;$('dirtyLabel').textContent='Unsaved changes';feedback('');}
function mayLeave(){return !busy&&(!dirty||confirm('Discard your unsaved changes?'));}
function setBusy(value){busy=value;for(const id of ['fields','save','reload','newProgram'])$(id).disabled=value;document.querySelectorAll('.program-choice').forEach(b=>b.disabled=value);}
function list(){
 $('programList').innerHTML=programs.length?programs.map(p=>`<button type="button" class="program-choice ${p.id===selected?.id?'selected':''}" data-id="${esc(p.id)}"><strong dir="auto">${esc(p.config.name)}</strong><small dir="auto">${esc(p.config.term_name)}</small><small>${esc(p.config.start_date)} → ${esc(p.config.end_date)}</small></button>`).join(''):'<p class="muted">No programs yet.</p>';
 $('programList').querySelectorAll('button').forEach(b=>b.onclick=()=>{if(mayLeave())open(programs.find(p=>p.id===b.dataset.id));});
}
function bandMarkup(b={}){return `<div class="band"><input aria-label="Minimum score" class="minimum" type="number" min="0" max="10000" step="any" required placeholder="Minimum" value="${esc(b.minimum)}"><input aria-label="Points awarded" class="points" type="number" min="0" max="1000000" step="any" required placeholder="Points" value="${esc(b.points)}"><button class="remove remove-band" type="button" aria-label="Remove score rule">×</button></div>`;}
function addSubject(subject={name:'',max_score:'',bands:[{}]}){
 const el=document.createElement('section');el.className='subject';
 el.innerHTML=`<div class="subject-top"><h3>Subject rules</h3><button class="remove remove-subject" type="button">Remove subject</button></div><div class="grid"><label>Subject name<input class="subject-name" dir="auto" maxlength="80" required  value="${esc(subject.name)}"></label><label>Maximum exam score<input class="max-score" type="number" min="1" max="10000" step="any" required value="${esc(subject.max_score)}"></label></div><div class="bands"><div class="band-head"><span>Minimum score</span><span>Points awarded</span><span></span></div><div class="band-rows">${subject.bands.map(bandMarkup).join('')}</div></div><button class="add-band" type="button">+ Add score rule</button><div class="preview"><label>Try an exam score<input class="try-score" type="number" min="0" step="any" placeholder="Test score"></label><output aria-live="polite">Enter a score to preview</output></div>`;
 el.querySelector('.remove-subject').onclick=()=>{el.remove();changed();};
 el.querySelector('.add-band').onclick=()=>{if(el.querySelectorAll('.band').length>=50){feedback('Maximum 50 rules per subject.','error');return;}el.querySelector('.band-rows').insertAdjacentHTML('beforeend',bandMarkup());changed();preview(el);};
 el.addEventListener('click',e=>{const button=e.target.closest('.remove-band');if(button){button.closest('.band').remove();changed();preview(el);}});
 el.addEventListener('input',()=>preview(el));$('subjects').append(el);
}
function readSubject(el){
 const name=el.querySelector('.subject-name').value.trim(),max=Number(el.querySelector('.max-score').value);
 if(!name||!el.querySelector('.max-score').value||!Number.isFinite(max)||max<1||max>10000)throw Error('Enter a subject name and a valid maximum score.');
 const bands=[...el.querySelectorAll('.band')].map(row=>{
  const a=row.querySelector('.minimum'),b=row.querySelector('.points'),minimum=Number(a.value),points=Number(b.value);
  if(a.value===''||b.value===''||!Number.isFinite(minimum)||minimum<0||minimum>max||!Number.isFinite(points)||points<0||points>1000000)throw Error('Complete each rule with a valid minimum score and points.');
  return {minimum,points};
 }).sort((a,b)=>a.minimum-b.minimum);
 if(!bands.length)throw Error('Add at least one score rule, or remove this subject.');
 if(bands.some((b,i)=>i&&b.minimum===bands[i-1].minimum))throw Error('Each minimum score must be different.');
 return {name,max_score:max,bands};
}
function preview(el){
 const output=el.querySelector('output'),input=el.querySelector('.try-score');
 if(input.value===''){output.textContent='Enter a score to preview';return;}
 try{const subject=readSubject(el),score=Number(input.value);if(!Number.isFinite(score)||score<0||score>subject.max_score)throw Error(`Enter a score from 0 to ${subject.max_score}.`);
 const match=subject.bands.filter(b=>score>=b.minimum).at(-1);output.textContent=`${match?.points??0} points`;}
 catch(e){output.textContent=e.message;}
}
function open(program){
 selected=program||null;const c=program?.config||{name:'',term_name:'',start_date:'',end_date:'',target_points:null,subjects:[]};
 for(const [id,key] of [['programName','name'],['termName','term_name'],['startDate','start_date'],['endDate','end_date'],['targetPoints','target_points']])$(id).value=c[key]??'';
 $('subjects').replaceChildren();c.subjects.forEach(addSubject);$('empty').hidden=true;$('editor').hidden=false;
 $('editorTitle').textContent=program?'Edit Hatzlacha program':'New Hatzlacha program';$('revision').textContent=program?`Saved version ${program.revision}`:'';
 dirty=false;$('dirtyLabel').textContent='';feedback('');list();
}
async function load(){const {data,error}=await db.rpc('rr_motivation_list',{p_org:org});if(error)throw error;if(!Array.isArray(data))throw Error('Invalid response. Please reload.');programs=data;list();}
$('newProgram').onclick=()=>{if(mayLeave()){open(null);location.hash='settings/general';$('programName').focus();}};
$('addSubject').onclick=()=>{if($('subjects').children.length>=30){feedback('Maximum 30 subjects.','error');return;}addSubject();changed();};
$('editor').addEventListener('input',e=>{if(!e.target.classList.contains('try-score'))changed();});
$('reload').onclick=async()=>{if(!mayLeave())return;setBusy(true);const id=selected?.id;try{await load();open(programs.find(p=>p.id===id));feedback('Saved version loaded.');}catch(e){feedback(e.message||'Unable to reload. Your edits are still here.','error');}finally{setBusy(false);}};
$('editor').onsubmit=async e=>{
 e.preventDefault();if(busy)return;
 try{
 const config={name:$('programName').value.trim(),term_name:$('termName').value.trim(),start_date:$('startDate').value,end_date:$('endDate').value,target_points:$('targetPoints').value===''?null:Number($('targetPoints').value),subjects:[...$('subjects').children].map(readSubject)};
 if(!config.name||!config.term_name)throw Error('Enter the program and term names.');
 if(!config.start_date||!config.end_date||config.end_date<config.start_date)throw Error('Enter valid term dates, with the end on or after the start.');
 if(new Set(config.subjects.map(s=>s.name.toLowerCase())).size!==config.subjects.length)throw Error('Use a different name for each subject.');
 setBusy(true);feedback('Saving…');
 const {data,error}=await db.rpc('rr_motivation_save',{p_org:org,p_id:selected?.id??null,p_config:config,p_expected_revision:selected?.revision??0});
 if(error)throw error;
 const saved={id:data.id,organization_id:org,product_key:'hatzlacha',config,revision:data.revision};
 programs=[saved,...programs.filter(p=>p.id!==saved.id)];open(saved);window.dispatchEvent(new Event('motivation-programs-changed'));feedback('Program saved. Your exam rules are ready.','success');
 }catch(e){feedback(e.code==='40001'?'Another administrator changed this program. Your edits are still here. Reload the saved version before editing again.':e.message||'Unable to save. Your edits are still here.','error');}
 finally{setBusy(false);}
};
window.addEventListener('beforeunload',e=>{if(dirty||busy){e.preventDefault();e.returnValue='';}});
document.querySelectorAll('header a, .adminSidebar a[href="../../#home"]').forEach(a=>a.addEventListener('click',e=>{if(!mayLeave())e.preventDefault();}));
window.addEventListener('keydown',e=>{if(document.body.hasAttribute('data-auth-locked')){e.stopImmediatePropagation();}},true);
window.addEventListener('pagehide',()=>document.body.setAttribute('data-auth-locked',''));
window.addEventListener('pageshow',e=>{if(e.persisted)location.reload();});
initNavigation();
try{
 const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');db=createClient(SUPABASE_URL,SUPABASE_KEY);
 const {data,error}=await db.auth.getSession();if(error)throw error;
 db.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||(authUser&&session?.user?.id!==authUser))lockAuth('Your session ended. Sign in again to continue.');});
 if(!data.session){lockAuth('Please sign in to continue.');location.replace('../../#motivation');}else{
 const verified=await db.auth.getUser();if(verified.error||!verified.data?.user)throw Error('Sign-in could not be verified. Please sign in again.');authUser=verified.data.user.id;if(authUser!==data.session.user.id)throw Error('Session changed. Reload and sign in again.');
 const member=await resolveMembership(db,data.session.user.id,new URLSearchParams(location.search).get('org'));
 if(!member||!['admin','super_admin'].includes(member.role))throw Error('This workspace requires a school administrator account.');
 org=member.organization_id;await load();if(authBlocked)throw Error('Session ended. Please sign in again.');const roster=initRoster(db,org);initWorkspace(db,org,roster);initAccountTools();initAccountProfile(db,org,member.role).catch(e=>status(e.message,true));window.dispatchEvent(new Event('motivation-navigation'));$('newProgram').disabled=false;status('Connected to your school.');if(!authBlocked)document.body.removeAttribute('data-auth-locked');
 }
}catch(e){lockAuth(e.message||'Access could not be verified. Reload or sign in again.');$('rosterStatus').textContent=e.message||'Unable to connect. Reload or sign in through All programs.';status(e.code==='PGRST202'||e.code==='42883'?'Hatzlacha setup is not activated in the database yet. Ask your platform administrator to run the Hatzlacha setup SQL, then reload.':e.message||'Unable to connect. Please reload.',true);}

let currentRoute='',currentHash=location.hash||'#dashboard';
function route(){
 const routes={eligibility:'eligibilityView',dashboard:'rosterView',students:'studentsView',settings:'settingsView',documents:'documentsView',reports:'reportsView',display:'displayView',phone:'phoneView',support:'supportView',faq:'faqView',training:'trainingView',teachers:'teachersView'};const key=location.hash.slice(1).split('/')[0];const next=routes[key]?key:'dashboard';
 if(currentRoute&&next!==currentRoute&&!mayLeave()){history.replaceState(null,'',currentHash);window.dispatchEvent(new Event('motivation-navigation'));return;}
 if(currentRoute&&next!==currentRoute&&!window.dispatchEvent(new CustomEvent('motivation-section-leave',{cancelable:true,detail:{from:currentRoute,to:next}}))){history.replaceState(null,'',currentHash);window.dispatchEvent(new Event('motivation-navigation'));return;}
 if(currentRoute==='settings'&&next!=='settings'&&dirty)open(selected);
 const entering=next!==currentRoute;
 // Main-menu links already target section roots; preserve explicit nested links such as planner week folders.
 currentRoute=next;currentHash=location.hash||'#dashboard';$('programBar').hidden=!['dashboard','students'].includes(next);for(const [key,id] of Object.entries(routes))$(id).hidden=key!==next;document.querySelectorAll('.adminSidebar a[href^="#"]').forEach(a=>a.classList.toggle('active',a.hash.split('/')[0]==='#'+next));
 if(entering)window.dispatchEvent(new CustomEvent('motivation-section-enter',{detail:next}));
 $('navDashboard').classList.toggle('active',next==='dashboard');$('navSettings').classList.toggle('active',next==='settings');window.dispatchEvent(new Event('motivation-navigation'));
}
window.addEventListener('hashchange',route);route();

function initAccountTools(){
 $('notificationBell').innerHTML='<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg>';
 $('adminSignOut').onclick=async()=>{const {error}=await db.auth.signOut();if(error){alert(error.message);return;}lockAuth('Signed out.');location.href='../../';};
 $('notificationBell').onclick=async()=>{const panel=$('notificationList');panel.hidden=!panel.hidden;if(panel.hidden)return;panel.textContent='Loading…';const {data,error}=await db.from('admin_notifications').select('id,title,body,created_at,read_at').order('created_at',{ascending:false}).limit(50);if(error){panel.textContent='Notifications could not load. '+error.message;return;}panel.innerHTML='<strong>Notifications</strong>'+((data||[]).map(n=>'<article><b>'+esc(n.title)+'</b><p>'+esc(n.body)+'</p><small>'+esc(new Date(n.created_at).toLocaleString())+'</small></article>').join('')||'<p>No notifications.</p>');};
 document.addEventListener('click',e=>{if(!e.target.closest('.accountTools'))$('notificationList').hidden=true;});
}
