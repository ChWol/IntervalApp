-- Restrict the public Data API tables to the operations used by Interval.
-- RLS filters rows for authenticated users, but TRUNCATE is not governed by RLS.

revoke all privileges on table public.tasks from anon, authenticated;
revoke all privileges on table public.habits from anon, authenticated;
revoke all privileges on table public.scratchpad_lists from anon, authenticated;
revoke all privileges on table public.scratchpad_items from anon, authenticated;
revoke all privileges on table public.scratchpad_list_members from anon, authenticated;

grant select, insert, update, delete on table public.tasks to authenticated;
grant select, insert, update, delete on table public.habits to authenticated;
grant select, insert, update, delete on table public.scratchpad_lists to authenticated;
grant select, insert, update, delete on table public.scratchpad_items to authenticated;
grant select, insert, update, delete on table public.scratchpad_list_members to authenticated;
