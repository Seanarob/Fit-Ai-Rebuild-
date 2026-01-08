from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..supabase_client import get_supabase

router = APIRouter()


class ExerciseCreateRequest(BaseModel):
    name: str
    muscle_groups: list[str] = Field(default_factory=list)
    equipment: list[str] = Field(default_factory=list)
    metadata: dict | None = None


@router.post("/")
async def create_exercise(payload: ExerciseCreateRequest):
    supabase = get_supabase()
    try:
        result = supabase.table("exercises").insert(payload.dict()).execute().data
        if result:
            return {"exercise": result[0]}
        return {"exercise": payload.dict()}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/search")
async def search_exercises(query: str, limit: int = 20):
    supabase = get_supabase()
    result = (
        supabase.table("exercises")
        .select("*")
        .ilike("name", f"%{query}%")
        .limit(limit)
        .execute()
        .data
    )
    return {"query": query, "results": result}
