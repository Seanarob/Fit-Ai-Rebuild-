from datetime import date
import hashlib
import json
import os
import uuid
from urllib.parse import urlencode
from urllib.request import urlopen
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..prompts import run_prompt
from ..supabase_client import get_supabase
from ..fatsecret_client import fatsecret_request

router = APIRouter()
USDA_BASE_URL = "https://api.nal.usda.gov/fdc/v1"


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
    normalized_user_id = _normalize_user_id(user_id) if user_id else None
    if normalized_user_id:
        supabase.table("search_history").insert(
            {"user_id": normalized_user_id, "query": query, "source": "search"}
        ).execute()
    return {"query": query, "results": result}


def _usda_request(path: str, params: dict) -> dict:
    api_key = os.environ.get("USDA_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="USDA API key is not configured.")
    params_with_key = {"api_key": api_key, **params}
    url = f"{USDA_BASE_URL}{path}?{urlencode(params_with_key)}"
    try:
        with urlopen(url) as response:
            body = response.read().decode("utf-8")
            return json.loads(body)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"USDA request failed: {exc}")


def _nutrient_value(nutrients: list[dict], name_matches: list[str]) -> float:
    for nutrient in nutrients:
        name = (
            nutrient.get("nutrientName")
            or nutrient.get("nutrient", {}).get("name")
            or ""
        ).lower()
        if any(match in name for match in name_matches):
            value = nutrient.get("value")
            if value is None:
                value = nutrient.get("amount")
            try:
                return float(value)
            except (TypeError, ValueError):
                return 0.0
    return 0.0


def _normalize_usda_food(food: dict) -> dict:
    nutrients = food.get("foodNutrients", [])
    name = food.get("description") or food.get("description", "Food")
    fdc_id = str(food.get("fdcId") or "")
    calories = _nutrient_value(nutrients, ["energy"])
    protein = _nutrient_value(nutrients, ["protein"])
    carbs = _nutrient_value(nutrients, ["carbohydrate"])
    fats = _nutrient_value(nutrients, ["total lipid", "fat"])
    serving_size = food.get("servingSize")
    serving_unit = food.get("servingSizeUnit")
    serving = None
    if serving_size and serving_unit:
        serving = f"{serving_size} {serving_unit}"

    return {
        "source": "usda",
        "name": name.title(),
        "serving": serving or "100 g",
        "protein": protein,
        "carbs": carbs,
        "fats": fats,
        "calories": calories,
        "metadata": {"fdc_id": fdc_id, "source": "usda"},
        "fdc_id": fdc_id,
    }


def _safe_float(value) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _fatsecret_serving_value(serving: dict, key: str) -> float:
    return _safe_float(serving.get(key))


def _normalize_fatsecret_search_item(food: dict) -> dict:
    return {
        "source": "fatsecret",
        "name": (food.get("food_name") or "Food").title(),
        "food_id": str(food.get("food_id") or ""),
        "brand": food.get("brand_name"),
        "description": food.get("food_description") or "",
    }


def _parse_serving_option(serving: dict) -> dict | None:
    """Parse a single serving option from FatSecret API."""
    if not serving:
        return None
    
    serving_id = serving.get("serving_id")
    serving_desc = serving.get("serving_description") or ""
    metric_amount = serving.get("metric_serving_amount")
    metric_unit = serving.get("metric_serving_unit")
    number_of_units = serving.get("number_of_units")
    
    # Build display text
    display_text = serving_desc
    if not display_text and metric_amount and metric_unit:
        display_text = f"{metric_amount} {metric_unit}"
    
    # Calculate metric grams for conversion
    metric_grams = None
    if metric_amount and metric_unit:
        try:
            metric_grams = float(metric_amount) if metric_unit == "g" else None
        except (TypeError, ValueError):
            pass
    
    return {
        "id": str(serving_id) if serving_id else None,
        "description": display_text or "1 serving",
        "metric_grams": metric_grams,
        "number_of_units": float(number_of_units) if number_of_units else 1.0,
        "calories": _fatsecret_serving_value(serving, "calories"),
        "protein": _fatsecret_serving_value(serving, "protein"),
        "carbs": _fatsecret_serving_value(serving, "carbohydrate"),
        "fats": _fatsecret_serving_value(serving, "fat"),
    }


def _normalize_fatsecret_detail(food: dict) -> dict:
    servings_data = (food.get("servings") or {}).get("serving")
    
    # Parse all serving options
    all_servings = []
    if isinstance(servings_data, list):
        for s in servings_data:
            parsed = _parse_serving_option(s)
            if parsed:
                all_servings.append(parsed)
    elif isinstance(servings_data, dict):
        parsed = _parse_serving_option(servings_data)
        if parsed:
            all_servings.append(parsed)
    
    # Use first serving for default values
    default_serving = all_servings[0] if all_servings else {}
    serving_text = default_serving.get("description", "1 serving")

    return {
        "id": str(food.get("food_id") or ""),
        "source": "fatsecret",
        "name": (food.get("food_name") or "Food").title(),
        "serving": serving_text,
        "protein": default_serving.get("protein", 0),
        "carbs": default_serving.get("carbs", 0),
        "fats": default_serving.get("fats", 0),
        "calories": default_serving.get("calories", 0),
        "serving_options": all_servings,  # All available serving sizes
        "metadata": {
            "food_id": str(food.get("food_id") or ""),
            "brand": food.get("brand_name"),
        },
        "food_id": str(food.get("food_id") or ""),
    }


