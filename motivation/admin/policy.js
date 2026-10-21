const $=id=>document.getElementById(id);
export function initCardPolicy(rpc,org){
 let saved=null,busy=false,dirty=false;
 const panels=[['dailyPanel','Daily card limit','dailyCap','Cards per student / program each day',1000,'Blank means no daily limit. The counter restarts at midnight in the school timezone. The weekly limit still applies, including to class overrides.']];
 for(const [panel,title,input,label,max,note] of panels){
  $(panel).innerHTML=`<h2>${title}</h2><form><label>${label}<input id="${input}" type="number" min="1" max="${max}" step="1"></label><p>${note}</p><button type="submit" disabled>Save</button> <button type="button" data-reload>Reload</button><p role="status"></p></form>`;
  $(panel).oninput=()=>dirty=true;
  $(panel).querySelector('[data-reload]').onclick=()=>{if(!dirty||confirm('Discard unsaved daily limit changes?'))load();};
  $(panel).querySelector('form').onsubmit=async e=>{e.preventDefault();if(busy||!saved)return;
   if(!panels.every(x=>$(x[2]).reportValidity()))return;
   busy=true;buttons();status('Saving…');
   try{saved=await rpc('rr_motivation_policy_save',{p_org:org,p_daily:$('dailyCap').value===''?null:Number($('dailyCap').value),p_expiry:null,p_revision:saved.revision});dirty=false;status('Saved. Daily limits apply immediately. Reward cards never expire.');}
   catch(e){status(e.code==='40001'?'Rules changed elsewhere. Your entries are kept. Reload before editing again.':e.message||'Could not save. Reload to check the saved values.');}
   finally{busy=false;buttons();}
  };
 }
 function status(text){panels.forEach(x=>$(x[0]).querySelector('[role=status]').textContent=text);}
 function buttons(){panels.forEach(x=>{const p=$(x[0]);p.querySelector('[type=submit]').disabled=busy||!saved;p.querySelector('[data-reload]').disabled=busy;$(x[2]).disabled=busy;});}
 async function load(){if(busy)return;busy=true;buttons();status('Loading…');try{saved=await rpc('rr_motivation_policy_read',{p_org:org});$('dailyCap').value=saved.daily_cap??'';dirty=false;status('Saved rules loaded.');}catch(e){saved=null;status(['PGRST202','42883'].includes(e.code)?'Run the new card policy activation SQL to enable these settings.':e.message||'Could not load rules.');}finally{busy=false;buttons();}}
 window.addEventListener('beforeunload',e=>{if(dirty||busy){e.preventDefault();e.returnValue='';}});
 load();
}
