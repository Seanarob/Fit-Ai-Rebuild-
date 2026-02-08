# Custom Workout Exercise Searching - Implementation Plan

## Issue Summary

The exercise search functionality for custom workouts freezes the page and fails to load results. Users cannot search for and add exercises to their custom workouts.

---

## Root Cause Analysis

After investigating the codebase, the following issues have been identified:

### 1. **Empty Exercises Database Table**

The `exercises` table in Supabase is empty. The search endpoint (`/exercises/search`) queries this table but returns no results because no exercise data has been seeded.

**Evidence:**
- No seed data exists in migrations (`supabase/migrations/001_initial_schema.sql`)
- No INSERT statements for exercises found in the codebase
- The search endpoint in `supabase/functions/api/index.ts` (lines 1137-1147) queries the empty table:

```typescript
if (method === "GET" && segments[1] === "search") {
  const query = url.searchParams.get("query") ?? "";
  const limit = Number(url.searchParams.get("limit") ?? 20);
  const { data, error } = await supabase
    .from("exercises")
    .select("*")
    .ilike("name", `%${query}%`)
    .limit(limit);
  if (error) throw new HttpError(500, error.message);
  return jsonResponse({ query, results: data ?? [] });
}
```

### 2. **No Initial Exercise Catalog Load**

In `ExercisePickerModal` (`WorkoutFlows.swift`, lines 99-306), the modal doesn't load any exercises when it first appears:

```swift
.onAppear {
    if catalog.isEmpty {
        isLoading = false  // Just sets loading to false, doesn't trigger search
    }
}
```

This means users see an empty state with "No exercises found" immediately.

### 3. **Fallback Logic Not Triggered on Empty Results**

The `searchExercises` function in `WorkoutView.swift` (lines 959-968) only uses the local fallback when the API throws an error, NOT when it returns an empty array:

```swift
private static func searchExercises(query: String) async -> [ExerciseDefinition] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return fallbackExerciseDefinitions(matching: "")
    }
    do {
        return try await WorkoutAPIService.shared.searchExercises(query: trimmed)
        // Returns empty array from API - no fallback triggered
    } catch {
        return fallbackExerciseDefinitions(matching: trimmed)
    }
}
```

### 4. **Potential UI Freeze Causes**

- The 250ms debounce delay in `performSearch` may cause timing issues
- State updates during async operations may block the main thread
- The `filteredExercises` computed property recalculates on every state change

---

## Implementation Plan

### Phase 1: Database Exercise Seeding (Backend)

**Priority: CRITICAL**

#### Task 1.1: Create Exercise Seed Data Migration

Create a new migration file with comprehensive exercise data:

**File:** `supabase/migrations/007_seed_exercises.sql`

**Contents should include:**
- 100+ common exercises covering all muscle groups
- Proper muscle group assignments (array format)
- Equipment categorization (Barbell, Dumbbell, Cable, Machine, Bodyweight)
- Metadata for exercise type (compound vs isolation)

**Exercise categories to cover:**
| Muscle Group | Compound Exercises | Isolation Exercises |
|--------------|-------------------|---------------------|
| Chest | Bench Press, Incline Press, Push-ups | Cable Fly, Pec Deck, Dumbbell Fly |
| Back | Pull-ups, Rows, Lat Pulldown | Face Pulls, Straight-Arm Pulldown |
| Shoulders | Overhead Press, Push Press | Lateral Raise, Rear Delt Fly |
| Arms | Close-Grip Bench, Chin-ups | Bicep Curl, Tricep Extension |
| Legs | Squat, Deadlift, Leg Press | Leg Extension, Leg Curl |
| Core | Hanging Leg Raise | Crunches, Planks |
| Glutes | Hip Thrust, RDL | Glute Bridge, Kickbacks |

#### Task 1.2: Apply Migration to Supabase

Run the migration against the production Supabase database.

---

### Phase 2: Frontend Exercise Search Fixes (iOS)

**Priority: HIGH**

#### Task 2.1: Load Initial Exercise Catalog on Modal Appear

**File:** `FIT AI/FIT AI/WorkoutFlows.swift`

Modify `ExercisePickerModal` to load popular/featured exercises when the modal opens:

