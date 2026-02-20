-- supabase/migrations/014_add_exercise_sets_table.sql

create table if not exists exercise_sets (
  id uuid primary key default gen_random_uuid(),
  exercise_log_id uuid references exercise_logs(id) on delete cascade,
  set_index int not null,
  is_warmup boolean default false,
  reps int default 0,
  weight numeric default 0,
  duration_seconds int default 0,
  created_at timestamptz default now(),
  unique (exercise_log_id, set_index)
);
