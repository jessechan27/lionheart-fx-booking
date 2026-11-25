-- Lionheart FX：新會員申請權限（記錄申請時間 + Email 通知管理者）
-- 前置條件：已執行 supabase.sql 與 admin_migration.sql（需要 profiles.approval_status 欄位）。
-- 請在 Supabase SQL Editor 執行本檔一次（可重複執行）。
--
-- 1. profiles 新增 requested_at（申請權限時間），管理後台「會員審核」顯示申請時間。
-- 2. 新使用者註冊（建立待審核 profile）時，透過 pg_net 呼叫 Resend Email API，
--    寄信通知管理者「有新使用者需要管理者核准」。寄信在交易提交後於背景送出，
--    寄信失敗不會影響使用者註冊。
--
-- 敏感設定（Resend API key、管理者收件 Email）存放在 Supabase Vault，不寫入本檔或 GitHub。
-- 執行本檔後，請另外執行一次（將兩個值換成您的設定）：
--   select lionheart_private.set_notification_settings('re_您的ResendAPIKey', '管理者收件Email');

-- ===============================================================
-- 1. 記錄申請權限時間
-- ===============================================================
do $$
begin
 if not exists (
  select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'profiles' and column_name = 'requested_at'
 ) then
  alter table public.profiles add column requested_at timestamptz;
  -- 既有會員以帳號建立時間作為申請時間。
  update public.profiles p set requested_at = u.created_at from auth.users u where u.id = p.id;
  update public.profiles set requested_at = now() where requested_at is null;
  alter table public.profiles alter column requested_at set default now();
  alter table public.profiles alter column requested_at set not null;
 end if;
end;
$$;
-- 一般會員沒有 requested_at 的更新權限（沿用 admin_migration.sql 的欄位級權限：只能更新 full_name、lab）。

-- 管理員會員清單加入申請時間，依申請時間由新到舊排序。
create or replace function public.admin_list_members()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare result jsonb;
begin
 if not public.is_lionheart_admin() then raise exception 'Admin access required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'full_name',p.full_name,'lab',p.lab,'email',u.email,
  'status',p.approval_status,'created_at',u.created_at,'requested_at',p.requested_at,
  'is_admin',exists(select 1 from public.admin_users a where a.user_id=p.id)
 ) order by p.requested_at desc),'[]'::jsonb) into result
 from public.profiles p join auth.users u on u.id=p.id;
 return result;
end;
$$;
revoke all on function public.admin_list_members() from public,anon;
grant execute on function public.admin_list_members() to authenticated;

-- ===============================================================
-- 2. 新會員註冊 Email 通知管理者
-- ===============================================================
create extension if not exists pg_net with schema extensions;

-- 私有 schema：不對 anon / authenticated 開放，前端 API 無法呼叫這些函式。
create schema if not exists lionheart_private;
revoke all on schema lionheart_private from public, anon, authenticated;

