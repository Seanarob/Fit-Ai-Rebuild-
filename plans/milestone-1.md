# Milestone 1 Checklist – Foundations & Directions

## 1. Design mockups
- [ ] Onboarding flow (12 steps, macro targets, dietary preferences)
- [ ] First-login walkthrough + setup prompt (check-in day + starting photos)
- [ ] Home dashboard with stacked cards (training, nutrition, progress)
- [ ] Workout tab (Generate/Saved/Create + session screen + exercise history/1RM)
- [ ] Nutrition tab (macros summary + search/scan + meal plan + grocery list)
- [ ] Progress tab (photo gallery + weekly check-in card + results breakdown)
- [ ] More tab (goals/macros, check-in day, starting photos, walkthrough replay, subscription status)

## 2. Supabase schema
- [ ] `users`, `profiles`, `auth_tokens` (check-in day, tutorial completion)
- [ ] `onboarding_states`, `progress_photos`, `weekly_checkins` (AI comparison fields)
- [ ] `workout_templates`, `workout_template_exercises`, `workout_sessions`, `exercise_logs`, `prs`
- [ ] `exercises` catalog
- [ ] `nutrition_logs`, `food_items`, `meal_plans`, `search_history`, `nutrition_favorites`
- [ ] `ai_prompts`, `ai_jobs`
- [ ] `payment_records`

## 3. FastAPI + OpenAI prompts
- [ ] Endpoints for workout generation, meal photo parsing, meal plan generation, check-in analysis
- [ ] Exercise history endpoint with estimated 1RM calculations
- [ ] Prompt template store (versioned, server-side)
- [ ] Logging of request/response metadata for audits
- [ ] Supabase persistence for AI drafts + approved results

## 4. Frontend scaffolding (Expo/SwiftUI)
- [ ] Design system components (Card, StatRow, ProgressBar, PrimaryButton, SegmentedControl, ExerciseCard, ChartCard, PhotoGrid)
- [ ] Navigation shell (auth stack + 5 tabs incl More)
- [ ] First-login walkthrough + required setup (check-in day, starting photos)
- [ ] Data layer hookups to Supabase (auth, profile, logs, meal plans, payments)

## 5. Review checkpoints
- [ ] Approve mockups before implementing UI
- [ ] Validate schema design with backend
- [ ] Confirm OpenAI prompt versions & inputs
- [ ] Confirm check-in comparison output + 1RM formula requirements
- [ ] Validate meal plan + grocery list scope
