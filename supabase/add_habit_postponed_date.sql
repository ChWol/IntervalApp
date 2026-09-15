-- Persist a habit postponed for the current day across devices and sessions.
alter table public.habits
  add column if not exists postponed_date timestamptz;
