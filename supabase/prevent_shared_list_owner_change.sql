-- A collaborator may edit a shared list, but must never be able to become its owner.

create or replace function public.prevent_scratchpad_list_owner_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.user_id is distinct from old.user_id then
    raise exception 'scratchpad list ownership cannot be changed';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_scratchpad_list_owner_change() from public, anon, authenticated;

drop trigger if exists protect_scratchpad_list_owner on public.scratchpad_lists;
create trigger protect_scratchpad_list_owner
before update on public.scratchpad_lists
for each row execute function public.prevent_scratchpad_list_owner_change();
