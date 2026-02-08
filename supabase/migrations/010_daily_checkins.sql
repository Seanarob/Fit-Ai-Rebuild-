-- Migration: Add daily_checkins table for streak system
-- This table stores daily check-in data for the App Streak feature

CREATE TABLE IF NOT EXISTS daily_checkins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  hit_macros BOOLEAN NOT NULL,
  training_status TEXT NOT NULL CHECK (training_status IN ('trained', 'off_day')),
  sleep_quality TEXT NOT NULL CHECK (sleep_quality IN ('good', 'okay', 'poor')),
  coach_response TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Ensure only one check-in per user per day
  UNIQUE(user_id, date)
);

-- Index for quick lookups by user and date
CREATE INDEX IF NOT EXISTS idx_daily_checkins_user_date ON daily_checkins(user_id, date DESC);

-- Index for analytics queries
CREATE INDEX IF NOT EXISTS idx_daily_checkins_date ON daily_checkins(date DESC);

-- Comment on table
COMMENT ON TABLE daily_checkins IS 'Stores daily check-in data for the App Streak feature. Users complete a quick 3-question check-in to save their streak.';


