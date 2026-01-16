import json
import os
from datetime import datetime

import openai

from .supabase_client import get_supabase

openai.api_key = os.environ.get("OPENAI_API_KEY", "")

def log_job(payload: dict):
    supabase = get_supabase()
    supabase.table("ai_jobs").insert(payload).execute()

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
        "metadata": {"version": prompt["version"]},
        "created_at": datetime.utcnow().isoformat(),
    }
    log_job(job_payload)
    try:
        input_payload = inputs or {}
        user_content: list[dict] | str
        photo_urls = input_payload.get("photo_urls") if isinstance(input_payload, dict) else None
        if photo_urls:
            user_content = [{"type": "text", "text": json.dumps(input_payload)}]
            user_content.extend(
                {"type": "image_url", "image_url": {"url": url}} for url in photo_urls if url
            )
        else:
            user_content = json.dumps(input_payload)
        response = openai.ChatCompletion.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": prompt["template"]},
                {"role": "user", "content": user_content},
            ],
        )
        output = response.choices[0].message.content
        update_job(job_payload["id"], {"output": output, "status": "completed"})
        return output
    except Exception as exc:
        update_job(job_payload["id"], {"status": "failed", "metadata": {"error": str(exc)}})
        raise
