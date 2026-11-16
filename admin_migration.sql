-- Lionheart FX 管理者後台資料庫升級
-- 先執行原本 supabase.sql（如尚未執行），再執行本檔。
-- 請在 Supabase SQL Editor 使用專案管理者身分執行。
-- 管理員只由資料庫授權，不能透過前端自行指定。

create table if not exists public.admin_users (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
revoke all on public.admin_users from anon, authenticated;

create or replace function public.is_lionheart_admin()
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.admin_users where user_id=(select auth.uid()));
$$;
revoke all on function public.is_lionheart_admin() from public,anon;
grant execute on function public.is_lionheart_admin() to authenticated;

alter table public.profiles add column if not exists approval_status text not null default 'pending';
alter table public.profiles drop constraint if exists profiles_approval_status_check;
alter table public.profiles add constraint profiles_approval_status_check check (approval_status in ('pending','approved','rejected'));
-- 新註冊者預設 pending，舊會員也須審核；管理員不受此限制。
-- 禁止一般會員更新 approval_status，沿用先前的欄位級 update 權限。
revoke update on public.profiles from authenticated;
grant update (full_name,lab) on public.profiles to authenticated;

alter table public.bookings add column if not exists booking_group uuid;
create index if not exists bookings_group_idx on public.bookings(booking_group);

-- 取代既有會員預約 RPC：從會員資料讀取姓名、實驗室及 Email，檢查審核狀態。
create or replace function public.create_member_booking_range(
 p_date date,p_start integer,p_end integer,p_notes text default ''
) returns void
language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid := (select auth.uid());
 v_name text;
 v_lab text;
 v_status text;
 v_email text;
 v_group uuid := gen_random_uuid();
begin
 if v_user is null then raise exception 'Login required'; end if;
 select full_name,lab,approval_status into v_name,v_lab,v_status from public.profiles where id=v_user;
 if v_name is null or v_lab is null then raise exception 'Member profile not found'; end if;
 if v_status <> 'approved' and not public.is_lionheart_admin() then
  raise exception 'Member is not approved';
 end if;
 select email into v_email from auth.users where id=v_user;
 if v_email is null then raise exception 'Email not found'; end if;
 if p_date is null or p_start is null or p_end is null or p_start<8 or p_end>20 or p_start>=p_end then
  raise exception 'Invalid booking range';
 end if;
 if length(coalesce(p_notes,''))>500 then raise exception 'Notes too long'; end if;
 if (p_date + pg_catalog.make_interval(hours => p_start)) <= (now() at time zone 'Asia/Taipei')
    or p_date > ((now() at time zone 'Asia/Taipei')::date + 90) then
  raise exception 'Booking must be in the future and within 90 days';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('lionheart_fx'),(p_date-date '2000-01-01')::integer);
 if exists(select 1 from public.bookings where booking_date=p_date and start_hour>=p_start and start_hour<p_end) then
  raise exception 'Booking conflict';
 end if;
 insert into public.bookings(booking_date,start_hour,name,lab,email,notes,user_id,booking_group)
 select p_date,h,v_name,v_lab,v_email,coalesce(p_notes,''),v_user,v_group
 from pg_catalog.generate_series(p_start,p_end-1) as h;
end;
$$;
revoke all on function public.create_member_booking_range(date,integer,integer,text) from public,anon;
grant execute on function public.create_member_booking_range(date,integer,integer,text) to authenticated;

-- 管理員可查看會員姓名、實驗室、狀態、Email，非管理員無權呼叫成功。
create or replace function public.admin_list_members()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare result jsonb;
begin
 if not public.is_lionheart_admin() then raise exception 'Admin access required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'full_name',p.full_name,'lab',p.lab,'email',u.email,
  'status',p.approval_status,'created_at',u.created_at,
  'is_admin',exists(select 1 from public.admin_users a where a.user_id=p.id)
 ) order by u.created_at desc),'[]'::jsonb) into result
 from public.profiles p join auth.users u on u.id=p.id;
 return result;
end;
$$;

create or replace function public.admin_set_member_status(p_user uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.is_lionheart_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('pending','approved','rejected') then raise exception 'Invalid status'; end if;
 if exists(select 1 from public.admin_users where user_id=p_user) then
  raise exception 'Cannot change an administrator account';
 end if;
 update public.profiles set approval_status=p_status,updated_at=now() where id=p_user;
 if not found then raise exception 'Member not found'; end if;
end;
$$;

-- 日期範圍內，依實驗室彙總實際占用的小時數。
create or replace function public.admin_lab_usage(p_from date,p_to date)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare result jsonb;
begin
 if not public.is_lionheart_admin() then raise exception 'Admin access required'; end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 then
  raise exception 'Invalid date range (maximum 366 days)';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('lab',lab,'hours',hours,'users',users)
  order by hours desc,lab),'[]'::jsonb) into result
 from (
  select lab,count(*)::integer as hours,count(distinct coalesce(user_id::text,email))::integer as users
  from public.bookings where booking_date between p_from and p_to group by lab
 ) t;
 return result;
end;
$$;

create or replace function public.admin_list_bookings(p_from date,p_to date)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare result jsonb;
begin
 if not public.is_lionheart_admin() then raise exception 'Admin access required'; end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 then
  raise exception 'Invalid date range (maximum 366 days)';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'booking_group',booking_group,'booking_date',booking_date,'start_hour',start_hour,
  'name',name,'lab',lab,'email',email,'notes',notes,'user_id',user_id
 ) order by booking_date desc,start_hour asc),'[]'::jsonb) into result
 from public.bookings where booking_date between p_from and p_to;
 return result;
end;
$$;

-- 支援取消單一小時，或同一次連續預約的所有小時。
create or replace function public.admin_cancel_booking(p_booking uuid,p_entire_group boolean default false)
returns integer language plpgsql security definer set search_path=''
as $$
declare v_group uuid;v_count integer;
begin
 if not public.is_lionheart_admin() then raise exception 'Admin access required'; end if;
 select booking_group into v_group from public.bookings where id=p_booking;
 if not found then raise exception 'Booking not found'; end if;
 if p_entire_group and v_group is not null then
  delete from public.bookings where booking_group=v_group;
 else
  delete from public.bookings where id=p_booking;
 end if;
 get diagnostics v_count = row_count;
 return v_count;
end;
$$;

revoke all on function public.admin_list_members() from public,anon;
revoke all on function public.admin_set_member_status(uuid,text) from public,anon;
revoke all on function public.admin_lab_usage(date,date) from public,anon;
revoke all on function public.admin_list_bookings(date,date) from public,anon;
revoke all on function public.admin_cancel_booking(uuid,boolean) from public,anon;
grant execute on function public.admin_list_members() to authenticated;
grant execute on function public.admin_set_member_status(uuid,text) to authenticated;
grant execute on function public.admin_lab_usage(date,date) to authenticated;
grant execute on function public.admin_list_bookings(date,date) to authenticated;
grant execute on function public.admin_cancel_booking(uuid,boolean) to authenticated;

-- 重要：註冊並完成 Email 驗證後，請在 SQL Editor 以管理者權限執行：
-- insert into public.admin_users(user_id)
-- select id from auth.users where email = 'YOUR_ADMIN_EMAIL@example.com'
-- on conflict (user_id) do nothing;
-- 不要把管理者 Email 或 service_role key 寫入公開前端。
