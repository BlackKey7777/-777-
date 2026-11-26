-- YUMAS: post photos, private chat photos, and last-seen presence
-- Run once in Supabase Dashboard -> SQL Editor.

alter table public.profiles
  add column if not exists last_seen timestamptz;

create or replace function public.yumas_touch_presence()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last_seen timestamptz;
begin
  update public.profiles
     set last_seen = now()
   where id = auth.uid()
   returning last_seen into v_last_seen;
  return v_last_seen;
end;
$$;

grant execute on function public.yumas_touch_presence() to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'post-images', 'post-images', true, 5242880,
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do update
set public = true,
    file_size_limit = 5242880,
    allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-images', 'chat-images', false, 5242880,
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do update
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "YUMAS post images public read" on storage.objects;
create policy "YUMAS post images public read"
on storage.objects for select
using (bucket_id = 'post-images');

drop policy if exists "YUMAS post images owner upload" on storage.objects;
create policy "YUMAS post images owner upload"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'post-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "YUMAS post images owner delete" on storage.objects;
create policy "YUMAS post images owner delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'post-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "YUMAS chat images participants read" on storage.objects;
create policy "YUMAS chat images participants read"
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-images'
  and auth.uid()::text in (
    (storage.foldername(name))[1],
    (storage.foldername(name))[2]
  )
);

drop policy if exists "YUMAS chat images sender upload" on storage.objects;
create policy "YUMAS chat images sender upload"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "YUMAS chat images sender delete" on storage.objects;
create policy "YUMAS chat images sender delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