```swift
.onAppear {
    Task {
        isLoading = true
        // Load featured/popular exercises initially
        catalog = await onSearch("")  // Empty query returns all or featured
        isLoading = false
    }
}
```

#### Task 2.2: Improve Fallback Logic

**File:** `FIT AI/FIT AI/WorkoutView.swift`

Update `searchExercises` to use fallback when API returns empty results:

```swift
private static func searchExercises(query: String) async -> [ExerciseDefinition] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
        let results = try await WorkoutAPIService.shared.searchExercises(query: trimmed)
        // Use fallback if API returns empty
        if results.isEmpty {
            return fallbackExerciseDefinitions(matching: trimmed)
        }
        return results
    } catch {
        return fallbackExerciseDefinitions(matching: trimmed)
    }
}
```

#### Task 2.3: Expand Local Exercise Library

**File:** `FIT AI/FIT AI/WorkoutView.swift`

Expand `exerciseLibrary` to include more exercises for robust fallback:

Current library has ~30 exercises. Expand to 80+ exercises covering:
- More variations (e.g., Incline, Decline, Seated, Standing)
- More equipment options
- Popular exercises users expect to find

#### Task 2.4: Debounce Search Input (Live Search)

**File:** `FIT AI/FIT AI/WorkoutFlows.swift`

Implement live search as user types (instead of only on submit):

```swift
.onChange(of: searchText) { newValue in
    submitTask?.cancel()
    submitTask = Task {
        await performSearch(for: newValue)
    }
}
```

---

### Phase 3: Fix UI Freeze Issues (iOS)

**Priority: HIGH**

#### Task 3.1: Ensure Main Actor for UI Updates

**File:** `FIT AI/FIT AI/WorkoutFlows.swift`

Verify all UI state updates happen on MainActor:

```swift
private func performSearch(for query: String) async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Debounce
    if !trimmed.isEmpty {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    guard !Task.isCancelled else { return }
    
    await MainActor.run { isLoading = true }
    
    let results = await onSearch(trimmed)
    
    guard !Task.isCancelled else { return }
    
    await MainActor.run {
        catalog = Array(results.prefix(60))
        isLoading = false
    }
}
```

#### Task 3.2: Add Loading State to Prevent Multiple Searches

Prevent overlapping search requests:

```swift
@State private var isSearching = false

private func performSearch(for query: String) async {
    guard !isSearching else { return }
    isSearching = true
    defer { 
        Task { @MainActor in isSearching = false }
    }
    // ... rest of search logic
}
```

#### Task 3.3: Optimize `filteredExercises` Computed Property

Cache filter results to prevent recalculation on every render:

```swift
@State private var cachedFilteredExercises: [ExerciseDefinition] = []

// Update cache when dependencies change
.onChange(of: searchText) { _ in updateFilteredExercises() }
.onChange(of: selectedMuscleGroups) { _ in updateFilteredExercises() }
.onChange(of: selectedEquipment) { _ in updateFilteredExercises() }
.onChange(of: catalog) { _ in updateFilteredExercises() }

private func updateFilteredExercises() {
    cachedFilteredExercises = catalog.filter { exercise in
        let matchesSearch = searchText.isEmpty ||
            exercise.name.lowercased().contains(searchText.lowercased())
        let matchesMuscle = selectedMuscleGroups.isEmpty ||
            !selectedMuscleGroups.isDisjoint(with: exercise.muscleGroups)
        let matchesEquipment = selectedEquipment.isEmpty ||
            !selectedEquipment.isDisjoint(with: exercise.equipment)
        return matchesSearch && matchesMuscle && matchesEquipment
    }
}
```

---

### Phase 4: Backend API Improvements

**Priority: MEDIUM**

#### Task 4.1: Add Default/Featured Exercises Endpoint

**File:** `supabase/functions/api/index.ts`

Modify search to return popular exercises when query is empty:

```typescript
if (method === "GET" && segments[1] === "search") {
  const query = url.searchParams.get("query") ?? "";
  const limit = Number(url.searchParams.get("limit") ?? 30);
  
  let data;
  if (query.trim() === "") {
    // Return popular/featured exercises when no query
    const result = await supabase
      .from("exercises")
      .select("*")
      .order("name")
      .limit(limit);
    data = result.data;
  } else {
    const result = await supabase
      .from("exercises")
      .select("*")
      .ilike("name", `%${query}%`)
      .limit(limit);
    data = result.data;
  }
  
  return jsonResponse({ query, results: data ?? [] });
}
```

