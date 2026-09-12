-- Read-only pre-release audit. This returns one result row. Every column must
-- say true.

with app_tables(table_name) as (
  values ('tasks'), ('habits'), ('scratchpad_lists'), ('scratchpad_items'), ('scratchpad_list_members')
),
rls as (
  select count(*) as found, count(*) filter (where c.relrowsecurity) as enabled
  from app_tables a
  join pg_class c on c.relname = a.table_name
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
),
grants as (
  select
    count(*) filter (where grantee = 'anon') as anon_count,
    count(*) filter (where grantee = 'authenticated') as authenticated_count,
    count(*) filter (where grantee = 'authenticated' and privilege_type not in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')) as unexpected_authenticated_count
  from information_schema.role_table_grants g
  join app_tables a on a.table_name = g.table_name
  where g.table_schema = 'public' and g.grantee in ('anon', 'authenticated')
),
policies as (
  select count(*) as policy_count
  from pg_policies p join app_tables a on a.table_name = p.tablename
  where p.schemaname = 'public'
),
owner_trigger as (
  select count(*) as trigger_count
  from information_schema.triggers
  where event_object_schema = 'public' and event_object_table = 'scratchpad_lists'
    and trigger_name = 'protect_scratchpad_list_owner'
    and event_manipulation = 'UPDATE' and action_timing = 'BEFORE'
),
deletion_rpc as (
  select count(*) as rpc_count
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'delete_interval_account' and p.prosecdef = true
)
select
  (rls.found = 5 and rls.enabled = 5) as all_5_tables_have_rls_expected_true,
  (grants.anon_count = 0) as anon_has_no_table_access_expected_true,
  (grants.unexpected_authenticated_count = 0) as authenticated_has_no_dangerous_grants_expected_true,
  (grants.authenticated_count = 20) as authenticated_has_exactly_20_crud_grants_expected_true,
  (policies.policy_count = 10) as all_10_policies_present_expected_true,
  (owner_trigger.trigger_count = 1) as owner_protection_trigger_expected_true,
  (deletion_rpc.rpc_count = 1) as protected_account_deletion_rpc_expected_true
from rls, grants, policies, owner_trigger, deletion_rpc;
