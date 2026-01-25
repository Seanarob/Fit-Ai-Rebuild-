import json
import os
import re
from datetime import datetime

from openai import OpenAI

from .supabase_client import get_supabase

def _get_client() -> OpenAI:
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        raise ValueError("OPENAI_API_KEY is not set")
    return OpenAI(api_key=api_key)

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

def _dedupe_photo_urls(urls: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for url in urls:
        if url in seen:
            continue
        seen.add(url)
        result.append(url)
    return result


def parse_json_output(raw_output: str) -> dict:
    text = (raw_output or "").strip()
    if not text:
        raise ValueError("AI output empty")

    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE)
        text = re.sub(r"\s*```$", "", text)

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        try:
            parsed = json.loads(text[start : end + 1])
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass

    raise ValueError("AI output did not contain valid JSON object")

def log_job(payload: dict) -> str | None:
    supabase = get_supabase()
    result = supabase.table("ai_jobs").insert(payload).execute()
    rows = result.data or []
    if rows:
        return rows[0].get("id")
    return None

def update_job(job_id, payload: dict):
    supabase = get_supabase()
    supabase.table("ai_jobs").update(payload).eq("id", job_id).execute()

def run_prompt(name: str, user_id=None, inputs=None):
    supabase = get_supabase()
    prompt = (
        supabase.table("ai_prompts")
        .select("*")
        .eq("name", name)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
        .data
    )
    if not prompt:
        raise ValueError("Prompt not found")
    prompt = prompt[0]
    job_payload = {
        "user_id": user_id,
        "prompt_id": prompt["id"],
        "input": inputs or {},
        "status": "running",
        "metadata": {"version": prompt.get("version")},
        "created_at": datetime.utcnow().isoformat(),
    }
    job_id = log_job(job_payload)
    try:
        input_payload = inputs or {}
        user_content: list[dict] | str
        photo_urls = _extract_photo_urls(input_payload.get("photo_urls")) if isinstance(input_payload, dict) else []
        comparison_urls = (
            _extract_photo_urls(input_payload.get("comparison_photo_urls")) if isinstance(input_payload, dict) else []
        )
        all_urls = _dedupe_photo_urls(photo_urls + comparison_urls)
        if all_urls:
            user_content = [{"type": "text", "text": json.dumps(input_payload)}]
            user_content.extend({"type": "image_url", "image_url": {"url": url}} for url in all_urls)
        else:
            user_content = json.dumps(input_payload)
        client = _get_client()
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": prompt["template"]},
                {"role": "user", "content": user_content},
            ],
        )
        output = response.choices[0].message.content
        if job_id:
            update_job(job_id, {"output": output, "status": "completed"})
        return output
    except Exception as exc:
        if job_id:
            update_job(job_id, {"status": "failed", "metadata": {"error": str(exc)}})
        raise
