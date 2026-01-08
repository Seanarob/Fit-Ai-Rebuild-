from datetime import datetime

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..supabase_client import get_supabase

router = APIRouter()


class TutorialCompleteRequest(BaseModel):
    user_id: str
    completed: bool = True


class CheckInDayRequest(BaseModel):
    user_id: str
    check_in_day: str


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
