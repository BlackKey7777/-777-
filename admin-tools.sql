-- YUMAS admin tools migration
-- Run this once in Supabase Dashboard -> SQL Editor -> New query.
-- Adds a public profile badge and a secure owner-only RPC to assign it by account email.

alter table public.profiles
  add column if not exists special_emoji text;

create or replace function public.admin_set_profile_badge_by_email(
  target_email text,
  badge text default '💣'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_rows integer;
begin
  if not coalesce(public.is_yumas_admin(), false) then
    raise exception 'Недостаточно прав';
  end if;

  if target_email is null or position('@' in target_email) < 2 then
    raise exception 'Некорректный email';
  end if;

  if badge not in ('💣', '') then
    raise exception 'Разрешён только значок 💣 или пустое значение';
  end if;

  update public.profiles p
     set special_emoji = nullif(badge, '')
   where p.id = (
     select u.id
       from auth.users u
      where lower(u.email) = lower(trim(target_email))
      limit 1
   );

  get diagnostics changed_rows = row_count;
  return changed_rows > 0;
end;
$$;

revoke all on function public.admin_set_profile_badge_by_email(text, text) from public, anon;
grant execute on function public.admin_set_profile_badge_by_email(text, text) to authenticated;
