from datetime import date

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..prompts import run_prompt
from ..supabase_client import get_supabase

router = APIRouter()


@router.get("/search")
async def search_food(query: str, user_id: str | None = None):
    supabase = get_supabase()
    result = (
        supabase.table("food_items")
        .select("*")
        .ilike("name", f"%{query}%")
        .limit(20)
        .execute()
        .data
    )
    if user_id:
        supabase.table("search_history").insert(
            {"user_id": user_id, "query": query, "source": "search"}
        ).execute()
    return {"query": query, "results": result}


@router.post("/log")
async def log_nutrition(
    user_id: str, meal_type: str, photo_url: str | None = None, log_date: str | None = None
):
    supabase = get_supabase()
    prompt_input = {"meal_type": meal_type, "photo_url": photo_url}
    date_value = log_date or date.today().isoformat()
    try:
        ai_output = run_prompt("meal_photo_parse", user_id=user_id, inputs=prompt_input)
        supabase.table("nutrition_logs").insert(
            {
                "user_id": user_id,
                "date": date_value,
                "meal_type": meal_type,
                "items": [{"raw": ai_output}],
                "totals": {"calories": 0, "protein": 0, "carbs": 0, "fats": 0},
            }
        ).execute()
        return {"status": "logged", "ai_result": ai_output}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


class FavoriteRequest(BaseModel):
    user_id: str
    food_item_id: str


@router.post("/favorites")
async def add_favorite(payload: FavoriteRequest):
    supabase = get_supabase()
    try:
        supabase.table("nutrition_favorites").insert(payload.dict()).execute()
        return {"status": "saved"}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/favorites")
async def list_favorites(user_id: str, limit: int = 50):
    supabase = get_supabase()
    result = (
        supabase.table("nutrition_favorites")
        .select("*")
        .eq("user_id", user_id)
        .limit(limit)
        .execute()
        .data
    )
    return {"user_id": user_id, "favorites": result}
