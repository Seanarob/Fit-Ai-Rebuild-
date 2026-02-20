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


SYSTEM_PROMPT = """You are FitAI Coach - a real personal trainer texting a client.

RESPONSE RULES (CRITICAL):
- Default to SHORT replies unless the user explicitly asks for a detailed/long answer.
- Single response only. No multi-part replies or separate messages.
- No bullet points, numbered lists, or headers unless explicitly asked.
- Never repeat prior info verbatim; avoid robotic restating.
- Be encouraging but brief, like iMessage with a coach between sets.
- Plain text only. No markdown symbols (**, __, `), no label-style sections.
- Avoid phrases like "key areas" followed by formatted structure.
- Only fitness/nutrition topics. Politely redirect others.
- For injuries: one brief tip + "see a professional."
- If user gender is provided, tailor advice and examples accordingly; use neutral language otherwise.

SHORT MODE (default):
- 2-5 short sentences.
- Under 120 words.

DETAILED MODE (only if requested):
- Clear, structured answer.
- Up to 250 words.

ACTIVE WORKOUT MODE:
- If device_active_workout or active_workout_session is present, they're mid-workout.
- Reference their current exercises and performance naturally, especially last_completed_set if present.

WORKOUT GENERATION:
- If user asks to build/create/make/generate a workout, use the generate_workout function.
- Do NOT list exercises yourself.
- Final message must mention the workout view.

APP ACTION PROPOSALS:
- If user agrees to change workout split or macro targets, call propose_app_action.
- Use propose_app_action to suggest concrete app changes with exact values.
- Keep the assistant message short and ask for confirmation to apply changes.
- Never say you cannot change macros or split in-app; use propose_app_action instead.
- Never claim a split/macros change is already applied unless it was actually executed.

CONTEXT: You have user profile, macros, nutrition, workout history, PRs, templates, and live workout data."""

MAX_COACH_WORDS_SHORT = 120
MAX_COACH_WORDS_DETAILED = 250

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

ACTION_CONFIRMATION_PHRASES = (
    "do it",
    "go ahead",
    "apply it",
    "apply them",
    "update it",
    "update them",
    "make the change",
    "make that change",
    "please update",
    "please apply",
    "yes",
    "yeah",
    "yep",
    "sure",
    "ok",
    "okay",
    "sounds good",
    "let's do it",
    "lets do it",
    "can you update",
    "can you apply",
    "did you update",
    "did you apply",
)

VALID_SPLIT_TYPES = {
    "smart",
    "fullBody",
    "upperLower",
    "pushPullLegs",
    "hybrid",
    "bodyPart",
    "arnold",
}
VALID_SPLIT_MODES = {"ai", "custom"}
WEEKDAY_ORDER = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
]


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
    },
    {
        "type": "function",
        "function": {
            "name": "propose_app_action",
            "description": "Propose an in-app change the user can approve, such as updating macro targets or workout split.",
            "parameters": {
                "type": "object",
                "properties": {
                    "action_type": {
                        "type": "string",
                        "enum": ["update_macros", "update_workout_split"],
                        "description": "Type of app change being proposed."
                    },
                    "title": {
                        "type": "string",
                        "description": "Short title shown in the app card."
                    },
                    "description": {
                        "type": "string",
                        "description": "One-line summary of what will change."
                    },
                    "assistant_message": {
                        "type": "string",
                        "description": "Natural language message asking the user to apply this in the app."
                    },
                    "confirmation_prompt": {
                        "type": "string",
                        "description": "Optional direct confirmation question."
                    },
                    "macros": {
                        "type": "object",
                        "properties": {
                            "calories": {"type": "integer"},
                            "protein": {"type": "integer"},
                            "carbs": {"type": "integer"},
                            "fats": {"type": "integer"}
                        },
                        "description": "Macro values for update_macros."
                    },
                    "split": {
                        "type": "object",
                        "properties": {
                            "days_per_week": {"type": "integer"},
                            "training_days": {
                                "type": "array",
                                "items": {"type": "string"}
                            },
                            "split_type": {
                                "type": "string",
                                "enum": ["smart", "fullBody", "upperLower", "pushPullLegs", "hybrid", "bodyPart", "arnold"]
                            },
                            "mode": {
                                "type": "string",
                                "enum": ["ai", "custom"]
                            },
                            "focus": {"type": "string"}
                        },
                        "description": "Split values for update_workout_split."
                    }
                },
                "required": ["action_type", "title", "description", "assistant_message"]
            }
        }
    },
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
        .select("role,content,metadata")
        .eq("thread_id", thread_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )
    return list(reversed(result))


