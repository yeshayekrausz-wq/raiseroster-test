import {createClient} from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import {SUPABASE_URL,SUPABASE_KEY} from './config.js';
import {readSchoolMenu} from './programs.js';
const db=createClient(SUPABASE_URL,SUPABASE_KEY);
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let user=null, members=[], schools=[], generation=0, menuGeneration=0, schoolMenu=null;
const icon={campaigns:'<path d="M5 22V12h5v10M13 22V7h5v15M21 22V3h5v19M3 27h26"/>',motivation:'<path d="m16 3 4 8 9 1-6.5 6.5 1.5 9L16 23l-8 4.5 1.5-9L3 12l9-1z"/>',admin:'<rect x="4" y="4" width="24" height="24" rx="4"/><path d="M4 12h24M13 12v16"/>',projector:'<rect x="3" y="4" width="26" height="18" rx="3"/><path d="M16 22v7M10 29h12"/>'};
const svg=k=>'<span class="icon"><svg viewBox="0 0 32 32" aria-hidden="true">'+icon[k]+'</svg></span>';
function card(key,title,body,href,tag='',gold=false){return '<a class="program '+(gold?'gold':'')+'" href="'+esc(href)+'">'+svg(key)+(tag?'<span class="tag">'+esc(tag)+'</span>':'')+'<h2>'+esc(title)+'</h2><p>'+esc(body)+'</p><span class="arrow">Open '+esc(title)+' →</span></a>';}
function selected(){return members.find(m=>m.organization_id===$('schoolSelect').value);}
function draw(){
 if(!user)return;
 const member=selected(), org=member?.organization_id;
 const isSuper=members.some(m=>m.role==='super_admin');
 $('platform').hidden=!isSuper;
 const school=schools.find(s=>s.id===org);
 $('schoolName').textContent=school?.name||'YOUR WORKSPACE';
 const route=location.hash.replace(/^#/,'')||'home';
 $('breadcrumb').innerHTML=route==='home'?'':'<a href="#home">← All programs</a>';
 $('viewTitle').textContent=route==='campaigns'?'Campaigns':route==='motivation'?'Motivation':'Your programs';
 $('viewIntro').textContent=route==='home'?'Choose a program to get started.':'Choose your workspace.';
 $('programs').innerHTML='';
 if(!member){$('workspaceStatus').textContent='No school membership is assigned to this account. Contact your administrator.';return;}
 // Stage 1 does not expose legacy full-admin pages to teacher/staff roles.
 if(!['admin','super_admin'].includes(member.role)){
  $('workspaceStatus').textContent='Your account is connected. Your class-specific staff portal is not available yet. Contact your administrator.';return;
 }
 $('workspaceStatus').textContent='';
 if(!schoolMenu){$('workspaceStatus').textContent='Loading school programs…';return;}
 if(route==='campaigns'&&!schoolMenu.campaigns||route==='motivation'&&!schoolMenu.motivation){$('workspaceStatus').textContent='This program is not shown in your school menu. Contact your administrator.';return;}
 const suffix='?org='+encodeURIComponent(org)+'&hub=1';
 if(route==='campaigns'){
  $('programs').innerHTML=card('admin','Admin portal','Manage students, contributions, reports and campaign settings.','./admin/'+suffix)+card('projector','Projector portal','Open the live campaign display.','./projector/'+suffix);
 }else if(route==='motivation'){
  $('programs').innerHTML=card('admin','Admin portal','Open school students, class lists and Hatzlacha program settings.','./motivation/admin/'+suffix,'Program setup')+card('projector','Projector portal','The motivation display is being prepared.','./motivation/projector/'+suffix,'In preparation',true);
 }else{
  if(route!=='home')history.replaceState(null,'','#home');
  $('programs').innerHTML=(schoolMenu.campaigns?card('campaigns','Campaigns','Your fundraising workspace, student accounts and live projector display.','#campaigns','Available'):'')+(schoolMenu.motivation?card('motivation','Motivation','A collection of motivation programs, starting with Hatzlacha.','#motivation','Program setup'):'')+(schoolMenu.library?'<article class="program"><span class="tag">In preparation</span><h2>Library</h2><p>Books, student cards and lending. This program is not available yet.</p></article>':'');
  if(!Object.values(schoolMenu).some(Boolean))$('workspaceStatus').textContent='No programs are shown in this school’s menu. Contact your administrator.';
 }
}
async function loadSchoolMenu(){
 const token=++menuGeneration;schoolMenu=null;draw();
 const org=selected()?.organization_id;if(!org)return;
 try{const result=await readSchoolMenu(db,org);if(token!==menuGeneration)return;schoolMenu=result.programs;draw();}
 catch(error){if(token===menuGeneration){$('programs').innerHTML='';$('workspaceStatus').textContent='Unable to load school programs. '+(error.message||'Please reload.');}}
}
async function refresh(){
 const token=++generation;
 const {data,error}=await db.auth.getSession();if(error)throw error;
 user=data.session?.user||null;
 $('loading').hidden=true;$('login').hidden=!!user;$('workspace').hidden=true;$('sessionActions').hidden=!user;
 if(!user){members=[];schools=[];schoolMenu=null;++menuGeneration;return;}
 $('signedIn').textContent=user.email||'Signed in';
 const r=await db.from('organization_members').select('organization_id,role').eq('user_id',user.id);
 if(token!==generation)return;if(r.error)throw r.error;
 members=r.data||[];
 schools=[];
 if(members.length){const result=await db.from('organizations').select('id,name').in('id',members.map(m=>m.organization_id));if(result.error)throw result.error;schools=result.data||[];}
 if(token!==generation)return;
 const previous=sessionStorage.getItem('rr-school:'+user.id);
 $('schoolSelect').replaceChildren();
 for(const m of members){const option=document.createElement('option');option.value=m.organization_id;option.textContent=schools.find(s=>s.id===m.organization_id)?.name||'School';$('schoolSelect').append(option);}
 if(members.some(m=>m.organization_id===previous))$('schoolSelect').value=previous;
 $('schoolChoice').hidden=members.length<2;$('workspace').hidden=false;await loadSchoolMenu();
}
function report(error){$('loading').hidden=false;$('loadingText').textContent=error.message||'Unable to load your workspace.';$('retry').hidden=false;$('workspace').hidden=true;}
$('schoolSelect').onchange=()=>{sessionStorage.setItem('rr-school:'+user.id,$('schoolSelect').value);loadSchoolMenu();};
$('loginForm').onsubmit=async event=>{
 event.preventDefault();$('loginSubmit').disabled=true;$('loginStatus').textContent='Signing in…';
 try{const {error}=await db.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value});if(error)throw error;$('password').value='';$('loginStatus').textContent='';await refresh();}
 catch(error){if($('login').hidden)report(error);else $('loginStatus').textContent=error.message;}
 finally{$('loginSubmit').disabled=false;}
};
$('signOut').onclick=async()=>{try{const {error}=await db.auth.signOut();if(error)throw error;await refresh();}catch(error){report(error);}};
window.addEventListener('hashchange',draw);
db.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT')setTimeout(()=>refresh().catch(report),0);});
await refresh();
