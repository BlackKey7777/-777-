-- YUMAS: voice messages stored in Supabase Storage + delete sent messages
begin;

-- Keep audio files out of the messages table: only a short storage path is stored there.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'voice-messages',
  'voice-messages',
  false,
  3145728,
  array['audio/mp4','audio/webm','audio/ogg','audio/aac','audio/mpeg']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 3145728,
  allowed_mime_types = array['audio/mp4','audio/webm','audio/ogg','audio/aac','audio/mpeg'];

-- Only the sender and recipient may create signed playback URLs.
drop policy if exists "YUMAS voice messages public read" on storage.objects;
drop policy if exists "YUMAS voice messages participants read" on storage.objects;
create policy "YUMAS voice messages participants read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'voice-messages'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or (storage.foldername(name))[2] = (select auth.uid())::text
  )
);

-- Each user can upload only into their own folder.
drop policy if exists "YUMAS users upload own voice messages" on storage.objects;
create policy "YUMAS users upload own voice messages"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'voice-messages'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "YUMAS users delete own voice files" on storage.objects;
create policy "YUMAS users delete own voice files"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'voice-messages'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- A user may delete only messages they sent. The row disappears for both participants.
alter table public.direct_messages enable row level security;
drop policy if exists "Users delete own messages" on public.direct_messages;
create policy "Users delete own messages"
on public.direct_messages for delete
to authenticated
using ((select auth.uid()) = sender_id);
grant delete on public.direct_messages to authenticated;

commit;
