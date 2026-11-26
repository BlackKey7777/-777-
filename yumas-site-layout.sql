-- YUMAS global visual layout editor
-- Run once in Supabase SQL Editor.
create table if not exists public.yumas_site_layout (
  id integer primary key default 1 check (id = 1),
  config jsonb not null default '{"groups":{}}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.yumas_site_layout enable row level security;
drop policy if exists "Anyone can read YUMAS site layout" on public.yumas_site_layout;
create policy "Anyone can read YUMAS site layout"
  on public.yumas_site_layout for select to anon, authenticated using (true);

insert into public.yumas_site_layout (id, config)
values (1, '{"groups":{}}'::jsonb)
on conflict (id) do nothing;

create or replace function public.get_yumas_site_layout()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select config from public.yumas_site_layout where id = 1;
$$;

create or replace function public.save_yumas_site_layout(new_config jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_yumas_admin() then
    raise exception 'Недостаточно прав';
  end if;
  if new_config is null or jsonb_typeof(new_config) <> 'object' then
    raise exception 'Некорректные настройки расположения';
  end if;
  insert into public.yumas_site_layout (id, config, updated_at)
  values (1, new_config, now())
  on conflict (id) do update
    set config = excluded.config, updated_at = now();
  return true;
end;
$$;

grant select on public.yumas_site_layout to anon, authenticated;
grant execute on function public.get_yumas_site_layout() to anon, authenticated;
grant execute on function public.save_yumas_site_layout(jsonb) to authenticated;