@router.get("/usda/search")
async def usda_search(query: str, user_id: str | None = None):
    supabase = get_supabase()
    payload = _usda_request("/foods/search", {"query": query, "pageSize": 20})
    foods = payload.get("foods", [])
    results = []
    for food in foods:
        normalized = _normalize_usda_food(food)
        row = {
            "source": normalized["source"],
            "name": normalized["name"],
            "serving": normalized["serving"],
            "protein": normalized["protein"],
            "carbs": normalized["carbs"],
            "fats": normalized["fats"],
            "calories": normalized["calories"],
            "metadata": normalized["metadata"],
        }
        try:
            supabase.table("food_items").insert(row).execute()
        except Exception:
            pass
        results.append(normalized)

    if user_id:
        supabase.table("search_history").insert(
            {"user_id": user_id, "query": query, "source": "usda"}
        ).execute()
    return {"query": query, "results": results}


@router.get("/usda/food/{fdc_id}")
async def usda_food_detail(fdc_id: str, user_id: str | None = None):
    supabase = get_supabase()
    payload = _usda_request(f"/food/{fdc_id}", {})
    normalized = _normalize_usda_food(payload)
    row = {
        "source": normalized["source"],
        "name": normalized["name"],
        "serving": normalized["serving"],
        "protein": normalized["protein"],
        "carbs": normalized["carbs"],
        "fats": normalized["fats"],
        "calories": normalized["calories"],
        "metadata": normalized["metadata"],
    }
    try:
        supabase.table("food_items").insert(row).execute()
    except Exception:
        pass
    return normalized


@router.get("/fatsecret/autocomplete")
async def fatsecret_autocomplete(query: str, max_results: int = 10):
    """
    Lightweight autocomplete endpoint for food name suggestions.
    Returns just food names/IDs without full nutrition details.
    Optimized for real-time typing suggestions.
    """
    if len(query) < 2:
        return {"suggestions": []}
    
    payload = fatsecret_request(
        "foods.autocomplete", {"expression": query, "max_results": min(max_results, 20)}
    )
    if payload.get("error"):
        raise HTTPException(status_code=502, detail=payload.get("error"))
    
    suggestions_raw = payload.get("suggestions") or {}
    suggestion_list = suggestions_raw.get("suggestion") or []
    
    # Handle single item returned as dict
    if isinstance(suggestion_list, str):
        suggestion_list = [suggestion_list]
    
    return {"suggestions": suggestion_list}


@router.get("/fatsecret/search")
async def fatsecret_search(query: str, user_id: str | None = None):
    payload = fatsecret_request(
        "foods.search", {"search_expression": query, "max_results": 20, "page_number": 0}
    )
    if payload.get("error"):
        raise HTTPException(status_code=502, detail=payload.get("error"))
    foods = (payload.get("foods") or {}).get("food", [])
    if isinstance(foods, dict):
        foods = [foods]
    results = []
    for food in foods:
        food_id = str(food.get("food_id") or "")
        if not food_id:
            continue
        try:
            detail_payload = fatsecret_request("food.get", {"food_id": food_id})
            normalized = _normalize_fatsecret_detail(detail_payload.get("food") or {})
            results.append(normalized)
        except HTTPException:
            fallback = _normalize_fatsecret_search_item(food)
            results.append(
                {
                    "id": fallback.get("food_id") or food_id,
                    "source": "fatsecret",
                    "name": fallback.get("name") or "Food",
                    "serving": fallback.get("description") or "1 serving",
                    "protein": 0,
                    "carbs": 0,
                    "fats": 0,
                    "calories": 0,
                    "metadata": {"brand": fallback.get("brand")},
                    "food_id": fallback.get("food_id") or food_id,
                }
            )

    if user_id:
        supabase = get_supabase()
        supabase.table("search_history").insert(
            {"user_id": user_id, "query": query, "source": "fatsecret"}
        ).execute()
    return {"query": query, "results": results}


def _extract_fatsecret_food_id(payload):
    if isinstance(payload, dict):
        if payload.get("food_id"):
            return str(payload.get("food_id"))
        for value in payload.values():
            found = _extract_fatsecret_food_id(value)
            if found:
                return found
    elif isinstance(payload, list):
        for item in payload:
            found = _extract_fatsecret_food_id(item)
            if found:
                return found
    return None


