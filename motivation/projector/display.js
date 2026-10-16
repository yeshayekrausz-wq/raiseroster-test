import {scheduleActive} from './schedule.js';
import {SUPABASE_URL,SUPABASE_KEY} from '../../shared/config.js';
const $=id=>document.getElementById(id),esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let db,org,program,workspace,roster,config,index=0,timer,refreshTimer,viewGeneration=0,scorePage=0,refreshing=false;
$('fullscreen').onclick=()=>document.documentElement.requestFullscreen().catch(()=>{});
function localDate(s){return new Intl.DateTimeFormat('en-US',{timeZone:s.timezone,month:'2-digit',day:'2-digit'}).format(new Date());}
function totals(){const students=roster.students.slice().sort((a,b)=>Number(workspace.totals[b.id]||0)-Number(workspace.totals[a.id]||0)||a.name.localeCompare(b.name,'he'));const pages=Math.max(1,Math.ceil(students.length/12)),page=scorePage++%pages;return `<div><h1 dir="auto">${esc(config?.name||'Hatzlacha')}</h1><p>${esc(config?.term_name||'')} · ${page+1}/${pages}</p><div class="scores">${students.slice(page*12,page*12+12).map(s=>`<div class="score"><span dir="auto">${esc(s.name)}</span><b>${esc(workspace.totals[s.id]||0)}</b></div>`).join('')}</div></div>`;}
async function show(){clearTimeout(timer);const token=++viewGeneration;if(!workspace)return;const s=workspace.settings;
 try{
 if(!s.display_enabled||!scheduleActive(s)){$('screen').innerHTML='<h1>Display paused</h1>';timer=setTimeout(show,10000);return;}
 const playlist=[...s.playlist];if(s.show_birthdays){const today=localDate(s),ids=workspace.birthdays.filter(x=>x.birthday?.slice(5).replace('-','/')===today).map(x=>x.id),names=roster.students.filter(x=>ids.includes(x.id)).map(x=>x.name);if(names.length)playlist.push({type:'text',text:'מזל טוב! '+names.join(' · '),seconds:10});}
 const slide=playlist[index++%playlist.length];let html='';
 if(slide.type==='totals')html=totals();else if(slide.type==='date')html='<div><h1>'+esc(new Intl.DateTimeFormat('en-US',{timeZone:s.timezone,dateStyle:'full'}).format(new Date()))+'</h1></div>';else if(slide.type==='text')html='<h1 dir="auto">'+esc(slide.text)+'</h1>';
 else{const {data,error}=await db.storage.from('motivation-media').createSignedUrl(slide.path,600);if(error)throw error;if(!data?.signedUrl?.startsWith('https://'))throw Error('Media URL unavailable');const video=slide.type.includes('video'),background=slide.type.startsWith('background_');html=(video?`<video class="${background?'background':'media'}" src="${esc(data.signedUrl)}" autoplay muted loop playsinline></video>`:`<img class="${background?'background':'media'}" src="${esc(data.signedUrl)}" alt="${esc(slide.text||'Display image')}">`)+(background?'<div class="shade"></div>'+totals():'');}
 if(token!==viewGeneration)return;$('screen').innerHTML=html;$('status').textContent='';timer=setTimeout(show,Number(slide.seconds)*1000);
 }catch(e){if(token!==viewGeneration)return;$('screen').textContent='Unable to display this slide.';$('status').textContent=e.message;timer=setTimeout(show,5000);}
}
async function refresh(){if(refreshing)return;refreshing=true;try{
 const responses=await Promise.all([db.rpc('rr_motivation_workspace',{p_org:org,p_program:program}),db.rpc('rr_motivation_roster',{p_org:org}),db.rpc('rr_motivation_list',{p_org:org})]);const failed=responses.find(x=>x.error);if(failed)throw failed.error;
 workspace=responses[0].data;roster=responses[1].data;config=responses[2].data.find(x=>x.id===program)?.config;if(!config)throw Error('Program unavailable');if(!timer)await show();
 if(!workspace.settings.display_enabled||!scheduleActive(workspace.settings))await show();
 }catch(e){workspace=null;clearTimeout(timer);timer=null;++viewGeneration;$('screen').textContent='Display unavailable. Sign in again or check the connection.';$('status').textContent=e.message||'Connection failed';}finally{refreshing=false;}}
try{const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');db=createClient(SUPABASE_URL,SUPABASE_KEY);const params=new URLSearchParams(location.search);org=params.get('org');program=params.get('program');if(!org||!program)throw Error('Open this display from Display Settings after choosing a program.');$('back').href='../admin/?org='+encodeURIComponent(org)+'#display';const {data,error}=await db.auth.getSession();if(error)throw error;if(!data.session)throw Error('Sign in to the school account first.');await refresh();refreshTimer=setInterval(refresh,30000);}catch(e){$('screen').textContent=e.message;}
window.addEventListener('pagehide',()=>{clearTimeout(timer);clearInterval(refreshTimer);});
