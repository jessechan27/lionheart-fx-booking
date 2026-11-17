-- Lionheart FX: allow everyone to view occupied time slots, without personal data.
-- Execute once in Supabase SQL Editor. No table permissions or RLS changes required.
create or replace function public.public_booking_availability(p_from date,p_to date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_result jsonb;
begin
 if p_from is null or p_to is null or p_from > p_to or p_to-p_from > 7 then
  raise exception 'Invalid calendar date range';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'booking_date',b.booking_date,'start_hour',b.start_hour
 ) order by b.booking_date,b.start_hour),'[]'::jsonb)
 into v_result
 from public.bookings b
 where b.booking_date between p_from and p_to;
 return v_result;
end;
$$;
revoke all on function public.public_booking_availability(date,date) from public;
grant execute on function public.public_booking_availability(date,date) to anon,authenticated;
