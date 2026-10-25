const $=id=>document.getElementById(id);
const icons={general:'M4 5h16M4 12h16M4 19h16M8 3v4M16 10v4M10 17v4',conditions:'m4 12 5 5L20 6',cards:'M3 5h18v14H3zM7 9h6M7 14h10',limits:'M5 4v16M19 4v16M5 12h14',schedule:'M4 5h16v16H4zM8 3v4M16 3v4M4 10h16',scanning:'M3 7V3h4M17 3h4v4M21 17v4h-4M7 21H3v-4M7 7v10M11 7v10M15 7v10M18 7v10'};
const icon=key=>`<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${(icons[key]||icons.general).split('|').map(d=>`<path d="${d}"/>`).join('')}</svg>`;
const categories=[['planner','Planner','Plan targets, card values and automatic weekly releases.'],['general','General','Program name, term dates and points target.'],['conditions','Conditions','Subjects, exam scores and points rules.'],['cards','Cards','Card rules and point visibility.'],['limits','Limits','Daily and weekly card limits.'],['schedule','Schedule','Week boundaries and school timezone.'],['scanning','Scanning','Scanner input and confirmation sounds.'],['reset','Reset','Delete Motivation test cards, points and logs.']];
const titles={planner:'Planner',weeks:'Program weeks',new:'New cards',saved:'Saved orders',ids:'Student cards',eligibility:'Eligibility',reset:'Reset',settings:'Program Settings',dashboard:'Dashboard',documents:'Documents',reports:'Reports',display:'Display Settings',phone:'Phone Settings',teachers:'Teacher Portals',support:'Support',faq:'Questions & Answers',training:'Training',general:'General',conditions:'Conditions',exams:'Exams',cards:'Cards',limits:'Limits',schedule:'Schedule',week:'Week',timezone:'Timezone',scanning:'Scanning',slides:'Slides',media:'Media',devices:'Computers',numbers:'Numbers',freeze:'Freeze',layout:'Layout',daily:'Daily',weekly:'Weekly',expiry:'Expiry',rules:'Rules'};
function tiles(parent,root,items){parent.innerHTML=items.map(([key,label,description])=>`<article class="settingChoice"><a class="settingTile" href="#${root}/${key}">${icon(key)}<span>${label}</span><span class="tileArrow" aria-hidden="true">›</span></a><p>${description}</p></article>`).join('');}
export function initNavigation(){
 const settings=$('settingsView');const heading=document.createElement('div');heading.id='settingsHeading';heading.innerHTML='<h1 id="settingsTitle">Program Settings</h1><p id="settingsDescription">Choose a category to continue.</p>';settings.prepend(heading);
 const menu=document.createElement('div');menu.id='settingsMenu';menu.className='settingsMenu';heading.after(menu);
 const general=$('programName').closest('.grid');general.id='generalFields';const exams=document.createElement('div');exams.id='examFields';general.after(exams);while(exams.nextSibling)exams.append(exams.nextSibling);
 $('editor').noValidate=true;$('empty').innerHTML='<h2>Choose a program</h2><p>Select a saved program on the left, or <a href="#settings/general">open General</a> to create one.</p>';
 $('settingsView').querySelector('.intro .eyebrow').remove();$('settingsView').querySelector('.intro h1').textContent='Programs';$('settingsView').querySelector(':scope > .notice').remove();
 const scanning=document.createElement('section');scanning.id='scanningPanel';scanning.className='card';scanning.hidden=true;settings.append(scanning);
 const week=document.createElement('section');week.id='weekPanel';week.className='card';week.hidden=true;settings.append(week);
 const zone=document.createElement('section');zone.id='timezonePanel';zone.className='card';zone.hidden=true;settings.append(zone);
 const limits=document.createElement('section');limits.id='limitsPanel';limits.className='card';limits.hidden=true;settings.append(limits);
 for(const id of ['dailyPanel','expiryPanel','resetPanel']){const panel=document.createElement('section');panel.id=id;panel.className='card';panel.hidden=true;settings.append(panel);}
 const home=document.createElement('div');home.id='documentsHome';home.className='settingsMenu';home.innerHTML='<article class="settingChoice"><a class="settingTile" href="#documents/weeks">Weeks</a><p>Planned weeks, generation and downloads.</p></article><article class="settingChoice"><button id="newCardsHome" class="settingTile">New cards</button><p>Generate a new card order.</p></article><article class="settingChoice"><a class="settingTile" href="#documents/saved">Saved orders</a><p>View, download and reprint.</p></article><article class="settingChoice"><a class="settingTile" href="#documents/ids">Student cards</a></article><article class="settingChoice"><a class="settingTile" href="#documents/layout">Layout</a></article>';$('documentsView').prepend(home);
 $('newProgram').addEventListener('click',()=>{location.hash='settings/general';});
 function draw(){
  let parts=location.hash.slice(1).split('/').filter(Boolean);if(!titles[parts[0]])parts=['dashboard'];if(parts[0]==='settings'&&parts[1]==='exams'){history.replaceState(null,'','#settings/conditions/exams');parts=['settings','conditions','exams'];}
  $('pageTrail').innerHTML=parts.map((key,i)=>`<a href="#${parts.slice(0,i+1).join('/')}" ${i===parts.length-1?'aria-current="page"':''}>${titles[key]||key.replace(/[^a-zA-Z ]/g,'')}</a>`).join('');
  const root=parts[0],category=parts[1],leaf=parts[2];
  if(root==='settings'){
   const generalView=category==='general',examView=category==='conditions'&&leaf==='exams';
   $('workspace').hidden=!(generalView||examView);$('generalFields').hidden=!generalView;$('examFields').hidden=!examView;
   settings.querySelector('.intro').hidden=!(generalView||examView);$('status').hidden=!(generalView||examView);$('newProgram').hidden=!generalView;
   $('resetPanel').hidden=category!=='reset';$('rulesPanel').hidden=!(category==='cards'&&leaf==='rules');$('expiryPanel').hidden=true;$('limitsPanel').hidden=!(category==='limits'&&leaf==='weekly');$('dailyPanel').hidden=!(category==='limits'&&leaf==='daily');$('weekPanel').hidden=!(category==='schedule'&&leaf==='week');$('timezonePanel').hidden=!(category==='schedule'&&leaf==='timezone');$('scanningPanel').hidden=category!=='scanning';
   const items=!category?categories:category==='cards'&&!leaf?[['rules','Rules','Enable cards, point reveal and teacher names.']]:category==='limits'&&!leaf?[['weekly','Weekly','Maximum cards redeemed per week.'],['daily','Daily','Optional maximum cards redeemed per day.']]:category==='conditions'&&!leaf?[['exams','Exams','Set subject scores and the points each score earns.']]:category==='schedule'&&!leaf?[['week','Week','Choose the day and time your weekly limits restart.'],['timezone','Timezone','Confirm the school clock used throughout the program.']]:null;
   menu.hidden=!items;if(items)tiles(menu,parts.join('/'),items);
   $('settingsTitle').textContent=titles[leaf||category]||'Program Settings';$('settingsDescription').textContent=category==='planner'?'Plan cards and release dates for the currently selected Motivation program.':!category?'Choose a category. Settings appear only after you open it.':category==='conditions'&&!leaf?'Choose which rules to edit.':category==='schedule'&&!leaf?'Choose the school timing settings to edit.':category==='general'||category==='conditions'?'Choose a program on the left. Changes apply to that program.':category==='scanning'?'Preferences for this browser and school.':'These preferences apply across this school’s Motivation programs.';
   settings.dataset.depth=String(parts.length);
  }
  if(root==='documents'){$('cardDesigner').hidden=category!=='layout';$('documentFiles').hidden=!['saved','ids'].includes(category);$('documentsHome').hidden=!!category;const order=$('orderPanel');if(order)order.hidden=category!=='new';}
  if(root==='display'||root==='phone'){
   const panel=$(root+'Panel'),sections=[...panel.querySelectorAll('[data-subsection]')];sections.forEach(el=>el.hidden=el.dataset.subsection!==category);
   let home=panel.querySelector('.settingsMenu');if(!home){home=document.createElement('div');home.className='settingsMenu';panel.prepend(home);}home.hidden=!!category;
   tiles(home,root,root==='display'?[['schedule','Schedule','Display days and start/end times.'],['slides','Slides','Choose the slideshow content and durations.'],['media','Media','Upload pictures and videos.'],['devices','Computers','Dedicated player availability.']]:[['numbers','Numbers','Allowed phone types and school-wide access.'],['freeze','Freeze','Block telephone access by class and student.']]);
   panel.querySelectorAll(':scope > [data-save-settings],:scope > .actions').forEach(el=>el.hidden=!category||category==='devices');
  }
  document.body.dataset.route=location.hash;
 }
 window.addEventListener('hashchange',draw);window.addEventListener('motivation-settings-rendered',draw);window.addEventListener('motivation-navigation',draw);draw();
}
