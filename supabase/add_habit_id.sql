-- Links hour tasks created from habits during the hourly migration.
-- Safe to re-run. Without this column the app still works: habit links stay
-- device-local and task upserts automatically drop the field.
alter table public.tasks
  add column if not exists habit_id text;

create index if not exists tasks_habit_id_idx
  on public.tasks (habit_id)
  where habit_id is not null;
