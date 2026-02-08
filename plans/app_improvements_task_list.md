# FIT AI App Improvements Checklist

**Created:** January 29, 2026  
**Last Updated:** January 29, 2026  
**Status:** ✅ COMPLETE

---

## Progress Overview

| Category | Completed | Total |
|----------|-----------|-------|
| UI/UX | 1 | 1 |
| Workout | 2 | 2 |
| Nutrition | 4 | 4 |
| Meal Plan | 2 | 2 |
| Onboarding | 3 | 3 |
| Reminders | 1 | 1 |
| AI Coach | 1 | 1 |
| **TOTAL** | **14** | **14** |

---

## Checklist

### 1. UI/UX Improvements

- [x] **1.1 Color Blocking for Cards** ✅
  - Added 6 distinct card color sets to FitTheme:
    - `cardNutrition` - warm coral/salmon tint
    - `cardWorkout` - cool blue/indigo tint  
    - `cardProgress` - soft teal/mint tint
    - `cardCoach` - warm purple tint
    - `cardReminder` - amber/gold tint
    - `cardStreak` - gradient purple-blue
  - Updated CardContainer to accept backgroundColor and accentBorder
  - Applied colors to TodayTrainingCard, CoachQuickCard, GoalCard
  - InfoChip now accepts optional accentColor

---

### 2. Workout Features

- [x] **2.1 Weight Recommendations for Workouts** ✅
  - Fetches exercise history via `WorkoutAPIService.fetchExerciseHistory()`
  - Calculates recommended weight: 2.5% progressive overload from best set
  - Rounds to nearest 5 lbs (or 2.5 kg for metric)
  - Shows recommendation card with "Apply" button in WorkoutExerciseLoggingSheet
  - Displays last best set info for context
  - "Apply" button fills weight into all incomplete working sets

- [x] **2.2 Today's Training - Show Listed Workout** ✅
  - Made TodayTrainingCard expandable with chevron button
  - Shows preview (2 exercises) collapsed, full workout expanded
  - Displays exercise name, sets × reps when expanded
  - Added duration estimate and workout type label
  - Tap "+X more exercises" to expand

---

### 3. Nutrition & Food Logging

- [x] **3.1 Flexible Serving Sizes** ✅
  - Backend now returns all serving options from FatSecret API
  - Added `ServingOption` model with pre-calculated macros per serving
  - Updated UI with horizontal serving picker (1 egg, 1 banana, etc.)
  - Macros update dynamically based on selected serving
  - Custom g/oz still available as fallback

- [x] **3.2 Calorie Display - Over/Under Tracking** ✅
  - Added calorie status banner showing "X kcal remaining" or "Over by X kcal"
  - Color coded: green when under, red when over
  - MacroRingView now changes to red when over target
  - Header shows consumed/target ratio
  - Large calorie ring shows "left" or "over" status

- [x] **3.3 Barcode Scanning Fix** ✅
  - Fixed camera permission handling with explicit authorization check
  - Added background thread for session start/stop
  - Added more barcode types: UPC-A, Code39, Code93, ITF14, DataMatrix, QR
  - Added haptic feedback on successful scan
  - Added continuous autofocus for better detection

- [x] **3.4 FatSecret Autocomplete for Food Search** ✅
  - Added `/fatsecret/autocomplete` backend endpoint using FatSecret foods.autocomplete API
  - Added `autocompleteFoods()` method to NutritionAPIService
  - Implemented 300ms debounced autocomplete in NutritionLogSheet
  - Dropdown appears below search field with suggestions
  - Tap suggestion to auto-fill and search

---

### 4. Meal Plan Features

- [x] **4.1 Meal Plan Adjustability** ✅
  - Meals in meal plan are now tappable to open detail view
  - "Swap For Different Meal" button regenerates the meal plan
  - Future enhancement: single-meal regeneration endpoint

- [x] **4.2 Meal Detail View with Macro Breakdown** ✅
  - Created `MealPlanDetailSheet` component
  - Shows total calories with large display
  - Color-coded macro breakdown (Protein/Carbs/Fat)
  - Full ingredient list with bullet points
  - "Log This Meal" and "Swap" action buttons

---

### 5. Onboarding Improvements

- [x] **5.1 Ask User Name** ✅
  - Added name input as step 1 (right after welcome)
  - Clean text field with centered input and personalization hint
  - Name saved to OnboardingForm and synced to backend via full_name field
  - Validation requires non-empty name to proceed

