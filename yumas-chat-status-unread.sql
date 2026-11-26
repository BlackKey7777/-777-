-- YUMAS chat features: typing indicator and unread message counters
-- Run once in Supabase Dashboard -> SQL Editor.

create table if not exists public.yumas_chat_typing (
  user_id uuid not null references auth.users(id) on delete cascade,
  peer_id uuid not null references auth.users(id) on delete cascade,
  is_typing boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, peer_id),
  constraint yumas_chat_typing_not_self check (user_id <> peer_id)
);

alter table public.yumas_chat_typing enable row level security;

drop policy if exists "YUMAS typing participants read" on public.yumas_chat_typing;
create policy "YUMAS typing participants read"
on public.yumas_chat_typing for select to authenticated
using (auth.uid() = user_id or auth.uid() = peer_id);

drop policy if exists "YUMAS typing own insert" on public.yumas_chat_typing;
create policy "YUMAS typing own insert"
on public.yumas_chat_typing for insert to authenticated
with check (auth.uid() = user_id and user_id <> peer_id);

drop policy if exists "YUMAS typing own update" on public.yumas_chat_typing;
create policy "YUMAS typing own update"
on public.yumas_chat_typing for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id and user_id <> peer_id);

create table if not exists public.yumas_chat_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  peer_id uuid not null references auth.users(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (user_id, peer_id),
  constraint yumas_chat_reads_not_self check (user_id <> peer_id)
);

alter table public.yumas_chat_reads enable row level security;

drop policy if exists "YUMAS reads own select" on public.yumas_chat_reads;
create policy "YUMAS reads own select"
on public.yumas_chat_reads for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "YUMAS reads own insert" on public.yumas_chat_reads;
create policy "YUMAS reads own insert"
on public.yumas_chat_reads for insert to authenticated
with check (auth.uid() = user_id and user_id <> peer_id);

drop policy if exists "YUMAS reads own update" on public.yumas_chat_reads;
create policy "YUMAS reads own update"
on public.yumas_chat_reads for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id and user_id <> peer_id);

grant select, insert, update on public.yumas_chat_typing to authenticated;
grant select, insert, update on public.yumas_chat_reads to authenticated;
