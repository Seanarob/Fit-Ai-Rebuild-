-- supabase/migrations/002_add_indexes.sql

-- Foreign key indexes and common query paths
create index if not exists idx_auth_tokens_user_id on auth_tokens (user_id);
create index if not exists idx_onboarding_states_user_id on onboarding_states (user_id);
create index if not exists idx_coach_interest_user_id on coach_interest (user_id);

create index if not exists idx_workout_templates_user_id on workout_templates (user_id);
create index if not exists idx_workout_sessions_user_id on workout_sessions (user_id);
create index if not exists idx_workout_sessions_template_id on workout_sessions (template_id);
create index if not exists idx_workout_sessions_user_created_at on workout_sessions (user_id, created_at);
create index if not exists idx_exercise_logs_session_id on exercise_logs (session_id);
create index if not exists idx_prs_user_id on prs (user_id);

create index if not exists idx_food_items_name on food_items (name);
create index if not exists idx_nutrition_logs_user_id on nutrition_logs (user_id);
create index if not exists idx_nutrition_logs_user_date on nutrition_logs (user_id, date);
create index if not exists idx_meal_plans_user_id on meal_plans (user_id);

create index if not exists idx_progress_photos_user_id on progress_photos (user_id);
create index if not exists idx_weekly_checkins_user_id on weekly_checkins (user_id);
create index if not exists idx_weekly_checkins_user_date on weekly_checkins (user_id, date);

create index if not exists idx_ai_jobs_user_id on ai_jobs (user_id);
create index if not exists idx_ai_jobs_prompt_id on ai_jobs (prompt_id);
create index if not exists idx_ai_jobs_status on ai_jobs (status);

-- Profiles and coach profiles already enforce unique user_id constraints.
create index if not exists idx_payment_records_user_id on payment_records (user_id);
create index if not exists idx_payment_records_status on payment_records (status);

create index if not exists idx_exercises_name on exercises (name);
create index if not exists idx_workout_template_exercises_template_id on workout_template_exercises (template_id);
create index if not exists idx_workout_template_exercises_exercise_id on workout_template_exercises (exercise_id);
create index if not exists idx_workout_template_exercises_template_pos on workout_template_exercises (template_id, position);

create index if not exists idx_search_history_user_id on search_history (user_id);
create index if not exists idx_nutrition_favorites_user_id on nutrition_favorites (user_id);

-- Uniqueness for prompt versioning
create unique index if not exists idx_ai_prompts_name_version on ai_prompts (name, version);
