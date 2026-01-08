from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from supabase import Client

from ..prompts import run_prompt
from ..supabase_client import get_supabase

router = APIRouter()


class GenerateWorkoutRequest(BaseModel):
    user_id: str | None = None
    muscle_groups: list[str]
    workout_type: str | None = None
    equipment: list[str] | None = None


class ExerciseInput(BaseModel):
    name: str
    muscle_groups: list[str] = Field(default_factory=list)
    equipment: list[str] = Field(default_factory=list)
    sets: int | None = None
    reps: int | None = None
    rest_seconds: int | None = None
    notes: str | None = None


class SaveTemplateRequest(BaseModel):
    user_id: str | None = None
    title: str
    description: str | None = None
    mode: str = "manual"
    exercises: list[ExerciseInput] = Field(default_factory=list)


def _get_or_create_exercise(supabase: Client, exercise: ExerciseInput) -> str:
    existing = (
        supabase.table("exercises")
        .select("id")
        .eq("name", exercise.name)
        .limit(1)
        .execute()
        .data
    )
    if existing:
        return existing[0]["id"]

    created = (
        supabase.table("exercises")
        .insert(
            {
                "name": exercise.name,
                "muscle_groups": exercise.muscle_groups,
                "equipment": exercise.equipment,
            }
        )
        .execute()
        .data
    )
    if not created:
        raise HTTPException(status_code=500, detail="Failed to create exercise")
    return created[0]["id"]


@router.post("/generate")
async def generate_workout(payload: GenerateWorkoutRequest):
    supabase: Client = get_supabase()
    prompt_input = {
        "muscle_groups": payload.muscle_groups,
        "workout_type": payload.workout_type,
        "equipment": payload.equipment,
    }
    try:
        result = run_prompt(
            "workout_generation", user_id=payload.user_id, inputs=prompt_input
        )
        supabase.table("workout_templates").insert(
            {
                "user_id": payload.user_id,
                "title": "AI Generated Workout",
                "mode": "ai",
                "metadata": {"raw": result, "input": prompt_input},
            }
        ).execute()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {"template": result}


@router.post("/templates")
async def create_template(payload: SaveTemplateRequest):
    supabase: Client = get_supabase()
    try:
        template_rows = (
            supabase.table("workout_templates")
            .insert(
                {
                    "user_id": payload.user_id,
                    "title": payload.title,
                    "description": payload.description,
                    "mode": payload.mode,
                }
            )
            .execute()
            .data
        )
        if not template_rows:
            raise HTTPException(status_code=500, detail="Failed to create template")
        template_id = template_rows[0]["id"]

        for idx, exercise in enumerate(payload.exercises):
            exercise_id = _get_or_create_exercise(supabase, exercise)
            supabase.table("workout_template_exercises").insert(
                {
                    "template_id": template_id,
                    "exercise_id": exercise_id,
                    "position": idx,
                    "sets": exercise.sets or 0,
                    "reps": exercise.reps or 0,
                    "rest_seconds": exercise.rest_seconds or 0,
                    "notes": exercise.notes,
                }
            ).execute()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {"template_id": template_id}
