import os
from datetime import date, datetime
from urllib.parse import unquote, urlparse

from fastapi import APIRouter, HTTPException

from ..prompts import parse_json_output, run_prompt
from ..supabase_client import get_supabase

router = APIRouter()

PHOTO_RETENTION_STORE = "store"
PHOTO_RETENTION_DELETE_AFTER_SCAN = "delete_after_scan"


def _to_number(value: int | float | str | None) -> int | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(round(value))
    try:
        return int(round(float(value)))
    except ValueError:
        return None


def _normalize_macros(raw_macros: dict | None) -> dict | None:
    if not isinstance(raw_macros, dict):
        return None
    calories = _to_number(raw_macros.get("calories"))
    protein = _to_number(raw_macros.get("protein"))
    carbs = _to_number(raw_macros.get("carbs"))
    fats = _to_number(raw_macros.get("fats"))
    if None in (calories, protein, carbs, fats):
        return None
    return {"calories": calories, "protein": protein, "carbs": carbs, "fats": fats}


def _normalize_macro_delta(raw_delta: dict | None) -> dict:
    if not isinstance(raw_delta, dict):
        return {}
    return {
        "calories": _to_number(raw_delta.get("calories")) or 0,
        "protein": _to_number(raw_delta.get("protein")) or 0,
        "carbs": _to_number(raw_delta.get("carbs")) or 0,
        "fats": _to_number(raw_delta.get("fats")) or 0,
    }


def _apply_macro_delta(current: dict, delta: dict) -> dict:
    updated = {}
    for key in ("calories", "protein", "carbs", "fats"):
        updated[key] = max(0, (current.get(key) or 0) + (delta.get(key) or 0))
    if updated["calories"] < 1200:
        updated["calories"] = 1200
    return updated


def _clean_photo_url(value) -> str | None:
    if not isinstance(value, str):
        return None
    trimmed = value.strip()
    return trimmed or None


def _extract_photo_urls(value) -> list[str]:
    if not isinstance(value, list):
        return []
    urls: list[str] = []
    for item in value:
        if isinstance(item, str):
            cleaned = _clean_photo_url(item)
        elif isinstance(item, dict):
            cleaned = _clean_photo_url(item.get("url"))
        else:
            cleaned = None
        if cleaned:
            urls.append(cleaned)
    return urls


def _extract_photo_items(value, default_date: str | None = None) -> list[dict]:
    if not isinstance(value, list):
        return []
    items: list[dict] = []
    for item in value:
        if isinstance(item, str):
            cleaned_url = _clean_photo_url(item)
            photo_type = None
            photo_date = default_date
        elif isinstance(item, dict):
            cleaned_url = _clean_photo_url(item.get("url"))
            photo_type = item.get("type") if isinstance(item.get("type"), str) else None
            raw_date = item.get("date")
            photo_date = raw_date.strip() if isinstance(raw_date, str) and raw_date.strip() else default_date
        else:
            cleaned_url = None
            photo_type = None
            photo_date = default_date

        if not cleaned_url:
            continue

        photo_item = {"url": cleaned_url}
        if photo_type:
            photo_item["type"] = photo_type
        if photo_date:
            photo_item["date"] = photo_date
        items.append(photo_item)
    return items


def _extract_starting_photo_urls(value) -> list[str]:
    if not isinstance(value, dict):
        return []
    urls: list[str] = []
    for key in ("front", "side", "back"):
        entry = value.get(key)
        if not isinstance(entry, dict):
            continue
        cleaned = _clean_photo_url(entry.get("url"))
        if cleaned:
            urls.append(cleaned)
    return urls

def _preference_string(preferences: dict | None, keys: tuple[str, ...]) -> str | None:
    if not isinstance(preferences, dict):
        return None
    for key in keys:
        value = preferences.get(key)
        if isinstance(value, str):
            trimmed = value.strip()
            if trimmed:
                return trimmed
    return None


def _preference_string_array(preferences: dict | None, keys: tuple[str, ...]) -> list[str]:
    if not isinstance(preferences, dict):
        return []
    for key in keys:
        value = preferences.get(key)
        if not isinstance(value, list):
            continue
        cleaned = [
            item.strip()
            for item in value
            if isinstance(item, str) and item.strip()
        ]
        if cleaned:
            return cleaned
    return []

def _filter_by_tag(query, tag: str):
    if hasattr(query, "contains"):
        return query.contains("tags", [tag])
    return query.filter("tags", "cs", f"{{{tag}}}")


