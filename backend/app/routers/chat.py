import asyncio
import json
import os
import re
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from typing import Generator

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from openai import OpenAI
from pydantic import BaseModel, Field

from ..supabase_client import get_supabase

# Thread pool for parallel I/O operations
_executor = ThreadPoolExecutor(max_workers=4)

router = APIRouter()


SYSTEM_PROMPT = """You are FitAI Coach - a gym buddy who texts quick, punchy advice.

RESPONSE RULES (CRITICAL):
- MAX 18 words. Prefer 1 sentence; 2 sentences allowed only if under 18 words.
- Single response only. No multi-part replies or separate messages.
- NO bullet points, lists, or headers unless explicitly asked.
- NEVER repeat info from previous messages or restate what you already know.
- Be encouraging but brief - like texting a friend between sets.
- Only fitness/nutrition topics. Politely redirect others.
- For injuries: one brief tip + "see a professional."
- If user gender is provided, tailor advice and examples accordingly; use neutral language otherwise.

ACTIVE WORKOUT MODE:
- If device_active_workout or active_workout_session is present, they're mid-workout.
- Reference their current exercises and performance naturally, especially last_completed_set if present.
- Keep feedback under 18 words.

WORKOUT GENERATION:
- If user asks to build/create/make/generate a workout, use the generate_workout function.
- Do NOT list exercises yourself.
- Final message must be under 18 words and mention the workout view.

CONTEXT: You have user profile, macros, nutrition, workout history, PRs, templates, and live workout data."""

MAX_COACH_WORDS = 18

WORKOUT_KEYWORDS = (
    "workout",
    "routine",
    "session",
)

WORKOUT_ACTIONS = (
    "build",
    "create",
    "make",
    "generate",
    "design",
    "plan",
)

MUSCLE_KEYWORDS = {
    "glute": "glutes",
    "glutes": "glutes",
    "booty": "glutes",
    "hamstring": "hamstrings",
    "hamstrings": "hamstrings",
    "quad": "quads",
    "quads": "quads",
    "leg": "legs",
    "legs": "legs",
    "calf": "calves",
    "calves": "calves",
    "chest": "chest",
    "pec": "chest",
    "pecs": "chest",
    "back": "back",
    "lat": "back",
    "lats": "back",
    "shoulder": "shoulders",
    "shoulders": "shoulders",
    "delt": "shoulders",
    "delts": "shoulders",
    "biceps": "biceps",
    "triceps": "triceps",
    "arms": "arms",
    "core": "core",
    "abs": "core",
    "upper": "upper body",
    "lower": "lower body",
    "push": "push",
    "pull": "pull",
    "full body": "full body",
    "hiit": "hiit",
}


# OpenAI function definitions for coach actions
COACH_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "generate_workout",
            "description": "Creates a new workout for the user based on their request. Call this when the user asks to build, create, make, or generate a workout.",
            "parameters": {
                "type": "object",
                "properties": {
                    "focus": {
                        "type": "string",
                        "description": "Primary focus of the workout (e.g., 'leg workout focusing on glutes', 'upper body push', 'chest and triceps')"
                    },
                    "muscle_groups": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Target muscle groups (e.g., ['glutes', 'quads', 'hamstrings'] or ['chest', 'triceps'])"
                    },
                    "duration_minutes": {
                        "type": "integer",
                        "description": "Estimated workout duration in minutes. Default to 45 if not specified."
                    }
                },
                "required": ["focus", "muscle_groups"]
            }
        }
    }
]


class CreateThreadRequest(BaseModel):
    user_id: str
    title: str | None = None


class PostMessageRequest(BaseModel):
    user_id: str
    thread_id: str
    content: str
    stream: bool = True
    local_workout_snapshot: dict | None = None


def _get_client() -> OpenAI:
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not set")
    return OpenAI(api_key=api_key)


def _touch_thread(supabase, thread_id: str) -> None:
    now = datetime.utcnow().isoformat()
    supabase.table("chat_threads").update(
        {"updated_at": now, "last_message_at": now}
    ).eq("id", thread_id).execute()


