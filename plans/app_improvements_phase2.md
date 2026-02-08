# FIT AI App Improvements - Phase 2

**Created:** January 29, 2026  
**Status:** Planning Phase

---

## Progress Overview

| Category | Completed | Total |
|----------|-----------|-------|
| Color Blocking | 0 | 3 |
| Workout Features | 0 | 3 |
| Check-in Improvements | 0 | 3 |
| Profile Features | 0 | 1 |
| UI/UX Redesign | 0 | 2 |
| **TOTAL** | **0** | **12** |

---

## Checklist

### 1. Color Blocking Expansion

- [ ] **1.1 Apply Color Blocking to Workout Page**
  - Use `cardWorkout` colors for workout-related cards
  - Update `WorkoutView.swift` CardContainer usages
  - Apply to: Today's Training, Saved Workouts, Create Workout, AI Workout Builder

- [ ] **1.2 Apply Color Blocking to Nutrition Page**
  - Use `cardNutrition` colors for meal/food cards
  - Update `NutritionView.swift` CardContainer usages
  - Apply to: Macro summary, Meal plan, Meal sections

- [ ] **1.3 Apply Color Blocking to Progress Page**
  - Use `cardProgress` colors for progress/stats cards
  - Update `ProgressTabView.swift` CardContainer usages

---

### 2. Workout Tab Improvements

- [ ] **2.1 Make Today's Training Clickable in Workout Tab**
  - Add tap gesture to Today's Training card
  - Navigate to workout detail/start view

- [ ] **2.2 AI Workout Builder Card → Edit Plan**
  - When AI Workout Builder clicked, open same view as "Edit Plan"

- [ ] **2.3 Workout Generation Loading Card**
  - Show "Generating your workout..." card with animation
  - Match visual style of check-in analyzing card

---

### 3. Check-in Improvements

- [ ] **3.1 Accurate Check-in Day Calculation**
  - Use user's chosen check-in day from onboarding
  - Calculate next occurrence of chosen weekday correctly

- [ ] **3.2 Check-in Card Click → Start Check-in Flow**
  - Navigate to same view as "Start Check-in" button

- [ ] **3.3 Weekly Check-in Card Redesign**
  - Redesign `CheckInReminderCard` UI/UX
  - Apply `cardReminder` color blocking
  - Improve visual hierarchy and urgency indicators

---

### 4. Profile Features

- [ ] **4.1 Profile Snapshot → Editable Profile Card**
  - Make Profile Snapshot card tappable
  - Create `ProfileEditSheet` with editable fields:
    - Name, Height, Weight, Age, Gender, Goal
  - Save to UserDefaults and backend

---

### 5. UI/UX Redesigns

- [ ] **5.1 Coach Chat Tab Redesign**
  - Redesign `CoachChatView.swift`
  - Apply `cardCoach` color blocking
  - Improve message bubbles, input area, header

- [ ] **5.2 White Text on Purple Backgrounds**
  - Create `FitTheme.textOnAccent = Color.white`
  - Apply throughout app on all purple/accent backgrounds
  - Locations: buttons, tags, badges, gradients

---

## Implementation Order

### Phase 2A - Quick Fixes
- [ ] 5.2 White text on purple backgrounds
- [ ] 2.1 Today's Training clickable
- [ ] 3.2 Check-in card click behavior

### Phase 2B - Color Blocking Expansion
- [ ] 1.1 Workout page colors
- [ ] 1.2 Nutrition page colors
- [ ] 1.3 Progress page colors

### Phase 2C - Check-in & Profile
- [ ] 3.1 Accurate check-in day calculation
- [ ] 3.3 Check-in card redesign
- [ ] 4.1 Profile edit card

### Phase 2D - Major Redesigns
- [ ] 2.2 AI Workout Builder → Edit Plan
- [ ] 2.3 Workout generation loading card
- [ ] 5.1 Coach chat redesign

---

## Files to Modify

| Feature | Primary Files |
|---------|--------------|
| 1.1 Workout colors | `WorkoutView.swift` |
| 1.2 Nutrition colors | `NutritionView.swift` |
| 1.3 Progress colors | `ProgressTabView.swift` |
| 2.1-2.3 Workout features | `WorkoutView.swift`, `WorkoutFlows.swift` |
| 3.1-3.2 Check-in logic | `HomeViewModel.swift`, `HomeView.swift` |
| 3.3 Check-in card | `HomeView.swift` (CheckInReminderCard) |
| 4.1 Profile edit | `HomeView.swift`, new `ProfileEditSheet` |
| 5.1 Chat redesign | `CoachChatView.swift` |
| 5.2 White text | `FitTheme`, multiple files |

---

## Navigation Flow Mappings

| Card Clicked | Should Open |
|--------------|-------------|
| Today's Training (Workout tab) | Start workout / workout detail |
| AI Workout Builder | Edit Plan view |
| Weekly Check-in (Home) | Start Check-in flow |
| Profile Snapshot | Profile Edit sheet |

---

## Completed Tasks Log

| Task | Completed Date | Notes |
|------|----------------|-------|
| *None yet* | | |



