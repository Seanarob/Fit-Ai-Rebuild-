-- supabase/migrations/003_add_user_settings.sql

alter table profiles
  add column if not exists check_in_day text,
  add column if not exists tutorial_completed boolean default false,
  add column if not exists tutorial_completed_at timestamptz;
