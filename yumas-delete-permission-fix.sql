-- YUMAS: fix permission denied when deleting posts
begin;

grant usage on schema public to authenticated;
grant select, delete on table public.posts to authenticated;

-- Keep deletion restricted to the post author or the verified YUMAS owner.
drop policy if exists "Admins delete any post" on public.posts;
drop policy if exists "Users delete their own posts" on public.posts;

create policy "Authors and YUMAS owner delete posts"
on public.posts
for delete
to authenticated
using (
  author_id = (select auth.uid())
  or (select public.is_yumas_admin())
);

grant execute on function public.is_yumas_admin() to authenticated;

commit;
