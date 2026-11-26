-- YUMAS: comments, likes and owner post deletion fixes
begin;

create table if not exists public.comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_created_idx
  on public.comments (post_id, created_at asc);

alter table public.comments enable row level security;
drop policy if exists "Comments are publicly readable" on public.comments;
create policy "Comments are publicly readable"
  on public.comments for select to anon, authenticated using (true);
drop policy if exists "Users add comments as themselves" on public.comments;
create policy "Users add comments as themselves"
  on public.comments for insert to authenticated
  with check ((select auth.uid()) = user_id);
drop policy if exists "Users delete own comments or admins delete any" on public.comments;
create policy "Users delete own comments or admins delete any"
  on public.comments for delete to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (select 1 from public.yumas_admins a where a.user_id = (select auth.uid()))
  );

-- Recreate the expected like policies safely.
alter table public.likes enable row level security;
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

-- Only the owner/admin role can delete any post; authors can delete their own.
drop policy if exists "Admins delete any post" on public.posts;
create policy "Admins delete any post"
  on public.posts for delete to authenticated
  using (
    author_id = (select auth.uid())
    or exists (select 1 from public.yumas_admins a where a.user_id = (select auth.uid()))
  );

grant select on public.comments to anon, authenticated;
grant insert, delete on public.comments to authenticated;
grant usage, select on sequence public.comments_id_seq to authenticated;
grant select, insert, delete on public.likes to authenticated;
grant delete on public.posts to authenticated;

commit;
