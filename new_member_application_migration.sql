-- Lionheart FX：新會員申請（記錄申請時間、Email 通知管理者、核准後通知使用者）
-- 前置條件：已執行 supabase.sql 與 admin_migration.sql（需要 profiles.approval_status 欄位）。
-- 請在 Supabase SQL Editor 執行本檔（可重複執行）。
--
-- 1. profiles.requested_at：記錄申請權限時間，管理後台「會員審核」顯示申請時間。
-- 2. 新使用者註冊 → 寄信通知管理者「有新使用者需要管理者核准」。
-- 3. 管理者核准 → 寄信通知使用者，主旨「Lionheart FX註冊申請通過」。
--
-- 寄信方式：資料庫觸發器以 pg_net 呼叫管理者自己的 Google Apps Script（google_apps_script_mailer.gs），
-- 由管理者的 Gmail 寄出。寄信在交易提交後於背景送出，寄信失敗不會影響註冊或審核。
-- Apps Script 網址與驗證碼存放在 Supabase Vault，不寫入本檔或 GitHub。
-- 執行本檔後，請另外執行一次（換成您的 Apps Script 網址與 MAILER_TOKEN）：
--   select lionheart_private.set_mailer_settings('https://script.google.com/macros/s/…/exec', 'MAILER_TOKEN');

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
-- 2. 寄信服務設定（Google Apps Script）
-- ===============================================================
create extension if not exists pg_net with schema extensions;

-- 私有 schema：不對 anon / authenticated 開放，前端 API 無法呼叫這些函式。
create schema if not exists lionheart_private;
revoke all on schema lionheart_private from public, anon, authenticated;

-- 移除早期 Resend 版本的函式（若曾執行過）。
drop trigger if exists on_lionheart_profile_created_notify on public.profiles;
drop function if exists lionheart_private.send_member_notification(text, text, text, timestamptz);
drop function if exists lionheart_private.html_escape(text);
drop function if exists lionheart_private.set_notification_settings(text, text);

create or replace function lionheart_private.upsert_secret(p_name text, p_value text, p_description text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
 select id into v_id from vault.secrets where name = p_name;
 if v_id is null then
  perform vault.create_secret(p_value, p_name, p_description);
 else
  perform vault.update_secret(v_id, p_value);
 end if;
end;
$$;

-- 設定或更新 Apps Script 網頁應用程式網址與 MAILER_TOKEN（存入 Vault）。
create or replace function lionheart_private.set_mailer_settings(p_url text, p_token text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
 if coalesce(trim(p_url), '') !~ '^https://script\.google\.com/(macros|a/macros/[^/]+)/s/[^/]+/exec$' then
  raise exception '請貼上 Apps Script 網頁應用程式網址（https://script.google.com/macros/s/…/exec）';
 end if;
 if length(coalesce(trim(p_token), '')) < 20 then
  raise exception 'MAILER_TOKEN 長度不足，請貼上 Apps Script setup 執行紀錄中的驗證碼';
 end if;
 perform lionheart_private.upsert_secret('lionheart_mailer_url', trim(p_url), 'Lionheart FX 通知信：Apps Script 網址');
 perform lionheart_private.upsert_secret('lionheart_mailer_token', trim(p_token), 'Lionheart FX 通知信：MAILER_TOKEN');
end;
$$;

-- 呼叫 Apps Script 寄信；回傳 pg_net 請求編號（可在 net._http_response 查詢），未設定時回傳 NULL。
create or replace function lionheart_private.send_mail(p_payload jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_url text; v_token text;
begin
 select decrypted_secret into v_url from vault.decrypted_secrets where name = 'lionheart_mailer_url' limit 1;
 select decrypted_secret into v_token from vault.decrypted_secrets where name = 'lionheart_mailer_token' limit 1;
 if coalesce(v_url, '') = '' or coalesce(v_token, '') = '' then
  raise warning 'Lionheart FX：尚未設定 Apps Script 寄信服務，略過通知信';
  return null;
 end if;
 return net.http_post(
  url := v_url,
  body := p_payload || jsonb_build_object('token', v_token),
  headers := jsonb_build_object('Content-Type', 'application/json'),
  timeout_milliseconds := 20000
 );
end;
$$;

-- ===============================================================
-- 3. 通知觸發器（任何錯誤只記錄警告，不阻擋註冊或審核）
-- ===============================================================
-- 新使用者註冊（建立待審核 profile）→ 通知管理者。
create or replace function lionheart_private.notify_new_member()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_email text;
begin
 begin
  select email into v_email from auth.users where id = new.id;
  perform lionheart_private.send_mail(jsonb_build_object(
   'type', 'new_member',
   'name', new.full_name,
   'lab', new.lab,
   'email', v_email,
   'requested_at', to_char(new.requested_at at time zone 'Asia/Taipei', 'YYYY-MM-DD HH24:MI')
  ));
 exception when others then
  raise warning 'Lionheart FX 新會員通知失敗：%', sqlerrm;
 end;
 return new;
end;
$$;

-- 審核狀態改為「已核准」→ 通知使用者「Lionheart FX註冊申請通過」。
create or replace function lionheart_private.notify_member_approved()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_email text;
begin
 begin
  if exists (select 1 from public.admin_users where user_id = new.id) then
   return new;
  end if;
  select email into v_email from auth.users where id = new.id;
  if coalesce(v_email, '') <> '' then
   perform lionheart_private.send_mail(jsonb_build_object(
    'type', 'approved',
    'name', new.full_name,
    'email', v_email
   ));
  end if;
 exception when others then
  raise warning 'Lionheart FX 核准通知失敗：%', sqlerrm;
 end;
 return new;
end;
$$;

create trigger on_lionheart_profile_created_notify
after insert on public.profiles
for each row when (new.approval_status = 'pending')
execute function lionheart_private.notify_new_member();

drop trigger if exists on_lionheart_profile_approved_notify on public.profiles;
create trigger on_lionheart_profile_approved_notify
after update of approval_status on public.profiles
for each row when (new.approval_status = 'approved' and old.approval_status is distinct from 'approved')
execute function lionheart_private.notify_member_approved();

revoke all on function lionheart_private.upsert_secret(text, text, text) from public, anon, authenticated;
revoke all on function lionheart_private.set_mailer_settings(text, text) from public, anon, authenticated;
revoke all on function lionheart_private.send_mail(jsonb) from public, anon, authenticated;
revoke all on function lionheart_private.notify_new_member() from public, anon, authenticated;
revoke all on function lionheart_private.notify_member_approved() from public, anon, authenticated;

-- 測試（設定完成後於 SQL Editor 執行，會實際寄信）：
--   select lionheart_private.send_mail(jsonb_build_object('type','new_member','name','測試使用者','lab','測試實驗室','email','test@example.com','requested_at','2026-11-25 10:00'));
--   select lionheart_private.send_mail(jsonb_build_object('type','approved','name','測試使用者','email','收件測試Email'));
-- 查看送出結果（status_code 302 或 200 代表已送達 Apps Script；實際寄送結果請看 Apps Script「執行項目」）：
--   select id, status_code, error_msg, created from net._http_response order by created desc limit 5;
