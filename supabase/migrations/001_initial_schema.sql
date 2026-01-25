-- supabase/migrations/001_initial_schema.sql

-- 1. Users & auth
create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  hashed_password text not null,
  role text not null check (role in ('user', 'coach')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists auth_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  refresh_token text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz default now()
);

-- 2. Onboarding + coach interest
create table if not exists onboarding_states (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  step_index int not null default 0,
  data jsonb default '{}'::jsonb,
  is_complete boolean default false,
  updated_at timestamptz default now()
);

create table if not exists coach_interest (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  interest_enum text not null check (interest_enum in ('hire', 'coach', 'none')),
  invited boolean default false,
  created_at timestamptz default now()
);

-- 3. Workouts
create table if not exists workout_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  title text not null,
  description text,
  mode text not null,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

create table if not exists workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  template_id uuid references workout_templates(id) on delete set null,
  status text not null default 'in_progress',
  duration_seconds int default 0,
  stats jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

create table if not exists exercise_logs (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references workout_sessions(id) on delete cascade,
  exercise_name text not null,
  sets int default 0,
  reps int default 0,
  weight numeric default 0,
  notes text,
  created_at timestamptz default now()
);

create table if not exists prs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  exercise_name text not null,
  metric text not null,
  value numeric not null,
  recorded_at timestamptz default now()
);

-- 4. Nutrition
create table if not exists food_items (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  name text not null,
  serving text,
  protein numeric default 0,
  carbs numeric default 0,
  fats numeric default 0,
  calories numeric default 0,
  metadata jsonb default '{}'::jsonb
);

create table if not exists nutrition_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  date date not null,
  meal_type text not null,
  items jsonb default '[]'::jsonb,
  totals jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

create table if not exists meal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  range_start date,
  range_end date,
  meal_map jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);

-- 5. Progress + check-ins
create table if not exists progress_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  photo_type text not null,
  url text not null,
  tags text[],
  created_at timestamptz default now()
);

create table if not exists weekly_checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  weight numeric,
  adherence jsonb default '{}',
  photos jsonb default '[]'::jsonb,
  notes text,
  ai_summary jsonb default '{}',
  macro_update jsonb default '{}',
  cardio_update jsonb default '{}',
  created_at timestamptz default now()
);

-- 6. AI jobs + prompts
create table if not exists ai_prompts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  version text not null,
  description text,
  template text not null,
  created_at timestamptz default now()
);

create table if not exists ai_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete set null,
  prompt_id uuid references ai_prompts(id),
  input jsonb,
  output jsonb,
  status text not null default 'pending',
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

-- 7. Profiles + coach profiles
create table if not exists profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade unique,
  full_name text,
  age int,
  height_cm numeric,
  weight_kg numeric,
  goal text,
  macros jsonb default '{}'::jsonb,
  preferences jsonb default '{}'::jsonb,
  units jsonb default '{}'::jsonb,
  subscription_status text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists coach_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade unique,
  bio text,
  specialties text[],
  pricing jsonb default '{}'::jsonb,
  availability jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 8. Payments (subscriptions + coaching purchases)
create table if not exists payment_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  type text not null,
  status text not null,
  amount numeric,
  currency text,
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_session_id text,
  stripe_payment_intent_id text,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 9. Exercise catalog + template exercises
create table if not exists exercises (
  id text primary key default gen_random_uuid()::text,
  name text not null,
  muscle_groups text[],
  equipment text[],
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

create table if not exists workout_template_exercises (
  id uuid primary key default gen_random_uuid(),
  template_id uuid references workout_templates(id) on delete cascade,
  exercise_id text references exercises(id) on delete set null,
  position int default 0,
  sets int default 0,
  reps int default 0,
  rest_seconds int default 0,
  notes text,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

alter table exercises
  alter column id set default gen_random_uuid()::text,
  add column if not exists muscle_groups text[],
  add column if not exists equipment text[],
  add column if not exists metadata jsonb default '{}'::jsonb,
  add column if not exists created_at timestamptz default now();

-- 10. Nutrition recents/favorites
create table if not exists search_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  query text not null,
  source text default 'manual',
  created_at timestamptz default now()
);

create table if not exists nutrition_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  food_item_id uuid references food_items(id) on delete set null,
  created_at timestamptz default now()
);

-- 11. PRD-required column additions
alter table weekly_checkins
  add column if not exists date date default current_date;

alter table progress_photos
  add column if not exists photo_set_id uuid;

alter table workout_sessions
  add column if not exists started_at timestamptz,
  add column if not exists completed_at timestamptz;
