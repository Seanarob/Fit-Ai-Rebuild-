# FIT AI - Phase 3 Improvements Task List

## Overview
This document outlines the bugs, UI/UX improvements, and new features to be implemented. Target audience: serious gym goers and beginners learning to start in the gym.

---

## 🔴 Critical Bug Fixes

### 1. Profile Card Issues ✅ COMPLETED
- [x] **Profile changes don't save** - Fixed goal mapping, added proper API payload
- [x] **Keyboard dismissal broken** - Added tap gesture and dismissKeyboard function

### 2. Text Visibility Issues (App-Wide) ✅ COMPLETED
- [x] **White text on white backgrounds** - Fixed in OnboardingView
  - Fixed welcome screen text colors
  - Fixed Sign In/Create Account buttons (now use textOnAccent)
  - Fixed all TextField foreground colors
- [x] **Rule**: All text now has proper foregroundColor set

### 3. Workout Tab Crashes ✅ COMPLETED
- [x] **Today's Training start button crashes** - Added better error handling in startSession
- [x] **Saved workouts three-dots menu crashes** - Added loading states
- [x] **Starting saved workouts crashes** - Added fallback view for invalid sessions

---

## 🟠 Core Feature Fixes

### 4. Coach Chat - New Thread Support ✅ COMPLETED
- [x] Add ability to start a new conversation thread
- [x] Added "New Chat" button (plus.message icon) in coach chat toolbar
- [x] Calls viewModel.createThread() with haptic feedback

### 5. Exercise Logging UX Fix ✅ COMPLETED
- [x] **Exercise row tap behavior** - Only arrow button now navigates to exercise detail page
- [x] Main row no longer navigates on tap
- [x] **Added visible three-dots Menu** with superset, drop set, edit, and clear tag options

### 6. Meal Plan Editing ✅ COMPLETED (Already Implemented)
- [x] **Meals are editable** - MealPlanDetailSheet allows modification
- [x] **Delete individual ingredients** - Swipe to delete functionality
- [x] **Add new ingredients** - Add ingredient text field with plus button
- Note: Quantities need to come from backend API

---

## 🟡 Nutrition Tab Enhancements

### 7. Macro Ring Toggle System ✅ COMPLETED
- [x] **Added segmented picker toggle**: "Remaining" ↔ "Consumed"
- [x] **Remaining mode**: Rings show how much is LEFT to eat
- [x] **Consumed mode**: Rings show how much has been EATEN
- [x] **Over-goal state**: Ring turns RED when exceeding target, shows "Xg over"

---

## 🟢 UI/UX Redesign

### 8. Color Blocking Overhaul ✅ COMPLETED
**Problem**: Nutrition, Progress, and Workout tabs all have same colors - doesn't look good or make sense.

**Solution**:
- [x] **Strategic color blocking** - Only key feature cards are accented
- [x] **WorkoutCard** - Updated with `isAccented` parameter for strategic highlighting
- [x] **NutritionView** - Macro summary card is accented
- [x] **ProgressTabView** - Weight trend card is accented
- [x] Default cards use neutral colors, feature cards use tab-specific accent colors

### 9. Coach Chat Complete Redesign ✅ COMPLETED
**Target Audience**: Serious gym-goers AND beginners

- [x] **Modern, motivational aesthetic** - Gym-focused theme with strength icons
- [x] **Clean message bubbles** with proper contrast and coach avatar
- [x] **Coach avatar** - Gradient circle with dumbbell/strength icon
- [x] **Quick action suggestions** - Gym-specific icons (dumbbell, calendar, fork, flame)
- [x] **Thread header** - Animated pulse effect, motivational subtitle

### 10. Progress Tab - Weight Trend Chart ✅ COMPLETED
- [x] **Match onboarding weight trend style** - Added AreaMark with gradient fill
- [x] Same colors (cardProgressAccent) and visual design
- [x] Catmull-Rom interpolation for smooth curves
- [x] Point markers with white fill and colored stroke

### 11. Homepage - Progress Summary Card Redesign ✅ COMPLETED
- [x] **Encouraging and motivating** - "You're making great strides! 💪" message
- [x] Display user's PRs prominently with trophy icon
- [x] Show current weight with trend visualization
- [x] Chart icon in header with accent background
- [x] Progress accent color scheme

### 12. Homepage - Streak Icon Enhancement ✅ COMPLETED
**Gen Z loves streaks!**

- [x] **Made streak icon BIGGER and more prominent** - New StreakBadge with large flame
- [x] Eye-catching design with animated glow effect
- [x] Animated/dynamic appearance with pulsing flame
- [x] Shows streak number prominently with day count

---

## 🔵 New Feature: Daily Streak System ✅ COMPLETED

### 13. Streak Mechanics & Animation
- [x] **Daily app open = streak increment** - Uses AppStorage for persistence
- [x] Tracks last open date in UserDefaults (fitai.appOpen.lastDate)
- [x] Increments streak on consecutive days, resets if day missed

- [x] **Welcome screen on first daily open** - DailyCoachGreetingView
  - Shows streak count in greeting message
  - Time-based greeting (Good morning/afternoon/evening)
  
- [x] **Streak celebration animation** - StreakCelebrationView:
  - After user taps "Next" or "Get Started"
  - Show streak number evolving animation
  - Number animates from previous → new value
  - Fire/celebration effects
  - **Haptic feedback** (impact or notification)
  
- [ ] **Streak persistence**:
  - Save streak count
  - Track consecutive days
  - Handle streak breaks gracefully

---

## Implementation Order

### Phase 3A - Critical Fixes (Do First)
1. Profile save fix + keyboard dismissal
2. Text visibility audit (white on white)
3. Workout crashes (Today's Training, saved workouts)

### Phase 3B - Core Features
4. Coach chat new thread
5. Exercise logging UX (tap behavior, three-dots menu)
6. Meal plan editing with quantities

### Phase 3C - Nutrition Enhancement
7. Macro ring toggle (remaining/consumed/over)

### Phase 3D - Visual Redesign
8. Color blocking overhaul (all tabs)
9. Coach chat redesign
10. Weight trend chart styling
11. Progress summary card redesign
12. Streak icon enhancement

### Phase 3E - Streak Feature
13. Daily streak system with animation

---

## Technical Notes

### Text Visibility Fix Strategy
```swift
// Ensure text colors adapt to background
// Use semantic colors:
FitTheme.textPrimary    // For light backgrounds
FitTheme.textOnAccent   // For purple/dark backgrounds
FitTheme.textSecondary  // For secondary text
```

### Keyboard Dismissal Pattern
```swift
// Add to views with text fields
.onTapGesture {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
```

### Streak Animation Approach
- Use SwiftUI `.transition()` and `.animation()`
- Number counter animation with `Text("\(count)").contentTransition(.numericText())`
- Haptics via `UIImpactFeedbackGenerator`

---

## Files Likely to be Modified

- `HomeView.swift` - Streak, progress summary, greeting
- `ProfileEditSheet` (in HomeView) - Save fix, keyboard
- `WorkoutView.swift` - Crash fixes, color blocking
- `WorkoutFlows.swift` - Exercise tap behavior, three-dots
- `NutritionView.swift` - Ring toggle, meal editing, color blocking
- `ProgressTabView.swift` - Weight trend, color blocking
- `CoachChatView.swift` - Complete redesign, new thread
- `OnboardingView.swift` - Text visibility
- `FitTheme` colors - New color palette
- Backend meal plan endpoints - Quantities support

---

*Awaiting approval to begin implementation.*

