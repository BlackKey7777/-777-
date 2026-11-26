-- YUMAS Supabase schema
-- Run this SQL only in a NEW Supabase project created for YUMAS.
-- This file contains no project URL, API key, password, or other secret.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null default 'Пользователь',
  bio text not null default '',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  id bigint generated always as identity primary key,
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 5000),
  image_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.likes (
  post_id bigint not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_author_id_idx on public.posts (author_id);
create index if not exists likes_user_id_idx on public.likes (user_id);

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.likes enable row level security;

drop policy if exists "Profiles are publicly readable" on public.profiles;
create policy "Profiles are publicly readable"
  on public.profiles for select to anon, authenticated using (true);

drop policy if exists "Users create their own profile" on public.profiles;
create policy "Users create their own profile"
  on public.profiles for insert to authenticated with check ((select auth.uid()) = id);

drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "Posts are publicly readable" on public.posts;
create policy "Posts are publicly readable"
  on public.posts for select to anon, authenticated using (true);

drop policy if exists "Users create their own posts" on public.posts;
create policy "Users create their own posts"
  on public.posts for insert to authenticated
  with check ((select auth.uid()) = author_id);

drop policy if exists "Users update their own posts" on public.posts;
create policy "Users update their own posts"
  on public.posts for update to authenticated
  using ((select auth.uid()) = author_id)
  with check ((select auth.uid()) = author_id);

drop policy if exists "Users delete their own posts" on public.posts;
create policy "Users delete their own posts"
  on public.posts for delete to authenticated
  using ((select auth.uid()) = author_id);

drop policy if exists "Likes are publicly readable" on public.likes;
create policy "Likes are publicly readable"
  on public.likes for select to anon, authenticated using (true);

drop policy if exists "Users add their own likes" on public.likes;
create policy "Users add their own likes"
  on public.likes for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users remove their own likes" on public.likes;
create policy "Users remove their own likes"
  on public.likes for delete to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.handle_new_yumas_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    'user_' || replace(new.id::text, '-', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Пользователь')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_yumas on auth.users;
create trigger on_auth_user_created_yumas
  after insert on auth.users
  for each row execute procedure public.handle_new_yumas_user();

grant select on public.profiles, public.posts, public.likes to anon, authenticated;
grant insert, update, delete on public.profiles, public.posts, public.likes to authenticated;
grant usage, select on all sequences in schema public to authenticated;
