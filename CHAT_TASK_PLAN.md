# FIT AI iOS - Chat Features Task Plan

> **Created:** February 1, 2026
> **Status:** Planning only (no code changes yet)
> **Project Path:** `/Users/seanrobinson/FIT AI IOS/Fit-Ai-Rebuild-/`

---

## Goals (from request)
- Keep chat responses short (under 18 words) and in a single message (no multi-block splits).
- Trigger workout building when the user asks; use the existing workout-generation tool.
- Show “Coaches Pick” text for today’s training on both Home and Workout tabs.
- During generation: send “One moment while I build your workout.”
- After generation: tell the user the workout is live in their workout view.
- Chat can read live workouts (active sets/reps/weight) for feedback.
- Do not load prior chat messages; new session on cold launch.
- Fix chat delay and partial messages that appear only after tab switch.

---

## Phase 1: Audit & Repro
- Locate current chat flow (backend endpoint and iOS client) and message persistence.
- Identify streaming or chunked response behavior causing partial message display.
- Confirm how workouts are currently generated and how the chat triggers that tool.
- Map where “Today’s training” UI is rendered on Home and Workout tabs.

## Phase 2: Data & State Design
- Define a local, device-stored “ActiveWorkoutSnapshot” model that captures:
  - exercise name, set number, reps, weight, timestamp
  - current exercise/active set index
- Decide where the chat request builds its context:
  - pull from local workout snapshot
  - optionally include last workout summary if active session is empty
- Define a chat session lifecycle:
  - new session on cold launch (no historical messages)
  - keep in-session memory after launch (until app quits)

## Phase 3: Chat Response Behavior
- Enforce single-message responses in the backend or client renderer.
- Constrain output length to under 18 words (backend prompt + max tokens).
- Ensure streaming (if used) is properly appended and rendered in-place.
- Ensure “build workout” flow sends:
  1) immediate “One moment…” message
  2) final “Workout is live…” message after tool completion

## Phase 4: Workout Generation Flow
- Ensure chat intent routing detects workout requests (e.g., “glute workout”).
- Call the existing workout generation tool with user goal context.
- Confirm new workout is persisted and visible in Workout tab.

## Phase 5: UI Copy + Labels
- Add “Coaches Pick” label to Today’s Training on:
  - Home tab
  - Workout tab
- Confirm label is visible for both generated and suggested workouts.

## Phase 6: Validation & UX QA
- Verify chat no longer shows old messages after cold relaunch.
- Verify single, short response for standard Q&A.
- Verify workout feedback references live active sets/reps/weight.
- Verify no message truncation or delayed display.
- Verify generation flow messages appear in order without leaving the tab.

---

## Target Files (to inspect when you give the go-ahead)
- `Fit-Ai-Rebuild-/backend/app/routers/chat.py`
- iOS chat view / view model files (to identify)
- iOS workout session storage / logger (to identify)
- Home and Workout tab UI files (to identify)

---

## Open Questions
- If no active workout is in progress, should feedback still reference last logged workout (even though you expect this question only during workouts)?
