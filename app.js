(()=>{
'use strict';
const $=id=>document.getElementById(id),cfg=window.LIONHEART_CONFIG||{},online=Boolean(cfg.supabaseUrl&&cfg.supabaseAnonKey),storageKey='lionheart_fx_bookings_v1';
let monday=startMonday(new Date()),bookings=[],selected=null,activeDay=(new Date().getDay()+6)%7;
const days=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'],pad=n=>String(n).padStart(2,'0');
const localDate=d=>`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
const addDays=(d,n)=>{const x=new Date(d);x.setDate(x.getDate()+n);return x};
function startMonday(d){const x=new Date(d.getFullYear(),d.getMonth(),d.getDate());x.setDate(x.getDate()-(x.getDay()+6)%7);return x}
const readable=d=>`${d.getMonth()+1}/${d.getDate()}`;
const timeOptions=(select,min,max)=>{select.replaceChildren();for(let h=min;h<=max;h++){const opt=document.createElement('option');opt.value=String(h);opt.textContent=`${pad(h)}:00`;select.append(opt)}};
timeOptions($('startTime'),8,19);timeOptions($('endTime'),9,20);
function updateRange(){
 const date=$('bookingDate').value,start=Number($('startTime').value),end=Number($('endTime').value);
 const valid=date&&start>=8&&start<20&&end>start&&end<=20;
 const conflicts=valid?bookings.filter(b=>b.booking_date===date&&b.start_hour>=start&&b.start_hour<end):[];
 const inPast=valid&&new Date(`${date}T${pad(start)}:00:00`).getTime()<=Date.now();
 $('selectedSlot').textContent=valid?`${date} · ${pad(start)}:00–${pad(end)}:00（${end-start} 小時）`:'請選擇有效的時間範圍';
 $('rangeHint').textContent=!valid?'結束時間必須晚於開始時間。':inPast?'無法預約已過去的時段。':conflicts.length?`所選時間有 ${conflicts.length} 個時段已被預約，請調整時間。`:`將一次預約 ${end-start} 個連續小時，資料只需填寫一次。`;
 $('rangeHint').style.color=(!valid||inPast||conflicts.length)?'#c63838':'#6e6e73';
 return {valid:!!valid&&!inPast&&!conflicts.length,date,start,end};
}
for(const id of ['bookingDate','startTime','endTime'])$(id).addEventListener('change',updateRange);
const headers=()=>({'apikey':cfg.supabaseAnonKey,'Authorization':`Bearer ${cfg.supabaseAnonKey}`,'Content-Type':'application/json'});
async function api(path,options={}){
 const res=await fetch(`${cfg.supabaseUrl.replace(/\/$/,'')}/${path.startsWith('rpc/')?'rest/v1/':'rest/v1/'}${path}`,{...options,headers:{...headers(),...(options.headers||{})}});
 if(!res.ok){let data;try{data=await res.json()}catch{data={}}throw Error(data.message||data.details||`伺服器錯誤 ${res.status}`)}
 return res.status===204?null:res.json();
}
async function load(){
 if(online){
  const from=localDate(monday),to=localDate(addDays(monday,7));
  bookings=await api(`bookings?select=id,booking_date,start_hour,name,lab,notes&booking_date=gte.${from}&booking_date=lt.${to}&order=booking_date.asc,start_hour.asc`);
 }else{try{bookings=JSON.parse(localStorage.getItem(storageKey)||'[]')}catch{bookings=[]}}
 render();
}
function render(){
 const last=addDays(monday,6);
 $('weekLabel').textContent=`${monday.getFullYear()}/${readable(monday)} — ${readable(last)}`;
 $('weekRange').textContent=`${readable(monday)} – ${readable(last)}`;
 const weekDates=Array.from({length:7},(_,i)=>localDate(addDays(monday,i)));
 $('weeklyCount').textContent=`${bookings.filter(b=>weekDates.includes(b.booking_date)).length} 筆`;
 const nav=$('mobileDayNav');nav.replaceChildren();
 weekDates.forEach((date,i)=>{
  const b=document.createElement('button');b.type='button';b.className='day-pill'+(activeDay===i?' active':'');
  b.setAttribute('aria-pressed',String(activeDay===i));
  b.textContent=`${['一','二','三','四','五','六','日'][i]} ${readable(addDays(monday,i))}`;
  b.onclick=()=>{activeDay=i;render()};
  nav.append(b);
 });
 const cal=$('calendar');cal.replaceChildren();
 const mk=(tag,cls,txt)=>{const el=document.createElement(tag);el.className=cls;if(txt!==undefined)el.textContent=txt;return el};
 cal.append(mk('div','cell day-head','時間'));
 for(let i=0;i<7;i++){
  const d=addDays(monday,i),head=mk('div',`cell day-head${localDate(d)===localDate(new Date())?' current':''}`);
  head.dataset.day=String(i);if(i===activeDay)head.classList.add('mobile-selected');
  head.append(mk('b','',days[i]),mk('small','',`${d.getMonth()+1}月${d.getDate()}日`));cal.append(head);
 }
 for(let h=8;h<20;h++){
  cal.append(mk('div','cell time-cell',`${pad(h)}:00`));
  for(let i=0;i<7;i++){
   const date=weekDates[i],found=bookings.find(b=>b.booking_date===date&&b.start_hour===h);
   const past=new Date(`${date}T${pad(h)}:00:00`).getTime()<=Date.now();
   const btn=mk('button',`slot ${found?'reserved':past?'past-slot':'available'}`);
   btn.type='button';
   if(found){
    btn.append(mk('strong','',found.name),mk('small','',found.lab));
    btn.setAttribute('aria-label',`${date} ${h}點 已預約 ${found.name}`);
    btn.addEventListener('click',()=>showDetail(found));
   }else if(past){btn.append(mk('small','','—'));btn.disabled=true}
   else{
    btn.append(mk('span','plus','＋'));
    btn.setAttribute('aria-label',`預約 ${date} ${h}:00`);
    btn.addEventListener('click',()=>openBooking(date,h));
   }
   btn.dataset.day=String(i);if(i===activeDay)btn.classList.add('mobile-selected');
   cal.append(btn);
  }
 }
}
function openBooking(date,h){
 selected={booking_date:date,start_hour:h};
 $('formMessage').textContent='';$('bookingForm').reset();
 $('bookingDate').min=localDate(new Date());$('bookingDate').max=localDate(addDays(new Date(),90));
 $('bookingDate').value=date;$('startTime').value=String(h);$('endTime').value=String(h+1);
 updateRange();$('bookingDialog').showModal();
}
function showDetail(b){
 const body=$('detailBody');body.replaceChildren();
 for(const [label,value] of [['日期',b.booking_date],['使用時段',`${pad(b.start_hour)}:00–${pad(b.start_hour+1)}:00`],['使用者',b.name],['所屬單位',b.lab],['實驗備註',b.notes||'無']]){
  const line=document.createElement('div');line.className='detail-line';
  const cap=document.createElement('span');cap.textContent=label;line.append(cap,document.createTextNode(value));body.append(line);
 }
 $('detailDialog').showModal();
}
async function save(e){
 e.preventDefault();if(!selected)return;
 const range=updateRange();
 if(!range.valid){$('formMessage').textContent='請調整日期及時間，確認整段時間都可以預約。';return}
 const record={booking_date:range.date,start_hour:range.start,name:$('name').value.trim(),lab:$('lab').value.trim(),email:$('email').value.trim(),notes:$('notes').value.trim()};
 if(!record.name||!record.lab||!record.email)return;
 $('submitBooking').disabled=true;$('formMessage').textContent='';
 try{
  if(online){
   await api('rpc/create_booking_range',{method:'POST',headers:{Prefer:'return=minimal'},body:JSON.stringify({
    p_date:range.date,p_start:range.start,p_end:range.end,p_name:record.name,p_lab:record.lab,p_email:record.email,p_notes:record.notes
   })});
  }else{
   const all=JSON.parse(localStorage.getItem(storageKey)||'[]');
   const conflict=all.some(b=>b.booking_date===range.date&&b.start_hour>=range.start&&b.start_hour<range.end);
   if(conflict)throw Error('所選時間內已有其他預約');
   const batch=Array.from({length:range.end-range.start},(_,i)=>({...record,start_hour:range.start+i,id:crypto.randomUUID()}));
   localStorage.setItem(storageKey,JSON.stringify([...all,...batch]));
  }
  $('bookingDialog').close();
  monday=startMonday(new Date(range.date+'T12:00:00'));activeDay=(new Date(range.date+'T12:00:00').getDay()+6)%7;
  await load();
 }catch(err){
  $('formMessage').textContent=/duplicate|unique|conflict|already|已被|已有|時段衝突/i.test(err.message)?'所選時間已有預約，請調整起訖時間。':`預約失敗：${err.message}`;
  await load().catch(()=>{});updateRange();
 }finally{$('submitBooking').disabled=false}
}
$('bookingForm').addEventListener('submit',save);
$('openBooking').onclick=()=>{
 const now=new Date();let date=localDate(now),hour=Math.max(8,now.getHours()+1);
 if(hour>=20){date=localDate(addDays(now,1));hour=8}
 openBooking(date,hour);
};
$('today').onclick=()=>{activeDay=(new Date().getDay()+6)%7;monday=startMonday(new Date());load().catch(showError)};
$('prev').onclick=()=>{monday=addDays(monday,-7);load().catch(showError)};
$('next').onclick=()=>{monday=addDays(monday,7);load().catch(showError)};
for(const [id,dialog] of [['closeBooking','bookingDialog'],['cancelBooking','bookingDialog'],['closeDetail','detailDialog'],['dismissDetail','detailDialog']])$(id).onclick=()=>$(dialog).close();
function showError(e){$('status').textContent='● 資料讀取失敗';console.error(e);alert(`無法讀取預約資料：${e.message}`)}
$('status').textContent=online?'● 雲端同步已啟用':'● 本機示範模式';
$('year').textContent=new Date().getFullYear();
load().catch(showError);
if(online){setInterval(()=>load().catch(console.error),30000);document.addEventListener('visibilitychange',()=>{if(!document.hidden)load().catch(console.error)})}
})();