def _parse_message_metadata(raw_metadata) -> dict | None:
    if isinstance(raw_metadata, dict):
        return raw_metadata
    if not isinstance(raw_metadata, str) or not raw_metadata.strip():
        return None
    try:
        parsed = json.loads(raw_metadata)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def _extract_latest_action_proposal(history_rows: list[dict]) -> dict | None:
    for row in reversed(history_rows):
        if row.get("role") != "assistant":
            continue
        metadata = _parse_message_metadata(row.get("metadata"))
        if not metadata:
            continue
        raw_proposal = metadata.get("coach_action_proposal")
        if not isinstance(raw_proposal, dict):
            continue
        normalized = _normalize_action_proposal(raw_proposal)
        if normalized:
            return normalized
    return None


def _history_for_model(history_rows: list[dict]) -> list[dict]:
    history: list[dict] = []
    for row in history_rows:
        role = row.get("role")
        content = row.get("content")
        if role not in {"user", "assistant"}:
            continue
        if not isinstance(content, str):
            continue
        history.append({"role": role, "content": content})
    return history


def _is_action_confirmation(text: str) -> bool:
    lowered = text.strip().lower()
    if not lowered:
        return False
    if re.fullmatch(r"(yes|yeah|yep|sure|ok|okay)[\s!.?]*", lowered):
        return True
    return any(phrase in lowered for phrase in ACTION_CONFIRMATION_PHRASES)


def _build_action_execution_reply(action_proposal: dict) -> str:
    action_type = action_proposal.get("action_type")
    if action_type == "update_macros":
        macros = action_proposal.get("macros")
        if isinstance(macros, dict):
            parts = []
            calories = macros.get("calories")
            protein = macros.get("protein")
            carbs = macros.get("carbs")
            fats = macros.get("fats")
            if isinstance(calories, int):
                parts.append(f"{calories} kcal")
            if isinstance(protein, int):
                parts.append(f"{protein}g protein")
            if isinstance(carbs, int):
                parts.append(f"{carbs}g carbs")
            if isinstance(fats, int):
                parts.append(f"{fats}g fats")
            if parts:
                return "On it. Applying your macro targets now: " + ", ".join(parts) + "."
        return "On it. Applying your macro targets in your app now."
    return "On it. Applying your split update in your app now."


def _is_macro_related_text(text: str) -> bool:
    lowered = text.lower()
    triggers = (
        "macro",
        "macros",
        "protein",
        "carb",
        "fat",
        "calorie",
        "kcal",
        "%",
    )
    return any(trigger in lowered for trigger in triggers)


def _normalize_macro_key(raw: str) -> str | None:
    lowered = raw.lower().strip()
    if lowered.startswith("protein"):
        return "protein"
    if lowered.startswith("carb"):
        return "carbs"
    if lowered.startswith("fat"):
        return "fats"
    return None


def _parse_int_token(value: str, min_value: int = 0, max_value: int = 10000) -> int | None:
    cleaned = value.replace(",", "").strip()
    if not cleaned:
        return None
    try:
        parsed = int(round(float(cleaned)))
    except (TypeError, ValueError):
        return None
    return max(min_value, min(max_value, parsed))


