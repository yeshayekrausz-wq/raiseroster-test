export function initPhoneTest(host,{rpc,org,program}){
 host.innerHTML='<h2>Test phone</h2><p><strong>Simulation only — no real points or cards are changed.</strong> Uses saved phone permissions and the real reward rules. No phone provider is connected. Test calls expire after 15 minutes.</p><label>Calling phone number<input data-caller type="tel" autocomplete="off"></label><button type="button" data-start>Start test call</button><div data-call hidden><label>Keypad input<input data-digits inputmode="numeric" maxlength="6" autocomplete="off"></label><div data-keypad style="display:grid;grid-template-columns:repeat(3,minmax(50px,90px));gap:8px;margin:12px 0"></div><button type="button" data-end>End call</button></div><p data-status role="status" aria-live="polite"></p><ol data-log></ol><button type="button" data-history>Previous test calls</button><div data-history-list></div>';
 host.addEventListener('input',e=>e.stopPropagation());
 const el=s=>host.querySelector(s),status=el('[data-status]'),input=el('[data-digits]');let call=null,identified=false,busy=false,pending=null,callProgram=null;
 const log=(text,error=false)=>{status.textContent=text;status.style.color=error?'#b91c1c':'';const li=document.createElement('li');li.textContent=text;el('[data-log]').prepend(li);};
 const enable=()=>{host.querySelectorAll('button').forEach(b=>b.disabled=busy);input.disabled=busy;el('[data-caller]').disabled=busy||!!call;el('[data-start]').disabled=busy||!!call;};
 async function send(action,value=''){
  if(busy)return;
  const selected=program();if(!selected){log('Choose a program first.',true);return;}
  if(call&&selected!==callProgram){log('The selected program changed. Return to the original program to finish this test call, or refresh to start again.',true);return;}
  const payload={p_org:org,p_program:selected,p_call:action==='start'?null:call,p_action:action,p_value:value};
  if(pending&&JSON.stringify(pending.payload)!==JSON.stringify(payload)){log('Retry the same action first; its result is still uncertain.',true);return;}
  pending||={payload,id:crypto.randomUUID()};busy=true;enable();status.textContent='Checking…';
  try{
   const r=await rpc('rr_phone_test',{...payload,p_request:pending.id});pending=null;call=r.call;callProgram=selected;identified=r.identified;
   el('[data-call]').hidden=false;input.maxLength=identified?6:4;input.value='';input.setAttribute('aria-label',identified?'Six-digit card code':'Four-digit student ID');
   log((r.name?r.name+' — ':'')+r.message+(r.outcome==='accepted'?' · '+r.points+' points · '+(r.held?'On Hold':'Approved')+' (simulation)':''),r.outcome==='denied');
   if(r.outcome==='ended'){call=null;identified=false;el('[data-call]').hidden=true;}
  }catch(e){if(e.code)pending=null;log(e.code==='PGRST202'||e.code==='42883'?'Run Activate_Phone_Test.sql in Supabase first.':e.message||'Connection uncertain. Retry the same action.',true);}
  finally{busy=false;enable();if(call)input.focus();}
 }
 el('[data-history]').onclick=async()=>{if(busy)return;try{const rows=await rpc('rr_phone_test_history',{p_org:org,p_program:program()});const box=el('[data-history-list]');box.replaceChildren();for(const row of rows){const details=document.createElement('details'),title=document.createElement('summary');title.textContent=new Date(row.created_at).toLocaleString()+' — Simulation';details.append(title);for(const entry of row.history){const line=document.createElement('p');line.textContent=entry.action+': '+entry.result.message;details.append(line);}box.append(details);}if(!rows.length)box.textContent='No previous test calls.';}catch(e){log(e.message||'Could not load test history.',true);}};
 const submit=()=>{if(!call)return;const digits=input.value;if(!new RegExp('^[0-9]{'+(identified?6:4)+'}$').test(digits)){log('Enter exactly '+(identified?6:4)+' digits, then press #.',true);return;}send(identified?'card':'identify',digits);};
 el('[data-start]').onclick=()=>send('start',el('[data-caller]').value);
 el('[data-end]').onclick=()=>send('end');
 input.oninput=()=>{input.value=input.value.replace(/[^0-9]/g,'');};
 input.onkeydown=e=>{if(e.key==='Enter'||e.key==='#'){e.preventDefault();submit();}};
 for(const key of ['1','2','3','4','5','6','7','8','9','*','0','#']){const b=document.createElement('button');b.type='button';b.textContent=key;b.onclick=()=>{if(key==='#')submit();else if(key==='*')input.value='';else if(input.value.length<input.maxLength)input.value+=key;input.focus();};el('[data-keypad]').append(b);}
}