-- 設定或更新 Resend API key 與管理者收件 Email（存入 Vault）。
create or replace function lionheart_private.set_notification_settings(p_resend_api_key text, p_admin_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
 if coalesce(trim(p_resend_api_key), '') = '' or coalesce(trim(p_admin_email), '') = '' then
  raise exception 'Resend API key 與管理者 Email 皆不可空白';
 end if;
 select id into v_id from vault.secrets where name = 'lionheart_resend_api_key';
 if v_id is null then
  perform vault.create_secret(trim(p_resend_api_key), 'lionheart_resend_api_key', 'Lionheart FX 新會員通知：Resend API key');
 else
  perform vault.update_secret(v_id, trim(p_resend_api_key));
 end if;
 v_id := null;
 select id into v_id from vault.secrets where name = 'lionheart_admin_notify_email';
 if v_id is null then
  perform vault.create_secret(trim(p_admin_email), 'lionheart_admin_notify_email', 'Lionheart FX 新會員通知：管理者收件 Email');
 else
  perform vault.update_secret(v_id, trim(p_admin_email));
 end if;
end;
$$;

-- 避免使用者在姓名／實驗室欄位輸入 HTML 影響郵件內容。
create or replace function lionheart_private.html_escape(p text)
returns text language sql immutable set search_path = ''
as $$
 select replace(replace(replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
$$;

-- 寄出新會員通知；回傳 pg_net 請求編號（可在 net._http_response 查詢寄送結果），未設定時回傳 NULL。
create or replace function lionheart_private.send_member_notification(
 p_name text, p_lab text, p_email text, p_requested_at timestamptz default now()
) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
 v_api_key text;
 v_to text;
 v_admin_url constant text := 'https://jessechan27.github.io/lionheart-fx-booking/admin.html';
 v_time text := to_char(coalesce(p_requested_at, now()) at time zone 'Asia/Taipei', 'YYYY-MM-DD HH24:MI');
 v_name text := coalesce(nullif(trim(p_name), ''), '未填寫姓名');
 v_lab text := coalesce(nullif(trim(p_lab), ''), '未填寫實驗室');
 v_email text := coalesce(nullif(trim(p_email), ''), '（無）');
 v_html text;
 v_text text;
begin
 select decrypted_secret into v_api_key from vault.decrypted_secrets where name = 'lionheart_resend_api_key' limit 1;
 select decrypted_secret into v_to from vault.decrypted_secrets where name = 'lionheart_admin_notify_email' limit 1;
 if coalesce(v_api_key, '') = '' or coalesce(v_to, '') = '' then
  raise warning 'Lionheart FX：尚未設定 Resend API key 或管理者收件 Email，略過新會員通知';
  return null;
 end if;

 v_html :=
  '<div style="font-family:-apple-system,BlinkMacSystemFont,''Segoe UI'',''Microsoft JhengHei'',sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#1d1d1f">'
  || '<p style="font-size:13px;color:#6e6e73;margin:0 0 8px">Lionheart FX 儀器預約系統 · 中醫藥核心平台實驗室</p>'
  || '<h2 style="font-size:20px;margin:0 0 16px">有新使用者需要管理者核准</h2>'
  || '<p style="font-size:15px;line-height:1.6;margin:0 0 16px">以下使用者剛完成註冊並申請預約權限，目前狀態為「待審核」，經管理者核准後才能預約儀器。</p>'
  || '<table style="border-collapse:collapse;width:100%;font-size:15px">'
  || '<tr><td style="padding:8px 0;color:#6e6e73;width:110px;border-top:1px solid #e5e5ea">姓名</td><td style="padding:8px 0;border-top:1px solid #e5e5ea">' || lionheart_private.html_escape(v_name) || '</td></tr>'
  || '<tr><td style="padding:8px 0;color:#6e6e73;border-top:1px solid #e5e5ea">實驗室／單位</td><td style="padding:8px 0;border-top:1px solid #e5e5ea">' || lionheart_private.html_escape(v_lab) || '</td></tr>'
  || '<tr><td style="padding:8px 0;color:#6e6e73;border-top:1px solid #e5e5ea">Email</td><td style="padding:8px 0;border-top:1px solid #e5e5ea">' || lionheart_private.html_escape(v_email) || '</td></tr>'
  || '<tr><td style="padding:8px 0;color:#6e6e73;border-top:1px solid #e5e5ea;border-bottom:1px solid #e5e5ea">申請時間</td><td style="padding:8px 0;border-top:1px solid #e5e5ea;border-bottom:1px solid #e5e5ea">' || v_time || '（台灣時間）</td></tr>'
  || '</table>'
  || '<p style="margin:24px 0"><a href="' || v_admin_url || '" style="background:#0071e3;color:#ffffff;text-decoration:none;padding:10px 20px;border-radius:980px;display:inline-block;font-size:15px">前往管理後台審核</a></p>'
  || '<p style="font-size:12px;color:#86868b;line-height:1.6;margin:0">使用者須完成 Email 驗證後才能登入。此信由系統自動發送，請勿直接回覆。</p>'
  || '</div>';

 v_text := '有新使用者需要管理者核准。' || chr(10) || chr(10)
  || '姓名：' || v_name || chr(10)
  || '實驗室／單位：' || v_lab || chr(10)
  || 'Email：' || v_email || chr(10)
  || '申請時間：' || v_time || '（台灣時間）' || chr(10) || chr(10)
  || '請登入管理後台審核：' || v_admin_url || chr(10);

 return net.http_post(
  url := 'https://api.resend.com/emails',
  body := jsonb_build_object(
   'from', 'Lionheart FX Booking <onboarding@resend.dev>',
   'to', jsonb_build_array(v_to),
   'subject', '【Lionheart FX】有新使用者需要管理者核准：' || left(v_name, 60),
   'html', v_html,
   'text', v_text
  ),
  headers := jsonb_build_object('Authorization', 'Bearer ' || v_api_key, 'Content-Type', 'application/json'),
  timeout_milliseconds := 10000
 );
end;
$$;

-- profiles 新增（即新使用者註冊）時觸發；任何錯誤只記錄警告，不阻擋註冊。
create or replace function lionheart_private.notify_new_member()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_email text;
begin
 begin
  select email into v_email from auth.users where id = new.id;
  perform lionheart_private.send_member_notification(new.full_name, new.lab, v_email, new.requested_at);
 exception when others then
  raise warning 'Lionheart FX 新會員通知失敗：%', sqlerrm;
 end;
 return new;
end;
$$;

drop trigger if exists on_lionheart_profile_created_notify on public.profiles;
create trigger on_lionheart_profile_created_notify
after insert on public.profiles
for each row when (new.approval_status = 'pending')
execute function lionheart_private.notify_new_member();

revoke all on function lionheart_private.set_notification_settings(text, text) from public, anon, authenticated;
revoke all on function lionheart_private.html_escape(text) from public, anon, authenticated;
revoke all on function lionheart_private.send_member_notification(text, text, text, timestamptz) from public, anon, authenticated;
revoke all on function lionheart_private.notify_new_member() from public, anon, authenticated;

-- 測試（設定完成後於 SQL Editor 執行；會寄出一封測試信）：
--   select lionheart_private.send_member_notification('測試使用者', '測試實驗室', 'test@example.com');
-- 查看寄送結果（status_code 200 代表 Resend 已接受）：
--   select id, status_code, content, error_msg, created from net._http_response order by created desc limit 5;