def _extract_macro_candidates(text: str) -> tuple[dict[str, int], dict[str, int], int | None]:
    lowered = text.lower()
    gram_macros: dict[str, int] = {}
    percents: dict[str, int] = {}
    calories: int | None = None

    for match in re.finditer(
        r"(protein|carbs?|fats?)\s*(?:to|at|around|about|=|:)?\s*(\d{1,4})\s*g\b",
        lowered,
    ):
        macro_key = _normalize_macro_key(match.group(1))
        grams = _parse_int_token(match.group(2), min_value=0, max_value=1000)
        if macro_key and grams is not None:
            gram_macros[macro_key] = grams

    for match in re.finditer(
        r"(\d{1,4})\s*g\s*(protein|carbs?|fats?)\b",
        lowered,
    ):
        macro_key = _normalize_macro_key(match.group(2))
        grams = _parse_int_token(match.group(1), min_value=0, max_value=1000)
        if macro_key and grams is not None:
            gram_macros[macro_key] = grams

    for match in re.finditer(
        r"(protein|carbs?|fats?)\s*(?:to|at|around|about|=|:)?\s*(\d{1,3})\s*%",
        lowered,
    ):
        macro_key = _normalize_macro_key(match.group(1))
        percent = _parse_int_token(match.group(2), min_value=0, max_value=100)
        if macro_key and percent is not None:
            percents[macro_key] = percent

    for match in re.finditer(
        r"(\d{1,3})\s*%\s*(protein|carbs?|fats?)\b",
        lowered,
    ):
        macro_key = _normalize_macro_key(match.group(2))
        percent = _parse_int_token(match.group(1), min_value=0, max_value=100)
        if macro_key and percent is not None:
            percents[macro_key] = percent

    calorie_patterns = (
        r"(?:calories?|kcal|cals?)\D{0,24}(\d{1,2}(?:,\d{3})+|\d{3,5})",
        r"(\d{1,2}(?:,\d{3})+|\d{3,5})\D{0,24}(?:calories?|kcal|cals?)",
    )
    for pattern in calorie_patterns:
        match = re.search(pattern, lowered)
        if not match:
            continue
        parsed = _parse_int_token(match.group(1), min_value=0, max_value=10000)
        if parsed is not None:
            calories = parsed
            break

    return gram_macros, percents, calories


def _coalesce_macro_action_from_history(
    user_text: str,
    history_rows: list[dict],
    context_payload: dict | None = None,
) -> dict | None:
    latest_assistant_text: str | None = None
    for row in reversed(history_rows):
        if row.get("role") != "assistant":
            continue
        content = row.get("content")
        if isinstance(content, str) and content.strip():
            latest_assistant_text = content
            break
    if not latest_assistant_text or not _is_macro_related_text(latest_assistant_text):
        return None

    text_sources = [user_text, latest_assistant_text]
    for row in reversed(history_rows):
        if row.get("role") != "assistant":
            continue
        content = row.get("content")
        if not isinstance(content, str) or not content.strip():
            continue
        if content == latest_assistant_text:
            continue
        if _is_macro_related_text(content):
            text_sources.append(content)
        if len(text_sources) >= 4:
            break

    combined_grams: dict[str, int] = {}
    combined_percents: dict[str, int] = {}
    inferred_calories: int | None = None
    for source in text_sources:
        grams, percents, calories = _extract_macro_candidates(source)
        combined_grams.update(grams)
        combined_percents.update(percents)
        if inferred_calories is None and calories is not None:
            inferred_calories = calories

    if inferred_calories is None and isinstance(context_payload, dict):
        current_targets = context_payload.get("macro_targets")
        if isinstance(current_targets, dict):
            inferred_calories = _safe_int(current_targets.get("calories"), min_value=0, max_value=10000)

    needed = {"protein", "carbs", "fats"}
    has_direct_macro_targets = bool(combined_grams) or needed.issubset(combined_percents.keys())
    if not has_direct_macro_targets:
        return None

    macros: dict[str, int] = {}
    macros.update(combined_grams)
    if inferred_calories is not None:
        macros["calories"] = inferred_calories

    if needed.issubset(combined_percents.keys()):
        calorie_base = inferred_calories
        if calorie_base is None and isinstance(context_payload, dict):
            current_targets = context_payload.get("macro_targets")
            if isinstance(current_targets, dict):
                calorie_base = _safe_int(current_targets.get("calories"), min_value=0, max_value=10000)
        if calorie_base is not None and calorie_base > 0:
            percent_to_kcal = {
                "protein": 4,
                "carbs": 4,
                "fats": 9,
            }
            for key, kcal_per_gram in percent_to_kcal.items():
                if key in macros:
                    continue
                pct = combined_percents.get(key)
                if pct is None:
                    continue
                grams = int(round((calorie_base * (pct / 100.0)) / kcal_per_gram))
                macros[key] = max(0, min(1000, grams))

    if not macros:
        return None

    raw_proposal = {
        "action_type": "update_macros",
        "title": "Update Macro Targets",
        "description": "Apply the macro target changes in your app.",
        "assistant_message": _build_action_execution_reply({"action_type": "update_macros", "macros": macros}),
        "confirmation_prompt": _build_default_action_message("update_macros"),
        "macros": macros,
    }
    return _normalize_action_proposal(raw_proposal)


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


