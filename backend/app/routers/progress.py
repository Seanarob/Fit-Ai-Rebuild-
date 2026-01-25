from datetime import date, timedelta
import os
import uuid

from fastapi import APIRouter, HTTPException, UploadFile, File, Form

from ..supabase_client import get_supabase

router = APIRouter()

def _to_number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0

def _extract_tag_value(tags, prefix: str):
    if not isinstance(tags, list):
        return None
    for tag in tags:
        if isinstance(tag, str) and tag.startswith(prefix):
            return tag[len(prefix) :]
    return None

def _build_tags(category: str | None, date_value: str | None):
    tags = []
    if category:
        tags.append(f"category:{category}")
    if date_value:
        tags.append(f"date:{date_value}")
    return tags

def _decorate_photo_row(row: dict):
    tags = row.get("tags")
    if "category" not in row:
        row["category"] = _extract_tag_value(tags, "category:")
    if "date" not in row:
        row["date"] = _extract_tag_value(tags, "date:")
    if "type" not in row and "photo_type" in row:
        row["type"] = row.get("photo_type")
    return row

def _filter_by_tag(query, tag: str):
    if hasattr(query, "contains"):
        return query.contains("tags", [tag])
    return query.filter("tags", "cs", f"{{{tag}}}")


@router.post("/photos")
async def upload_progress_photo(
    user_id: str = Form(...),
    photo: UploadFile = File(...),
    photo_type: str | None = Form(None),
    photo_category: str | None = Form(None),
    checkin_date: str | None = Form(None),
):
    supabase = get_supabase()
    image_bytes = await photo.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Photo is required.")

    bucket = os.environ.get("SUPABASE_PROGRESS_PHOTO_BUCKET", "progress-photos")
    date_value = checkin_date or date.today().isoformat()
    filename = f"{uuid.uuid4().hex}.jpg"
    path = f"{user_id}/{date_value}/{filename}"

    try:
        supabase.storage.from_(bucket).upload(
            path,
            image_bytes,
            file_options={"content-type": photo.content_type or "image/jpeg"},
        )
        public_url = supabase.storage.from_(bucket).get_public_url(path)
        tags = _build_tags(photo_category, date_value)
        supabase.table("progress_photos").insert(
            {
                "user_id": user_id,
                "url": public_url,
                "photo_type": photo_type or "checkin",
                "tags": tags or None,
            }
        ).execute()
        return {
            "status": "uploaded",
            "photo_url": public_url,
            "photo_type": photo_type or "checkin",
            "photo_category": photo_category,
            "date": date_value,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/photos")
async def list_progress_photos(
    user_id: str,
    category: str | None = None,
    photo_type: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    limit: int = 60,
):
    supabase = get_supabase()
    query = supabase.table("progress_photos").select("*").eq("user_id", user_id)
    if category:
        query = _filter_by_tag(query, f"category:{category}")
    if photo_type:
        query = query.eq("photo_type", photo_type)
    if start_date:
        query = query.gte("created_at", start_date)
    if end_date:
        query = query.lte("created_at", end_date)
    result = query.order("created_at", desc=True).limit(limit).execute().data or []
    return {"photos": [_decorate_photo_row(dict(row)) for row in result]}


@router.get("/macro-adherence")
async def macro_adherence(
    user_id: str,
    range_days: int = 30,
):
    supabase = get_supabase()
    end_date = date.today()
    start_date = end_date - timedelta(days=max(range_days - 1, 0))

    profile = (
        supabase.table("profiles")
        .select("macros")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    macros = {}
    if profile:
        raw_macros = profile[0].get("macros") or {}
        if isinstance(raw_macros, dict):
            macros = {
                "calories": _to_number(raw_macros.get("calories")),
                "protein": _to_number(raw_macros.get("protein")),
                "carbs": _to_number(raw_macros.get("carbs")),
                "fats": _to_number(raw_macros.get("fats")),
            }

    rows = (
        supabase.table("nutrition_logs")
        .select("date, totals")
        .eq("user_id", user_id)
        .gte("date", start_date.isoformat())
        .lte("date", end_date.isoformat())
        .execute()
        .data
    )

    totals_by_date: dict[str, dict] = {}
    for row in rows:
        day = row.get("date")
        totals = row.get("totals") or {}
        if not day:
            continue
        existing = totals_by_date.get(day, {"calories": 0, "protein": 0, "carbs": 0, "fats": 0})
        totals_by_date[day] = {
            "calories": _to_number(existing.get("calories")) + _to_number(totals.get("calories")),
            "protein": _to_number(existing.get("protein")) + _to_number(totals.get("protein")),
            "carbs": _to_number(existing.get("carbs")) + _to_number(totals.get("carbs")),
            "fats": _to_number(existing.get("fats")) + _to_number(totals.get("fats")),
        }

    days = [
        {"date": day, "logged": totals, "target": macros}
        for day, totals in totals_by_date.items()
    ]
    days.sort(key=lambda item: item["date"])
    return {"days": days}
