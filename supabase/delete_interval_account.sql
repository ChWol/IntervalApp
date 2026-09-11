-- Transactional account deletion used by Settings > Delete Everything.
-- Run as a Supabase migration. SECURITY DEFINER is required to delete auth.users;
-- the function can target only auth.uid(), never a caller-supplied account.
create or replace function public.delete_interval_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  delete from public.scratchpad_members
    where owner_id = current_user_id or member_user_id = current_user_id;
  delete from public.scratchpad_items where user_id = current_user_id;
  delete from public.scratchpad_lists where user_id = current_user_id;
  delete from public.tasks where user_id = current_user_id;
  delete from public.habits where user_id = current_user_id;
  delete from auth.users where id = current_user_id;
end;
$$;

revoke all on function public.delete_interval_account() from public, anon;
grant execute on function public.delete_interval_account() to authenticated;
