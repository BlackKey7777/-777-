-- YUMAS: allow voice messages stored as data URLs in direct_messages.content
-- Voice recordings are capped at 1.1 MB by the client; base64 adds about 33%.
begin;

alter table public.direct_messages
  drop constraint if exists direct_messages_content_check;

alter table public.direct_messages
  add constraint direct_messages_content_check
  check (char_length(content) between 1 and 1500000);

commit;