def _dedupe_urls(urls: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for url in urls:
        if url in seen:
            continue
        seen.add(url)
        result.append(url)
    return result


def _extract_storage_path_from_public_url(photo_url: str, bucket: str) -> str | None:
    parsed = urlparse(photo_url)
    if not parsed.path:
        return None
    markers = (
        f"/storage/v1/object/public/{bucket}/",
        f"/object/public/{bucket}/",
    )
    for marker in markers:
        index = parsed.path.find(marker)
        if index == -1:
            continue
        path = parsed.path[index + len(marker) :]
        if path:
            return unquote(path)
    return None


def _delete_checkin_photo_assets(supabase, user_id: str, urls: list[str]) -> None:
    cleaned_urls = _dedupe_urls(_extract_photo_urls(urls))
    if not cleaned_urls:
        return

    for photo_url in cleaned_urls:
        try:
            (
                supabase.table("progress_photos")
                .delete()
                .eq("user_id", user_id)
                .eq("url", photo_url)
                .execute()
            )
        except Exception:
            # Best effort cleanup; rows might not exist for temporary uploads.
            continue

    bucket = os.environ.get("SUPABASE_PROGRESS_PHOTO_BUCKET", "progress-photos")
    paths = [
        path
        for path in (_extract_storage_path_from_public_url(url, bucket) for url in cleaned_urls)
        if path
    ]
    if not paths:
        return

    try:
        supabase.storage.from_(bucket).remove(paths)
    except Exception:
        # Keep check-in submission resilient if storage cleanup partially fails.
        pass


def _get_previous_checkin_photo_urls(supabase, user_id: str, checkin_date: str) -> list[str]:
    if not checkin_date:
        return []
    result = (
        supabase.table("weekly_checkins")
        .select("photos,date")
        .eq("user_id", user_id)
        .lt("date", checkin_date)
        .order("date", desc=True)
        .limit(1)
        .execute()
        .data
    )
    if not result:
        return []
    return _extract_photo_urls(result[0].get("photos"))


def _get_starting_photo_urls(supabase, user_id: str, preferences: dict | None = None) -> list[str]:
    resolved_preferences = preferences if isinstance(preferences, dict) else None
    if resolved_preferences is None:
        profile_rows = (
            supabase.table("profiles")
            .select("preferences")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
            .data
        )
        resolved_preferences = profile_rows[0].get("preferences") if profile_rows else None
    starting = (
        resolved_preferences.get("starting_photos")
        if isinstance(resolved_preferences, dict)
        else None
    )
    starting_urls = _extract_starting_photo_urls(starting)
    if starting_urls:
        return starting_urls
    query = (
        supabase.table("progress_photos")
        .select("url,tags")
        .eq("user_id", user_id)
    )
    query = _filter_by_tag(query, "category:starting")
    photo_rows = query.limit(3).execute().data
    return _extract_photo_urls(photo_rows)


@router.get("/")
async def list_checkins(
    user_id: str,
    limit: int = 12,
    start_date: str | None = None,
    end_date: str | None = None,
):
    supabase = get_supabase()
    query = supabase.table("weekly_checkins").select("*").eq("user_id", user_id)
    if start_date:
        query = query.gte("date", start_date)
    if end_date:
        query = query.lte("date", end_date)
    result = query.order("date", desc=True).limit(limit).execute().data
    return {"checkins": result}


@router.post("/")
async def submit_checkin(
    user_id: str,
    adherence: dict,
    photos: list[dict] | None = None,
    photo_urls: list[str] | None = None,
    photo_retention: str | None = None,
    checkin_date: str | None = None,
):
    supabase = get_supabase()
    profile_rows = (
        supabase.table("profiles")
        .select("goal,preferences")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    profile = profile_rows[0] if profile_rows else {}
    preferences = profile.get("preferences") if isinstance(profile, dict) else None
    date_value = checkin_date or date.today().isoformat()
    retention_value = (photo_retention or PHOTO_RETENTION_STORE).strip().lower()
    if retention_value not in {PHOTO_RETENTION_STORE, PHOTO_RETENTION_DELETE_AFTER_SCAN}:
        retention_value = PHOTO_RETENTION_STORE

    keep_photos = retention_value != PHOTO_RETENTION_DELETE_AFTER_SCAN
    photo_list = _extract_photo_items(photos, default_date=date_value)
    fallback_urls = _extract_photo_urls(photo_urls or [])
    prompt_urls = _extract_photo_urls(photo_list) or _extract_photo_urls(fallback_urls)
    prompt_urls = _dedupe_urls(prompt_urls)
    comparison_urls = _get_previous_checkin_photo_urls(supabase, user_id, date_value)
    comparison_source = None
    if comparison_urls:
        comparison_source = "previous_checkin"
    else:
        comparison_urls = _get_starting_photo_urls(supabase, user_id, preferences)
        if comparison_urls:
            comparison_source = "starting_photos"
    comparison_urls = [url for url in comparison_urls if url not in prompt_urls]
    prompt_input = {"adherence": adherence, "photo_urls": prompt_urls}
    if profile.get("goal"):
        prompt_input["goal"] = profile.get("goal")
    legacy_physique_focus = _preference_string_array(preferences, ("physique_focus", "physiqueFocus"))
    physique_priority = _preference_string(preferences, ("physiquePriority", "physique_priority"))
    if not physique_priority and legacy_physique_focus:
        physique_priority = legacy_physique_focus[0]
    if physique_priority:
        prompt_input["physique_priority"] = physique_priority
    secondary_goals = _preference_string_array(preferences, ("secondaryGoals", "secondary_goals"))
    secondary_goals.extend(legacy_physique_focus[1:])
    secondary_goals = list(dict.fromkeys(
        goal for goal in secondary_goals if goal and goal != physique_priority
    ))
    if secondary_goals:
        prompt_input["secondary_goals"] = secondary_goals
    physique_goal_description = _preference_string(preferences, ("physiqueGoalDescription", "physique_goal_description"))
    if physique_goal_description:
        prompt_input["physique_goal_description"] = physique_goal_description
    secondary_priority = _preference_string(preferences, ("secondaryPriority", "secondary_priority"))
    if not secondary_priority and secondary_goals:
        secondary_priority = secondary_goals[0]
    if secondary_priority and secondary_priority != physique_priority:
        prompt_input["secondary_priority"] = secondary_priority
    if comparison_urls:
        prompt_input["comparison_photo_urls"] = comparison_urls
        if comparison_source:
            prompt_input["comparison_source"] = comparison_source
    try:
        ai_output = run_prompt("weekly_checkin_analysis", user_id=user_id, inputs=prompt_input)
        parsed_output = {}
        try:
            parsed_output = parse_json_output(ai_output)
        except ValueError:
            parsed_output = {}

        macro_delta = _normalize_macro_delta(parsed_output.get("macro_delta"))
        update_macros = bool(parsed_output.get("update_macros")) or any(
            value != 0 for value in macro_delta.values()
        )
        updated_macros = None
        macro_applied = False

        if update_macros:
            profile_rows = (
                supabase.table("profiles")
                .select("macros")
                .eq("user_id", user_id)
                .limit(1)
                .execute()
                .data
            )
            current_macros = _normalize_macros(profile_rows[0].get("macros")) if profile_rows else None
            if current_macros:
                updated_macros = _apply_macro_delta(current_macros, macro_delta)
                supabase.table("profiles").upsert(
                    {
                        "user_id": user_id,
                        "macros": updated_macros,
                        "updated_at": datetime.utcnow().isoformat(),
                    },
                    on_conflict="user_id",
                ).execute()
                macro_applied = True

        if not keep_photos and prompt_urls:
            _delete_checkin_photo_assets(supabase, user_id, prompt_urls)

        stored_photos = photo_list or [{"url": url, "date": date_value} for url in fallback_urls]

        checkin_payload = {
            "user_id": user_id,
            "date": date_value,
            "weight": adherence.get("current_weight"),
            "adherence": adherence,
            "photos": stored_photos if keep_photos else [],
            "ai_summary": {"raw": ai_output, "parsed": parsed_output},
            "macro_update": {
                "suggested": update_macros,
                "delta": macro_delta,
                "applied": macro_applied,
                "new_macros": updated_macros,
            },
            "cardio_update": {"suggested": True},
        }
        inserted = supabase.table("weekly_checkins").insert(checkin_payload).execute().data or []
        inserted_checkin = inserted[0] if inserted else checkin_payload
        return {
            "status": "complete",
            "ai_result": ai_output,
            "checkin": inserted_checkin,
            "macro_update": {
                "suggested": update_macros,
                "delta": macro_delta,
                "applied": macro_applied,
                "new_macros": updated_macros,
            },
            "photo_retention": retention_value,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
