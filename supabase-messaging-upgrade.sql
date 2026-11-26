-- YUMAS messaging upgrade (run once in Supabase SQL Editor)
-- Adds presence, group conversations, message reactions and private chat attachments.

alter table public.profiles add column if not exists last_seen timestamptz;
create index if not exists profiles_last_seen_idx on public.profiles(last_seen desc);

create or replace function public.generate_yumas_group_number()
returns text language plpgsql volatile security definer set search_path=public as $$
declare v text;
begin
 loop
  v := (1000000 + floor(random()*9000000)::int)::text;
  exit when not exists(select 1 from public.yumas_groups where group_number=v);
 end loop;
 return v;
end; $$;

create table if not exists public.yumas_groups(
 id uuid primary key default gen_random_uuid(),
 group_number text not null unique default public.generate_yumas_group_number(),
 name text not null check(char_length(name) between 1 and 60),
 description text not null default '',
 photo_url text,
 privacy text not null default 'private' check(privacy in ('private','public')),
 owner_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
create table if not exists public.yumas_group_members(
 group_id uuid not null references public.yumas_groups(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null default 'member' check(role in ('owner','admin','member')),
 joined_at timestamptz not null default now(),
 primary key(group_id,user_id)
);
create table if not exists public.yumas_group_messages(
 id bigint generated always as identity primary key,
 group_id uuid not null references public.yumas_groups(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 content text not null check(char_length(content) between 1 and 12000),
 created_at timestamptz not null default now()
);
create index if not exists yumas_group_messages_group_time_idx on public.yumas_group_messages(group_id,created_at);
create table if not exists public.yumas_message_reactions(
 id bigint generated always as identity primary key,
 direct_message_id bigint,
 group_message_id bigint references public.yumas_group_messages(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 emoji text not null check(char_length(emoji) between 1 and 8),
 created_at timestamptz not null default now(),
 check ((direct_message_id is not null)::int + (group_message_id is not null)::int = 1)
);
create unique index if not exists yumas_reaction_dm_unique on public.yumas_message_reactions(direct_message_id,user_id,emoji) where direct_message_id is not null;
create unique index if not exists yumas_reaction_group_unique on public.yumas_message_reactions(group_message_id,user_id,emoji) where group_message_id is not null;

alter table public.yumas_groups enable row level security;
alter table public.yumas_group_members enable row level security;
alter table public.yumas_group_messages enable row level security;
alter table public.yumas_message_reactions enable row level security;

drop policy if exists "Yumas groups visible to members and public" on public.yumas_groups;
create policy "Yumas groups visible to members and public" on public.yumas_groups for select to authenticated
using (privacy='public' or owner_id=auth.uid() or exists(select 1 from public.yumas_group_members m where m.group_id=id and m.user_id=auth.uid()));
drop policy if exists "Yumas users create groups" on public.yumas_groups;
create policy "Yumas users create groups" on public.yumas_groups for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists "Yumas owners update groups" on public.yumas_groups;
create policy "Yumas owners update groups" on public.yumas_groups for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "Yumas owners delete groups" on public.yumas_groups;
create policy "Yumas owners delete groups" on public.yumas_groups for delete to authenticated using(owner_id=auth.uid());

drop policy if exists "Yumas members read membership" on public.yumas_group_members;
create policy "Yumas members read membership" on public.yumas_group_members for select to authenticated
using(user_id=auth.uid() or exists(select 1 from public.yumas_group_members mine where mine.group_id=group_id and mine.user_id=auth.uid()));
drop policy if exists "Yumas owners add members" on public.yumas_group_members;
create policy "Yumas owners add members" on public.yumas_group_members for insert to authenticated
with check(user_id=auth.uid() and exists(select 1 from public.yumas_groups g where g.id=group_id and g.owner_id=auth.uid()));
drop policy if exists "Yumas users leave groups" on public.yumas_group_members;
create policy "Yumas users leave groups" on public.yumas_group_members for delete to authenticated using(user_id=auth.uid());

drop policy if exists "Yumas group members read messages" on public.yumas_group_messages;
create policy "Yumas group members read messages" on public.yumas_group_messages for select to authenticated
using(exists(select 1 from public.yumas_group_members m where m.group_id=group_id and m.user_id=auth.uid()));
drop policy if exists "Yumas group members send messages" on public.yumas_group_messages;
create policy "Yumas group members send messages" on public.yumas_group_messages for insert to authenticated
with check(sender_id=auth.uid() and exists(select 1 from public.yumas_group_members m where m.group_id=group_id and m.user_id=auth.uid()));
drop policy if exists "Yumas senders delete own group messages" on public.yumas_group_messages;
create policy "Yumas senders delete own group messages" on public.yumas_group_messages for delete to authenticated using(sender_id=auth.uid());

drop policy if exists "Yumas users read reactions" on public.yumas_message_reactions;
create policy "Yumas users read reactions" on public.yumas_message_reactions for select to authenticated
using(
 (group_message_id is not null and exists(select 1 from public.yumas_group_messages gm join public.yumas_group_members m on m.group_id=gm.group_id where gm.id=group_message_id and m.user_id=auth.uid()))
 or
 (direct_message_id is not null and exists(select 1 from public.direct_messages dm where dm.id=direct_message_id and (dm.sender_id=auth.uid() or dm.recipient_id=auth.uid())))
);
drop policy if exists "Yumas users add own reactions" on public.yumas_message_reactions;
create policy "Yumas users add own reactions" on public.yumas_message_reactions for insert to authenticated
with check(user_id=auth.uid() and (
 (group_message_id is not null and exists(select 1 from public.yumas_group_messages gm join public.yumas_group_members m on m.group_id=gm.group_id where gm.id=group_message_id and m.user_id=auth.uid()))
 or
 (direct_message_id is not null and exists(select 1 from public.direct_messages dm where dm.id=direct_message_id and (dm.sender_id=auth.uid() or dm.recipient_id=auth.uid())))
));
drop policy if exists "Yumas users remove own reactions" on public.yumas_message_reactions;
create policy "Yumas users remove own reactions" on public.yumas_message_reactions for delete to authenticated using(user_id=auth.uid());

create or replace function public.join_yumas_group_by_number(p_group_number text)
returns uuid language plpgsql security definer set search_path=public as $$
declare g public.yumas_groups;
begin
 if auth.uid() is null then raise exception 'Нужно войти в аккаунт'; end if;
 select * into g from public.yumas_groups where group_number=p_group_number;
 if not found then raise exception 'Беседа не найдена'; end if;
 insert into public.yumas_group_members(group_id,user_id,role) values(g.id,auth.uid(),'member') on conflict(group_id,user_id) do nothing;
 return g.id;
end; $$;
create or replace function public.join_yumas_public_group(p_group_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Нужно войти в аккаунт'; end if;
 if not exists(select 1 from public.yumas_groups where id=p_group_id and privacy='public') then raise exception 'Публичная беседа не найдена'; end if;
 insert into public.yumas_group_members(group_id,user_id,role) values(p_group_id,auth.uid(),'member') on conflict(group_id,user_id) do nothing;
end; $$;
revoke all on function public.join_yumas_group_by_number(text) from public,anon;
revoke all on function public.join_yumas_public_group(uuid) from public,anon;
grant execute on function public.join_yumas_group_by_number(text),public.join_yumas_public_group(uuid) to authenticated;

grant select,insert,update,delete on public.yumas_groups,public.yumas_group_members,public.yumas_group_messages,public.yumas_message_reactions to authenticated;
grant usage,select on sequence public.yumas_group_messages_id_seq,public.yumas_message_reactions_id_seq to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('yumas-chat-files','yumas-chat-files',false,26214400,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','video/webm','application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','text/plain','application/zip','audio/mp4','audio/webm','audio/ogg'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('yumas-group-photos','yumas-group-photos',true,5242880,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit;

drop policy if exists "Yumas chat files upload" on storage.objects;
create policy "Yumas chat files upload" on storage.objects for insert to authenticated
with check(bucket_id='yumas-chat-files' and (
 (split_part(name,'/',1)='dm' and split_part(name,'/',2)=auth.uid()::text)
 or
 (split_part(name,'/',1)<>'dm' and exists(select 1 from public.yumas_group_members m where m.group_id=split_part(name,'/',1)::uuid and m.user_id=auth.uid()))
));
drop policy if exists "Yumas chat files read" on storage.objects;
create policy "Yumas chat files read" on storage.objects for select to authenticated
using(bucket_id='yumas-chat-files' and (
 (split_part(name,'/',1)<>'dm' and exists(select 1 from public.yumas_group_members m where m.group_id=split_part(name,'/',1)::uuid and m.user_id=auth.uid()))
 or
 (split_part(name,'/',1)='dm' and exists(select 1 from public.direct_messages dm where dm.content like '%'||name||'%' and (dm.sender_id=auth.uid() or dm.recipient_id=auth.uid())))
));
drop policy if exists "Yumas chat files delete" on storage.objects;
create policy "Yumas chat files delete" on storage.objects for delete to authenticated
using(bucket_id='yumas-chat-files' and split_part(name,'/',1)='dm' and split_part(name,'/',2)=auth.uid()::text);

drop policy if exists "Yumas group photos upload" on storage.objects;
create policy "Yumas group photos upload" on storage.objects for insert to authenticated
with check(bucket_id='yumas-group-photos' and exists(select 1 from public.yumas_groups g where g.id=split_part(name,'/',1)::uuid and g.owner_id=auth.uid()));
drop policy if exists "Yumas group photos public read" on storage.objects;
create policy "Yumas group photos public read" on storage.objects for select to public using(bucket_id='yumas-group-photos');
