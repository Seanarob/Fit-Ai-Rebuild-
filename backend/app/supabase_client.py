import os

from supabase import create_client

def get_supabase():
    supabase_url = os.environ.get("SUPABASE_URL")
    supabase_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not supabase_url or not supabase_key:
        raise RuntimeError("SUPABASE_URL/SERVICE_ROLE_KEY must be set")
    return create_client(supabase_url, supabase_key)
