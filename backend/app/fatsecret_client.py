import base64
import json
import os
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from fastapi import HTTPException

FATSECRET_OAUTH_URL = "https://oauth.fatsecret.com/connect/token"
FATSECRET_API_URL = "https://platform.fatsecret.com/rest/server.api"
_TOKEN_CACHE = {"access_token": None, "expires_at": 0}


def _get_credentials() -> tuple[str, str]:
    client_id = os.environ.get("FATSECRET_CLIENT_ID")
    client_secret = os.environ.get("FATSECRET_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise HTTPException(
            status_code=500,
            detail="FatSecret client credentials are not configured.",
        )
    return client_id, client_secret


def _fetch_token() -> str:
    client_id, client_secret = _get_credentials()
    auth = base64.b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode(
        "utf-8"
    )
    data = urlencode({"grant_type": "client_credentials", "scope": "basic"}).encode(
        "utf-8"
    )
    request = Request(
        FATSECRET_OAUTH_URL,
        data=data,
        headers={
            "Authorization": f"Basic {auth}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    try:
        with urlopen(request) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        raise HTTPException(
            status_code=500, detail=f"FatSecret token request failed: {exc}"
        )
    access_token = payload.get("access_token")
    expires_in = int(payload.get("expires_in") or 0)
    if not access_token:
        raise HTTPException(
            status_code=500,
            detail="FatSecret token response missing access_token.",
        )
    _TOKEN_CACHE["access_token"] = access_token
    _TOKEN_CACHE["expires_at"] = int(time.time()) + max(expires_in - 30, 0)
    return access_token


def _get_token() -> str:
    now = int(time.time())
    access_token = _TOKEN_CACHE.get("access_token")
    if access_token and now < int(_TOKEN_CACHE.get("expires_at") or 0):
        return access_token
    return _fetch_token()


def fatsecret_request(method: str, params: dict) -> dict:
    token = _get_token()
    query = {"method": method, "format": "json", **params}
    url = f"{FATSECRET_API_URL}?{urlencode(query)}"
    request = Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urlopen(request) as response:
            body = response.read().decode("utf-8")
            return json.loads(body)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"FatSecret request failed: {exc}")
