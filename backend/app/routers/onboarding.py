from uuid import uuid4
import hashlib

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..supabase_client import get_supabase

router = APIRouter()


class OnboardingRequest(BaseModel):
    user_id: str | None = None
    email: str | None = None
    password: str | None = None
    full_name: str
    age: str
    sex: str
    height_feet: str
    height_inches: str
    weight_lbs: str
    goal: str
    training_level: str
    workout_days_per_week: int
    workout_duration_minutes: int
    equipment: str
    food_allergies: str = ""
    food_dislikes: str = ""
    diet_style: str = ""
    checkin_day: str


class OnboardingResponse(BaseModel):
    user_id: str
    workout_plan: str


def _parse_int(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def _height_cm(feet: str | None, inches: str | None) -> float | None:
    feet_value = _parse_int(feet)
    inches_value = _parse_int(inches)
    if feet_value is None and inches_value is None:
        return None
    feet_value = feet_value or 0
    inches_value = inches_value or 0
    return round((feet_value * 30.48) + (inches_value * 2.54), 2)


def _weight_kg(pounds: str | None) -> float | None:
    pounds_value = _parse_float(pounds)
    if pounds_value is None:
        return None
    return round(pounds_value * 0.45359237, 2)


def _hash_password(password: str) -> str:
    return hashlib.sha256(password.encode("utf-8")).hexdigest()


def _resolve_user_id(payload: OnboardingRequest, supabase) -> str:
    email = (payload.email or "").strip().lower()
    if payload.user_id:
        existing = (
            supabase.table("users")
            .select("id")
            .eq("id", payload.user_id)
            .limit(1)
            .execute()
        )
        if existing.data:
            return payload.user_id
    if email:
        existing_by_email = (
            supabase.table("users")
            .select("id")
            .eq("email", email)
            .limit(1)
            .execute()
        )
        if existing_by_email.data:
            return existing_by_email.data[0]["id"]
    if not email:
        raise HTTPException(status_code=400, detail="Email is required.")

    user_id = payload.user_id or str(uuid4())
    password = payload.password or str(uuid4())
    supabase.table("users").insert(
        {
            "id": user_id,
            "email": email,
            "hashed_password": _hash_password(password),
            "role": "user",
        }
    ).execute()
    return user_id


@router.post("/", response_model=OnboardingResponse)
async def submit_onboarding(payload: OnboardingRequest):
    supabase = get_supabase()
    user_id = _resolve_user_id(payload, supabase)

    payload_dict = payload.dict(by_alias=True, exclude={"user_id", "email", "password"})

    try:
        supabase.table("onboarding_states").insert(
            {
                "user_id": user_id,
                "step_index": 5,
                "data": payload_dict,
                "is_complete": True,
            }
        ).execute()

        profile_payload = {
            "user_id": user_id,
            "full_name": payload.full_name,
            "age": _parse_int(payload.age),
            "height_cm": _height_cm(payload.height_feet, payload.height_inches),
            "weight_kg": _weight_kg(payload.weight_lbs),
            "goal": payload.goal,
            "preferences": {
                "training_level": payload.training_level,
                "workout_days_per_week": payload.workout_days_per_week,
                "workout_duration_minutes": payload.workout_duration_minutes,
                "equipment": payload.equipment,
                "food_allergies": payload.food_allergies,
                "food_dislikes": payload.food_dislikes,
                "diet_style": payload.diet_style,
                "checkin_day": payload.checkin_day,
                "sex": payload.sex,
            },
        }

        supabase.table("profiles").upsert(
            profile_payload, on_conflict="user_id"
        ).execute()

        return {"user_id": user_id, "workout_plan": ""}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
