import json
import os
from datetime import datetime
from typing import Generator

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from openai import OpenAI
from pydantic import BaseModel, Field

from ..supabase_client import get_supabase

router = APIRouter()


SYSTEM_PROMPT = (
    "You are FitAI Coach, a concise fitness coach. Only answer fitness topics. "
    "If the user asks about non-fitness topics, refuse and redirect back to fitness. "
    "If medical or injury advice is requested, give general info and advise a professional. "
    "Refuse illegal, dangerous, or self-harm related requests. "
    "Keep responses short, conversational, and specific to the provided user context. "
    "Answer only what was asked; do not add extra tips or follow-up advice unless requested. "
    "Default to 1-2 sentences (under ~40 words). Do not output long plans or deep analysis unless the user asks. "
    "If required context is missing, ask one short clarifying question. "
    "Avoid headings or report-style formatting unless explicitly requested."
)


class CreateThreadRequest(BaseModel):
    user_id: str
    title: str | None = None


class PostMessageRequest(BaseModel):
    user_id: str
    thread_id: str
    content: str
    stream: bool = True


def _get_client() -> OpenAI:
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not set")
    return OpenAI(api_key=api_key)


def _touch_thread(supabase, thread_id: str) -> None:
    now = datetime.utcnow().isoformat()
    supabase.table("chat_threads").update(
        {"updated_at": now, "last_message_at": now}
    ).eq("id", thread_id).execute()


