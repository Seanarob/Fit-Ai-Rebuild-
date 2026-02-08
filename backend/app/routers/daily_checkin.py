"""
Daily Check-In Router

Handles the daily check-in functionality for the streak system.
Users complete a quick 3-question check-in to save their App Streak.
"""

import os
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, HTTPException
from openai import OpenAI
from pydantic import BaseModel

from ..supabase_client import get_supabase

router = APIRouter()


class DailyCheckInRequest(BaseModel):
    user_id: str
    hit_macros: bool
    training_status: Literal["trained", "off_day"]
    sleep_quality: Literal["good", "okay", "poor"]


class DailyCheckInResponse(BaseModel):
    coach_response: str
    streak_saved: bool
    current_streak: int | None = None


def _get_openai_client() -> OpenAI:
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not set")
    return OpenAI(api_key=api_key)


def _generate_coach_response(
    hit_macros: bool,
    training_status: str,
    sleep_quality: str,
) -> str:
    """Generate a short motivational response based on check-in answers."""
    
    # Try AI generation first, fall back to local generation
    try:
        client = _get_openai_client()
        
        prompt = f"""You are FitAI Coach, a friendly fitness coach. 
A user just completed their daily check-in with these answers:
- Hit macros yesterday: {"Yes" if hit_macros else "No"}
- Training: {training_status.replace("_", " ")}
- Sleep quality: {sleep_quality}

Respond with ONE short motivational sentence (15-20 words max).
Be encouraging and acknowledge their honest answers.
If they didn't hit macros or had poor sleep, be supportive not critical.
Use a casual, friendly tone like a gym buddy.
Don't use hashtags or emojis at the start."""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a concise, motivational fitness coach."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=50,
            temperature=0.7,
        )
        
        return response.choices[0].message.content.strip()
    except Exception:
        # Fall back to local response generation
        return _generate_local_response(hit_macros, training_status, sleep_quality)


def _generate_local_response(
    hit_macros: bool,
    training_status: str,
    sleep_quality: str,
) -> str:
    """Generate a local response without API call."""
    
    trained = training_status == "trained"
    good_sleep = sleep_quality == "good"
    
    if hit_macros and trained and good_sleep:
        responses = [
            "Perfect day yesterday! Keep that energy going today.",
            "You're crushing it! Consistency like this builds champions.",
            "Elite habits! Your future self is thanking you right now.",
            "All boxes checked! This is how transformations happen.",
        ]
    elif hit_macros and trained:
        responses = [
            "Great work on training and nutrition! Prioritize sleep tonight.",
            "Two out of three ain't bad! Rest up and keep building.",
            "Solid effort! Better sleep = better gains tomorrow.",
        ]
    elif hit_macros:
        responses = [
            "Nutrition on point! Rest day recovery is important too.",
            "Macros hit! Even rest days are progress days.",
            "Great job fueling right! Your body's recovering.",
        ]
    elif trained:
        responses = [
            "Great workout! Let's dial in those macros today.",
            "Training done! Fuel that body right and watch the gains come.",
            "Good session! Remember: nutrition amplifies your hard work.",
        ]
    else:
        responses = [
            "New day, fresh start! Let's make today count.",
            "Every day is a chance to build momentum. Let's go!",
            "Progress isn't always perfect. Keep showing up!",
            "One day at a time. You've got this!",
        ]
    
    import random
    return random.choice(responses)


@router.post("/daily-checkin", response_model=DailyCheckInResponse)
async def submit_daily_checkin(request: DailyCheckInRequest):
    """
    Submit a daily check-in to save the App Streak.
    
    The check-in includes:
    - Whether the user hit their macros yesterday
    - Whether they trained or had an off day
    - Their sleep quality (good/okay/poor)
    
    Returns a motivational coach response.
    """
    
    # Generate coach response
    coach_response = _generate_coach_response(
        hit_macros=request.hit_macros,
        training_status=request.training_status,
        sleep_quality=request.sleep_quality,
    )
    
    # Optionally log to database for analytics
    try:
        supabase = get_supabase()
        supabase.table("daily_checkins").insert({
            "user_id": request.user_id,
            "date": datetime.utcnow().date().isoformat(),
            "hit_macros": request.hit_macros,
            "training_status": request.training_status,
            "sleep_quality": request.sleep_quality,
            "coach_response": coach_response,
            "created_at": datetime.utcnow().isoformat(),
        }).execute()
    except Exception:
        # Don't fail the request if logging fails
        pass
    
    return DailyCheckInResponse(
        coach_response=coach_response,
        streak_saved=True,
    )


@router.get("/daily-checkin/status")
async def get_checkin_status(user_id: str):
    """
    Check if user has completed their daily check-in today.
    """
    try:
        supabase = get_supabase()
        today = datetime.utcnow().date().isoformat()
        
        result = (
            supabase.table("daily_checkins")
            .select("*")
            .eq("user_id", user_id)
            .eq("date", today)
            .limit(1)
            .execute()
            .data
        )
        
        if result:
            return {
                "completed": True,
                "checkin": result[0],
            }
        
        return {"completed": False}
    except Exception:
        return {"completed": False}