def _sanitize_coach_text(text: str) -> str:
    cleaned = (text or "").replace("\r\n", "\n")
    cleaned = re.sub(r"```[\s\S]*?```", lambda m: m.group(0).replace("```", ""), cleaned)
    cleaned = re.sub(r"\*\*([^*]+)\*\*", r"\1", cleaned)
    cleaned = re.sub(r"__([^_]+)__", r"\1", cleaned)
    cleaned = re.sub(r"`([^`]+)`", r"\1", cleaned)
    cleaned = cleaned.replace("**", "").replace("__", "").replace("`", "")
    cleaned = re.sub(r"(?m)^\s{0,3}#{1,6}\s+", "", cleaned)
    cleaned = re.sub(r"(?m)^\s*[-*•]\s+", "", cleaned)
    cleaned = re.sub(r"(?m)^\s*\d+\s*[.)]\s+", "", cleaned)
    cleaned = " ".join(cleaned.split())
    return cleaned.strip()


def _trim_coach_reply(text: str, max_words: int, max_sentences: int = 2) -> str:
    cleaned = _sanitize_coach_text(text)
    if not cleaned:
        return cleaned

    # Split into sentence-ish chunks, but avoid treating list enumerators like "1."
    # as standalone sentences (which can truncate replies at "1.").
    parts = re.split(r"(?<=[.!?])\s+", cleaned)
    merged: list[str] = []
    i = 0
    while i < len(parts):
        part = parts[i]
        part_stripped = part.strip()
        ends_with_enumerator = re.search(r"\b\d+\.$", part_stripped) is not None
        is_pure_enumerator = re.fullmatch(r"\d+\.", part_stripped) is not None
        looks_like_list_intro = ":" in part

        if ends_with_enumerator and i + 1 < len(parts) and (is_pure_enumerator or looks_like_list_intro):
            part = f"{part} {parts[i + 1]}"
            i += 1

        merged.append(part)
        i += 1

    trimmed = " ".join(merged[:max_sentences])
    words = trimmed.split()
    if len(words) > max_words:
        trimmed = " ".join(words[:max_words]).rstrip(".,!?")
    trimmed = _sanitize_coach_text(trimmed)
    trimmed = re.sub(r"\b\d+\.$", "", trimmed).strip()
    return trimmed


def _wants_detailed_reply(text: str) -> bool:
    lowered = text.lower()
    triggers = (
        "detailed",
        "in-depth",
        "in depth",
        "deep dive",
        "thorough",
        "comprehensive",
        "lengthy",
        "long answer",
        "super detailed",
        "full breakdown",
        "step-by-step",
        "step by step",
        "elaborate",
        "expand on",
        "go deeper",
    )
    return any(trigger in lowered for trigger in triggers)


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


