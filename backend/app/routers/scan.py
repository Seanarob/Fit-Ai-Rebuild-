from datetime import date
import hashlib
import os
import uuid
from uuid import UUID

from fastapi import APIRouter, HTTPException, UploadFile, File, Form

from ..prompts import run_prompt
from ..supabase_client import get_supabase

router = APIRouter()


def _normalize_user_id(user_id: str | None) -> str | None:
    if not user_id:
        return None
    try:
        return str(UUID(user_id))
    except ValueError:
        return str(uuid.uuid5(uuid.NAMESPACE_URL, f"fitai:{user_id}"))


def _ensure_user_record(supabase, user_id: str | None) -> str | None:
    normalized = _normalize_user_id(user_id)
    if not normalized:
        return None
    existing = (
        supabase.table("users").select("id").eq("id", normalized).limit(1).execute().data
    )
    if existing:
        return normalized

    email = f"user-{normalized}@fitai.local"
    hashed_password = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    supabase.table("users").insert(
        {
            "id": normalized,
            "email": email,
            "hashed_password": hashed_password,
            "role": "user",
        }
    ).execute()
    return normalized


@router.post("/meal-photo")
async def scan_meal_photo(
    user_id: str = Form(...),
    meal_type: str = Form(...),
    photo: UploadFile = File(...),
):
    supabase = get_supabase()
    normalized_user_id = _ensure_user_record(supabase, user_id)
    image_bytes = await photo.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Photo is required.")

    bucket = os.environ.get("SUPABASE_MEAL_PHOTO_BUCKET", "meal-photos")
    filename = f"{uuid.uuid4().hex}.jpg"
    path = f"{normalized_user_id}/{date.today().isoformat()}/{filename}"

    try:
        supabase.storage.from_(bucket).upload(
            path,
            image_bytes,
            file_options={"content-type": photo.content_type or "image/jpeg"},
        )
        public_url = supabase.storage.from_(bucket).get_public_url(path)
        prompt_input = {"meal_type": meal_type, "photo_url": public_url, "photo_urls": [public_url]}
        ai_output = run_prompt(
            "meal_photo_parse", user_id=normalized_user_id, inputs=prompt_input
        )
        supabase.table("nutrition_logs").insert(
            {
                "user_id": normalized_user_id,
                "date": date.today().isoformat(),
                "meal_type": meal_type,
                "items": [{"raw": ai_output, "photo_url": public_url}],
                "totals": {"calories": 0, "protein": 0, "carbs": 0, "fats": 0},
            }
        ).execute()
        return {"status": "logged", "ai_result": ai_output, "photo_url": public_url}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
