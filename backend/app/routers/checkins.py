from datetime import date

from fastapi import APIRouter, HTTPException

from ..prompts import run_prompt
from ..supabase_client import get_supabase

router = APIRouter()


@router.post("/")
async def submit_checkin(
    user_id: str,
    adherence: dict,
    photo_urls: list[str] | None = None,
    checkin_date: str | None = None,
):
    supabase = get_supabase()
    prompt_input = {"adherence": adherence, "photo_urls": photo_urls or []}
    date_value = checkin_date or date.today().isoformat()
    try:
        ai_output = run_prompt("weekly_checkin_analysis", user_id=user_id, inputs=prompt_input)
        supabase.table("weekly_checkins").insert(
            {
                "user_id": user_id,
                "date": date_value,
                "weight": adherence.get("current_weight"),
                "adherence": adherence,
                "photos": [{"url": url} for url in (photo_urls or [])],
                "ai_summary": {"raw": ai_output},
                "macro_update": {"suggested": True},
                "cardio_update": {"suggested": True},
            }
        ).execute()
        return {"status": "complete", "ai_result": ai_output}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
