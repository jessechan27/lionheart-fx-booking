(()=>{
'use strict';
const $=id=>document.getElementById(id),cfg=window.LIONHEART_CONFIG||{};
const client=cfg.supabaseUrl&&cfg.supabaseAnonKey&&window.supabase?window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey):null;
let members=[],usage=[],bookings=[],authorized=false;
const today=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`};
const dateOffset=days=>{const d=new Date();d.setDate(d.getDate()+days);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`};
// 管理預約時預設顯示未來 90 天，避免未來預約被「本月到今天」的範圍排除。
$('dateFrom').value=today();$('dateTo').value=dateOffset(90);
const setStatus=(msg,error=false)=>{$('adminStatus').textContent=msg;$('adminStatus').style.color=error?'#bf3535':'#6e6e73'};
const cell=(row,value)=>{const el=document.createElement('td');el.textContent=value==null?'':String(value);row.append(el);return el};
const button=(label,fn,variant='secondary')=>{const b=document.createElement('button');b.type='button';b.className=variant+' admin-small';b.textContent=label;b.onclick=fn;return b};
const statusLabel={pending:'待審核',approved:'已核准',rejected:'已拒絕'};
const formatTime=v=>{if(!v)return '—';const d=new Date(v);return isNaN(d)?'—':d.toLocaleString('zh-TW',{timeZone:'Asia/Taipei',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false})};
async function rpc(name,args={}){const {data,error}=await client.rpc(name,args);if(error)throw error;return data}
function showGate(message){authorized=false;$('adminGate').hidden=false;$('adminDashboard').hidden=true;$('adminLogout').hidden=true;$('gateMessage').textContent=message||'請使用管理者帳號登入。'}
async function verify(){
 if(!client){showGate('尚未設定 Supabase。請先完成 config.js 與 admin_migration.sql。');return}
 const {data:{user},error}=await client.auth.getUser();
 if(error||!user){showGate('請使用具有管理權限的會員帳號登入。');return}
 try{
  const isAdmin=await rpc('is_lionheart_admin');
  if(!isAdmin){showGate('此帳號沒有管理者權限。請先在 Supabase SQL Editor 將此帳號加入 admin_users。');return}
  authorized=true;$('adminGate').hidden=true;$('adminDashboard').hidden=false;$('adminLogout').hidden=false;await refresh();
 }catch(err){showGate('無法驗證管理者權限：'+err.message)}
}
async function refresh(){
 if(!authorized)return;
 const from=$('dateFrom').value,to=$('dateTo').value;
 if(!from||!to||from>to){setStatus('請選擇有效日期範圍',true);return}
 setStatus('資料更新中…');$('refreshAdmin').disabled=true;
 try{
  const [m,u,b]=await Promise.all([
   rpc('admin_list_members'),rpc('admin_lab_usage',{p_from:from,p_to:to}),rpc('admin_list_bookings',{p_from:from,p_to:to})
  ]);
  members=Array.isArray(m)?m:[];usage=Array.isArray(u)?u:[];bookings=Array.isArray(b)?b:[];
  renderMembers();renderUsage();renderBookings();setStatus('已更新 · '+new Date().toLocaleTimeString('zh-TW'));
 }catch(err){setStatus('讀取失敗：'+err.message,true)}
 finally{$('refreshAdmin').disabled=false}
}
function renderMembers(){
 $('pendingCount').textContent=members.filter(x=>x.status==='pending').length+' 人';
 const rows=$('memberRows');rows.replaceChildren();
 const list=members.filter(x=>$('memberFilter').value==='all'||x.status===$('memberFilter').value);
 if(!list.length){const r=document.createElement('tr');cell(r,'目前沒有符合條件的會員').colSpan=6;rows.append(r);return}
 for(const m of list){
  const r=document.createElement('tr');cell(r,m.full_name+(m.is_admin?'（管理者）':''));cell(r,m.lab);cell(r,m.email);
  // 申請權限時間；尚未執行 new_member_application_migration.sql 時以帳號建立時間代替。
  cell(r,formatTime(m.requested_at||m.created_at)).style.whiteSpace='nowrap';
  cell(r,statusLabel[m.status]||m.status);
  const action=cell(r,'');
  if(!m.is_admin){
   if(m.status!=='approved')action.append(button('核准',()=>setMember(m,'approved'),'primary'));
   if(m.status!=='rejected')action.append(button('拒絕',()=>setMember(m,'rejected')));
   if(m.status==='approved')action.append(button('停用',()=>setMember(m,'pending')));
  }
  rows.append(r);
 }
}
async function setMember(m,status){
 const label=statusLabel[status];
 const mailNote=status==='approved'?`\n\n核准後系統將寄送「Lionheart FX註冊申請通過」通知信至 ${m.email}。`:'';
 if(!confirm(`確定將「${m.full_name}」（${m.lab}）設為「${label}」？${mailNote}`))return;
 try{await rpc('admin_set_member_status',{p_user:m.id,p_status:status});await refresh()}
 catch(err){alert('會員狀態更新失敗：'+err.message)}
}
function renderUsage(){
 const total=usage.reduce((n,u)=>n+Number(u.hours||0),0);
 $('totalHours').textContent=total+' 小時';$('labCount').textContent=usage.length+' 間';
 const rows=$('usageRows'),bars=$('usageBars');rows.replaceChildren();bars.replaceChildren();
 if(!usage.length){const r=document.createElement('tr');cell(r,'統計期間沒有預約紀錄').colSpan=4;rows.append(r);return}
 const max=Math.max(...usage.map(x=>Number(x.hours)),1);
 for(const u of usage){
  const r=document.createElement('tr');cell(r,u.lab);cell(r,u.hours+' 小時');cell(r,u.users+' 人');cell(r,total?((u.hours/total)*100).toFixed(1)+'%':'0%');rows.append(r);
  const item=document.createElement('div');item.className='usage-item';
  const head=document.createElement('div');head.className='usage-item-head';
  const name=document.createElement('strong');name.textContent=u.lab;const amount=document.createElement('span');amount.textContent=u.hours+' 小時';head.append(name,amount);
  const track=document.createElement('div');track.className='usage-track';const fill=document.createElement('div');fill.className='usage-fill';fill.style.width=(100*u.hours/max)+'%';track.append(fill);item.append(head,track);bars.append(item);
 }
}
function renderBookings(){
 const rows=$('bookingRows');rows.replaceChildren();
 if(!bookings.length){const r=document.createElement('tr');cell(r,'統計期間沒有預約紀錄').colSpan=6;rows.append(r);return}
 for(const b of bookings){
  const r=document.createElement('tr');cell(r,b.booking_date);cell(r,`${String(b.start_hour).padStart(2,'0')}:00–${String(b.start_hour+1).padStart(2,'0')}:00`);cell(r,b.name);cell(r,b.lab);cell(r,b.notes||'—');
  const action=cell(r,'');action.append(button('取消此小時',()=>cancelBooking(b,false)));
  if(b.booking_group)action.append(button('取消整段',()=>cancelBooking(b,true)));
  rows.append(r);
 }
}
async function cancelBooking(b,entire){
 const msg=entire?'同一次預約的全部時段':'這一個小時';
 if(!confirm(`確定取消 ${b.booking_date} ${b.start_hour}:00 的${msg}？此操作無法復原。`))return;
 try{const count=await rpc('admin_cancel_booking',{p_booking:b.id,p_entire_group:entire});alert('已取消 '+count+' 個小時的預約。');await refresh()}
 catch(err){alert('取消失敗：'+err.message)}
}
function csvExport(filename,columns,data){
 const escape=v=>'"'+String(v??'').replace(/"/g,'""')+'"';
 const content='\uFEFF'+[columns.map(x=>escape(x[0])).join(','),...data.map(x=>columns.map(c=>escape(x[c[1]])).join(','))].join('\r\n');
 const blob=new Blob([content],{type:'text/csv;charset=utf-8;'}),url=URL.createObjectURL(blob);
 const a=document.createElement('a');a.href=url;a.download=filename;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
$('exportUsage').onclick=()=>csvExport('lionheart_lab_usage.csv',[['實驗室','lab'],['使用時數','hours'],['使用人數','users']],usage);
$('exportBookings').onclick=()=>csvExport('lionheart_bookings.csv',[['日期','booking_date'],['開始時間','start_hour'],['姓名','name'],['實驗室','lab'],['Email','email'],['備註','notes']],bookings);
$('memberFilter').onchange=renderMembers;
$('refreshAdmin').onclick=refresh;
$('adminLogin').onsubmit=async e=>{
 e.preventDefault();if(!client){showGate('尚未設定 Supabase');return}
 const btn=e.submitter;btn.disabled=true;
 const {error}=await client.auth.signInWithPassword({email:$('adminEmail').value.trim(),password:$('adminPassword').value});
 $('adminPassword').value='';btn.disabled=false;
 if(error){showGate('登入失敗：'+error.message);return}await verify();
};
$('adminLogout').onclick=async()=>{if(client)await client.auth.signOut();showGate('已登出管理者後台。')};
verify();
})();