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
