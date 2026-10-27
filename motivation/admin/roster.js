const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const lastName=s=>{const p=s.trim().split(/\s+/);return (p.pop()||'')+' '+p.join(' ');};
const digits=s=>String(s||'').replace(/\D/g,'');
const phone=s=>{const n=digits(s);return n.length===10?`(${n.slice(0,3)}) ${n.slice(3,6)}-${n.slice(6)}`:n;};
export function initRoster(db,org){
 let students=[],classes=[],currentClass=null,currentStudent=null,results=[],searchIndex=-1,nav=null,suppressed=false,adding=false,loading=false,request=null,totals={},heldTotals={},onProfile=()=>{},onLoaded=()=>{};
 const group=id=>students.filter(s=>(s.class_id||'unassigned')===id);
 const status=(text,error=false)=>{$('rosterStatus').textContent=text;$('rosterStatus').className=error?'error':'';};
 function render(){
  $('studentCount').textContent=students.length;$('classCount').textContent=classes.filter(c=>c.id!=='unassigned').length;
  $('classes').innerHTML=classes.map(c=>`<button class="classbox" data-class="${esc(c.id)}"><b dir="auto">${esc(c.name)}</b><small>${group(c.id).length} students</small></button>`).join('')||'<p>No active classes. Set up the school year and classes in Campaign Admin first.</p>';
  $('classes').querySelectorAll('button').forEach(b=>b.onclick=()=>openClass(b.dataset.class));
  if(currentClass&&classes.some(c=>c.id===currentClass))openClass(currentClass);else $('classPanel').hidden=true;
  $('allStudents').innerHTML=studentButtons(students);bindStudents($('allStudents'));search();
 }
 function studentButtons(rows){return rows.map(s=>`<button class="studentrow" data-student="${esc(s.id)}"><span dir="auto">${esc(s.name)}</span><small dir="ltr">#${esc(s.short_id||'')} · ${esc([s.phone,s.home_phone,s.father_phone,s.mother_phone,s.other_phone].filter(Boolean).map(phone).join(' / '))}</small><small dir="ltr">${totals[s.id]===undefined?'—':esc(totals[s.id])} approved · ${esc(heldTotals[s.id]||0)} on Hold</small><small dir="auto">${esc(classes.find(c=>c.id===(s.class_id||'unassigned'))?.name||'')}</small></button>`).join('');}
 function bindStudents(parent){parent.querySelectorAll('[data-student]').forEach(b=>b.onclick=()=>openStudent(b.dataset.student));}
 function openClass(id){currentClass=id;$('rosterContent').classList.add('classFocused');$('allStudentsPanel').hidden=true;$('classTitle').textContent=classes.find(c=>c.id===id)?.name||'';$('classStudents').innerHTML=studentButtons(group(id))||'<p>No students in this class.</p>';bindStudents($('classStudents'));$('classPanel').hidden=false;$('classPanel').scrollIntoView({block:'start',behavior:'smooth'});}
 function clearSearch(){$('studentSearch').value='';$('searchResults').hidden=true;$('studentSearch').setAttribute('aria-expanded','false');$('studentSearch').removeAttribute('aria-activedescendant');results=[];searchIndex=-1;}
 function openStudent(id){
  const s=students.find(s=>s.id===id);if(!s)return;currentStudent=s;
  $('profileName').textContent=s.name+ (s.short_id?' · #'+s.short_id:'');$('profileClass').textContent='כתה '+(classes.find(c=>c.id===(s.class_id||'unassigned'))?.name||'Unassigned');
  $('profilePhones').innerHTML=[['Main phone',s.phone],['Home',s.home_phone],['Father',s.father_phone],['Mother',s.mother_phone],['Additional',s.other_phone]].filter(([,n])=>n).map(([label,n])=>`<p>${label}: <span dir="ltr">${esc(phone(n))}</span></p>`).join('')||'<p>No phone numbers saved.</p>';
  $('profileAddress').textContent=s.address?'Address: '+s.address:'Address: —';$('profileExtra').innerHTML=[['Birth date',s.gregorian_birthday],['Hebrew birthday',s.hebrew_birthday],['Notes',s.notes]].filter(([,v])=>v).map(([label,value])=>`<p><strong>${label}:</strong> <span dir="auto" class="profileDetail">${esc(value)}</span></p>`).join('');
  clearSearch();if(!$('studentProfile').open)$('studentProfile').showModal();$('closeProfile').focus();onProfile(s,true);
 }
 function search(){
  const q=$('studentSearch').value.trim().toLocaleLowerCase(),n=digits(q);searchIndex=-1;$('studentSearch').removeAttribute('aria-activedescendant');
  if(!q){results=[];$('searchResults').hidden=true;$('studentSearch').setAttribute('aria-expanded','false');return;}
  results=students.filter(s=>s.name.toLocaleLowerCase().includes(q)||String(s.short_id||'')===q||(n.length>0&&[s.phone,s.home_phone,s.father_phone,s.mother_phone,s.other_phone].some(p=>digits(p).includes(n))));
  $('searchResults').innerHTML=results.length?studentButtons(results):'<p>No matching students.</p>';
  [...$('searchResults').querySelectorAll('button')].forEach((b,i)=>{b.id='search-option-'+i;b.setAttribute('role','option');b.setAttribute('aria-selected','false');b.tabIndex=-1;});bindStudents($('searchResults'));
  $('searchResults').hidden=false;$('studentSearch').setAttribute('aria-expanded','true');
 }
 $('studentSearch').oninput=search;
 $('studentSearch').onkeydown=e=>{
  if(e.ctrlKey||e.metaKey||e.altKey||e.shiftKey)return;
  if(['ArrowDown','ArrowUp','ArrowLeft','ArrowRight'].includes(e.key)&&results.length){e.preventDefault();const step=e.key==='ArrowUp'||e.key==='ArrowRight'?-1:1;searchIndex=searchIndex<0?0:Math.max(0,Math.min(results.length-1,searchIndex+step));
   $('searchResults').querySelectorAll('button').forEach((b,i)=>{b.classList.toggle('selected',i===searchIndex);b.setAttribute('aria-selected',String(i===searchIndex));});const b=$('searchResults').querySelectorAll('button')[searchIndex];$('studentSearch').setAttribute('aria-activedescendant',b.id);b.scrollIntoView({block:'nearest'});
  }else if(e.key==='Enter'&&results.length){e.preventDefault();openStudent(results[Math.max(0,searchIndex)].id);}else if(e.key==='Escape')clearSearch();
 };
 async function refresh(){
  if(loading)return;loading=true;$('refreshRoster').disabled=true;status('Loading school students…');
  try{const {data,error}=await db.rpc('rr_motivation_roster_v5',{p_org:org});if(error)throw error;
   if(!Array.isArray(data?.classes)||!Array.isArray(data?.students))throw Error('Invalid roster response.');
   classes=data.classes;students=data.students.sort((a,b)=>lastName(a.name).localeCompare(lastName(b.name),'he')||a.id.localeCompare(b.id));
   if(students.some(s=>!s.class_id))classes.push({id:'unassigned',name:'Unassigned'});
   $('rosterContent').hidden=false;render();status('Shared school roster · '+students.length+' students');onLoaded();window.dispatchEvent(new Event('motivation-roster-refreshed'));return true;
  }catch(e){$('rosterContent').hidden=true;status(e.code==='PGRST202'||e.code==='42883'?'Shared students are not activated yet. Run the Stage 5 activation SQL, then press Refresh students.':e.message||'Unable to load students. Try Refresh students.',true);return false;}
  finally{loading=false;$('refreshRoster').disabled=false;}
 }
 $('refreshRoster').onclick=refresh;$('closeClass').onclick=()=>{$('rosterContent').classList.remove('classFocused');$('classPanel').hidden=true;$('allStudentsPanel').hidden=true;currentClass=null;};
 const navigator=$('profileNavigator');navigator.setAttribute('popover','manual');document.body.append(navigator);
 function finish(commit){const choice=nav;nav=null;if(navigator.matches(':popover-open'))navigator.hidePopover();$('profileNavigator').hidden=true;if(commit&&choice&&(choice.id!==currentStudent?.id||!$('studentProfile').open))openStudent(choice.id);}
 function closeProfile(){finish(false);$('studentProfile').close();currentStudent=null;$('studentSearch').focus();}
 $('closeProfile').onclick=closeProfile;
 $('studentProfile').addEventListener('cancel',e=>{e.preventDefault();if(nav){finish(false);suppressed=true;}else closeProfile();});
 function drawNav(){const rows=group(nav.class_id);$('navClass').textContent=classes.find(c=>c.id===nav.class_id)?.name||'';
  $('navStudents').innerHTML=rows.map((s,i)=>`<div id="nav-student-${i}" class="nav-row ${s.id===nav.id?'selected':''}" role="option" aria-selected="${s.id===nav.id}"><span>#${esc(s.short_id||'')}</span><span dir="auto">${esc(s.name)}</span></div>`).join('');const selected=$('navStudents').querySelector('.selected');if(selected){$('navStudents').setAttribute('aria-activedescendant',selected.id);selected.scrollIntoView({block:'nearest'});}}
 function begin(){if(nav||suppressed||!students.length)return;const pupil=currentStudent||group(currentClass)[0]||students[0];nav={id:pupil.id,class_id:pupil.class_id||'unassigned'};$('profileNavigator').hidden=false;navigator.showPopover();drawNav();}
 document.addEventListener('keydown',e=>{
  if(e.target.id!=='scanCode'&&e.target.closest?.('input,textarea,select,[contenteditable=true],[role=textbox]')){finish(false);if(e.shiftKey)suppressed=true;return;}
  if(e.altKey&&e.key==='1'&&!adding&&!$('addStudentDialog').open&&!$('rosterView').hidden){e.preventDefault();if($('studentProfile').open)closeProfile();$('studentSearch').focus();return;}
  if([...document.querySelectorAll('dialog[open]')].some(d=>d.id!=='studentProfile'))return;
  if(e.ctrlKey||e.metaKey||e.altKey||e.isComposing){finish(false);if(e.shiftKey)suppressed=true;return;}
  if(e.key==='Shift'){begin();return;}
  if(e.key==='Escape'&&nav){e.preventDefault();e.stopImmediatePropagation();finish(false);suppressed=true;return;}
  if(!e.shiftKey)return;
  if(!['ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(e.key)){finish(false);suppressed=true;return;}
  begin();if(!nav)return;e.preventDefault();
  if(e.key==='ArrowUp'||e.key==='ArrowDown'){const rows=group(nav.class_id),i=rows.findIndex(s=>s.id===nav.id),next=rows[i+(e.key==='ArrowDown'?1:-1)];if(next)nav.id=next.id;}
  else{const step=e.key==='ArrowRight'?1:-1;for(let i=classes.findIndex(c=>c.id===nav.class_id)+step;i>=0&&i<classes.length;i+=step){const rows=group(classes[i].id);if(rows.length){nav={class_id:classes[i].id,id:rows[0].id};break;}}}drawNav();
 },true);
 document.addEventListener('keyup',e=>{if(e.key==='Shift'&&!e.shiftKey){finish(true);suppressed=false;}},true);
 const cancelNav=()=>{finish(false);suppressed=false;};window.addEventListener('blur',cancelNav);document.addEventListener('visibilitychange',()=>{if(document.hidden)cancelNav();});
 $('profileNavigator').onpointerdown=e=>e.preventDefault();
 window.addEventListener('motivation-section-enter',e=>{if(e.detail==='dashboard'){$('closeClass').click();clearSearch();}});
 function addDirty(){return $('newStudentName').value.trim()||$('newStudentPhone').value.trim();}
 function closeAdd(){if(adding)return;if(addDirty()&&!confirm('Discard the new student details?'))return;$('addStudentDialog').close();}
 $('classAddStudent').onclick=()=>{$('showAddStudent').click();};
 $('showAddStudent').onclick=()=>{
  $('addStudentForm').reset();request=null;$('addStatus').textContent='';$('newStudentClass').innerHTML='<option value="">Choose a class</option>'+classes.filter(c=>c.id!=='unassigned').map(c=>`<option value="${esc(c.id)}">${esc(c.name)}</option>`).join('');
  if(currentClass&&currentClass!=='unassigned')$('newStudentClass').value=currentClass;$('addStudentDialog').showModal();$('newStudentName').focus();
 };
 $('cancelAdd').onclick=closeAdd;$('addStudentDialog').addEventListener('cancel',e=>{e.preventDefault();closeAdd();});
 $('newStudentPhone').addEventListener('blur',()=>{$('newStudentPhone').value=phone($('newStudentPhone').value);});
 $('addStudentForm').onsubmit=async e=>{
  e.preventDefault();if(adding)return;
  const payload={p_org:org,p_class:$('newStudentClass').value,p_name:$('newStudentName').value.trim().replace(/\s+/g,' '),p_phone:digits($('newStudentPhone').value)};
  if(!payload.p_name||!payload.p_class){$('addStatus').textContent='Enter a name and choose a class.';return;}
  if(payload.p_phone&&(payload.p_phone.length<7||payload.p_phone.length>15)){$('addStatus').textContent='Enter a valid phone number, or leave it blank.';return;}
  const fingerprint=JSON.stringify(payload);if(!request||request.fingerprint!==fingerprint)request={fingerprint,id:crypto.randomUUID()};
  adding=true;$('addFields').disabled=true;$('saveStudent').disabled=true;$('cancelAdd').disabled=true;$('addStatus').textContent='Saving…';
  try{const {data,error}=await db.rpc('rr_motivation_add_student',{...payload,p_request:request.id});if(error)throw error;
   $('addStudentForm').reset();$('addStudentDialog').close();const loaded=await refresh();if(loaded){status('Student saved to the shared school roster.');openStudent(data.student_id);}else status('Student saved, but the roster could not reload. Press Refresh students; do not add again.',true);
  }catch(e){$('addStatus').textContent=e.code==='23505'?'This name already exists in this class. Select the existing student.':e.message||'Not confirmed saved. Your details are kept; retry to check the same request.';}
  finally{adding=false;$('addFields').disabled=false;$('saveStudent').disabled=false;$('cancelAdd').disabled=false;}
 };
 window.addEventListener('beforeunload',e=>{if(adding||($('addStudentDialog').open&&addDirty())){e.preventDefault();e.returnValue='';}});
 refresh();
 return {refresh,getStudents:()=>students,getClasses:()=>classes,getCurrent:()=>currentStudent,getClass:()=>currentClass,openStudent,setTotals(value,held={}){totals=value;heldTotals=held;$('schoolPointSummary').textContent=Object.values(value).reduce((a,b)=>a+Number(b),0)+' approved · '+Object.values(held).reduce((a,b)=>a+Number(b),0)+' on Hold';render();if(currentStudent)onProfile(currentStudent);},onProfile(fn){onProfile=fn;},onLoaded(fn){onLoaded=fn;}};
}
