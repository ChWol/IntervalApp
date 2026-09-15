-- Tracks how long a task has actually remained in its current time horizon.
alter table public.tasks
    add column if not exists interval_entered_at timestamptz;

notify pgrst, 'reload schema';
