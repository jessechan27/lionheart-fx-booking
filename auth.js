(()=>{
'use strict';
const $=id=>document.getElementById(id);
const cfg=window.LIONHEART_CONFIG||{};
const configured=Boolean(cfg.supabaseUrl&&cfg.supabaseAnonKey);
const client=configured&&window.supabase?window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
let user=null,profile=null,mode='login';
const setMessage=(id,msg,ok=false)=>{const el=$(id);el.textContent=msg;el.style.color=ok?'#147d4a':'#c63838'};
const notify=()=>{window.dispatchEvent(new CustomEvent('lionheart-auth-change',{detail:{user,profile}}))};
const openAuth=()=>{if(!client){alert('會員系統尚未啟用。請管理者先設定 Supabase URL 與公開金鑰，並執行最新 supabase.sql。');return}setMode('login');setMessage('authMessage','');$('authDialog').showModal()};
function setMode(next){
 mode=next;const registering=mode==='register';
 $('registerFields').hidden=!registering;
 $('regName').required=registering;$('regLab').required=registering;
 $('authTitle').textContent=registering?'建立會員帳號':'會員登入';
 $('authSubmit').textContent=registering?'註冊帳號':'登入';
 $('tabLogin').classList.toggle('active',!registering);
 $('tabRegister').classList.toggle('active',registering);
 $('authPassword').autocomplete=registering?'new-password':'current-password';
 setMessage('authMessage','');
}
async function refresh(){
 if(!client){user=null;profile=null;updateUI();notify();return}
 const {data:{user:current},error}=await client.auth.getUser();
 if(error||!current){user=null;profile=null;updateUI();notify();return}
 user=current;
 const {data,error:profileError}=await client.from('profiles').select('full_name,lab').eq('id',user.id).single();
 profile=profileError?null:data;
 updateUI();notify();
}
function updateUI(){
 $('userBadge').hidden=!user;
 $('logoutButton').hidden=!user;
 $('accountButton').textContent=user?'我的資料':'登入 / 註冊';
 $('userBadge').textContent=profile?profile.full_name:'已登入';
 $('status').textContent=!client?'● 尚未設定會員資料庫':user?'● 已登入 · 雲端同步':'● 請登入會員';
}
async function submitAuth(e){
 e.preventDefault();if(!client)return;
 const email=$('authEmail').value.trim(),password=$('authPassword').value;
 const btn=$('authSubmit');btn.disabled=true;
 try{
  if(mode==='register'){
   const name=$('regName').value.trim(),lab=$('regLab').value.trim();
   if(!name||!lab)throw Error('請填寫姓名與實驗室資訊。');
   const {data,error}=await client.auth.signUp({email,password,options:{emailRedirectTo:location.origin+location.pathname,data:{full_name:name,lab}}});
   if(error)throw error;
   if(data.session){$('authDialog').close();await refresh()}
   else setMessage('authMessage','註冊成功！請到信箱點選驗證連結，再返回登入。',true);
  }else{
   const {error}=await client.auth.signInWithPassword({email,password});
   if(error)throw error;
   $('authDialog').close();await refresh();
  }
 }catch(err){setMessage('authMessage',err.message)}finally{btn.disabled=false}
}
async function saveProfile(e){
 e.preventDefault();if(!client||!user)return;
 const full_name=$('profileName').value.trim(),lab=$('profileLab').value.trim();
 if(!full_name||!lab){setMessage('profileMessage','姓名與實驗室不可空白。');return}
 const {error}=await client.from('profiles').update({full_name,lab}).eq('id',user.id);
 if(error)setMessage('profileMessage',error.message);
 else{$('profileDialog').close();await refresh()}
}
$('authForm').addEventListener('submit',submitAuth);
$('profileForm').addEventListener('submit',saveProfile);
$('tabLogin').onclick=()=>setMode('login');
$('tabRegister').onclick=()=>setMode('register');
$('closeAuth').onclick=()=>$('authDialog').close();
$('closeProfile').onclick=()=>$('profileDialog').close();
$('cancelProfile').onclick=()=>$('profileDialog').close();
$('accountButton').onclick=()=>{
 if(!user){openAuth();return}
 $('profileName').value=profile?.full_name||'';
 $('profileLab').value=profile?.lab||'';
 $('profileEmail').textContent=user.email||'';
 setMessage('profileMessage','');$('profileDialog').showModal();
};
$('logoutButton').onclick=async()=>{
 if(client){const {error}=await client.auth.signOut();if(error){alert(error.message);return}}
 user=null;profile=null;updateUI();notify();
};
$('forgotPassword').onclick=async()=>{
 if(!client)return;
 const email=$('authEmail').value.trim();
 if(!email){setMessage('authMessage','請先輸入 Email，再點選忘記密碼。');return}
 const {error}=await client.auth.resetPasswordForEmail(email,{redirectTo:location.origin+location.pathname});
 setMessage('authMessage',error?error.message:'若帳號存在，將收到密碼重設郵件。',!error);
};
window.LionheartAuth={client,get user(){return user},get profile(){return profile},openAuth,refresh};
if(client){
 client.auth.onAuthStateChange((event)=>{
  if(event==='PASSWORD_RECOVERY'){
   const password=prompt('請輸入新的密碼（至少 6 個字元）：');
   if(password&&password.length>=6)client.auth.updateUser({password}).then(({error})=>alert(error?error.message:'密碼更新成功'));
  }
  if(['SIGNED_IN','SIGNED_OUT','USER_UPDATED','TOKEN_REFRESHED','INITIAL_SESSION'].includes(event))setTimeout(()=>refresh().catch(console.error),0);
 });
}
refresh().catch(console.error);
})();