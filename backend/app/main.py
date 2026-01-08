from fastapi import FastAPI

from .routers import (
    auth,
    workouts,
    nutrition,
    ai,
    checkins,
    onboarding,
    profiles,
    coach,
    payments,
    exercises,
    users,
)

app = FastAPI(title="FitAI Backend")

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(workouts.router, prefix="/workouts", tags=["workouts"])
app.include_router(nutrition.router, prefix="/nutrition", tags=["nutrition"])
app.include_router(ai.router, prefix="/ai", tags=["ai"])
app.include_router(checkins.router, prefix="/checkins", tags=["checkins"])
app.include_router(onboarding.router, prefix="/onboarding", tags=["onboarding"])
app.include_router(profiles.router, prefix="/profiles", tags=["profiles"])
app.include_router(coach.router, prefix="/coach", tags=["coach"])
app.include_router(payments.router, prefix="/payments", tags=["payments"])
app.include_router(exercises.router, prefix="/exercises", tags=["exercises"])
app.include_router(users.router, prefix="/users", tags=["users"])
