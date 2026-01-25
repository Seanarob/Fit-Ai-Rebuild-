from datetime import datetime
import json

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..prompts import run_prompt
from ..supabase_client import get_supabase

router = APIRouter()


class TutorialCompleteRequest(BaseModel):
    user_id: str
    completed: bool = True


class CheckInDayRequest(BaseModel):
    user_id: str
    check_in_day: str


class GenerateMacrosRequest(BaseModel):
    user_id: str


def _parse_macro_value(value: str | int | float | None) -> int | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(round(value))
    try:
        return int(round(float(value)))
    except ValueError:
        return None


def _normalize_ai_macros(raw_output: str) -> dict | None:
    try:
        parsed = json.loads(raw_output)
    except json.JSONDecodeError:
        return None

    if isinstance(parsed, dict) and "macros" in parsed and isinstance(parsed["macros"], dict):
        parsed = parsed["macros"]

    if not isinstance(parsed, dict):
        return None

    protein = _parse_macro_value(parsed.get("protein"))
    carbs = _parse_macro_value(parsed.get("carbs"))
    fats = _parse_macro_value(parsed.get("fats"))
    calories = _parse_macro_value(parsed.get("calories"))

    if None in (protein, carbs, fats, calories):
        return None

    return {
        "protein": protein,
        "carbs": carbs,
        "fats": fats,
        "calories": calories,
    }


def _build_macro_prompt_inputs(profile: dict) -> dict:
    preferences = profile.get("preferences") or {}
    return {
        "age": profile.get("age"),
        "gender": preferences.get("gender"),
        "height_cm": profile.get("height_cm"),
        "weight_kg": profile.get("weight_kg"),
        "goal": profile.get("goal"),
        "training_days": preferences.get("training_days"),
    }


def _has_required_macro_inputs(inputs: dict) -> bool:
    required = ["age", "gender", "height_cm", "weight_kg", "goal", "training_days"]
    return all(inputs.get(key) is not None for key in required)


@router.get("/me")
async def get_user_profile(user_id: str):
    supabase = get_supabase()
    result = (
        supabase.table("profiles")
        .select("*")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    if not result:
        raise HTTPException(status_code=404, detail="Profile not found")
    return {"profile": result[0]}


@router.post("/tutorial/complete")
async def complete_tutorial(payload: TutorialCompleteRequest):
    supabase = get_supabase()
    update_payload = {
        "user_id": payload.user_id,
        "tutorial_completed": payload.completed,
        "tutorial_completed_at": datetime.utcnow().isoformat()
        if payload.completed
        else None,
    }
    try:
        result = (
            supabase.table("profiles")
            .upsert(update_payload, on_conflict="user_id")
            .execute()
            .data
        )
        if result:
            return {"profile": result[0]}
        return {"profile": update_payload}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.put("/checkin-day")
async def update_checkin_day(payload: CheckInDayRequest):
    supabase = get_supabase()
    update_payload = {
        "user_id": payload.user_id,
        "check_in_day": payload.check_in_day,
    }
    try:
        result = (
            supabase.table("profiles")
            .upsert(update_payload, on_conflict="user_id")
            .execute()
            .data
        )
        if result:
            return {"profile": result[0]}
        return {"profile": update_payload}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/macros/generate")
async def generate_macros(payload: GenerateMacrosRequest):
    supabase = get_supabase()
    profile = (
        supabase.table("profiles")
        .select("*")
        .eq("user_id", payload.user_id)
        .limit(1)
        .execute()
        .data
    )
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    profile = profile[0]

    macro_inputs = _build_macro_prompt_inputs(profile)
    if not _has_required_macro_inputs(macro_inputs):
        raise HTTPException(status_code=400, detail="Profile data incomplete for macro generation")

    try:
        ai_output = run_prompt("macro_generation", user_id=payload.user_id, inputs=macro_inputs)
        ai_macros = _normalize_ai_macros(ai_output)
        if not ai_macros:
            raise HTTPException(status_code=502, detail="AI macro output invalid")
        update_payload = {
            "user_id": payload.user_id,
            "macros": ai_macros,
            "updated_at": datetime.utcnow().isoformat(),
        }
        result = (
            supabase.table("profiles")
            .upsert(update_payload, on_conflict="user_id")
            .execute()
            .data
        )
        if result:
            return {"macros": result[0].get("macros", ai_macros)}
        return {"macros": ai_macros}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
