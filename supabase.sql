-- 在 Supabase SQL Editor 執行一次
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  booking_date date not null,
  start_hour integer not null check (start_hour between 8 and 19),
  name text not null check (char_length(trim(name)) between 1 and 60),
  lab text not null check (char_length(trim(lab)) between 1 and 100),
  email text not null check (char_length(email) between 3 and 150),
  notes text not null default '' check (char_length(notes) <= 500),
  created_at timestamptz not null default now(),
  unique (booking_date,start_hour)
);
create index if not exists bookings_date_idx on public.bookings (booking_date);
alter table public.bookings enable row level security;
-- 僅允許公開讀取非敏感欄位（email 不開放查詢）
revoke all on public.bookings from anon, authenticated;
grant usage on schema public to anon;
grant select (id,booking_date,start_hour,name,lab,notes) on public.bookings to anon;
grant insert (booking_date,start_hour,name,lab,email,notes) on public.bookings to anon;
drop policy if exists "Public may view bookings" on public.bookings;
create policy "Public may view bookings" on public.bookings for select to anon using (true);
drop policy if exists "Public may create future bookings" on public.bookings;
create policy "Public may create future bookings" on public.bookings for insert to anon with check (
  (booking_date + make_interval(hours => start_hour)) > (now() at time zone 'Asia/Taipei')
  and booking_date <= ((now() at time zone 'Asia/Taipei')::date + 90)
);
-- 無公開更新/刪除權限；管理者請在 Supabase Table Editor 修改資料。
-- 目前允許匿名新增，正式使用請啟用驗證與防濫用機制。

-- 多小時預約：同一交易內一次建立全部時段，任一衝突則整筆回滾。
-- 既有 Supabase 專案需重新執行此 SQL 才能使用新版表單。
create or replace function public.create_booking_range(
 p_date date,p_start integer,p_end integer,
 p_name text,p_lab text,p_email text,p_notes text default ''
) returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
 if p_date is null or p_start is null or p_end is null
    or p_start < 8 or p_end > 20 or p_start >= p_end then
   raise exception 'Invalid booking time range';
 end if;
 if p_name is null or length(trim(p_name)) not between 1 and 60
    or p_lab is null or length(trim(p_lab)) not between 1 and 100
    or p_email is null or length(p_email) not between 3 and 150
    or length(coalesce(p_notes,'')) > 500 then
   raise exception 'Invalid booking details';
 end if;
 if (p_date + make_interval(hours => p_start)) <= (now() at time zone 'Asia/Taipei')
    or p_date > ((now() at time zone 'Asia/Taipei')::date + 90) then
   raise exception 'Booking date must be in the future and within 90 days';
 end if;
 -- 依日期序列化同日的寫入，避免同時預約的競爭條件。
 perform pg_advisory_xact_lock(hashtext('lionheart_fx'),(p_date - date '2000-01-01')::integer);
 if exists(select 1 from public.bookings
   where booking_date=p_date and start_hour >= p_start and start_hour < p_end) then
   raise exception 'Booking conflict: one or more hours are already reserved';
 end if;
 insert into public.bookings (booking_date,start_hour,name,lab,email,notes)
 select p_date,h,p_name,p_lab,p_email,coalesce(p_notes,'')
 from generate_series(p_start,p_end-1) as h;
end;
$$;
revoke all on function public.create_booking_range(date,integer,integer,text,text,text,text) from public;
grant execute on function public.create_booking_range(date,integer,integer,text,text,text,text) to anon;