def _parse_tool_arguments(raw_args: str) -> dict:
    if not raw_args:
        return {}
    try:
        parsed = json.loads(raw_args)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _safe_int(value, min_value: int | None = None, max_value: int | None = None) -> int | None:
    try:
        parsed = int(round(float(value)))
    except (TypeError, ValueError):
        return None
    if min_value is not None:
        parsed = max(min_value, parsed)
    if max_value is not None:
        parsed = min(max_value, parsed)
    return parsed


def _normalize_training_days(days: list[str] | None, target_count: int) -> list[str]:
    if not days:
        return WEEKDAY_ORDER[:target_count]
    day_map = {day.lower(): day for day in WEEKDAY_ORDER}
    normalized: list[str] = []
    for raw_day in days:
        if not isinstance(raw_day, str):
            continue
        key = raw_day.strip().lower()
        resolved = day_map.get(key)
        if resolved and resolved not in normalized:
            normalized.append(resolved)
    for day in WEEKDAY_ORDER:
        if len(normalized) >= target_count:
            break
        if day not in normalized:
            normalized.append(day)
    return normalized[:target_count]


def _build_default_action_message(action_type: str) -> str:
    if action_type == "update_macros":
        return "I can apply these macro targets in your app now. Want me to do it?"
    return "I can update your workout split in your app now. Want me to apply it?"


def _normalize_action_proposal(raw_args: dict) -> dict | None:
    action_type = raw_args.get("action_type")
    if action_type not in {"update_macros", "update_workout_split"}:
        return None

    raw_title = raw_args.get("title")
    if not isinstance(raw_title, str):
        raw_title = "Coach update"
    raw_description = raw_args.get("description")
    if not isinstance(raw_description, str):
        raw_description = ""
    raw_confirmation = raw_args.get("confirmation_prompt")
    if not isinstance(raw_confirmation, str):
        raw_confirmation = _build_default_action_message(action_type)

    proposal: dict = {
        "id": str(uuid.uuid4()),
        "action_type": action_type,
        "title": raw_title.strip() or "Coach update",
        "description": raw_description.strip(),
        "confirmation_prompt": raw_confirmation.strip() or _build_default_action_message(action_type),
    }

    if action_type == "update_macros":
        raw_macros = raw_args.get("macros")
        if not isinstance(raw_macros, dict):
            raw_macros = {}
        macros: dict[str, int] = {}
        for key in ("calories", "protein", "carbs", "fats"):
            value = _safe_int(raw_macros.get(key), min_value=0, max_value=10000)
            if value is not None:
                macros[key] = value
        if not macros:
            return None
        proposal["macros"] = macros
        return proposal

    raw_split = raw_args.get("split")
    if not isinstance(raw_split, dict):
        raw_split = {}
    days_per_week = _safe_int(raw_split.get("days_per_week"), min_value=2, max_value=7) or 3
    split_type = raw_split.get("split_type")
    if split_type not in VALID_SPLIT_TYPES:
        split_type = "smart"
    mode = raw_split.get("mode")
    if mode not in VALID_SPLIT_MODES:
        mode = "ai"
    training_days = _normalize_training_days(raw_split.get("training_days"), target_count=days_per_week)
    focus = raw_split.get("focus")
    focus = focus.strip() if isinstance(focus, str) else ""
    split_payload: dict[str, object] = {
        "days_per_week": days_per_week,
        "training_days": training_days,
        "split_type": split_type,
        "mode": mode,
    }
    if focus:
        split_payload["focus"] = focus
    proposal["split"] = split_payload
    return proposal