- [x] **5.2 Ask Preferred Check-in Day** ✅
  - Added check-in day picker as step 8 (after activity level)
  - Day of week selector (Sunday-Saturday) using CheckinDayButton
  - Helpful hint explaining weekly AI coach check-ins
  - Synced to backend via checkin_day preference field

- [x] **5.3 Macros Roll Over from Onboarding** ✅
  - Added local fallback to load macros from OnboardingForm in UserDefaults
  - NutritionView now loads local macros first, then fetches from server
  - HomeView now loads local macros as immediate fallback
  - Display name also loads from local form if not set

---

### 6. Check-in & Reminders

- [x] **6.1 Check-in Reminder on Dashboard** ✅
  - Added CheckInReminderCard component with dynamic styling
  - Shows "Check-in in X days" for upcoming, "Check-in day is today!" when due
  - Shows "You missed your check-in! Check in ASAP" when overdue with red styling
  - Added lastCheckinDate tracking in HomeViewModel
  - Card color changes: normal → orange (due soon) → red (overdue)

---

### 7. AI Coach Improvements

- [x] **7.1 Reduce Response Delay** ✅
  - Parallelized moderation, context building, history, and summary fetching
  - User message insertion now runs in background (non-blocking)
  - Increased iOS timeouts (30s request, 90s resource)
  - Already uses streaming and gpt-4o-mini (fast model)

---

## Implementation Order (Suggested)

### Phase 1 - Critical Fixes ✅ COMPLETE
- [x] 3.3 Barcode scanning fix
- [x] 5.3 Macros roll over from onboarding
- [x] 7.1 AI coach response time

### Phase 2 - Core Features ✅ COMPLETE
- [x] 3.1 Flexible serving sizes
- [x] 3.2 Calorie over/under display
- [x] 2.2 Today's training workout list
- [x] 6.1 Check-in reminder dashboard

### Phase 3 - Onboarding ✅ COMPLETE
- [x] 5.1 Ask user name
- [x] 5.2 Ask preferred check-in day

### Phase 4 - Enhancements ✅ COMPLETE
- [x] 3.4 FatSecret autocomplete
- [x] 2.1 Weight recommendations
- [x] 4.1 Meal plan adjustability
- [x] 4.2 Meal detail with macro breakdown

### Phase 5 - Polish ✅ COMPLETE
- [x] 1.1 Color blocking for cards

---

## Completed Tasks Log

| Task | Completed Date | Notes |
|------|----------------|-------|
| 3.3 Barcode Scanning Fix | Jan 29, 2026 | Added camera permissions, more barcode types, haptic feedback |
| 5.3 Macros Roll Over | Jan 29, 2026 | Added local fallback for macros from UserDefaults |
| 7.1 AI Coach Response | Jan 29, 2026 | Parallelized backend operations, increased timeouts |
| 3.1 Flexible Serving Sizes | Jan 29, 2026 | Backend returns all FatSecret serving options, UI picker added |
| 3.2 Calorie Over/Under | Jan 29, 2026 | Status banner, color-coded rings, remaining/over display |
| 2.2 Today's Training List | Jan 29, 2026 | Expandable card with sets × reps details |
| 6.1 Check-in Reminder | Jan 29, 2026 | Dynamic reminder card with overdue styling |
| 5.1 Ask User Name | Jan 29, 2026 | Added as step 1 with centered text field |
| 5.2 Check-in Day Preference | Jan 29, 2026 | Added as step 8 with day of week picker |
| 3.4 FatSecret Autocomplete | Jan 29, 2026 | Backend endpoint + debounced dropdown suggestions |
| 2.1 Weight Recommendations | Jan 29, 2026 | Progressive overload calc + apply button in exercise sheet |
| 4.1 Meal Plan Adjustability | Jan 29, 2026 | Tappable meals + swap/regenerate button |
| 4.2 Meal Detail Sheet | Jan 29, 2026 | Macro breakdown + ingredients list + log action |
| 1.1 Color Blocking | Jan 29, 2026 | 6 themed card colors + updated CardContainer + applied to key cards |

---

## Notes

- Many features depend on backend API support
- FatSecret API documentation: https://platform.fatsecret.com/api/
- Barcode scanning should be tested on physical device, not simulator
- Consider A/B testing AI models to measure latency improvements

---

## Questions to Clarify

1. For weight recommendations - should this use ML or simple progressive overload rules?
2. For meal plan - is there an existing meal plan feature or needs to be built?
3. For check-ins - what data should be collected during a check-in?
4. Color palette preferences for card color blocking?
