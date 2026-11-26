-- YUMAS avatar frames / accessories
alter table public.profiles
  add column if not exists avatar_frame text not null default '';

alter table public.profiles
  drop constraint if exists profiles_avatar_frame_check;

alter table public.profiles
  add constraint profiles_avatar_frame_check
  check (avatar_frame in ('', 'gold-wreath', 'niqab', 'barbed-wire', 'chains', 'diamonds', 'gothic', 'winter', 'emerald'));

create or replace function public.admin_set_profile_avatar_frame_by_email(target_email text, frame_id text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_user_id uuid;
begin
  if not public.is_yumas_admin() then
    raise exception 'Недостаточно прав';
  end if;

  if frame_id is null then
    frame_id := '';
  end if;

  if frame_id not in ('', 'gold-wreath', 'niqab', 'barbed-wire', 'chains', 'diamonds', 'gothic', 'winter', 'emerald') then
    raise exception 'Неизвестная рамка';
  end if;

  select id into target_user_id
  from auth.users
  where lower(email) = lower(trim(target_email))
  limit 1;

  if target_user_id is null then
    return false;
  end if;

  update public.profiles
  set avatar_frame = frame_id
  where id = target_user_id;

  return found;
end;
$$;

revoke all on function public.admin_set_profile_avatar_frame_by_email(text, text) from public;
grant execute on function public.admin_set_profile_avatar_frame_by_email(text, text) to authenticated;
