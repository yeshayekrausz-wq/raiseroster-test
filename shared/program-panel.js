import {PROGRAMS, validatePrograms, missingProgramBackend} from './programs.js';
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function createProgramPanel(client, root) {
  let generation=0, current=null, dirty=false, saving=false;
  const status=(message,error=false)=>{
    const el=root.querySelector('[data-status]');
    if(el){el.textContent=message;el.className='notice'+(error?' error':'');}
  };
  async function render(org) {
    const token=++generation;current=null;dirty=false;
    root.innerHTML='<p role="status">Loading school programs…</p>';
    try {
      const {data,error}=await client.rpc('rr_sa_get_program_settings',{p_org:org});
      if(token!==generation)return;
      if(error)throw error;
      const programs=validatePrograms(data.programs);
      if(!Number.isSafeInteger(data.revision)||data.revision<0)throw new Error('Invalid settings version.');
      current={org,revision:data.revision};
      root.innerHTML=`<h3>Programs in this school’s menu</h3>
        <p class="statusNote">Choose which programs appear in the school’s launcher. This does not revoke access to existing data or direct portal links. School permissions still apply.</p>
        <form data-program-form>
        ${PROGRAMS.map(p=>`<label class="rrRow" style="cursor:pointer"><span class="grow"><b>${p.name}</b> <span class="pill ${p.ready?'pACTIVE':'pTRIAL'}">${p.ready?'Available':'In preparation'}</span><span style="display:block;font-size:13px;color:var(--muted)">${p.description}</span></span><span><input type="checkbox" name="${p.key}" style="width:auto" ${programs[p.key]?'checked':''}> Show in menu</span></label>`).join('')}
        <label for="programReason">Reason for change</label>
        <input id="programReason" maxlength="500" required placeholder="For example: school requested the Motivation menu">
        <div class="row" style="margin-top:12px"><button class="btn primary" type="submit">Save program menu</button><button class="btn" type="button" data-reload>Reload saved settings</button></div>
        <div data-status role="status" aria-live="polite"></div></form>
        <h3>Program menu history</h3>
        <div>${(data.history||[]).map(h=>`<div class="rrRow"><div class="grow"><b>${esc(h.actor_label||'Administrator')}</b> · ${esc(new Date(h.created_at).toLocaleString())}<div>${esc(h.reason)}</div><div class="statusNote">${PROGRAMS.filter(p=>h.before?.[p.key]!==h.after?.[p.key]).map(p=>`${p.name}: ${h.before?.[p.key]?'shown':'hidden'} → ${h.after?.[p.key]?'shown':'hidden'}`).join(' · ')}</div></div></div>`).join('')||'<p>No program menu changes yet.</p>'}</div>`;
      const form=root.querySelector('form');
      form.oninput=()=>{dirty=true;};
      root.querySelector('[data-reload]').onclick=()=>{if(!dirty||confirm('Discard unsaved program settings?'))render(org);};
      form.onsubmit=async event=>{
        event.preventDefault();if(saving||token!==generation)return;
        const reason=root.querySelector('#programReason').value.trim();
        if(!reason){status('Enter a reason for the change.',true);return;}
        const programs=Object.fromEntries(PROGRAMS.map(p=>[p.key,form.elements.namedItem(p.key).checked]));
        saving=true;form.querySelectorAll('button,input').forEach(el=>el.disabled=true);status('Saving…');
        try {
          const {error}=await client.rpc('rr_sa_set_program_settings',{p_org:org,p_programs:programs,p_reason:reason,p_expected_revision:current.revision});
          if(error)throw error;
          if(token!==generation)return;
          dirty=false;await render(org);status('Program menu saved. History has been recorded.');
        }catch(error){if(token===generation)status(error.code==='40001'?'Another administrator changed these settings. Reload saved settings before trying again.':error.message||'Unable to save. Your changes are still here.',true);}
        finally{saving=false;if(token===generation)form.querySelectorAll('button,input').forEach(el=>el.disabled=false);}
      };
    } catch(error) {
      if(token!==generation)return;
      root.innerHTML=`<div class="notice error" role="alert">${esc(missingProgramBackend(error)?'Program menu settings are not activated yet. Ask the platform administrator to complete setup. No settings have been changed.':error.message||'Unable to load program settings.')}</div><button class="btn" data-retry>Try again</button>`;
      root.querySelector('[data-retry]').onclick=()=>render(org);
    }
  }
  window.addEventListener('beforeunload',e=>{if(dirty||saving){e.preventDefault();e.returnValue='';}});
  return {render,isDirty:()=>dirty,isSaving:()=>saving,reset:()=>{generation++;dirty=false;current=null;}};
}
