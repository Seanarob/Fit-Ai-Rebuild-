from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..supabase_client import get_supabase

router = APIRouter()


class CoachProfileRequest(BaseModel):
    user_id: str
    bio: str | None = None
    specialties: list[str] = Field(default_factory=list)
    pricing: dict | None = None
    availability: dict | None = None


@router.post("/profile")
async def upsert_coach_profile(payload: CoachProfileRequest):
    supabase = get_supabase()
    result = (
        supabase.table("coach_profiles")
        .upsert(payload.dict(), on_conflict="user_id")
        .execute()
        .data
    )
    if result:
        return {"profile": result[0]}
    return {"profile": payload.dict()}


@router.get("/profile/{user_id}")
async def get_coach_profile(user_id: str):
    supabase = get_supabase()
    result = (
        supabase.table("coach_profiles")
        .select("*")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    if not result:
        raise HTTPException(status_code=404, detail="Coach profile not found")
    return {"profile": result[0]}


@router.get("/discover")
async def discover_coaches(limit: int = 20):
    supabase = get_supabase()
    result = supabase.table("coach_profiles").select("*").limit(limit).execute().data
    return {"results": result}
