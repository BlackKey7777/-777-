begin;

create or replace function public.is_yumas_owner(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.yumas_admins
    where user_id = target_user_id
  );
$$;

revoke all on function public.is_yumas_owner(uuid) from public;
grant execute on function public.is_yumas_owner(uuid) to anon, authenticated;

commit;