def _run_tool_calls(choice, supabase, user_id: str) -> tuple[str, dict | None, dict | None]:
    assistant_text = choice.message.content or ""
    workout_result = None
    action_proposal = None

    if choice.finish_reason != "tool_calls" or not choice.message.tool_calls:
        return assistant_text, workout_result, action_proposal

    for tool_call in choice.message.tool_calls:
        tool_name = tool_call.function.name
        func_args = _parse_tool_arguments(tool_call.function.arguments)

        if tool_name == "generate_workout":
            workout_result = _create_coach_workout(
                supabase,
                user_id,
                focus=func_args.get("focus", "custom workout"),
                muscle_groups=func_args.get("muscle_groups", []),
                duration_minutes=func_args.get("duration_minutes", 45),
            )
            if workout_result.get("success"):
                assistant_text = "It's live in your workout view. Go check it out."
            else:
                assistant_text = "Workout failed. Tell me your goal and equipment."

        if tool_name == "propose_app_action":
            proposal = _normalize_action_proposal(func_args)
            if proposal:
                action_proposal = proposal
                tool_message = func_args.get("assistant_message")
                if isinstance(tool_message, str) and tool_message.strip():
                    assistant_text = tool_message.strip()
                else:
                    assistant_text = proposal["confirmation_prompt"]

    return assistant_text, workout_result, action_proposal


