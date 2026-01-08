from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from uuid import uuid4
import hashlib

from ..supabase_client import get_supabase

router = APIRouter()


class RegisterRequest(BaseModel):
    email: str
    password: str
    role: str = "user"


@router.post("/register")
async def register(payload: RegisterRequest):
    try:
        supabase = get_supabase()
        user_id = str(uuid4())
        hashed_password = hashlib.sha256(payload.password.encode("utf-8")).hexdigest()
        supabase.table("users").insert(
            {
                "id": user_id,
                "email": payload.email,
                "hashed_password": hashed_password,
                "role": payload.role,
            }
        ).execute()
        return {"status": "ok", "user_id": user_id}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


class LoginRequest(BaseModel):
    email: str
    password: str


@router.post("/login")
async def login(payload: LoginRequest):
    try:
        supabase = get_supabase()
        result = (
            supabase.table("users")
            .select("id, hashed_password")
            .eq("email", payload.email)
            .limit(1)
            .execute()
        )
        if not result.data:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        user = result.data[0]
        hashed_password = hashlib.sha256(payload.password.encode("utf-8")).hexdigest()
        if user["hashed_password"] != hashed_password:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        return {"status": "ok", "user_id": user["id"]}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
