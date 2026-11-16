-- 修復 Lionheart FX 登入後無法讀取會員審核狀態
-- 已登入會員只能讀取自己的 profile（仍由既有 RLS policy 限制）。
grant select (approval_status) on public.profiles to authenticated;
-- 管理者本身視為已核准，避免管理者出現在待審核名單。
update public.profiles p
set approval_status='approved', updated_at=now()
where exists (select 1 from public.admin_users a where a.user_id=p.id)
  and p.approval_status <> 'approved';
