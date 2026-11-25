-- Lionheart FX：預約取消功能
-- 會員：可取消自己「尚未開始」的預約。
-- 管理者：可取消任何會員的預約（與管理後台相同）。
-- 需已執行 supabase.sql 與 admin_migration.sql。請在 Supabase SQL Editor 執行一次。
-- 權限檢查在資料庫執行，不依賴前端隱藏按鈕。

-- 首頁需要 booking_group 才能判斷「同一次連續預約」並提供「取消整段」。
grant select (booking_group) on public.bookings to authenticated;

create or replace function public.cancel_booking(p_booking uuid,p_entire_group boolean default false)
returns integer language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid := (select auth.uid());
 v_now timestamp := (now() at time zone 'Asia/Taipei');
 v_owner uuid;
 v_group uuid;
 v_date date;
 v_hour integer;
 v_count integer;
begin
 if v_user is null then raise exception 'Login required'; end if;
 select user_id,booking_group,booking_date,start_hour into v_owner,v_group,v_date,v_hour
  from public.bookings where id=p_booking;
 if not found then raise exception 'Booking not found'; end if;

 if public.is_lionheart_admin() then
  if p_entire_group and v_group is not null then
   delete from public.bookings where booking_group=v_group;
  else
   delete from public.bookings where id=p_booking;
  end if;
 else
  if v_owner is distinct from v_user then
   raise exception 'You can only cancel your own bookings';
  end if;
  if (v_date + pg_catalog.make_interval(hours => v_hour)) <= v_now then
   raise exception 'Cannot cancel a booking that has already started';
  end if;
  if p_entire_group and v_group is not null then
   -- 只取消同一段預約中尚未開始的時段；已開始的時段保留為使用紀錄。
   delete from public.bookings
    where booking_group=v_group and user_id=v_user
      and (booking_date + pg_catalog.make_interval(hours => start_hour)) > v_now;
  else
   delete from public.bookings where id=p_booking;
  end if;
 end if;

 get diagnostics v_count = row_count;
 return v_count;
end;
$$;
revoke all on function public.cancel_booking(uuid,boolean) from public,anon;
grant execute on function public.cancel_booking(uuid,boolean) to authenticated;