def _get_profile(supabase, user_id: str) -> dict | None:
    result = (
        supabase.table("profiles")
        .select("age,goal,macros,preferences,height_cm,weight_kg,units,full_name")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    return result[0] if result else None


def _get_latest_checkin(supabase, user_id: str) -> dict | None:
    result = (
        supabase.table("weekly_checkins")
        .select("date,weight,adherence,ai_summary,macro_update,cardio_update,notes")
        .eq("user_id", user_id)
        .order("date", desc=True)
        .limit(1)
        .execute()
        .data
    )
    return result[0] if result else None


def _get_recent_workouts(supabase, user_id: str) -> dict:
    sessions = (
        supabase.table("workout_sessions")
        .select("id,template_id,status,duration_seconds,created_at,completed_at")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(5)
        .execute()
        .data
        or []
    )
    session_ids = [session.get("id") for session in sessions if session.get("id")]
    logs = []
    if session_ids:
        logs = (
            supabase.table("exercise_logs")
            .select("session_id,exercise_name,sets,reps,weight,notes,created_at")
            .in_("session_id", session_ids)
            .order("created_at", desc=True)
            .limit(30)
            .execute()
            .data
            or []
        )
    return {"sessions": sessions, "logs": logs}


def _get_recent_prs(supabase, user_id: str) -> list[dict]:
    return (
        supabase.table("prs")
        .select("exercise_name,metric,value,recorded_at")
        .eq("user_id", user_id)
        .order("recorded_at", desc=True)
        .limit(5)
        .execute()
        .data
        or []
    )


def _get_thread_summary(supabase, thread_id: str) -> str | None:
    result = (
        supabase.table("chat_thread_summaries")
        .select("summary")
        .eq("thread_id", thread_id)
        .limit(1)
        .execute()
        .data
    )
    if not result:
        return None
    return result[0].get("summary")


def _get_recent_messages(supabase, thread_id: str, limit: int = 12) -> list[dict]:
    result = (
        supabase.table("chat_messages")
        .select("role,content")
        .eq("thread_id", thread_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )
    return list(reversed(result))


def _build_user_context(supabase, user_id: str) -> str:
    profile = _get_profile(supabase, user_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    context_payload = {
        "profile": profile,
        "macros": profile.get("macros"),
        "latest_checkin": _get_latest_checkin(supabase, user_id),
        "recent_workouts": _get_recent_workouts(supabase, user_id),
        "recent_prs": _get_recent_prs(supabase, user_id),
    }
    return json.dumps(context_payload, default=str)


def _moderate_text(client: OpenAI, text: str) -> list[str]:
    response = client.moderations.create(model="omni-moderation-latest", input=text)
    if not response.results:
        return []
    result = response.results[0]
    if not result.flagged:
        return []
    categories = result.categories.model_dump() if result.categories else {}
    return [name for name, value in categories.items() if value]


def _build_refusal(flags: list[str]) -> str:
    if any("self-harm" in flag or "self_harm" in flag for flag in flags):
        return "Reply: I can't help with that. If you're in danger, contact a local professional or emergency service."
    return (
        "Reply: I can't help with that. I can help with training, nutrition, recovery, and your plan."
    )


@router.post("/thread")
async def create_thread(payload: CreateThreadRequest):
    supabase = get_supabase()
    row = (
        supabase.table("chat_threads")
        .insert({"user_id": payload.user_id, "title": payload.title})
        .execute()
        .data
    )
    if not row:
        raise HTTPException(status_code=500, detail="Failed to create thread")
    return {"thread": row[0]}


@router.get("/threads")
async def list_threads(user_id: str):
    supabase = get_supabase()
    threads = (
        supabase.table("chat_threads")
        .select("*")
        .eq("user_id", user_id)
        .order("last_message_at", desc=True)
        .execute()
        .data
        or []
    )
    return {"threads": threads}


@router.get("/thread/{thread_id}")
async def get_thread(thread_id: str, user_id: str):
    supabase = get_supabase()
    thread_rows = (
        supabase.table("chat_threads")
        .select("*")
        .eq("id", thread_id)
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    if not thread_rows:
        raise HTTPException(status_code=404, detail="Thread not found")
    messages = (
        supabase.table("chat_messages")
        .select("id,role,content,created_at")
        .eq("thread_id", thread_id)
        .order("created_at", desc=False)
        .execute()
        .data
        or []
    )
    summary = _get_thread_summary(supabase, thread_id)
    return {"thread": thread_rows[0], "messages": messages, "summary": summary}


@router.post("/message")
async def post_message(payload: PostMessageRequest):
    if not payload.content.strip():
        raise HTTPException(status_code=400, detail="Message content required")
    supabase = get_supabase()
    thread_rows = (
        supabase.table("chat_threads")
        .select("id")
        .eq("id", payload.thread_id)
        .eq("user_id", payload.user_id)
        .limit(1)
        .execute()
        .data
    )
    if not thread_rows:
        raise HTTPException(status_code=404, detail="Thread not found")

    supabase.table("chat_messages").insert(
        {
            "thread_id": payload.thread_id,
            "user_id": payload.user_id,
            "role": "user",
            "content": payload.content,
        }
    ).execute()
    _touch_thread(supabase, payload.thread_id)

    client = _get_client()
    flags = _moderate_text(client, payload.content)
    if flags:
        refusal_text = _build_refusal(flags)
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": payload.user_id,
                "role": "assistant",
                "content": refusal_text,
                "safety_flags": flags,
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        if payload.stream:
            def refusal_stream() -> Generator[str, None, None]:
                yield f"data: {refusal_text}\n\n"
                yield "data: [DONE]\n\n"

            return StreamingResponse(refusal_stream(), media_type="text/event-stream")
        return {"reply": refusal_text}

    history = _get_recent_messages(supabase, payload.thread_id, limit=12)
    if history and history[-1].get("role") == "user" and history[-1].get("content") == payload.content:
        history = history[:-1]

    context_blob = _build_user_context(supabase, payload.user_id)
    summary = _get_thread_summary(supabase, payload.thread_id)
    context_message = "User Context (server-trusted): " + context_blob
    if summary:
        context_message += f"\nThread Summary: {summary}"

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "system", "content": context_message},
        *history,
        {"role": "user", "content": payload.content},
    ]

    if not payload.stream:
        completion = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=200,
            temperature=0.3,
        )
        assistant_text = completion.choices[0].message.content or ""
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": payload.user_id,
                "role": "assistant",
                "content": assistant_text,
                "model": "gpt-4o-mini",
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        return {"reply": assistant_text}

    def stream_response() -> Generator[str, None, None]:
        assistant_text = ""
        stream = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=200,
            temperature=0.3,
            stream=True,
        )
        for chunk in stream:
            delta = chunk.choices[0].delta.content or ""
            if delta:
                assistant_text += delta
                yield f"data: {delta}\n\n"
        supabase.table("chat_messages").insert(
            {
                "thread_id": payload.thread_id,
                "user_id": payload.user_id,
                "role": "assistant",
                "content": assistant_text,
                "model": "gpt-4o-mini",
            }
        ).execute()
        _touch_thread(supabase, payload.thread_id)
        yield "data: [DONE]\n\n"

    return StreamingResponse(stream_response(), media_type="text/event-stream")
