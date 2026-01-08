from fastapi import APIRouter

router = APIRouter()


@router.post("/prompt")
async def run_prompt(name: str):
    # placeholder call against stored prompt template
    return {"prompt": name, "result": "Pending"}
