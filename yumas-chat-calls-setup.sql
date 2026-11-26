-- YUMAS: owner badge, direct messages and WebRTC call signaling
begin;

-- Re-apply owner assignment in case the account was registered after the first admin migration.
insert into public.yumas_admins (user_id)
select id from auth.users where lower(email)=lower('sashaketov501@gmail.com')
on conflict (user_id) do nothing;


create table if not exists public.direct_messages (
  id bigint generated always as identity primary key,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 1500000),
  created_at timestamptz not null default now(),
  constraint direct_messages_no_self check (sender_id <> recipient_id)
);
create index if not exists direct_messages_pair_time_idx
  on public.direct_messages (sender_id, recipient_id, created_at desc);

alter table public.direct_messages enable row level security;
drop policy if exists "Chat participants read messages" on public.direct_messages;
create policy "Chat participants read messages" on public.direct_messages
  for select to authenticated
  using ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id);
drop policy if exists "Users send messages as themselves" on public.direct_messages;
create policy "Users send messages as themselves" on public.direct_messages
  for insert to authenticated
  with check ((select auth.uid()) = sender_id and sender_id <> recipient_id);
grant select, insert, delete on public.direct_messages to authenticated;
grant usage, select on sequence public.direct_messages_id_seq to authenticated;
drop policy if exists "Users delete own messages" on public.direct_messages;
create policy "Users delete own messages" on public.direct_messages
  for delete to authenticated
  using ((select auth.uid()) = sender_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('voice-messages','voice-messages',true,3145728,array['audio/mp4','audio/webm','audio/ogg','audio/aac','audio/mpeg'])
on conflict (id) do update set public=true,file_size_limit=3145728,allowed_mime_types=array['audio/mp4','audio/webm','audio/ogg','audio/aac','audio/mpeg'];
drop policy if exists "YUMAS voice messages public read" on storage.objects;
create policy "YUMAS voice messages public read" on storage.objects for select to public using (bucket_id='voice-messages');
drop policy if exists "YUMAS users upload own voice messages" on storage.objects;
create policy "YUMAS users upload own voice messages" on storage.objects for insert to authenticated
  with check (bucket_id='voice-messages' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "YUMAS users delete own voice files" on storage.objects;
create policy "YUMAS users delete own voice files" on storage.objects for delete to authenticated
  using (bucket_id='voice-messages' and (storage.foldername(name))[1]=(select auth.uid())::text);

create table if not exists public.call_signals (
  id bigint generated always as identity primary key,
  room_id uuid not null,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('offer','answer','ice','hangup','reject')),
  payload jsonb,
  created_at timestamptz not null default now()
);
create index if not exists call_signals_recipient_idx
  on public.call_signals (recipient_id, created_at desc);
alter table public.call_signals enable row level security;
drop policy if exists "Call participants read signals" on public.call_signals;
create policy "Call participants read signals" on public.call_signals
  for select to authenticated
  using ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id);
drop policy if exists "Users send call signals as themselves" on public.call_signals;
create policy "Users send call signals as themselves" on public.call_signals
  for insert to authenticated
  with check ((select auth.uid()) = sender_id and sender_id <> recipient_id);
drop policy if exists "Users clear their own call signals" on public.call_signals;
create policy "Users clear their own call signals" on public.call_signals
  for delete to authenticated
  using ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id);
grant select, insert, delete on public.call_signals to authenticated;
grant usage, select on sequence public.call_signals_id_seq to authenticated;

-- Allows the client to show the owner's crown without exposing the admin table.
grant execute on function public.is_yumas_admin() to authenticated;

commit;