#### Task 4.2: Add Full-Text Search Support

Enable PostgreSQL full-text search for better matching:

**Migration file:** `supabase/migrations/008_exercises_fulltext_search.sql`

```sql
-- Add search vector column
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS search_vector tsvector;

-- Create index
CREATE INDEX IF NOT EXISTS idx_exercises_search ON exercises USING gin(search_vector);

-- Update existing rows
UPDATE exercises SET search_vector = 
  to_tsvector('english', coalesce(name, '') || ' ' || 
  coalesce(array_to_string(muscle_groups, ' '), ''));

-- Create trigger for future updates
CREATE OR REPLACE FUNCTION exercises_search_trigger() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := to_tsvector('english', 
    coalesce(NEW.name, '') || ' ' || 
    coalesce(array_to_string(NEW.muscle_groups, ' '), ''));
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER exercises_search_update 
  BEFORE INSERT OR UPDATE ON exercises 
  FOR EACH ROW EXECUTE FUNCTION exercises_search_trigger();
```

---

### Phase 5: UX Improvements

**Priority: LOW**

#### Task 5.1: Add Loading Skeleton

Show placeholder UI while exercises load:

```swift
if isLoading {
    ForEach(0..<5, id: \.self) { _ in
        ExercisePickerRowSkeleton()
    }
}
```

#### Task 5.2: Add "Recently Used" Section

Track and display user's recently used exercises at the top of results.

#### Task 5.3: Add "Create Custom Exercise" Option

Allow users to add exercises not in the database:

```swift
if filteredExercises.isEmpty && !searchText.isEmpty {
    Button("Create '\(searchText)' as new exercise") {
        onAdd(ExerciseDefinition(
            name: searchText,
            muscleGroups: [],
            equipment: []
        ))
    }
}
```

---

## Testing Checklist

- [ ] Exercises load when search modal opens
- [ ] Search returns results within 500ms
- [ ] UI does not freeze during search
- [ ] Filters (muscle groups, equipment) work correctly
- [ ] Empty search state shows helpful message
- [ ] Fallback exercises show when API fails
- [ ] "Add" button works and adds exercise to workout
- [ ] Already-added exercises show "Added" state
- [ ] Modal dismiss works correctly

---

## Files to Modify

| File | Changes |
|------|---------|
| `supabase/migrations/007_seed_exercises.sql` | NEW - Seed exercise data |
| `supabase/functions/api/index.ts` | Update search endpoint |
| `FIT AI/FIT AI/WorkoutFlows.swift` | Fix ExercisePickerModal |
| `FIT AI/FIT AI/WorkoutView.swift` | Improve search + fallback logic |
| `FIT AI/FIT AI/WorkoutAPIService.swift` | Add timeout handling |

---

## Estimated Timeline

| Phase | Effort | Priority |
|-------|--------|----------|
| Phase 1: Database Seeding | 2-3 hours | CRITICAL |
| Phase 2: Frontend Search Fixes | 3-4 hours | HIGH |
| Phase 3: UI Freeze Fixes | 2-3 hours | HIGH |
| Phase 4: Backend Improvements | 2-3 hours | MEDIUM |
| Phase 5: UX Improvements | 3-4 hours | LOW |

**Total Estimated Time:** 12-17 hours

---

## Quick Fix (Immediate Relief)

For immediate relief before full implementation, apply these minimal changes:

1. **Load fallback exercises on modal appear:**

```swift
// In ExercisePickerModal .onAppear
.onAppear {
    Task {
        catalog = await onSearch("")
        if catalog.isEmpty {
            // Use fallback immediately
            catalog = WorkoutView.fallbackExerciseDefinitions(matching: "")
        }
    }
}
```

2. **Make fallbackExerciseDefinitions accessible:**

Move `fallbackExerciseDefinitions` and `exerciseLibrary` to a shared location or make them static/internal for access from `WorkoutFlows.swift`.

This provides immediate functionality while the full solution is implemented.




