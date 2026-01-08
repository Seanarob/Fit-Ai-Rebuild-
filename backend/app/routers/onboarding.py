from uuid import uuid4

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..prompts import run_prompt
from ..supabase_client import get_supabase

router = APIRouter()


class OnboardingRequest(BaseModel):
    user_id: str | None = None
    full_name: str
    age: str
    gender: str
    height_feet: str
    height_inches: str
    weight_lbs: str
    goal: str
    training_days: int
    gym_access: str = "full_gym"
    equipment: list[str] = Field(default_factory=list)
    experience: str
    checkin_day: str
    has_injury: bool = False
    injury_notes: str = ""
    macro_protein: str
    macro_carbs: str
    macro_fats: str
    macro_calories: str
    photos_pending: bool = True
    coach_interest: bool = False
    wants_to_coach: bool = False


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


def _effective_equipment(payload: OnboardingRequest) -> list[str]:
    if payload.gym_access == "home_gym":
        return payload.equipment or ["bodyweight"]
    if payload.gym_access == "calisthenics":
        return ["bodyweight"]
    return ["full gym"]


@router.post("/", response_model=OnboardingResponse)
async def submit_onboarding(payload: OnboardingRequest):
    supabase = get_supabase()
    user_id = payload.user_id or str(uuid4())

    payload_dict = payload.dict(by_alias=True, exclude={"user_id"})

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
            "macros": {
                "protein": payload.macro_protein,
                "carbs": payload.macro_carbs,
                "fats": payload.macro_fats,
                "calories": payload.macro_calories,
            },
            "preferences": {
                "training_days": payload.training_days,
                "gym_access": payload.gym_access,
                "equipment": payload.equipment,
                "experience": payload.experience,
                "checkin_day": payload.checkin_day,
                "gender": payload.gender,
                "has_injury": payload.has_injury,
                "injury_notes": payload.injury_notes,
            },
        }

        supabase.table("profiles").upsert(
            profile_payload, on_conflict="user_id"
        ).execute()

        if payload.wants_to_coach or payload.coach_interest:
            interest_enum = "coach" if payload.wants_to_coach else "hire"
            supabase.table("coach_interest").insert(
                {"user_id": user_id, "interest_enum": interest_enum}
            ).execute()

        resolved_equipment = _effective_equipment(payload)
        prompt_inputs = {
            "muscle_groups": ["full body"],
            "workout_type": payload.goal,
            "equipment": resolved_equipment,
            "experience": payload.experience,
            "goal": payload.goal,
            "gym_access": payload.gym_access,
        }

        workout_plan = run_prompt(
            "workout_generation", user_id=user_id, inputs=prompt_inputs
        )

        supabase.table("workout_templates").insert(
            {
                "user_id": user_id,
                "title": "Starter plan",
                "description": "Plan generated during onboarding",
                "mode": "auto",
                "metadata": {
                    "summary": workout_plan,
                    "form": payload_dict,
                },
            }
        ).execute()

        return {"user_id": user_id, "workout_plan": workout_plan}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
