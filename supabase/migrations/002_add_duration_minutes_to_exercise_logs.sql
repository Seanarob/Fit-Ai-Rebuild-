alter table if exists exercise_logs
  add column if not exists duration_minutes int default 0;
