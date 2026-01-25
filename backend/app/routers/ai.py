from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..prompts import run_prompt
from ..supabase_client import get_supabase

router = APIRouter()


class PromptRequest(BaseModel):
    name: str
    user_id: str | None = None
    inputs: dict | None = None


class CoachChatRequest(BaseModel):
    user_id: str
    message: str
    history: list[dict] = Field(default_factory=list)
    thread_id: str | None = None


def _get_profile(supabase, user_id: str) -> dict | None:
    result = (
        supabase.table("profiles")
        .select("age,goal,macros,preferences,height_cm,weight_kg")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    return result[0] if result else None


def _get_recent_checkins(supabase, user_id: str, limit: int = 3) -> list[dict]:
    return (
        supabase.table("weekly_checkins")
        .select("date,weight,adherence,ai_summary")
        .eq("user_id", user_id)
        .order("date", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )


def _get_recent_workouts(supabase, user_id: str, limit: int = 5) -> list[dict]:
    return (
        supabase.table("workout_sessions")
        .select("id,template_id,status,duration_seconds,created_at,completed_at")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )


@router.post("/prompt")
async def run_prompt_endpoint(payload: PromptRequest):
    try:
        result = run_prompt(payload.name, user_id=payload.user_id, inputs=payload.inputs)
        return {"result": result}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/coach/chat")
async def coach_chat(payload: CoachChatRequest):
    supabase = get_supabase()
    profile = _get_profile(supabase, payload.user_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    prompt_inputs = {
        "message": payload.message,
        "history": payload.history,
        "profile": profile,
        "macros": profile.get("macros"),
        "recent_checkins": _get_recent_checkins(supabase, payload.user_id),
        "recent_workouts": _get_recent_workouts(supabase, payload.user_id),
        "thread_id": payload.thread_id,
    }
    try:
        result = run_prompt("coach_chat", user_id=payload.user_id, inputs=prompt_inputs)
        return {"response": result}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