@router.get("/fatsecret/barcode")
async def fatsecret_barcode(barcode: str, user_id: str | None = None):
    payload = fatsecret_request("food.find_id_for_barcode", {"barcode": barcode})
    if payload.get("error"):
        raise HTTPException(status_code=502, detail=payload.get("error"))
    food_id = _extract_fatsecret_food_id(payload)
    if not food_id:
        raise HTTPException(status_code=404, detail="No food found for barcode.")
    detail_payload = fatsecret_request("food.get", {"food_id": food_id})
    normalized = _normalize_fatsecret_detail(detail_payload.get("food") or {})
    if user_id:
        supabase = get_supabase()
        supabase.table("search_history").insert(
            {"user_id": user_id, "query": barcode, "source": "fatsecret_barcode"}
        ).execute()
    return normalized


@router.get("/fatsecret/food/{food_id}")
async def fatsecret_food_detail(food_id: str, user_id: str | None = None):
    supabase = get_supabase()
    payload = fatsecret_request("food.get", {"food_id": food_id})
    food = payload.get("food") or {}
    normalized = _normalize_fatsecret_detail(food)
    row = {
        "source": normalized["source"],
        "name": normalized["name"],
        "serving": normalized["serving"],
        "protein": normalized["protein"],
        "carbs": normalized["carbs"],
        "fats": normalized["fats"],
        "calories": normalized["calories"],
        "metadata": normalized["metadata"],
    }
    try:
        supabase.table("food_items").insert(row).execute()
    except Exception:
        pass
    if user_id:
        normalized_user_id = _normalize_user_id(user_id)
        if normalized_user_id:
            supabase.table("search_history").insert(
                {"user_id": normalized_user_id, "query": normalized["name"], "source": "fatsecret_detail"}
            ).execute()
    return normalized


@router.post("/log")
async def log_nutrition(
    user_id: str, meal_type: str, photo_url: str | None = None, log_date: str | None = None
):
    supabase = get_supabase()
    normalized_user_id = _ensure_user_record(supabase, user_id)
    prompt_input = {"meal_type": meal_type, "photo_url": photo_url}
    date_value = log_date or date.today().isoformat()
    try:
        ai_output = run_prompt(
            "meal_photo_parse", user_id=normalized_user_id, inputs=prompt_input
        )
        supabase.table("nutrition_logs").insert(
            {
                "user_id": normalized_user_id,
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


class ManualNutritionItem(BaseModel):
    name: str
    portion_value: float = Field(0, ge=0)
    portion_unit: str
    calories: float
    protein: float
    carbs: float
    fats: float
    serving: str | None = None


class ManualNutritionLog(BaseModel):
    user_id: str
    meal_type: str
    log_date: str | None = None
    item: ManualNutritionItem


@router.get("/logs")
async def fetch_logs(user_id: str, log_date: str | None = None):
    supabase = get_supabase()
    date_value = log_date or date.today().isoformat()
    normalized_user_id = _normalize_user_id(user_id)
    if not normalized_user_id:
        raise HTTPException(status_code=400, detail="Invalid user id.")
    result = (
        supabase.table("nutrition_logs")
        .select("*")
        .eq("user_id", normalized_user_id)
        .eq("date", date_value)
        .execute()
        .data
    )
    return {"date": date_value, "logs": result}


@router.post("/logs/manual")
async def log_manual_item(payload: ManualNutritionLog):
    supabase = get_supabase()
    normalized_user_id = _ensure_user_record(supabase, payload.user_id)
    date_value = payload.log_date or date.today().isoformat()
    item = payload.item
    totals = {
        "calories": item.calories,
        "protein": item.protein,
        "carbs": item.carbs,
        "fats": item.fats,
    }
    try:
        supabase.table("nutrition_logs").insert(
            {
                "user_id": normalized_user_id,
                "date": date_value,
                "meal_type": payload.meal_type,
                "items": [
                    {
                        "name": item.name,
                        "portion_value": item.portion_value,
                        "portion_unit": item.portion_unit,
                        "serving": item.serving,
                        "calories": item.calories,
                        "protein": item.protein,
                        "carbs": item.carbs,
                        "fats": item.fats,
                    }
                ],
                "totals": totals,
            }
        ).execute()
        return {"status": "logged", "date": date_value}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/favorites")
async def add_favorite(payload: FavoriteRequest):
    supabase = get_supabase()
    try:
        normalized_user_id = _normalize_user_id(payload.user_id)
        if not normalized_user_id:
            raise HTTPException(status_code=400, detail="Invalid user id.")
        payload_dict = payload.dict()
        payload_dict["user_id"] = normalized_user_id
        supabase.table("nutrition_favorites").insert(payload_dict).execute()
        return {"status": "saved"}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/favorites")
async def list_favorites(user_id: str, limit: int = 50):
    supabase = get_supabase()
    normalized_user_id = _normalize_user_id(user_id)
    if not normalized_user_id:
        raise HTTPException(status_code=400, detail="Invalid user id.")
    result = (
        supabase.table("nutrition_favorites")
        .select("*")
        .eq("user_id", normalized_user_id)
        .limit(limit)
        .execute()
        .data
    )
    return {"user_id": user_id, "favorites": result}
