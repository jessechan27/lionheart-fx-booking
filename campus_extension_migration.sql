-- Lionheart FX：預約時必填「校內分機」
-- 需已執行 supabase.sql 與 admin_migration.sql。請在 Supabase SQL Editor 執行一次，
-- 執行後再推送前端；若之後重新執行 supabase.sql 或 admin_migration.sql，請再執行本檔。
--
-- 1. bookings.extension：每筆預約記錄當時填寫的分機，僅管理者可透過後台查看（不開放其他會員讀取）。
-- 2. profiles.extension：會員最近一次填寫的分機，下次預約時自動帶入；只有本人可讀取。
-- 3. create_member_booking_range 新增必填參數 p_extension；舊版（無分機）函式移除，無法繞過。
-- 4. admin_list_bookings 回傳分機，供後台表格及 CSV 匯出。

alter table public.bookings add column if not exists extension text not null default '';
alter table public.bookings drop constraint if exists bookings_extension_check;
alter table public.bookings add constraint bookings_extension_check check (char_length(extension) <= 20);

alter table public.profiles add column if not exists extension text not null default '';
alter table public.profiles drop constraint if exists profiles_extension_check;
alter table public.profiles add constraint profiles_extension_check check (char_length(extension) <= 20);
-- 會員只能讀自己的 profile（既有 RLS policy），用於預約表單自動帶入。
grant select (extension) on public.profiles to authenticated;

drop function if exists public.create_member_booking_range(date,integer,integer,text);
create or replace function public.create_member_booking_range(
 p_date date,p_start integer,p_end integer,p_extension text,p_notes text default ''
) returns void
language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid := (select auth.uid());
 v_name text;
 v_lab text;
 v_status text;
 v_email text;
 v_ext text := pg_catalog.btrim(coalesce(p_extension,''));
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
 -- 校內分機：3–10 碼，數字開頭，可含 - 或 #（例如 1234、2203-15）。
 if v_ext !~ '^[0-9][0-9#-]{2,9}$' then raise exception 'Invalid campus extension'; end if;
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
 insert into public.bookings(booking_date,start_hour,name,lab,email,notes,user_id,booking_group,extension)
 select p_date,h,v_name,v_lab,v_email,coalesce(p_notes,''),v_user,v_group,v_ext
 from pg_catalog.generate_series(p_start,p_end-1) as h;
 -- 記住最近一次的分機，下次預約自動帶入（不影響審核狀態，不會觸發核准通知信）。
 update public.profiles set extension=v_ext where id=v_user and extension is distinct from v_ext;
end;
$$;
revoke all on function public.create_member_booking_range(date,integer,integer,text,text) from public,anon;
grant execute on function public.create_member_booking_range(date,integer,integer,text,text) to authenticated;

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
  'name',name,'lab',lab,'email',email,'extension',extension,'notes',notes,'user_id',user_id
 ) order by booking_date desc,start_hour asc),'[]'::jsonb) into result
 from public.bookings where booking_date between p_from and p_to;
 return result;
end;
$$;
revoke all on function public.admin_list_bookings(date,date) from public,anon;
grant execute on function public.admin_list_bookings(date,date) to authenticated;
