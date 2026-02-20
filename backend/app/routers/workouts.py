from datetime import datetime
import uuid

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from supabase import Client

from ..prompts import run_prompt
from ..supabase_client import get_supabase

router = APIRouter()


class GenerateWorkoutRequest(BaseModel):
    user_id: str | None = None
    muscle_groups: list[str]
    workout_type: str | None = None
    equipment: list[str] | None = None
    duration_minutes: int | None = None


class ExerciseInput(BaseModel):
    name: str
    muscle_groups: list[str] = Field(default_factory=list)
    equipment: list[str] = Field(default_factory=list)
    sets: int | None = None
    reps: int | None = None
    rest_seconds: int | None = None
    notes: str | None = None


class SaveTemplateRequest(BaseModel):
    user_id: str | None = None
    title: str
    description: str | None = None
    mode: str = "manual"
    exercises: list[ExerciseInput] = Field(default_factory=list)


class UpdateTemplateRequest(BaseModel):
    title: str
    description: str | None = None
    mode: str = "manual"
    exercises: list[ExerciseInput] = Field(default_factory=list)


class DuplicateTemplateRequest(BaseModel):
    user_id: str | None = None
    title: str | None = None


class StartSessionRequest(BaseModel):
    user_id: str
    template_id: str | None = None
    status: str = "in_progress"


class SessionLogRequest(BaseModel):
    exercise_name: str
    sets: int = 1
    reps: int = 0
    weight: float = 0
    duration_minutes: int | None = None
    duration_seconds: int | None = None
    is_warmup: bool = False
    set_index: int | None = None
    notes: str | None = None


class CompleteSessionRequest(BaseModel):
    duration_seconds: int | None = None
    status: str = "completed"


def _get_or_create_exercise(supabase: Client, exercise: ExerciseInput) -> str:
    existing = (
        supabase.table("exercises")
        .select("id")
        .eq("name", exercise.name)
        .limit(1)
        .execute()
        .data
    )
    if existing:
        return existing[0]["id"]

    created = (
        supabase.table("exercises")
        .insert(
            {
                "name": exercise.name,
                "muscle_groups": exercise.muscle_groups,
                "equipment": exercise.equipment,
            }
        )
        .execute()
        .data
    )
    if not created:
        raise HTTPException(status_code=500, detail="Failed to create exercise")
    return created[0]["id"]


def _estimate_one_rep_max(weight: float, reps: int) -> float:
    if weight <= 0 or reps <= 0:
        return 0
    return round(weight * (1 + reps / 30), 2)


def _is_missing_column_error(exc: Exception, column_name: str) -> bool:
    message = str(exc).lower()
    col = column_name.lower()
    return col in message and "column" in message and "does not exist" in message


def _is_missing_table_error(exc: Exception, table_name: str) -> bool:
    message = str(exc).lower()
    table = table_name.lower()
    return table in message and ("does not exist" in message or "relation" in message)


def _normalize_user_id(user_id: str | None) -> str | None:
    if not user_id:
        return None
    try:
        return str(uuid.UUID(user_id))
    except ValueError:
        return str(uuid.uuid5(uuid.NAMESPACE_URL, f"fitai:{user_id}"))


def _ensure_user_exists(supabase: Client, user_id: str | None) -> str | None:
    if not user_id:
        return None
    existing = (
        supabase.table("users")
        .select("id")
        .eq("id", user_id)
        .limit(1)
        .execute()
        .data
    )
    if existing:
        return user_id
    placeholder_email = f"user-{user_id}@placeholder.local"
    supabase.table("users").insert(
        {
            "id": user_id,
            "email": placeholder_email,
            "hashed_password": "placeholder",
            "role": "user",
        }
    ).execute()
    return user_id


