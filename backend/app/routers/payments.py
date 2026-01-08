from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..supabase_client import get_supabase

router = APIRouter()


class PaymentRecordRequest(BaseModel):
    user_id: str
    type: str
    status: str
    amount: float | None = None
    currency: str | None = None
    stripe_customer_id: str | None = None
    stripe_subscription_id: str | None = None
    stripe_session_id: str | None = None
    stripe_payment_intent_id: str | None = None
    metadata: dict | None = None


@router.post("/record")
async def record_payment(payload: PaymentRecordRequest):
    supabase = get_supabase()
    try:
        result = supabase.table("payment_records").insert(payload.dict()).execute().data
        if result:
            return {"record": result[0]}
        return {"record": payload.dict()}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/user/{user_id}")
async def list_payments(user_id: str, limit: int = 50):
    supabase = get_supabase()
    result = (
        supabase.table("payment_records")
        .select("*")
        .eq("user_id", user_id)
        .limit(limit)
        .execute()
        .data
    )
    return {"user_id": user_id, "records": result}
