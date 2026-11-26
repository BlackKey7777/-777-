-- YUMAS: secure owner/admin role migration
-- Run in Supabase SQL Editor for the YUMAS project.
-- Grants owner status only to the account matching this exact email.
begin;

create table if not exists public.yumas_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.yumas_admins enable row level security;

create or replace function public.is_yumas_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.yumas_admins
    where user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_yumas_admin() from public, anon;
grant execute on function public.is_yumas_admin() to authenticated;

-- The owner is granted the role only if this email already has a registered account.
insert into public.yumas_admins (user_id)
select id from auth.users
where lower(email) = lower('sashaketov501@gmail.com')
on conflict (user_id) do nothing;

drop policy if exists "Admins delete any post" on public.posts;
create policy "Admins delete any post"
on public.posts for delete to authenticated
using ((select public.is_yumas_admin()));

drop policy if exists "Admins update any profile" on public.profiles;
create policy "Admins update any profile"
on public.profiles for update to authenticated
using ((select public.is_yumas_admin()))
with check ((select public.is_yumas_admin()));

commit;
