-- Stores day-level habit completions for the in-app statistics calendar.
-- Safe to re-run; existing rows receive an empty history until the app records
-- the next completion. The value is JSON text to keep older clients compatible.
alter table public.habits
  add column if not exists completion_history text not null default '[]';