def _normalize_user_id(user_id: str) -> str:
    try:
        return str(uuid.UUID(user_id))
    except ValueError:
        return str(uuid.uuid5(uuid.NAMESPACE_URL, f"fitai:{user_id}"))


def _ensure_user_exists(supabase, user_id: str) -> None:
    existing = (
        supabase.table("users")
        .select("id")
        .eq("id", user_id)
        .limit(1)
        .execute()
        .data
    )
    if existing:
        return
    placeholder_email = f"user-{user_id}@placeholder.local"
    supabase.table("users").insert(
        {
            "id": user_id,
            "email": placeholder_email,
            "hashed_password": "placeholder",
            "role": "user",
        }
    ).execute()


def _get_profile(supabase, user_id: str) -> dict | None:
    result = (
        supabase.table("profiles")
        .select("age,goal,macros,preferences,height_cm,weight_kg,units,full_name,sex")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    return result[0] if result else None


def _get_latest_checkin(supabase, user_id: str) -> dict | None:
    result = (
        supabase.table("weekly_checkins")
        .select("date,weight,adherence,ai_summary,macro_update,cardio_update,notes")
        .eq("user_id", user_id)
        .order("date", desc=True)
        .limit(1)
        .execute()
        .data
    )
    return result[0] if result else None


def _get_recent_workouts(supabase, user_id: str) -> dict:
    sessions = (
        supabase.table("workout_sessions")
        .select("id,template_id,status,duration_seconds,created_at,completed_at")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(5)
        .execute()
        .data
        or []
    )
    session_ids = [session.get("id") for session in sessions if session.get("id")]
    logs = []
    if session_ids:
        logs = (
            supabase.table("exercise_logs")
            .select("session_id,exercise_name,sets,reps,weight,notes,created_at")
            .in_("session_id", session_ids)
            .order("created_at", desc=True)
            .limit(30)
            .execute()
            .data
            or []
        )
    return {"sessions": sessions, "logs": logs}


def _get_recent_prs(supabase, user_id: str) -> list[dict]:
    return (
        supabase.table("prs")
        .select("exercise_name,metric,value,recorded_at")
        .eq("user_id", user_id)
        .order("recorded_at", desc=True)
        .limit(5)
        .execute()
        .data
        or []
    )


def _get_thread_summary(supabase, thread_id: str) -> str | None:
    result = (
        supabase.table("chat_thread_summaries")
        .select("summary")
        .eq("thread_id", thread_id)
        .limit(1)
        .execute()
        .data
    )
    if not result:
        return None
    return result[0].get("summary")


def _get_recent_messages(supabase, thread_id: str, limit: int = 12) -> list[dict]:
    result = (
        supabase.table("chat_messages")
        .select("role,content")
        .eq("thread_id", thread_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )
    return list(reversed(result))


def _get_nutrition_logs(supabase, user_id: str) -> list[dict]:
    """Get recent nutrition logs for context."""
    from datetime import date, timedelta
    today = date.today()
    week_ago = today - timedelta(days=7)
    
    result = (
        supabase.table("nutrition_logs")
        .select("date,meal_type,calories,protein,carbs,fats,items")
        .eq("user_id", user_id)
        .gte("date", week_ago.isoformat())
        .order("date", desc=True)
        .limit(20)
        .execute()
        .data
        or []
    )
    return result


def _get_workout_templates(supabase, user_id: str) -> list[dict]:
    """Get user's saved workout templates for context."""
    result = (
        supabase.table("workout_templates")
        .select("id,title,mode,description")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(10)
        .execute()
        .data
        or []
    )
    return result


def _get_active_workout_session(supabase, user_id: str) -> dict | None:
    """Get current active/in-progress workout session for real-time context."""
    result = (
        supabase.table("workout_sessions")
        .select("id,template_id,status,created_at")
        .eq("user_id", user_id)
        .eq("status", "in_progress")
        .order("created_at", desc=True)
        .limit(1)
        .execute()
        .data
    )
    if not result:
        return None
    
    session = result[0]
    # Get exercise logs for this session
    logs = (
        supabase.table("exercise_logs")
        .select("exercise_name,sets,reps,weight,notes,created_at")
        .eq("session_id", session["id"])
        .order("created_at", desc=True)
        .execute()
        .data
        or []
    )
    session["exercise_logs"] = logs
    return session


def _build_user_context(supabase, user_id: str, local_workout_snapshot: dict | None = None) -> str:
    profile = _get_profile(supabase, user_id)
    preferences = profile.get("preferences") if profile else None
    gender = None
    if isinstance(preferences, dict):
        gender = preferences.get("gender") or preferences.get("sex")
    if not gender and profile:
        gender = profile.get("sex")
    
    # Build comprehensive context with all user data
    context_payload = {
        "profile": {
            "name": profile.get("full_name") if profile else None,
            "age": profile.get("age") if profile else None,
            "height_cm": profile.get("height_cm") if profile else None,
            "weight_kg": profile.get("weight_kg") if profile else None,
            "goal": profile.get("goal") if profile else None,
            "sex": profile.get("sex") if profile else None,
            "gender": gender,
            "preferences": preferences,
        },
        "macro_targets": profile.get("macros") if profile else None,
        "latest_checkin": _get_latest_checkin(supabase, user_id),
        "recent_workouts": _get_recent_workouts(supabase, user_id),
        "recent_prs": _get_recent_prs(supabase, user_id),
        "nutrition_last_7_days": _get_nutrition_logs(supabase, user_id),
        "saved_workout_templates": _get_workout_templates(supabase, user_id),
        "active_workout_session": _get_active_workout_session(supabase, user_id),
        "device_active_workout": local_workout_snapshot,
    }
    return json.dumps(context_payload, default=str)


def _moderate_text(client: OpenAI, text: str) -> list[str]:
    response = client.moderations.create(model="omni-moderation-latest", input=text)
    if not response.results:
        return []
    result = response.results[0]
    if not result.flagged:
        return []
    categories = result.categories.model_dump() if result.categories else {}
    return [name for name, value in categories.items() if value]


def _build_refusal(flags: list[str]) -> str:
    if any("self-harm" in flag or "self_harm" in flag for flag in flags):
        return "Reply: I can't help with that. If you're in danger, contact a local professional or emergency service."
    return (
        "Reply: I can't help with that. I can help with training, nutrition, recovery, and your plan."
    )


def _trim_coach_reply(text: str, max_words: int = MAX_COACH_WORDS) -> str:
    cleaned = " ".join(text.replace("\n", " ").split()).strip()
    if not cleaned:
        return cleaned
    sentences = re.split(r"(?<=[.!?])\s+", cleaned)
    trimmed = " ".join(sentences[:2])
    words = trimmed.split()
    if len(words) > max_words:
        trimmed = " ".join(words[:max_words]).rstrip(".,!?")
    return trimmed


def _is_workout_request(text: str) -> bool:
    lowered = text.lower()
    if any(keyword in lowered for keyword in WORKOUT_KEYWORDS) and any(
        action in lowered for action in WORKOUT_ACTIONS
    ):
        return True
    if "workout" in lowered and any(keyword in lowered for keyword in MUSCLE_KEYWORDS):
        return True
    if any(action in lowered for action in WORKOUT_ACTIONS) and any(
        keyword in lowered for keyword in MUSCLE_KEYWORDS
    ):
        return True
    return False


def _parse_workout_request(text: str) -> tuple[str, list[str], int]:
    lowered = text.lower()
    duration_minutes = 45
    duration_match = re.search(r"(\d{2,3})\s*(min|mins|minute|minutes)", lowered)
    if duration_match:
        duration_minutes = int(duration_match.group(1))
        duration_minutes = max(10, min(duration_minutes, 120))

    muscle_groups: list[str] = []
    for keyword, group in MUSCLE_KEYWORDS.items():
        if keyword in lowered and group not in muscle_groups:
            muscle_groups.append(group)

    if not muscle_groups:
        muscle_groups = ["full body"]

    focus = text.strip()
    if not focus:
        focus = "custom workout"

    return focus, muscle_groups, duration_minutes


def _create_coach_workout(
    supabase, user_id: str, focus: str, muscle_groups: list[str], duration_minutes: int = 45
) -> dict:
    """Generate a workout using AI and save it as a Coaches Pick template."""
    from ..prompts import run_prompt, parse_json_output
    
    # Generate workout using existing prompt
    prompt_input = {
        "muscle_groups": muscle_groups,
        "workout_type": focus,
        "duration_minutes": duration_minutes,
    }
    
    try:
        result = run_prompt("workout_generation", user_id=user_id, inputs=prompt_input)
        workout_data = parse_json_output(result)
    except Exception as exc:
        return {"success": False, "error": f"Failed to generate workout: {str(exc)}"}
    
    # Create template with "Coaches Pick" title
    generated_title = workout_data.get("title", focus.title())
    title = f"Coaches Pick: {generated_title}"
    
    try:
        template_rows = (
            supabase.table("workout_templates")
            .insert({
                "user_id": user_id,
                "title": title,
                "description": f"AI-generated {focus}",
                "mode": "coach",
                "metadata": json.dumps({
                    "generated_by": "coach_chat",
                    "focus": focus,
                    "muscle_groups": muscle_groups,
                })
            })
            .execute()
            .data
        )
        
        if not template_rows:
            return {"success": False, "error": "Failed to save workout template"}
        
        template_id = template_rows[0]["id"]
        
        # Add exercises to the template
        exercises = workout_data.get("exercises", [])
        for idx, exercise in enumerate(exercises):
            exercise_name = exercise.get("name", "Unknown Exercise")
            
            # Get or create exercise in exercises table
            existing = (
                supabase.table("exercises")
                .select("id")
                .eq("name", exercise_name)
                .limit(1)
                .execute()
                .data
            )
            
            if existing:
                exercise_id = existing[0]["id"]
            else:
                created = (
                    supabase.table("exercises")
                    .insert({
                        "name": exercise_name,
                        "muscle_groups": muscle_groups,
                        "equipment": [],
                    })
                    .execute()
                    .data
                )
                exercise_id = created[0]["id"] if created else None
            
            if exercise_id:
                # Handle reps that might be a string like "8-10"
                reps_val = exercise.get("reps", 10)
                if isinstance(reps_val, str):
                    # Take the lower number from range like "8-10"
                    reps_val = int(reps_val.split("-")[0]) if "-" in reps_val else int(reps_val)
                
                supabase.table("workout_template_exercises").insert({
                    "template_id": template_id,
                    "exercise_id": exercise_id,
                    "position": idx,
                    "sets": exercise.get("sets", 3),
                    "reps": reps_val,
                    "rest_seconds": exercise.get("rest_seconds", 60),
                    "notes": exercise.get("notes"),
                }).execute()
        
        return {
            "success": True,
            "template_id": template_id,
            "title": title,
            "exercise_count": len(exercises),
        }
        
    except Exception as exc:
        return {"success": False, "error": f"Database error: {str(exc)}"}


@router.post("/thread")
async def create_thread(payload: CreateThreadRequest):
    supabase = get_supabase()
    user_id = _normalize_user_id(payload.user_id)
    _ensure_user_exists(supabase, user_id)
    row = (
        supabase.table("chat_threads")
        .insert({"user_id": user_id, "title": payload.title})
        .execute()
        .data
    )
    if not row:
        raise HTTPException(status_code=500, detail="Failed to create thread")
    return {"thread": row[0]}


@router.get("/threads")
async def list_threads(user_id: str):
    supabase = get_supabase()
    normalized_user_id = _normalize_user_id(user_id)
    threads = (
        supabase.table("chat_threads")
        .select("*")
        .eq("user_id", normalized_user_id)
        .order("last_message_at", desc=True)
        .execute()
        .data
        or []
    )
    return {"threads": threads}


@router.get("/thread/{thread_id}")
async def get_thread(thread_id: str, user_id: str):
    supabase = get_supabase()
    normalized_user_id = _normalize_user_id(user_id)
    thread_rows = (
        supabase.table("chat_threads")
        .select("*")
        .eq("id", thread_id)
        .eq("user_id", normalized_user_id)
        .limit(1)
        .execute()
        .data
    )
    if not thread_rows:
        raise HTTPException(status_code=404, detail="Thread not found")
    messages = (
        supabase.table("chat_messages")
        .select("id,role,content,created_at")
        .eq("thread_id", thread_id)
        .order("created_at", desc=False)
        .execute()
        .data
        or []
    )
    summary = _get_thread_summary(supabase, thread_id)
    return {"thread": thread_rows[0], "messages": messages, "summary": summary}


@router.post("/message")
async def post_message(payload: PostMessageRequest):
    if not payload.content.strip():
        raise HTTPException(status_code=400, detail="Message content required")
    
    supabase = get_supabase()
    user_id = _normalize_user_id(payload.user_id)
    
    # Verify thread exists (lightweight query first)
    thread_rows = (
        supabase.table("chat_threads")
        .select("id")
        .eq("id", payload.thread_id)
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    if not thread_rows:
        raise HTTPException(status_code=404, detail="Thread not found")
    
    client = _get_client()
    loop = asyncio.get_event_loop()
    
    # Run moderation and context building in parallel for faster response
    moderation_future = loop.run_in_executor(
        _executor, _moderate_text, client, payload.content
    )
    context_future = loop.run_in_executor(
        _executor, _build_user_context, supabase, user_id, payload.local_workout_snapshot
    )
    history_future = loop.run_in_executor(
        _executor, _get_recent_messages, supabase, payload.thread_id, 12
    )
    summary_future = loop.run_in_executor(
        _executor, _get_thread_summary, supabase, payload.thread_id
    )
    
    # Ensure user exists (can run in background)
    loop.run_in_executor(_executor, _ensure_user_exists, supabase, user_id)
    
    # Insert user message early (don't wait for it)
    def insert_user_message():
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": user_id,
                "role": "user",
                "content": payload.content,
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
    loop.run_in_executor(_executor, insert_user_message)
    
    # Wait for moderation first (critical path)
    flags = await moderation_future
    if flags:
        refusal_text = _build_refusal(flags)
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": user_id,
                "role": "assistant",
                "content": refusal_text,
                "safety_flags": flags,
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        if payload.stream:
            def refusal_stream() -> Generator[str, None, None]:
                yield f"data: {refusal_text}\n\n"
                yield "data: [DONE]\n\n"
            return StreamingResponse(refusal_stream(), media_type="text/event-stream")
        return {"reply": refusal_text}

    workout_request = _is_workout_request(payload.content)
    if workout_request and not payload.stream:
        focus, muscle_groups, duration_minutes = _parse_workout_request(payload.content)
        workout_result = _create_coach_workout(
            supabase,
            user_id,
            focus=focus,
            muscle_groups=muscle_groups,
            duration_minutes=duration_minutes,
        )
        if workout_result.get("success"):
            assistant_text = "It's live in your workout view. Go check it out."
        else:
            assistant_text = "Workout failed. Tell me your goal and equipment."
        assistant_text = _trim_coach_reply(assistant_text)
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": user_id,
                "role": "assistant",
                "content": assistant_text,
                "model": "gpt-4o-mini",
                "metadata": json.dumps({"workout_created": workout_result}),
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        return {"reply": assistant_text, "workout_created": workout_result}

    if workout_request and payload.stream:
        focus, muscle_groups, duration_minutes = _parse_workout_request(payload.content)

        def stream_workout_response() -> Generator[str, None, None]:
            assistant_text = "One moment while I build your workout."
            yield f"data: {assistant_text}\n\n"

            workout_result = _create_coach_workout(
                supabase,
                user_id,
                focus=focus,
                muscle_groups=muscle_groups,
                duration_minutes=duration_minutes,
            )

            if workout_result.get("success"):
                tail = " It's live in your workout view. Go check it out."
            else:
                tail = " Workout failed. Tell me your goal and equipment."

            assistant_text += tail
            yield f"data: {tail}\n\n"

            supabase.table("chat_messages").insert(
                {
                    "thread_id": payload.thread_id,
                    "user_id": user_id,
                    "role": "assistant",
                    "content": assistant_text,
                    "model": "gpt-4o-mini",
                    "metadata": json.dumps({"workout_created": workout_result}),
                }
            ).execute()
            _touch_thread(supabase, payload.thread_id)
            yield "data: [DONE]\n\n"

        return StreamingResponse(stream_workout_response(), media_type="text/event-stream")
    
    # Now wait for context (was running in parallel)
    context_blob, history, summary = await asyncio.gather(
        context_future, history_future, summary_future
    )
    
    # Remove duplicate user message from history if present
    if history and history[-1].get("role") == "user" and history[-1].get("content") == payload.content:
        history = history[:-1]
    
    context_message = "User Context (server-trusted + device snapshot): " + context_blob
    if summary:
        context_message += f"\nThread Summary: {summary}"
    
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "system", "content": context_message},
        *history,
        {"role": "user", "content": payload.content},
    ]
    
    if not payload.stream:
        completion = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=60,
            temperature=0.4,
            tools=COACH_TOOLS,
            tool_choice="auto",
        )
        
        choice = completion.choices[0]
        assistant_text = ""
        workout_result = None
        
        # Check if AI wants to call a tool
        if choice.finish_reason == "tool_calls" and choice.message.tool_calls:
            for tool_call in choice.message.tool_calls:
                if tool_call.function.name == "generate_workout":
                    func_args = json.loads(tool_call.function.arguments)
                    workout_result = _create_coach_workout(
                        supabase,
                        user_id,
                        focus=func_args.get("focus", "custom workout"),
                        muscle_groups=func_args.get("muscle_groups", []),
                        duration_minutes=func_args.get("duration_minutes", 45)
                    )
                    
                    if workout_result.get("success"):
                        assistant_text = "It's live in your workout view. Go check it out."
                    else:
                        assistant_text = "Workout failed. Tell me your goal and equipment."
        else:
            assistant_text = choice.message.content or ""

        assistant_text = _trim_coach_reply(assistant_text)
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": user_id,
                "role": "assistant",
                "content": assistant_text,
                "model": "gpt-4o-mini",
                "metadata": json.dumps({"workout_created": workout_result}) if workout_result else None,
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        return {"reply": assistant_text, "workout_created": workout_result}
    
    def stream_response() -> Generator[str, None, None]:
        assistant_text = ""
        workout_result = None
        
        # First, make a non-streaming call to check for tool calls
        initial_completion = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=60,
            temperature=0.4,
            tools=COACH_TOOLS,
            tool_choice="auto",
        )
        
        choice = initial_completion.choices[0]
        
        # Check if AI wants to call a tool
        if choice.finish_reason == "tool_calls" and choice.message.tool_calls:
            for tool_call in choice.message.tool_calls:
                if tool_call.function.name == "generate_workout":
                    func_args = json.loads(tool_call.function.arguments)
                    workout_result = _create_coach_workout(
                        supabase,
                        user_id,
                        focus=func_args.get("focus", "custom workout"),
                        muscle_groups=func_args.get("muscle_groups", []),
                        duration_minutes=func_args.get("duration_minutes", 45)
                    )
                    
                    if workout_result.get("success"):
                        assistant_text = "It's live in your workout view. Go check it out."
                    else:
                        assistant_text = "Workout failed. Tell me your goal and equipment."
            
            assistant_text = _trim_coach_reply(assistant_text)
            yield f"data: {assistant_text}\n\n"
        else:
            assistant_text = choice.message.content or ""
            assistant_text = _trim_coach_reply(assistant_text)
            yield f"data: {assistant_text}\n\n"
        
        # Save the message
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": user_id,
                "role": "assistant",
                "content": assistant_text,
                "model": "gpt-4o-mini",
                "metadata": json.dumps({"workout_created": workout_result}) if workout_result else None,
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        yield "data: [DONE]\n\n"
    
    return StreamingResponse(stream_response(), media_type="text/event-stream")
