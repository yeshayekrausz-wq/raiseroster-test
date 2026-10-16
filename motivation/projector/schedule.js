export function scheduleActive(s,now=new Date()){
 const parts=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:s.timezone,weekday:'short',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(now).map(x=>[x.type,x.value]));
 const day=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].indexOf(parts.weekday),time=parts.hour+':'+parts.minute;
 if(s.display_start===s.display_end)return s.display_days.includes(day);
 if(s.display_start<s.display_end)return s.display_days.includes(day)&&time>=s.display_start&&time<s.display_end;
 return (time>=s.display_start&&s.display_days.includes(day))||(time<s.display_end&&s.display_days.includes((day+6)%7));
}
