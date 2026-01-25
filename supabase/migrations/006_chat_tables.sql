-- supabase/migrations/006_chat_tables.sql

create table if not exists chat_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  title text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_message_at timestamptz,
  archived_at timestamptz
);

create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid references chat_threads(id) on delete cascade,
  user_id uuid references users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  model text,
  token_count int,
  safety_flags text[],
  created_at timestamptz default now()
);

create table if not exists chat_thread_summaries (
  thread_id uuid primary key references chat_threads(id) on delete cascade,
  summary text not null,
  updated_at timestamptz default now()
);

create index if not exists idx_chat_threads_user_id on chat_threads (user_id);
create index if not exists idx_chat_threads_user_last on chat_threads (user_id, last_message_at desc);
create index if not exists idx_chat_messages_thread_id on chat_messages (thread_id, created_at);
create index if not exists idx_chat_messages_user_id on chat_messages (user_id);