def _assistant_metadata(
    workout_result: dict | None = None, action_proposal: dict | None = None
) -> str | None:
    payload: dict[str, object] = {}
    if workout_result:
        payload["workout_created"] = workout_result
    if action_proposal:
        payload["coach_action_proposal"] = action_proposal
    if not payload:
        return None
    return json.dumps(payload)


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

    detailed_mode = _wants_detailed_reply(payload.content)
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
        assistant_text = _trim_coach_reply(
            assistant_text,
            max_words=MAX_COACH_WORDS_SHORT,
            max_sentences=2,
        )
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
    context_blob, history_rows, summary = await asyncio.gather(
        context_future, history_future, summary_future
    )
    context_payload = {}
    try:
        parsed_context = json.loads(context_blob)
        if isinstance(parsed_context, dict):
            context_payload = parsed_context
    except (TypeError, json.JSONDecodeError):
        context_payload = {}
    latest_action_proposal = _extract_latest_action_proposal(history_rows)
    history = _history_for_model(history_rows)

    # Remove duplicate user message from history if present
    if history and history[-1].get("role") == "user" and history[-1].get("content") == payload.content:
        history = history[:-1]

    if latest_action_proposal and _is_action_confirmation(payload.content):
        assistant_text = _trim_coach_reply(
            _build_action_execution_reply(latest_action_proposal),
            max_words=MAX_COACH_WORDS_SHORT,
            max_sentences=2,
        )
        assistant_metadata = _assistant_metadata(action_proposal=latest_action_proposal)

        if payload.stream:
            def stream_action_confirmation() -> Generator[str, None, None]:
                yield f"data: {assistant_text}\n\n"
                action_event = json.dumps({"type": "coach_action", "action": latest_action_proposal})
                yield f"data: {action_event}\n\n"
                supabase.table("chat_messages").insert(
                    {
                        "thread_id": payload.thread_id,
                        "user_id": user_id,
                        "role": "assistant",
                        "content": assistant_text,
                        "model": "gpt-4o-mini",
                        "metadata": assistant_metadata,
                    }
                ).execute()
                _touch_thread(supabase, payload.thread_id)
                yield "data: [DONE]\n\n"

            return StreamingResponse(stream_action_confirmation(), media_type="text/event-stream")

        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": user_id,
                "role": "assistant",
                "content": assistant_text,
                "model": "gpt-4o-mini",
                "metadata": assistant_metadata,
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        return {"reply": assistant_text, "coach_action": latest_action_proposal}

    if _is_action_confirmation(payload.content):
        inferred_macro_proposal = _coalesce_macro_action_from_history(
            payload.content,
            history_rows,
            context_payload=context_payload,
        )
        if inferred_macro_proposal:
            assistant_text = _trim_coach_reply(
                _build_action_execution_reply(inferred_macro_proposal),
                max_words=MAX_COACH_WORDS_SHORT,
                max_sentences=2,
            )
            assistant_metadata = _assistant_metadata(action_proposal=inferred_macro_proposal)

            if payload.stream:
                def stream_inferred_action_confirmation() -> Generator[str, None, None]:
                    yield f"data: {assistant_text}\n\n"
                    action_event = json.dumps({"type": "coach_action", "action": inferred_macro_proposal})
                    yield f"data: {action_event}\n\n"
                    supabase.table("chat_messages").insert(
                        {
                            "thread_id": payload.thread_id,
                            "user_id": user_id,
                            "role": "assistant",
                            "content": assistant_text,
                            "model": "gpt-4o-mini",
                            "metadata": assistant_metadata,
                        }
                    ).execute()
                    _touch_thread(supabase, payload.thread_id)
                    yield "data: [DONE]\n\n"

                return StreamingResponse(stream_inferred_action_confirmation(), media_type="text/event-stream")

            supabase.table("chat_messages").insert(
                {
                    "thread_id": payload.thread_id,
                    "user_id": user_id,
                    "role": "assistant",
                    "content": assistant_text,
                    "model": "gpt-4o-mini",
                    "metadata": assistant_metadata,
                }
            ).execute()
            _touch_thread(supabase, payload.thread_id)
            return {"reply": assistant_text, "coach_action": inferred_macro_proposal}
    
    context_message = "User Context (server-trusted + device snapshot): " + context_blob
    if summary:
        context_message += f"\nThread Summary: {summary}"

    reply_mode_message = (
        "Reply mode: DETAILED. Be clear and structured. Up to 250 words."
        if detailed_mode
        else "Reply mode: SHORT. 2-5 short sentences, under 120 words, natural text message tone."
    )
    completion_max_tokens = 600 if detailed_mode else 120
    trim_max_words = MAX_COACH_WORDS_DETAILED if detailed_mode else MAX_COACH_WORDS_SHORT
    trim_max_sentences = 12 if detailed_mode else 5

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "system", "content": reply_mode_message},
        {"role": "system", "content": context_message},
        *history,
        {"role": "user", "content": payload.content},
    ]
    
    if not payload.stream:
        completion = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=completion_max_tokens,
            temperature=0.4,
            tools=COACH_TOOLS,
            tool_choice="auto",
        )
        
        choice = completion.choices[0]
        assistant_text, workout_result, action_proposal = _run_tool_calls(
            choice,
            supabase,
            user_id,
        )

        assistant_text = _trim_coach_reply(
            assistant_text,
            max_words=trim_max_words,
            max_sentences=trim_max_sentences,
        )
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": user_id,
                "role": "assistant",
                "content": assistant_text,
                "model": "gpt-4o-mini",
                "metadata": _assistant_metadata(
                    workout_result=workout_result,
                    action_proposal=action_proposal,
                ),
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        return {
            "reply": assistant_text,
            "workout_created": workout_result,
            "coach_action": action_proposal,
        }
    
    def stream_response() -> Generator[str, None, None]:
        assistant_text = ""
        workout_result = None
        action_proposal = None
        
        # First, make a non-streaming call to check for tool calls
        initial_completion = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=completion_max_tokens,
            temperature=0.4,
            tools=COACH_TOOLS,
            tool_choice="auto",
        )
        
        choice = initial_completion.choices[0]
        assistant_text, workout_result, action_proposal = _run_tool_calls(
            choice,
            supabase,
            user_id,
        )
        assistant_text = _trim_coach_reply(
            assistant_text,
            max_words=trim_max_words,
            max_sentences=trim_max_sentences,
        )
        yield f"data: {assistant_text}\n\n"
        if action_proposal:
            action_event = json.dumps({"type": "coach_action", "action": action_proposal})
            yield f"data: {action_event}\n\n"
        
        # Save the message
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": user_id,
                "role": "assistant",
                "content": assistant_text,
                "model": "gpt-4o-mini",
                "metadata": _assistant_metadata(
                    workout_result=workout_result,
                    action_proposal=action_proposal,
                ),
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        yield "data: [DONE]\n\n"
    
    return StreamingResponse(stream_response(), media_type="text/event-stream")
