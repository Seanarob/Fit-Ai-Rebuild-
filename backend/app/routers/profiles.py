from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..supabase_client import get_supabase

router = APIRouter()


class ProfileUpsertRequest(BaseModel):
    full_name: str | None = None
    age: int | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    goal: str | None = None
    macros: dict | None = None
    preferences: dict | None = None
    units: dict | None = None
    subscription_status: str | None = None


@router.get("/{user_id}")
async def get_profile(user_id: str):
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


@router.put("/{user_id}")
async def upsert_profile(user_id: str, payload: ProfileUpsertRequest):
    supabase = get_supabase()
    update_payload = payload.dict(exclude_none=True)
    update_payload["user_id"] = user_id
    result = (
        supabase.table("profiles")
        .upsert(update_payload, on_conflict="user_id")
        .execute()
        .data
    )
    if result:
        return {"profile": result[0]}
    return {"profile": update_payload}
