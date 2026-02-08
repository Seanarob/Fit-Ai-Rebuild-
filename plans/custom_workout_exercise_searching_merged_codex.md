# Custom Workout Exercise Searching — Merged Plan

## Goal
Users can search exercises and add them to custom workouts without freezes. Results load reliably, with graceful fallback.

---

## Phase 0 — Verify Hypotheses (30–45 min)
**Purpose:** confirm whether the issue is (a) a client freeze/crash, (b) empty data, or both.

1) **Reproduce on device with debugger**
- Capture the main thread backtrace at freeze.
- Note any EXC_BAD_ACCESS / deadlock in `WorkoutView.searchExercises` or `ExercisePickerModal`.

2) **Check search API output quickly**
- Log the result count from `/exercises/search?query=lat` (or via the app log).
- If results are `[]`, keep a note but **do not** assume DB is empty yet.

3) **Quick DB verification**
- Run `SELECT COUNT(*) FROM exercises;` against Supabase.
- If count = 0 → data is empty.
- If count > 0 → data exists, focus on client freeze.

**Exit criteria:** you know whether the freeze is client‑side and whether the data is empty.

---

## Phase 1 — Client Stability (Highest Priority)
**Objective:** eliminate freezes and crashes regardless of data status.

1) **Async safety**
- Ensure all async search work runs off main thread.
- Ensure all UI state mutations happen on the main actor.
- Cancel any in‑flight searches when query changes or modal dismisses.

2) **Throttle input**
- Debounce user input (300–500ms) and prevent overlapping searches.
- Don’t auto‑search on every keystroke if it triggers freezes; allow submit‑only if needed.

3) **Safe dismissal**
- Cancel search task on modal close to prevent state updates after deinit.

**Exit criteria:** typing in the search field never freezes on device.

---

## Phase 2 — Results Reliability
**Objective:** users see real results quickly.

1) **Empty query behavior**
- If query is empty, show a small local catalog (featured/top exercises), **no network call**.

2) **Fallback logic**
- If API returns empty or fails, display local fallback exercises (`exerciseLibrary`).

3) **Result caps**
- Limit results to a safe number (e.g., 50–100) to avoid rendering stalls.

**Exit criteria:** typing “lat” returns at least local results, even offline.

---

## Phase 3 — Data Verification and Seeding (Conditional)
**Only if Phase 0 confirms `exercises` is empty.**

1) **Seed exercises**
- Add a migration with 100+ common exercises + muscle group + equipment.
- Keep it minimal (core compounds + popular isolations).

2) **Optional: backend default results**
- If query empty, return popular exercises from DB.

**Exit criteria:** `/exercises/search?query=lat` returns data from DB.

---

## Phase 4 — UX Polish (Optional)
- Loading skeletons
- Recent exercises
- “Create custom exercise” when no matches

---

## Testing Checklist
- Tap search field → no freeze (device + simulator).
- Type fast → no freeze.
- Query returns results within 0.5–1s.
- Modal dismiss during search doesn’t crash.
- Add exercise → appears in workout list.

---

## Recommendation
Start with Phase 0 + Phase 1 immediately. If DB is empty, add Phase 3. This avoids wasting time on backend work if the client is still unstable, and ensures the freeze is actually fixed.