@router.post("/generate")
async def generate_workout(payload: GenerateWorkoutRequest):
    supabase: Client = get_supabase()
    user_id = _ensure_user_exists(supabase, _normalize_user_id(payload.user_id))
    prompt_input = {
        "muscle_groups": payload.muscle_groups,
        "workout_type": payload.workout_type,
        "equipment": payload.equipment,
        "duration_minutes": payload.duration_minutes,
    }
    try:
        result = run_prompt(
            "workout_generation", user_id=user_id, inputs=prompt_input
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {"template": result}


@router.post("/templates")
async def create_template(payload: SaveTemplateRequest):
    supabase: Client = get_supabase()
    user_id = _ensure_user_exists(supabase, _normalize_user_id(payload.user_id))
    try:
        template_rows = (
            supabase.table("workout_templates")
            .insert(
                {
                    "user_id": user_id,
                    "title": payload.title,
                    "description": payload.description,
                    "mode": payload.mode,
                }
            )
            .execute()
            .data
        )
        if not template_rows:
            raise HTTPException(status_code=500, detail="Failed to create template")
        template_id = template_rows[0]["id"]

        for idx, exercise in enumerate(payload.exercises):
            exercise_id = _get_or_create_exercise(supabase, exercise)
            supabase.table("workout_template_exercises").insert(
                {
                    "template_id": template_id,
                    "exercise_id": exercise_id,
                    "position": idx,
                    "sets": exercise.sets or 0,
                    "reps": exercise.reps or 0,
                    "rest_seconds": exercise.rest_seconds or 0,
                    "notes": exercise.notes,
                }
            ).execute()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {"template_id": template_id}


@router.get("/templates")
async def list_templates(user_id: str):
    supabase: Client = get_supabase()
    normalized_user_id = _normalize_user_id(user_id)
    try:
        templates = (
            supabase.table("workout_templates")
            .select("id,title,description,mode,created_at")
            .eq("user_id", normalized_user_id)
            .order("created_at", desc=True)
            .execute()
            .data
        )
        return {"templates": templates or []}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/templates/{template_id}")
async def get_template_detail(template_id: str):
    supabase: Client = get_supabase()
    try:
        template_rows = (
            supabase.table("workout_templates")
            .select("id,title,description,mode,created_at")
            .eq("id", template_id)
            .limit(1)
            .execute()
            .data
        )
        if not template_rows:
            raise HTTPException(status_code=404, detail="Template not found")
        template = template_rows[0]

        template_exercises = (
            supabase.table("workout_template_exercises")
            .select(
                "exercise_id,position,sets,reps,rest_seconds,notes"
            )
            .eq("template_id", template_id)
            .order("position")
            .execute()
            .data
        )

        exercise_ids = [row["exercise_id"] for row in template_exercises if row.get("exercise_id")]
        exercise_map: dict[str, dict] = {}
        if exercise_ids:
            exercises = (
                supabase.table("exercises")
                .select("id,name,muscle_groups,equipment")
                .in_("id", exercise_ids)
                .execute()
                .data
            )
            exercise_map = {row["id"]: row for row in exercises or []}

        enriched = []
        for row in template_exercises or []:
            exercise = exercise_map.get(row.get("exercise_id"), {})
            enriched.append(
                {
                    "exercise_id": row.get("exercise_id"),
                    "name": exercise.get("name", "Unknown"),
                    "muscle_groups": exercise.get("muscle_groups") or [],
                    "equipment": exercise.get("equipment") or [],
                    "sets": row.get("sets"),
                    "reps": row.get("reps"),
                    "rest_seconds": row.get("rest_seconds"),
                    "notes": row.get("notes"),
                    "position": row.get("position"),
                }
            )
        return {"template": template, "exercises": enriched}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.put("/templates/{template_id}")
async def update_template(template_id: str, payload: UpdateTemplateRequest):
    supabase: Client = get_supabase()
    try:
        updated = (
            supabase.table("workout_templates")
            .update(
                {
                    "title": payload.title,
                    "description": payload.description,
                    "mode": payload.mode,
                }
            )
            .eq("id", template_id)
            .execute()
            .data
        )
        if not updated:
            raise HTTPException(status_code=404, detail="Template not found")

        supabase.table("workout_template_exercises").delete().eq(
            "template_id", template_id
        ).execute()

        for idx, exercise in enumerate(payload.exercises):
            exercise_id = _get_or_create_exercise(supabase, exercise)
            supabase.table("workout_template_exercises").insert(
                {
                    "template_id": template_id,
                    "exercise_id": exercise_id,
                    "position": idx,
                    "sets": exercise.sets or 0,
                    "reps": exercise.reps or 0,
                    "rest_seconds": exercise.rest_seconds or 0,
                    "notes": exercise.notes,
                }
            ).execute()
        return {"template_id": template_id}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.delete("/templates/{template_id}")
async def delete_template(template_id: str):
    supabase: Client = get_supabase()
    try:
        deleted = (
            supabase.table("workout_templates")
            .delete()
            .eq("id", template_id)
            .execute()
            .data
        )
        if not deleted:
            raise HTTPException(status_code=404, detail="Template not found")
        return {"template_id": template_id}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/templates/{template_id}/duplicate")
async def duplicate_template(template_id: str, payload: DuplicateTemplateRequest):
    supabase: Client = get_supabase()
    try:
        normalized_user_id = _ensure_user_exists(
            supabase, _normalize_user_id(payload.user_id)
        )
        template_rows = (
            supabase.table("workout_templates")
            .select("id,user_id,title,description,mode")
            .eq("id", template_id)
            .limit(1)
            .execute()
            .data
        )
        if not template_rows:
            raise HTTPException(status_code=404, detail="Template not found")
        template = template_rows[0]

        new_title = payload.title or f"{template['title']} Copy"
        new_user_id = normalized_user_id or template.get("user_id")
        new_rows = (
            supabase.table("workout_templates")
            .insert(
                {
                    "user_id": new_user_id,
                    "title": new_title,
                    "description": template.get("description"),
                    "mode": template.get("mode"),
                }
            )
            .execute()
            .data
        )
        if not new_rows:
            raise HTTPException(status_code=500, detail="Failed to duplicate template")
        new_template_id = new_rows[0]["id"]

        template_exercises = (
            supabase.table("workout_template_exercises")
            .select("exercise_id,position,sets,reps,rest_seconds,notes")
            .eq("template_id", template_id)
            .order("position")
            .execute()
            .data
        )
        for row in template_exercises or []:
            supabase.table("workout_template_exercises").insert(
                {
                    "template_id": new_template_id,
                    "exercise_id": row.get("exercise_id"),
                    "position": row.get("position", 0),
                    "sets": row.get("sets", 0),
                    "reps": row.get("reps", 0),
                    "rest_seconds": row.get("rest_seconds", 0),
                    "notes": row.get("notes"),
                }
            ).execute()
        return {"template_id": new_template_id}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/sessions")
async def list_sessions(user_id: str):
    supabase: Client = get_supabase()
    normalized_user_id = _normalize_user_id(user_id)
    try:
        sessions = (
            supabase.table("workout_sessions")
            .select("id,template_id,status,duration_seconds,created_at")
            .eq("user_id", normalized_user_id)
            .order("created_at", desc=True)
            .limit(20)
            .execute()
            .data
        )
        template_ids = [row["template_id"] for row in sessions or [] if row.get("template_id")]
        template_titles = {}
        if template_ids:
            templates = (
                supabase.table("workout_templates")
                .select("id,title")
                .in_("id", template_ids)
                .execute()
                .data
            )
            template_titles = {row["id"]: row["title"] for row in templates or []}
        enriched = []
        for session in sessions or []:
            session["template_title"] = template_titles.get(session.get("template_id"))
            enriched.append(session)
        return {"sessions": enriched}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/sessions/start")
async def start_session(payload: StartSessionRequest):
    supabase: Client = get_supabase()
    user_id = _ensure_user_exists(supabase, _normalize_user_id(payload.user_id))
    try:
        rows = (
            supabase.table("workout_sessions")
            .insert(
                {
                    "user_id": user_id,
                    "template_id": payload.template_id,
                    "status": payload.status,
                    "started_at": datetime.utcnow().isoformat(),
                }
            )
            .execute()
            .data
        )
        if not rows:
            raise HTTPException(status_code=500, detail="Failed to start session")
        return {"session_id": rows[0]["id"]}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/sessions/{session_id}/log")
async def log_exercise(session_id: str, payload: SessionLogRequest):
    supabase: Client = get_supabase()
    try:
        duration_minutes = payload.duration_minutes or 0
        has_duration = duration_minutes > 0
        duration_seconds = payload.duration_seconds
        if duration_seconds is None and has_duration:
            duration_seconds = duration_minutes * 60
        duration_seconds = duration_seconds or 0
        is_warmup = bool(payload.is_warmup)
        set_index = payload.set_index if payload.set_index and payload.set_index > 0 else 1
        insert_payload = {
            "session_id": session_id,
            "exercise_name": payload.exercise_name,
            "sets": 0 if has_duration else payload.sets,
            "reps": 0 if has_duration else payload.reps,
            "weight": 0 if has_duration else payload.weight,
            "duration_minutes": duration_minutes if has_duration else 0,
            "notes": payload.notes,
        }
        try:
            rows = supabase.table("exercise_logs").insert(insert_payload).execute().data
        except Exception as exc:
            if not _is_missing_column_error(exc, "duration_minutes"):
                raise
            # Back-compat: older schemas may not have `duration_minutes`.
            # Store cardio duration in `reps` so the client can still render minutes.
            fallback = dict(insert_payload)
            fallback.pop("duration_minutes", None)
            if has_duration:
                fallback["reps"] = duration_minutes
            rows = supabase.table("exercise_logs").insert(fallback).execute().data
        if not rows:
            raise HTTPException(status_code=500, detail="Failed to log exercise")
        log_id = rows[0]["id"]

        set_payload = {
            "exercise_log_id": log_id,
            "set_index": set_index,
            "is_warmup": is_warmup,
            "reps": 0 if has_duration else payload.reps,
            "weight": 0 if has_duration else payload.weight,
            "duration_seconds": duration_seconds,
        }
        try:
            supabase.table("exercise_sets").insert(set_payload).execute()
        except Exception as exc:
            if _is_missing_table_error(exc, "exercise_sets"):
                pass
            elif _is_missing_column_error(exc, "duration_seconds"):
                fallback = dict(set_payload)
                fallback.pop("duration_seconds", None)
                supabase.table("exercise_sets").insert(fallback).execute()
            elif _is_missing_column_error(exc, "is_warmup"):
                fallback = dict(set_payload)
                fallback.pop("is_warmup", None)
                supabase.table("exercise_sets").insert(fallback).execute()
            elif _is_missing_column_error(exc, "set_index"):
                fallback = dict(set_payload)
                fallback.pop("set_index", None)
                supabase.table("exercise_sets").insert(fallback).execute()
            else:
                raise
        return {"log_id": rows[0]["id"]}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/sessions/{session_id}/complete")
async def complete_session(session_id: str, payload: CompleteSessionRequest):
    supabase: Client = get_supabase()
    try:
        sessions = (
            supabase.table("workout_sessions")
            .select("id,user_id")
            .eq("id", session_id)
            .limit(1)
            .execute()
            .data
        )
        if not sessions:
            raise HTTPException(status_code=404, detail="Session not found")
        session = sessions[0]

        supabase.table("workout_sessions").update(
            {
                "status": payload.status,
                "duration_seconds": payload.duration_seconds or 0,
                "completed_at": datetime.utcnow().isoformat(),
            }
        ).eq("id", session_id).execute()

        logs = (
            supabase.table("exercise_logs")
            .select("exercise_name,reps,weight")
            .eq("session_id", session_id)
            .execute()
            .data
        )

        best_by_exercise: dict[str, float] = {}
        for log in logs or []:
            reps = int(log.get("reps") or 0)
            weight = float(log.get("weight") or 0)
            estimate = _estimate_one_rep_max(weight, reps)
            if estimate <= 0:
                continue
            name = log.get("exercise_name") or "Unknown"
            best_by_exercise[name] = max(best_by_exercise.get(name, 0), estimate)

        pr_updates = []
        for exercise_name, value in best_by_exercise.items():
            existing = (
                supabase.table("prs")
                .select("id,value")
                .eq("user_id", session["user_id"])
                .eq("exercise_name", exercise_name)
                .eq("metric", "estimated_1rm")
                .order("value", desc=True)
                .limit(1)
                .execute()
                .data
            )
            previous_value = None
            if existing:
                previous_value = float(existing[0]["value"])
                if value <= previous_value:
                    continue

            supabase.table("prs").insert(
                {
                    "user_id": session["user_id"],
                    "exercise_name": exercise_name,
                    "metric": "estimated_1rm",
                    "value": value,
                }
            ).execute()

            pr_updates.append(
                {
                    "exercise_name": exercise_name,
                    "value": value,
                    "previous_value": previous_value,
                }
            )

        return {
            "session_id": session_id,
            "status": payload.status,
            "duration_seconds": payload.duration_seconds or 0,
            "prs": pr_updates,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/sessions/{session_id}/logs")
async def session_logs(session_id: str):
    supabase: Client = get_supabase()
    try:
        try:
            logs = (
                supabase.table("exercise_logs")
                .select("id,exercise_name,sets,reps,weight,duration_minutes,notes,created_at")
                .eq("session_id", session_id)
                .order("created_at")
                .execute()
                .data
            )
        except Exception as exc:
            if not _is_missing_column_error(exc, "duration_minutes"):
                raise
            logs = (
                supabase.table("exercise_logs")
                .select("id,exercise_name,sets,reps,weight,notes,created_at")
                .eq("session_id", session_id)
                .order("created_at")
                .execute()
                .data
            )
        logs = logs or []
        log_ids = [log.get("id") for log in logs if log.get("id")]
        if log_ids:
            try:
                set_rows = (
                    supabase.table("exercise_sets")
                    .select(
                        "exercise_log_id,set_index,reps,weight,is_warmup,duration_seconds"
                    )
                    .in_("exercise_log_id", log_ids)
                    .order("set_index")
                    .execute()
                    .data
                )
                set_map: dict[str, list[dict]] = {}
                for row in set_rows or []:
                    log_id = row.get("exercise_log_id")
                    if not log_id:
                        continue
                    set_map.setdefault(log_id, []).append(
                        {
                            "set_index": row.get("set_index"),
                            "reps": row.get("reps") or 0,
                            "weight": row.get("weight") or 0,
                            "is_warmup": row.get("is_warmup") or False,
                            "duration_seconds": row.get("duration_seconds") or 0,
                        }
                    )
                for log in logs:
                    log["set_details"] = set_map.get(log.get("id"), [])
            except Exception as exc:
                if not _is_missing_table_error(exc, "exercise_sets"):
                    raise
        return {"session_id": session_id, "logs": logs}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/exercises/history")
async def exercise_history(user_id: str, exercise_name: str, limit: int = 20):
    supabase: Client = get_supabase()
    normalized_user_id = _normalize_user_id(user_id)
    try:
        sessions = (
            supabase.table("workout_sessions")
            .select("id,created_at")
            .eq("user_id", normalized_user_id)
            .execute()
            .data
        )
        if not sessions:
            return {
                "exercise_name": exercise_name,
                "entries": [],
                "best_set": None,
                "estimated_1rm": 0,
                "trend": [],
            }

        session_map = {row["id"]: row.get("created_at") for row in sessions}
        session_ids = list(session_map.keys())
        logs = (
            supabase.table("exercise_logs")
            .select("id,session_id,exercise_name,sets,reps,weight,notes,created_at")
            .eq("exercise_name", exercise_name)
            .in_("session_id", session_ids)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
            .data
        )

        entries = []
        best_set = None
        best_estimated = 0.0
        trend = []
        for log in logs or []:
            reps = int(log.get("reps") or 0)
            weight = float(log.get("weight") or 0)
            estimated = _estimate_one_rep_max(weight, reps)
            entry = {
                "id": log.get("id"),
                "date": session_map.get(log.get("session_id")),
                "sets": log.get("sets") or 0,
                "reps": reps,
                "weight": weight,
                "estimated_1rm": estimated,
            }
            entries.append(entry)
            trend.append({"date": entry["date"], "estimated_1rm": estimated})
            if estimated > best_estimated:
                best_estimated = estimated
                best_set = {
                    "weight": weight,
                    "reps": reps,
                    "estimated_1rm": estimated,
                }

        return {
            "exercise_name": exercise_name,
            "entries": entries,
            "best_set": best_set,
            "estimated_1rm": best_estimated,
            "trend": trend,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
