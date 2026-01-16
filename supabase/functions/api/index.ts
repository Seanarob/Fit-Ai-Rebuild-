import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const openaiApiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
const fatsecretClientId = Deno.env.get("FATSECRET_CLIENT_ID") ?? "";
const fatsecretClientSecret = Deno.env.get("FATSECRET_CLIENT_SECRET") ?? "";
const fatsecretScope = Deno.env.get("FATSECRET_SCOPE") ?? "premier";
const usdaApiKey = Deno.env.get("USDA_API_KEY") ?? "";
const mealPhotoBucket = Deno.env.get("SUPABASE_MEAL_PHOTO_BUCKET") ?? "meal-photos";
const progressPhotoBucket = Deno.env.get("SUPABASE_PROGRESS_PHOTO_BUCKET") ?? "progress-photos";

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: { persistSession: false },
});

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
};

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const urlNamespaceUuid = "6ba7b811-9dad-11d1-80b4-00c04fd430c8";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders },
  });
}

function normalizePath(path: string) {
  if (path.length > 1 && path.endsWith("/")) {
    return path.slice(0, -1);
  }
  return path;
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function uuidToBytes(uuid: string) {
  const hex = uuid.replace(/-/g, "");
  const bytes = new Uint8Array(16);
  for (let i = 0; i < 16; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function bytesToUuid(bytes: Uint8Array) {
  const hex = Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}

async function uuidV5(name: string, namespace = urlNamespaceUuid) {
  const namespaceBytes = uuidToBytes(namespace);
  const nameBytes = new TextEncoder().encode(name);
  const data = new Uint8Array(namespaceBytes.length + nameBytes.length);
  data.set(namespaceBytes);
  data.set(nameBytes, namespaceBytes.length);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-1", data)).slice(0, 16);
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  return bytesToUuid(hash);
}

async function normalizeUserId(userId?: string | null) {
  if (!userId) return null;
  if (isUuid(userId)) return userId;
  return await uuidV5(`fitai:${userId}`);
}

async function sha256Hex(value: string) {
  const data = new TextEncoder().encode(value);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

async function parseJson<T = Record<string, unknown>>(req: Request): Promise<T> {
  try {
    return (await req.json()) as T;
  } catch {
    throw new HttpError(400, "Invalid JSON payload.");
  }
}

function ensureEnv(value: string, name: string) {
  if (!value) {
    throw new HttpError(500, `${name} is not configured.`);
  }
  return value;
}

async function runPrompt(name: string, userId: string | null, inputs: Record<string, unknown>) {
  const { data: promptRows } = await supabase
    .from("ai_prompts")
    .select("*")
    .eq("name", name)
    .order("created_at", { ascending: false })
    .limit(1);

  if (!promptRows || promptRows.length === 0) {
    throw new HttpError(404, "Prompt not found");
  }

  const prompt = promptRows[0];
  const jobPayload = {
    user_id: userId,
    prompt_id: prompt.id,
    input: inputs,
    status: "running",
    metadata: { version: prompt.version },
    created_at: new Date().toISOString(),
  };

  const { data: jobRows } = await supabase.from("ai_jobs").insert(jobPayload).select();
  const jobId = jobRows && jobRows[0] ? jobRows[0].id : null;

  const key = ensureEnv(openaiApiKey, "OPENAI_API_KEY");
  const photoUrls = Array.isArray(inputs.photo_urls) ? inputs.photo_urls : [];

  const userContent = photoUrls.length
    ? [
        { type: "text", text: JSON.stringify(inputs) },
        ...photoUrls.filter(Boolean).map((url) => ({ type: "image_url", image_url: { url } })),
      ]
    : JSON.stringify(inputs);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: prompt.template },
        { role: "user", content: userContent },
      ],
    }),
  });

  const payload = await response.json();
  if (!response.ok) {
    if (jobId) {
      await supabase.from("ai_jobs").update({ status: "failed", metadata: { error: payload } }).eq("id", jobId);
    }
    throw new HttpError(502, "AI request failed");
  }

  const output = payload.choices?.[0]?.message?.content ?? "";
  if (jobId) {
    await supabase.from("ai_jobs").update({ status: "completed", output }).eq("id", jobId);
  }
  return output;
}

let fatsecretToken: { token: string; expiresAt: number } | null = null;

async function getFatsecretToken() {
  const clientId = ensureEnv(fatsecretClientId, "FATSECRET_CLIENT_ID");
  const clientSecret = ensureEnv(fatsecretClientSecret, "FATSECRET_CLIENT_SECRET");
  const now = Date.now() / 1000;

  if (fatsecretToken && fatsecretToken.expiresAt > now + 30) {
    return fatsecretToken.token;
  }

  const auth = btoa(`${clientId}:${clientSecret}`);
  const response = await fetch("https://oauth.fatsecret.com/connect/token", {
    method: "POST",
    headers: {
      authorization: `Basic ${auth}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({ grant_type: "client_credentials", scope: fatsecretScope }),
  });

  const payload = await response.json();
  if (!response.ok) {
    throw new HttpError(500, `FatSecret token request failed: ${JSON.stringify(payload)}`);
  }

  const token = payload.access_token as string | undefined;
  const expiresIn = Number(payload.expires_in ?? 0);
  if (!token) {
    throw new HttpError(500, "FatSecret token response missing access_token.");
  }

  fatsecretToken = {
    token,
    expiresAt: now + Math.max(expiresIn - 30, 0),
  };
  return token;
}

async function fatsecretRequest(path: string, params: Record<string, string | number | boolean>) {
  const token = await getFatsecretToken();
  const url = new URL(`https://platform.fatsecret.com/rest${path}`);
  url.search = new URLSearchParams({ format: "json", ...params }).toString();
  const response = await fetch(url.toString(), {
    headers: { authorization: `Bearer ${token}` },
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new HttpError(500, `FatSecret request failed: ${JSON.stringify(payload)}`);
  }
  console.log("fatsecret_response", path, JSON.stringify(payload).slice(0, 2000));
  return payload;
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function parseIntSafe(value?: string | null) {
  if (value === null || value === undefined) return null;
  const parsed = Number.parseInt(value, 10);
  return Number.isNaN(parsed) ? null : parsed;
}

function parseFloatSafe(value?: string | null) {
  if (value === null || value === undefined) return null;
  const parsed = Number.parseFloat(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function heightCm(feet?: string | null, inches?: string | null) {
  const feetValue = parseIntSafe(feet) ?? 0;
  const inchesValue = parseIntSafe(inches) ?? 0;
  if (!feetValue && !inchesValue) return null;
  return Math.round((feetValue * 30.48 + inchesValue * 2.54) * 100) / 100;
}

function weightKg(pounds?: string | null) {
  const poundsValue = parseFloatSafe(pounds);
  if (poundsValue === null) return null;
  return Math.round(poundsValue * 0.45359237 * 100) / 100;
}

function estimateOneRepMax(weight: number, reps: number) {
  if (weight <= 0 || reps <= 0) return 0;
  return Math.round(weight * (1 + reps / 30) * 100) / 100;
}

function normalizeAiMacros(rawOutput: string) {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawOutput);
  } catch {
    return null;
  }
  if (typeof parsed === "object" && parsed && "macros" in parsed) {
    const macros = (parsed as { macros: unknown }).macros;
    if (typeof macros === "object" && macros) {
      parsed = macros;
    }
  }
  if (typeof parsed !== "object" || parsed === null) return null;
  const macros = parsed as Record<string, unknown>;
  const protein = toNumber(macros.protein);
  const carbs = toNumber(macros.carbs);
  const fats = toNumber(macros.fats);
  const calories = toNumber(macros.calories);
  if (!protein || !carbs || !fats || !calories) return null;
  return {
    protein: Math.round(protein),
    carbs: Math.round(carbs),
    fats: Math.round(fats),
    calories: Math.round(calories),
  };
}

function buildMacroPromptInputs(profile: Record<string, unknown>) {
  const preferences = (profile.preferences as Record<string, unknown>) ?? {};
  return {
    age: profile.age,
    gender: preferences.gender,
    height_cm: profile.height_cm,
    weight_kg: profile.weight_kg,
    goal: profile.goal,
    training_days: preferences.training_days,
  };
}

function hasRequiredMacroInputs(inputs: Record<string, unknown>) {
  const required = ["age", "gender", "height_cm", "weight_kg", "goal", "training_days"];
  return required.every((key) => inputs[key] !== null && inputs[key] !== undefined);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);
  let path = url.pathname;
  const prefix = "/functions/v1/api";
  if (path.startsWith(prefix)) {
    path = path.slice(prefix.length) || "/";
  }
  path = normalizePath(path);

  const method = req.method.toUpperCase();
  let segments = path.split("/").filter(Boolean);
  if (segments[0] === "api") {
    segments = segments.slice(1);
  }

  try {
    if (segments[0] === "auth") {
      if (method === "POST" && segments[1] === "register") {
        const payload = await parseJson<{ email: string; password: string; role?: string }>(req);
        const userId = crypto.randomUUID();
        const hashed = await sha256Hex(payload.password);
        const { error } = await supabase.from("users").insert({
          id: userId,
          email: payload.email,
          hashed_password: hashed,
          role: payload.role ?? "user",
        });
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ status: "ok", user_id: userId });
      }

      if (method === "POST" && segments[1] === "login") {
        const payload = await parseJson<{ email: string; password: string }>(req);
        const { data, error } = await supabase
          .from("users")
          .select("id, hashed_password")
          .eq("email", payload.email)
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        if (!data || data.length === 0) throw new HttpError(401, "Invalid credentials");
        const hashed = await sha256Hex(payload.password);
        if (data[0].hashed_password !== hashed) throw new HttpError(401, "Invalid credentials");
        return jsonResponse({ status: "ok", user_id: data[0].id });
      }
    }

    if (segments[0] === "onboarding" && method === "POST") {
      const payload = await parseJson<Record<string, unknown>>(req);
      const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
      let userId = typeof payload.user_id === "string" ? payload.user_id : null;
      if (userId) {
        const { data } = await supabase.from("users").select("id").eq("id", userId).limit(1);
        if (!data || data.length === 0) userId = null;
      }
      if (!userId && email) {
        const { data } = await supabase.from("users").select("id").eq("email", email).limit(1);
        if (data && data.length > 0) userId = data[0].id;
      }
      if (!userId && !email) throw new HttpError(400, "Email is required.");
      if (!userId) {
        const password = typeof payload.password === "string" && payload.password ? payload.password : crypto.randomUUID();
        const hashed = await sha256Hex(password);
        userId = crypto.randomUUID();
        const { error } = await supabase.from("users").insert({
          id: userId,
          email,
          hashed_password: hashed,
          role: "user",
        });
        if (error) throw new HttpError(500, error.message);
      }

      const onboardingData = { ...payload };
      delete onboardingData.user_id;
      delete onboardingData.email;
      delete onboardingData.password;

      const { error: onboardingError } = await supabase.from("onboarding_states").insert({
        user_id: userId,
        step_index: 5,
        data: onboardingData,
        is_complete: true,
      });
      if (onboardingError) throw new HttpError(500, onboardingError.message);

      const profilePayload = {
        user_id: userId,
        full_name: payload.full_name,
        age: parseIntSafe(payload.age as string),
        height_cm: heightCm(payload.height_feet as string, payload.height_inches as string),
        weight_kg: weightKg(payload.weight_lbs as string),
        goal: payload.goal,
        macros: {
          protein: payload.macro_protein,
          carbs: payload.macro_carbs,
          fats: payload.macro_fats,
          calories: payload.macro_calories,
        },
        preferences: {
          training_days: payload.training_days,
          gym_access: payload.gym_access ?? "full_gym",
          equipment: payload.equipment ?? [],
          experience: payload.experience,
          checkin_day: payload.checkin_day,
          gender: payload.gender,
          has_injury: payload.has_injury ?? false,
          injury_notes: payload.injury_notes ?? "",
        },
      };

      const { error: profileError } = await supabase
        .from("profiles")
        .upsert(profilePayload, { onConflict: "user_id" });
      if (profileError) throw new HttpError(500, profileError.message);

      if (payload.wants_to_coach || payload.coach_interest) {
        const interestEnum = payload.wants_to_coach ? "coach" : "hire";
        await supabase.from("coach_interest").insert({ user_id: userId, interest_enum: interestEnum });
      }

      return jsonResponse({ user_id: userId, workout_plan: "" });
    }

    if (segments[0] === "profiles") {
      if (method === "GET" && segments[1]) {
        const { data, error } = await supabase
          .from("profiles")
          .select("*")
          .eq("user_id", segments[1])
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        if (!data || data.length === 0) throw new HttpError(404, "Profile not found");
        return jsonResponse({ profile: data[0] });
      }
      if (method === "PUT" && segments[1]) {
        const payload = await parseJson<Record<string, unknown>>(req);
        const updatePayload = { ...payload, user_id: segments[1] };
        const { data, error } = await supabase
          .from("profiles")
          .upsert(updatePayload, { onConflict: "user_id" })
          .select();
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ profile: data?.[0] ?? updatePayload });
      }
    }

    if (segments[0] === "users") {
      if (method === "GET" && segments[1] === "me") {
        const userId = url.searchParams.get("user_id");
        if (!userId) throw new HttpError(400, "user_id is required");
        const { data, error } = await supabase
          .from("profiles")
          .select("*")
          .eq("user_id", userId)
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        if (!data || data.length === 0) throw new HttpError(404, "Profile not found");
        return jsonResponse({ profile: data[0] });
      }

      if (method === "POST" && segments[1] === "tutorial" && segments[2] === "complete") {
        const payload = await parseJson<{ user_id: string; completed?: boolean }>(req);
        const updatePayload = {
          user_id: payload.user_id,
          tutorial_completed: payload.completed ?? true,
          tutorial_completed_at: payload.completed === false ? null : new Date().toISOString(),
        };
        const { data, error } = await supabase
          .from("profiles")
          .upsert(updatePayload, { onConflict: "user_id" })
          .select();
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ profile: data?.[0] ?? updatePayload });
      }

      if (method === "PUT" && segments[1] === "checkin-day") {
        const payload = await parseJson<{ user_id: string; check_in_day: string }>(req);
        const updatePayload = {
          user_id: payload.user_id,
          check_in_day: payload.check_in_day,
        };
        const { data, error } = await supabase
          .from("profiles")
          .upsert(updatePayload, { onConflict: "user_id" })
          .select();
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ profile: data?.[0] ?? updatePayload });
      }

      if (method === "POST" && segments[1] === "macros" && segments[2] === "generate") {
        const payload = await parseJson<{ user_id: string }>(req);
        const { data: profiles, error } = await supabase
          .from("profiles")
          .select("*")
          .eq("user_id", payload.user_id)
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        if (!profiles || profiles.length === 0) throw new HttpError(404, "Profile not found");
        const profile = profiles[0];
        const inputs = buildMacroPromptInputs(profile);
        if (!hasRequiredMacroInputs(inputs)) throw new HttpError(400, "Profile data incomplete for macro generation");
        const aiOutput = await runPrompt("macro_generation", payload.user_id, inputs);
        const macros = normalizeAiMacros(aiOutput);
        if (!macros) throw new HttpError(502, "AI macro output invalid");
        const updatePayload = {
          user_id: payload.user_id,
          macros,
          updated_at: new Date().toISOString(),
        };
        const { data: updated, error: updateError } = await supabase
          .from("profiles")
          .upsert(updatePayload, { onConflict: "user_id" })
          .select();
        if (updateError) throw new HttpError(500, updateError.message);
        return jsonResponse({ macros: updated?.[0]?.macros ?? macros });
      }
    }

    if (segments[0] === "coach") {
      if (method === "POST" && segments[1] === "profile") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const { data, error } = await supabase
          .from("coach_profiles")
          .upsert(payload, { onConflict: "user_id" })
          .select();
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ profile: data?.[0] ?? payload });
      }

      if (method === "GET" && segments[1] === "profile" && segments[2]) {
        const { data, error } = await supabase
          .from("coach_profiles")
          .select("*")
          .eq("user_id", segments[2])
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        if (!data || data.length === 0) throw new HttpError(404, "Coach profile not found");
        return jsonResponse({ profile: data[0] });
      }

      if (method === "GET" && segments[1] === "discover") {
        const limit = Number(url.searchParams.get("limit") ?? 20);
        const { data, error } = await supabase.from("coach_profiles").select("*").limit(limit);
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ results: data ?? [] });
      }
    }

    if (segments[0] === "payments") {
      if (method === "POST" && segments[1] === "record") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const { data, error } = await supabase.from("payment_records").insert(payload).select();
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ record: data?.[0] ?? payload });
      }

      if (method === "GET" && segments[1] === "user" && segments[2]) {
        const limit = Number(url.searchParams.get("limit") ?? 50);
        const { data, error } = await supabase
          .from("payment_records")
          .select("*")
          .eq("user_id", segments[2])
          .limit(limit);
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ user_id: segments[2], records: data ?? [] });
      }
    }

    if (segments[0] === "exercises") {
      if (method === "POST" && segments.length === 1) {
        const payload = await parseJson<Record<string, unknown>>(req);
        const { data, error } = await supabase.from("exercises").insert(payload).select();
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ exercise: data?.[0] ?? payload });
      }

      if (method === "GET" && segments[1] === "search") {
        const query = url.searchParams.get("query") ?? "";
        const limit = Number(url.searchParams.get("limit") ?? 20);
        const { data, error } = await supabase
          .from("exercises")
          .select("*")
          .ilike("name", `%${query}%`)
          .limit(limit);
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ query, results: data ?? [] });
      }
    }

    if (segments[0] === "workouts") {
      if (method === "POST" && segments[1] === "generate") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const userId = await normalizeUserId(payload.user_id as string | undefined);
        if (userId) {
          const { data } = await supabase.from("users").select("id").eq("id", userId).limit(1);
          if (!data || data.length === 0) {
            await supabase.from("users").insert({
              id: userId,
              email: `user-${userId}@placeholder.local`,
              hashed_password: "placeholder",
              role: "user",
            });
          }
        }
        const promptInput = {
          muscle_groups: payload.muscle_groups,
          workout_type: payload.workout_type,
          equipment: payload.equipment,
          duration_minutes: payload.duration_minutes,
        };
        const result = await runPrompt("workout_generation", userId, promptInput as Record<string, unknown>);
        await supabase.from("workout_templates").insert({
          user_id: userId,
          title: "AI Generated Workout",
          mode: "ai",
          metadata: { raw: result, input: promptInput },
        });
        return jsonResponse({ template: result });
      }

      if (segments[1] === "templates" && method === "POST" && segments.length === 2) {
        const payload = await parseJson<Record<string, unknown>>(req);
        const userId = await normalizeUserId(payload.user_id as string | undefined);
        if (userId) {
          const { data } = await supabase.from("users").select("id").eq("id", userId).limit(1);
          if (!data || data.length === 0) {
            await supabase.from("users").insert({
              id: userId,
              email: `user-${userId}@placeholder.local`,
              hashed_password: "placeholder",
              role: "user",
            });
          }
        }

        const { data: templateRows, error } = await supabase
          .from("workout_templates")
          .insert({
            user_id: userId,
            title: payload.title,
            description: payload.description,
            mode: payload.mode ?? "manual",
          })
          .select();
        if (error) throw new HttpError(500, error.message);
        if (!templateRows || templateRows.length === 0) throw new HttpError(500, "Failed to create template");
        const templateId = templateRows[0].id;

        const exercises = Array.isArray(payload.exercises) ? payload.exercises : [];
        for (let idx = 0; idx < exercises.length; idx += 1) {
          const exercise = exercises[idx] as Record<string, unknown>;
          const { data: existing } = await supabase
            .from("exercises")
            .select("id")
            .eq("name", exercise.name)
            .limit(1);
          let exerciseId = existing?.[0]?.id;
          if (!exerciseId) {
            const { data: created } = await supabase
              .from("exercises")
              .insert({
                name: exercise.name,
                muscle_groups: exercise.muscle_groups ?? [],
                equipment: exercise.equipment ?? [],
              })
              .select();
            if (!created || created.length === 0) throw new HttpError(500, "Failed to create exercise");
            exerciseId = created[0].id;
          }

          await supabase.from("workout_template_exercises").insert({
            template_id: templateId,
            exercise_id: exerciseId,
            position: idx,
            sets: exercise.sets ?? 0,
            reps: exercise.reps ?? 0,
            rest_seconds: exercise.rest_seconds ?? 0,
            notes: exercise.notes,
          });
        }
        return jsonResponse({ template_id: templateId });
      }

      if (segments[1] === "templates" && method === "GET" && segments.length === 2) {
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
        if (!userId) throw new HttpError(400, "user_id is required");
        const { data, error } = await supabase
          .from("workout_templates")
          .select("id,title,description,mode,created_at")
          .eq("user_id", userId)
          .order("created_at", { ascending: false });
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ templates: data ?? [] });
      }

      if (segments[1] === "templates" && segments[2] && method === "GET" && segments.length === 3) {
        const templateId = segments[2];
        const { data: templateRows, error: templateError } = await supabase
          .from("workout_templates")
          .select("id,title,description,mode,created_at")
          .eq("id", templateId)
          .limit(1);
        if (templateError) throw new HttpError(500, templateError.message);
        if (!templateRows || templateRows.length === 0) throw new HttpError(404, "Template not found");
        const template = templateRows[0];

        const { data: templateExercises, error: exerciseError } = await supabase
          .from("workout_template_exercises")
          .select("exercise_id,position,sets,reps,rest_seconds,notes")
          .eq("template_id", templateId)
          .order("position", { ascending: true });
        if (exerciseError) throw new HttpError(500, exerciseError.message);

        const exerciseIds = (templateExercises ?? []).map((row) => row.exercise_id).filter(Boolean);
        let exerciseMap: Record<string, Record<string, unknown>> = {};
        if (exerciseIds.length) {
          const { data: exercises } = await supabase
            .from("exercises")
            .select("id,name,muscle_groups,equipment")
            .in("id", exerciseIds);
          exerciseMap = Object.fromEntries((exercises ?? []).map((row) => [row.id, row]));
        }

        const enriched = (templateExercises ?? []).map((row) => {
          const exercise = exerciseMap[row.exercise_id] ?? {};
          return {
            exercise_id: row.exercise_id,
            name: exercise.name ?? "Unknown",
            muscle_groups: exercise.muscle_groups ?? [],
            equipment: exercise.equipment ?? [],
            sets: row.sets,
            reps: row.reps,
            rest_seconds: row.rest_seconds,
            notes: row.notes,
            position: row.position,
          };
        });

        return jsonResponse({ template, exercises: enriched });
      }

      if (segments[1] === "templates" && segments[2] && method === "PUT" && segments.length === 3) {
        const templateId = segments[2];
        const payload = await parseJson<Record<string, unknown>>(req);
        const { data: updated, error: updateError } = await supabase
          .from("workout_templates")
          .update({
            title: payload.title,
            description: payload.description,
            mode: payload.mode ?? "manual",
          })
          .eq("id", templateId)
          .select();
        if (updateError) throw new HttpError(500, updateError.message);
        if (!updated || updated.length === 0) throw new HttpError(404, "Template not found");

        await supabase.from("workout_template_exercises").delete().eq("template_id", templateId);
        const exercises = Array.isArray(payload.exercises) ? payload.exercises : [];
        for (let idx = 0; idx < exercises.length; idx += 1) {
          const exercise = exercises[idx] as Record<string, unknown>;
          const { data: existing } = await supabase
            .from("exercises")
            .select("id")
            .eq("name", exercise.name)
            .limit(1);
          let exerciseId = existing?.[0]?.id;
          if (!exerciseId) {
            const { data: created } = await supabase
              .from("exercises")
              .insert({
                name: exercise.name,
                muscle_groups: exercise.muscle_groups ?? [],
                equipment: exercise.equipment ?? [],
              })
              .select();
            if (!created || created.length === 0) throw new HttpError(500, "Failed to create exercise");
            exerciseId = created[0].id;
          }
          await supabase.from("workout_template_exercises").insert({
            template_id: templateId,
            exercise_id: exerciseId,
            position: idx,
            sets: exercise.sets ?? 0,
            reps: exercise.reps ?? 0,
            rest_seconds: exercise.rest_seconds ?? 0,
            notes: exercise.notes,
          });
        }
        return jsonResponse({ template_id: templateId });
      }

      if (segments[1] === "templates" && segments[2] && method === "DELETE" && segments.length === 3) {
        const templateId = segments[2];
        const { data: deleted, error } = await supabase
          .from("workout_templates")
          .delete()
          .eq("id", templateId)
          .select();
        if (error) throw new HttpError(500, error.message);
        if (!deleted || deleted.length === 0) throw new HttpError(404, "Template not found");
        return jsonResponse({ template_id: templateId });
      }

      if (segments[1] === "templates" && segments[2] && segments[3] === "duplicate" && method === "POST") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const templateId = segments[2];
        const userId = await normalizeUserId(payload.user_id as string | undefined);
        if (userId) {
          const { data } = await supabase.from("users").select("id").eq("id", userId).limit(1);
          if (!data || data.length === 0) {
            await supabase.from("users").insert({
              id: userId,
              email: `user-${userId}@placeholder.local`,
              hashed_password: "placeholder",
              role: "user",
            });
          }
        }

        const { data: templateRows, error } = await supabase
          .from("workout_templates")
          .select("id,user_id,title,description,mode")
          .eq("id", templateId)
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        if (!templateRows || templateRows.length === 0) throw new HttpError(404, "Template not found");
        const template = templateRows[0];

        const newTitle = payload.title ?? `${template.title} Copy`;
        const newUserId = userId ?? template.user_id;
        const { data: newRows, error: insertError } = await supabase
          .from("workout_templates")
          .insert({
            user_id: newUserId,
            title: newTitle,
            description: template.description,
            mode: template.mode,
          })
          .select();
        if (insertError) throw new HttpError(500, insertError.message);
        if (!newRows || newRows.length === 0) throw new HttpError(500, "Failed to duplicate template");
        const newTemplateId = newRows[0].id;

        const { data: templateExercises } = await supabase
          .from("workout_template_exercises")
          .select("exercise_id,position,sets,reps,rest_seconds,notes")
          .eq("template_id", templateId)
          .order("position", { ascending: true });
        for (const row of templateExercises ?? []) {
          await supabase.from("workout_template_exercises").insert({
            template_id: newTemplateId,
            exercise_id: row.exercise_id,
            position: row.position ?? 0,
            sets: row.sets ?? 0,
            reps: row.reps ?? 0,
            rest_seconds: row.rest_seconds ?? 0,
            notes: row.notes,
          });
        }

        return jsonResponse({ template_id: newTemplateId });
      }

      if (segments[1] === "sessions" && method === "GET" && segments.length === 2) {
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
        if (!userId) throw new HttpError(400, "user_id is required");
        const { data: sessions, error } = await supabase
          .from("workout_sessions")
          .select("id,template_id,status,duration_seconds,created_at")
          .eq("user_id", userId)
          .order("created_at", { ascending: false })
          .limit(20);
        if (error) throw new HttpError(500, error.message);
        const templateIds = (sessions ?? []).map((row) => row.template_id).filter(Boolean);
        let templateTitles: Record<string, string> = {};
        if (templateIds.length) {
          const { data: templates } = await supabase.from("workout_templates").select("id,title").in("id", templateIds);
          templateTitles = Object.fromEntries((templates ?? []).map((row) => [row.id, row.title]));
        }
        const enriched = (sessions ?? []).map((session) => ({
          ...session,
          template_title: templateTitles[session.template_id] ?? null,
        }));
        return jsonResponse({ sessions: enriched });
      }

      if (segments[1] === "sessions" && segments[2] === "start" && method === "POST") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const userId = await normalizeUserId(payload.user_id as string | undefined);
        if (!userId) throw new HttpError(400, "user_id is required");
        const { data: existing } = await supabase.from("users").select("id").eq("id", userId).limit(1);
        if (!existing || existing.length === 0) {
          await supabase.from("users").insert({
            id: userId,
            email: `user-${userId}@placeholder.local`,
            hashed_password: "placeholder",
            role: "user",
          });
        }
        const { data: rows, error } = await supabase
          .from("workout_sessions")
          .insert({
            user_id: userId,
            template_id: payload.template_id ?? null,
            status: payload.status ?? "in_progress",
            started_at: new Date().toISOString(),
          })
          .select();
        if (error) throw new HttpError(500, error.message);
        if (!rows || rows.length === 0) throw new HttpError(500, "Failed to start session");
        return jsonResponse({ session_id: rows[0].id });
      }

      if (segments[1] === "sessions" && segments[3] === "log" && method === "POST") {
        const sessionId = segments[2];
        const payload = await parseJson<Record<string, unknown>>(req);
        const { data: rows, error } = await supabase
          .from("exercise_logs")
          .insert({
            session_id: sessionId,
            exercise_name: payload.exercise_name,
            sets: payload.sets ?? 1,
            reps: payload.reps ?? 0,
            weight: payload.weight ?? 0,
            notes: payload.notes ?? null,
          })
          .select();
        if (error) throw new HttpError(500, error.message);
        if (!rows || rows.length === 0) throw new HttpError(500, "Failed to log exercise");
        return jsonResponse({ log_id: rows[0].id });
      }

      if (segments[1] === "sessions" && segments[3] === "complete" && method === "POST") {
        const sessionId = segments[2];
        const payload = await parseJson<Record<string, unknown>>(req);
        const { data: sessions, error } = await supabase
          .from("workout_sessions")
          .select("id,user_id")
          .eq("id", sessionId)
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        if (!sessions || sessions.length === 0) throw new HttpError(404, "Session not found");
        const session = sessions[0];

        await supabase.from("workout_sessions").update({
          status: payload.status ?? "completed",
          duration_seconds: payload.duration_seconds ?? 0,
          completed_at: new Date().toISOString(),
        }).eq("id", sessionId);

        const { data: logs } = await supabase
          .from("exercise_logs")
          .select("exercise_name,reps,weight")
          .eq("session_id", sessionId);

        const bestByExercise: Record<string, number> = {};
        for (const log of logs ?? []) {
          const reps = Number(log.reps ?? 0);
          const weight = Number(log.weight ?? 0);
          const estimate = estimateOneRepMax(weight, reps);
          if (estimate <= 0) continue;
          const name = log.exercise_name ?? "Unknown";
          bestByExercise[name] = Math.max(bestByExercise[name] ?? 0, estimate);
        }

        const prUpdates: Record<string, unknown>[] = [];
        for (const [exerciseName, value] of Object.entries(bestByExercise)) {
          const { data: existing } = await supabase
            .from("prs")
            .select("id,value")
            .eq("user_id", session.user_id)
            .eq("exercise_name", exerciseName)
            .eq("metric", "estimated_1rm")
            .order("value", { ascending: false })
            .limit(1);
          let previousValue: number | null = null;
          if (existing && existing.length > 0) {
            previousValue = Number(existing[0].value);
            if (value <= previousValue) continue;
          }
          await supabase.from("prs").insert({
            user_id: session.user_id,
            exercise_name: exerciseName,
            metric: "estimated_1rm",
            value,
          });
          prUpdates.push({ exercise_name: exerciseName, value, previous_value: previousValue });
        }

        return jsonResponse({
          session_id: sessionId,
          status: payload.status ?? "completed",
          duration_seconds: payload.duration_seconds ?? 0,
          prs: prUpdates,
        });
      }

      if (segments[1] === "exercises" && segments[2] === "history" && method === "GET") {
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
        const exerciseName = url.searchParams.get("exercise_name") ?? "";
        const limit = Number(url.searchParams.get("limit") ?? 20);
        if (!userId) throw new HttpError(400, "user_id is required");

        const { data: sessions } = await supabase
          .from("workout_sessions")
          .select("id,created_at")
          .eq("user_id", userId);

        if (!sessions || sessions.length === 0) {
          return jsonResponse({
            exercise_name: exerciseName,
            entries: [],
            best_set: null,
            estimated_1rm: 0,
            trend: [],
          });
        }

        const sessionMap: Record<string, string> = {};
        for (const session of sessions) {
          sessionMap[session.id] = session.created_at;
        }
        const sessionIds = Object.keys(sessionMap);

        const { data: logs } = await supabase
          .from("exercise_logs")
          .select("id,session_id,exercise_name,sets,reps,weight,notes,created_at")
          .eq("exercise_name", exerciseName)
          .in("session_id", sessionIds)
          .order("created_at", { ascending: false })
          .limit(limit);

        const entries: Record<string, unknown>[] = [];
        let bestSet: Record<string, unknown> | null = null;
        let bestEstimated = 0;
        const trend: Record<string, unknown>[] = [];

        for (const log of logs ?? []) {
          const reps = Number(log.reps ?? 0);
          const weight = Number(log.weight ?? 0);
          const estimated = estimateOneRepMax(weight, reps);
          const entry = {
            id: log.id,
            date: sessionMap[log.session_id],
            sets: log.sets ?? 0,
            reps,
            weight,
            estimated_1rm: estimated,
          };
          entries.push(entry);
          trend.push({ date: entry.date, estimated_1rm: estimated });
          if (estimated > bestEstimated) {
            bestEstimated = estimated;
            bestSet = { weight, reps, estimated_1rm: estimated };
          }
        }

        return jsonResponse({
          exercise_name: exerciseName,
          entries,
          best_set: bestSet,
          estimated_1rm: bestEstimated,
          trend,
        });
      }
    }

    if (segments[0] === "nutrition") {
      if (method === "GET" && segments[1] === "search") {
        const query = url.searchParams.get("query") ?? "";
        const userId = url.searchParams.get("user_id");
        const { data, error } = await supabase
          .from("food_items")
          .select("*")
          .ilike("name", `%${query}%`)
          .limit(20);
        if (error) throw new HttpError(500, error.message);
        if (userId) {
          await supabase.from("search_history").insert({ user_id: userId, query, source: "search" });
        }
        return jsonResponse({ query, results: data ?? [] });
      }

      if (method === "GET" && segments[1] === "usda" && segments[2] === "search") {
        ensureEnv(usdaApiKey, "USDA_API_KEY");
        const query = url.searchParams.get("query") ?? "";
        const userId = url.searchParams.get("user_id");
        const response = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?${new URLSearchParams({
          api_key: usdaApiKey,
          query,
          pageSize: "20",
        })}`);
        const payload = await response.json();
        const foods = payload.foods ?? [];
        const results: Record<string, unknown>[] = [];
        for (const food of foods) {
          const nutrients = food.foodNutrients ?? [];
          const nutrientValue = (names: string[]) => {
            for (const nutrient of nutrients) {
              const name = (nutrient.nutrientName ?? nutrient.nutrient?.name ?? "").toLowerCase();
              if (names.some((match) => name.includes(match))) {
                const value = nutrient.value ?? nutrient.amount ?? 0;
                return toNumber(value);
              }
            }
            return 0;
          };

          const normalized = {
            source: "usda",
            name: (food.description ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
            serving: food.servingSize && food.servingSizeUnit ? `${food.servingSize} ${food.servingSizeUnit}` : "100 g",
            protein: nutrientValue(["protein"]),
            carbs: nutrientValue(["carbohydrate"]),
            fats: nutrientValue(["total lipid", "fat"]),
            calories: nutrientValue(["energy"]),
            metadata: { fdc_id: String(food.fdcId ?? ""), source: "usda" },
            fdc_id: String(food.fdcId ?? ""),
          };

          try {
            await supabase.from("food_items").insert({
              source: normalized.source,
              name: normalized.name,
              serving: normalized.serving,
              protein: normalized.protein,
              carbs: normalized.carbs,
              fats: normalized.fats,
              calories: normalized.calories,
              metadata: normalized.metadata,
            });
          } catch {
            // ignore duplicates
          }
          results.push(normalized);
        }
        if (userId) {
          await supabase.from("search_history").insert({ user_id: userId, query, source: "usda" });
        }
        return jsonResponse({ query, results });
      }

      if (method === "GET" && segments[1] === "usda" && segments[2] === "food" && segments[3]) {
        ensureEnv(usdaApiKey, "USDA_API_KEY");
        const userId = url.searchParams.get("user_id");
        const response = await fetch(`https://api.nal.usda.gov/fdc/v1/food/${segments[3]}?${new URLSearchParams({ api_key: usdaApiKey })}`);
        const payload = await response.json();
        const nutrients = payload.foodNutrients ?? [];
        const nutrientValue = (names: string[]) => {
          for (const nutrient of nutrients) {
            const name = (nutrient.nutrientName ?? nutrient.nutrient?.name ?? "").toLowerCase();
            if (names.some((match) => name.includes(match))) {
              const value = nutrient.value ?? nutrient.amount ?? 0;
              return toNumber(value);
            }
          }
          return 0;
        };
        const normalized = {
          source: "usda",
          name: (payload.description ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
          serving: payload.servingSize && payload.servingSizeUnit ? `${payload.servingSize} ${payload.servingSizeUnit}` : "100 g",
          protein: nutrientValue(["protein"]),
          carbs: nutrientValue(["carbohydrate"]),
          fats: nutrientValue(["total lipid", "fat"]),
          calories: nutrientValue(["energy"]),
          metadata: { fdc_id: String(payload.fdcId ?? ""), source: "usda" },
          fdc_id: String(payload.fdcId ?? ""),
        };
        try {
          await supabase.from("food_items").insert({
            source: normalized.source,
            name: normalized.name,
            serving: normalized.serving,
            protein: normalized.protein,
            carbs: normalized.carbs,
            fats: normalized.fats,
            calories: normalized.calories,
            metadata: normalized.metadata,
          });
        } catch {
          // ignore duplicates
        }
        if (userId) {
          await supabase.from("search_history").insert({ user_id: userId, query: segments[3], source: "usda" });
        }
        return jsonResponse(normalized);
      }

      if (method === "GET" && segments[1] === "fatsecret" && segments[2] === "search") {
        const query = url.searchParams.get("query") ?? "";
        const userId = url.searchParams.get("user_id");
        const payload = await fatsecretRequest("/foods/search/v3", {
          search_expression: query,
          max_results: 20,
          page_number: 0,
        });
        const foodsPayload = payload.foods_search?.results?.food ?? payload.foods?.food ?? [];
        const list = Array.isArray(foodsPayload) ? foodsPayload : [foodsPayload];
        const results: Record<string, unknown>[] = [];
        for (const food of list) {
          const foodId = String(food.food_id ?? "");
          if (!foodId) continue;
          try {
            const detailPayload = await fatsecretRequest("/food/v5", { food_id: foodId });
            const detail = detailPayload.food ?? {};
            const servings = detail.servings?.serving;
            const serving = Array.isArray(servings) ? servings[0] : servings ?? {};
            const metricAmount = serving.metric_serving_amount;
            const metricUnit = serving.metric_serving_unit;
            const servingText = metricAmount && metricUnit ? `${metricAmount} ${metricUnit}` : serving.serving_description ?? "1 serving";
            results.push({
              id: foodId,
              source: "fatsecret",
              name: (detail.food_name ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
              serving: servingText,
              protein: toNumber(serving.protein),
              carbs: toNumber(serving.carbohydrate),
              fats: toNumber(serving.fat),
              calories: toNumber(serving.calories),
              metadata: { food_id: foodId, brand: detail.brand_name ?? null },
              food_id: foodId,
            });
          } catch {
            results.push({
              id: foodId,
              source: "fatsecret",
              name: (food.food_name ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
              serving: food.food_description ?? "1 serving",
              protein: 0,
              carbs: 0,
              fats: 0,
              calories: 0,
              metadata: { brand: food.brand_name ?? null },
              food_id: foodId,
            });
          }
        }
        if (userId) {
          await supabase.from("search_history").insert({ user_id: userId, query, source: "fatsecret" });
        }
        return jsonResponse({ query, results });
      }

      if (method === "GET" && segments[1] === "fatsecret" && segments[2] === "barcode") {
        const barcode = url.searchParams.get("barcode") ?? "";
        const userId = url.searchParams.get("user_id");
        const payload = await fatsecretRequest("/food/barcode/v3", { barcode });
        const foodId = payload.food_id ?? payload.food?.food_id;
        if (!foodId) throw new HttpError(404, "No food found for barcode.");
        const detailPayload = await fatsecretRequest("/food/v5", { food_id: String(foodId) });
        const detail = detailPayload.food ?? {};
        const servings = detail.servings?.serving;
        const serving = Array.isArray(servings) ? servings[0] : servings ?? {};
        const metricAmount = serving.metric_serving_amount;
        const metricUnit = serving.metric_serving_unit;
        const servingText = metricAmount && metricUnit ? `${metricAmount} ${metricUnit}` : serving.serving_description ?? "1 serving";
        const normalized = {
          id: String(detail.food_id ?? foodId),
          source: "fatsecret",
          name: (detail.food_name ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
          serving: servingText,
          protein: toNumber(serving.protein),
          carbs: toNumber(serving.carbohydrate),
          fats: toNumber(serving.fat),
          calories: toNumber(serving.calories),
          metadata: { food_id: String(detail.food_id ?? foodId), brand: detail.brand_name ?? null },
          food_id: String(detail.food_id ?? foodId),
        };
        if (userId) {
          await supabase.from("search_history").insert({ user_id: userId, query: barcode, source: "fatsecret_barcode" });
        }
        return jsonResponse(normalized);
      }

      if (method === "GET" && segments[1] === "fatsecret" && segments[2] === "food" && segments[3]) {
        const foodId = segments[3];
        const detailPayload = await fatsecretRequest("/food/v5", { food_id: foodId });
        const detail = detailPayload.food ?? {};
        const servings = detail.servings?.serving;
        const serving = Array.isArray(servings) ? servings[0] : servings ?? {};
        const metricAmount = serving.metric_serving_amount;
        const metricUnit = serving.metric_serving_unit;
        const servingText = metricAmount && metricUnit ? `${metricAmount} ${metricUnit}` : serving.serving_description ?? "1 serving";
        const normalized = {
          id: String(detail.food_id ?? foodId),
          source: "fatsecret",
          name: (detail.food_name ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
          serving: servingText,
          protein: toNumber(serving.protein),
          carbs: toNumber(serving.carbohydrate),
          fats: toNumber(serving.fat),
          calories: toNumber(serving.calories),
          metadata: { food_id: String(detail.food_id ?? foodId), brand: detail.brand_name ?? null },
          food_id: String(detail.food_id ?? foodId),
        };
        return jsonResponse(normalized);
      }

      if (method === "POST" && segments[1] === "log") {
        const userId = url.searchParams.get("user_id") ?? "";
        const mealType = url.searchParams.get("meal_type") ?? "";
        const photoUrl = url.searchParams.get("photo_url");
        const logDate = url.searchParams.get("log_date") ?? todayIso();
        if (!userId || !mealType) throw new HttpError(400, "user_id and meal_type are required");
        const aiOutput = await runPrompt("meal_photo_parse", userId, {
          meal_type: mealType,
          photo_url: photoUrl,
        });
        await supabase.from("nutrition_logs").insert({
          user_id: userId,
          date: logDate,
          meal_type: mealType,
          items: [{ raw: aiOutput }],
          totals: { calories: 0, protein: 0, carbs: 0, fats: 0 },
        });
        return jsonResponse({ status: "logged", ai_result: aiOutput });
      }

      if (method === "GET" && segments[1] === "logs") {
        const userId = url.searchParams.get("user_id");
        if (!userId) throw new HttpError(400, "user_id is required");
        const logDate = url.searchParams.get("log_date") ?? todayIso();
        const { data, error } = await supabase
          .from("nutrition_logs")
          .select("*")
          .eq("user_id", userId)
          .eq("date", logDate);
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ date: logDate, logs: data ?? [] });
      }

      if (method === "POST" && segments[1] === "logs" && segments[2] === "manual") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const item = payload.item as Record<string, unknown>;
        const logDate = (payload.log_date as string | undefined) ?? todayIso();
        const totals = {
          calories: item.calories ?? 0,
          protein: item.protein ?? 0,
          carbs: item.carbs ?? 0,
          fats: item.fats ?? 0,
        };
        await supabase.from("nutrition_logs").insert({
          user_id: payload.user_id,
          date: logDate,
          meal_type: payload.meal_type,
          items: [
            {
              name: item.name,
              portion_value: item.portion_value,
              portion_unit: item.portion_unit,
              serving: item.serving ?? null,
              calories: item.calories,
              protein: item.protein,
              carbs: item.carbs,
              fats: item.fats,
            },
          ],
          totals,
        });
        return jsonResponse({ status: "logged", date: logDate });
      }

      if (segments[1] === "favorites") {
        if (method === "POST") {
          const payload = await parseJson<Record<string, unknown>>(req);
          const { data, error } = await supabase.from("nutrition_favorites").insert(payload).select();
          if (error) throw new HttpError(500, error.message);
          return jsonResponse({ status: "saved", favorite: data?.[0] ?? payload });
        }
        if (method === "GET") {
          const userId = url.searchParams.get("user_id");
          const limit = Number(url.searchParams.get("limit") ?? 50);
          if (!userId) throw new HttpError(400, "user_id is required");
          const { data, error } = await supabase
            .from("nutrition_favorites")
            .select("*")
            .eq("user_id", userId)
            .limit(limit);
          if (error) throw new HttpError(500, error.message);
          return jsonResponse({ user_id: userId, favorites: data ?? [] });
        }
      }
    }

    if (segments[0] === "scan" && segments[1] === "meal-photo" && method === "POST") {
      const form = await req.formData();
      const userId = form.get("user_id")?.toString() ?? "";
      const mealType = form.get("meal_type")?.toString() ?? "";
      const photo = form.get("photo");
      if (!userId || !mealType || !(photo instanceof File)) {
        throw new HttpError(400, "Photo, user_id, and meal_type are required.");
      }
      const bytes = new Uint8Array(await photo.arrayBuffer());
      const filename = `${crypto.randomUUID().replace(/-/g, "")}.jpg`;
      const path = `${userId}/${todayIso()}/${filename}`;
      const { error: uploadError } = await supabase.storage
        .from(mealPhotoBucket)
        .upload(path, bytes, { contentType: photo.type || "image/jpeg" });
      if (uploadError) throw new HttpError(500, uploadError.message);
      const { data: publicUrl } = supabase.storage.from(mealPhotoBucket).getPublicUrl(path);
      const aiOutput = await runPrompt("meal_photo_parse", userId, {
        meal_type: mealType,
        photo_url: publicUrl.publicUrl,
      });
      await supabase.from("nutrition_logs").insert({
        user_id: userId,
        date: todayIso(),
        meal_type: mealType,
        items: [{ raw: aiOutput, photo_url: publicUrl.publicUrl }],
        totals: { calories: 0, protein: 0, carbs: 0, fats: 0 },
      });
      return jsonResponse({ status: "logged", ai_result: aiOutput, photo_url: publicUrl.publicUrl });
    }

    if (segments[0] === "progress") {
      if (segments[1] === "photos" && method === "POST") {
        const form = await req.formData();
        const userId = form.get("user_id")?.toString() ?? "";
        const photo = form.get("photo");
        const photoType = form.get("photo_type")?.toString() ?? null;
        const photoCategory = form.get("photo_category")?.toString() ?? null;
        const checkinDate = form.get("checkin_date")?.toString() ?? todayIso();
        if (!userId || !(photo instanceof File)) {
          throw new HttpError(400, "Photo and user_id are required.");
        }
        const bytes = new Uint8Array(await photo.arrayBuffer());
        const filename = `${crypto.randomUUID().replace(/-/g, "")}.jpg`;
        const path = `${userId}/${checkinDate}/${filename}`;
        const { error: uploadError } = await supabase.storage
          .from(progressPhotoBucket)
          .upload(path, bytes, { contentType: photo.type || "image/jpeg" });
        if (uploadError) throw new HttpError(500, uploadError.message);
        const { data: publicUrl } = supabase.storage.from(progressPhotoBucket).getPublicUrl(path);
        await supabase.from("progress_photos").insert({
          user_id: userId,
          date: checkinDate,
          url: publicUrl.publicUrl,
          type: photoType,
          category: photoCategory,
        });
        return jsonResponse({
          status: "uploaded",
          photo_url: publicUrl.publicUrl,
          photo_type: photoType,
          photo_category: photoCategory,
          date: checkinDate,
        });
      }

      if (segments[1] === "photos" && method === "GET") {
        const userId = url.searchParams.get("user_id");
        if (!userId) throw new HttpError(400, "user_id is required");
        const category = url.searchParams.get("category");
        const photoType = url.searchParams.get("photo_type");
        const startDate = url.searchParams.get("start_date");
        const endDate = url.searchParams.get("end_date");
        const limit = Number(url.searchParams.get("limit") ?? 60);

        let query = supabase.from("progress_photos").select("*").eq("user_id", userId);
        if (category) query = query.eq("category", category);
        if (photoType) query = query.eq("type", photoType);
        if (startDate) query = query.gte("date", startDate);
        if (endDate) query = query.lte("date", endDate);
        const { data, error } = await query.order("date", { ascending: false }).limit(limit);
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ photos: data ?? [] });
      }

      if (segments[1] === "macro-adherence" && method === "GET") {
        const userId = url.searchParams.get("user_id");
        const rangeDays = Number(url.searchParams.get("range_days") ?? 30);
        if (!userId) throw new HttpError(400, "user_id is required");
        const endDate = new Date();
        const startDate = new Date(endDate);
        startDate.setDate(endDate.getDate() - Math.max(rangeDays - 1, 0));

        const { data: profile } = await supabase
          .from("profiles")
          .select("macros")
          .eq("user_id", userId)
          .limit(1);
        const rawMacros = profile?.[0]?.macros ?? {};
        const macros = {
          calories: toNumber(rawMacros.calories),
          protein: toNumber(rawMacros.protein),
          carbs: toNumber(rawMacros.carbs),
          fats: toNumber(rawMacros.fats),
        };

        const { data: rows } = await supabase
          .from("nutrition_logs")
          .select("date, totals")
          .eq("user_id", userId)
          .gte("date", startDate.toISOString().slice(0, 10))
          .lte("date", endDate.toISOString().slice(0, 10));

        const totalsByDate: Record<string, { calories: number; protein: number; carbs: number; fats: number }> = {};
        for (const row of rows ?? []) {
          const day = row.date;
          if (!day) continue;
          const totals = row.totals ?? {};
          const existing = totalsByDate[day] ?? { calories: 0, protein: 0, carbs: 0, fats: 0 };
          totalsByDate[day] = {
            calories: existing.calories + toNumber(totals.calories),
            protein: existing.protein + toNumber(totals.protein),
            carbs: existing.carbs + toNumber(totals.carbs),
            fats: existing.fats + toNumber(totals.fats),
          };
        }

        const days = Object.entries(totalsByDate)
          .map(([date, logged]) => ({ date, logged, target: macros }))
          .sort((a, b) => a.date.localeCompare(b.date));

        return jsonResponse({ days });
      }
    }

    if (segments[0] === "checkins") {
      if (method === "GET" && segments.length === 1) {
        const userId = url.searchParams.get("user_id");
        if (!userId) throw new HttpError(400, "user_id is required");
        const limit = Number(url.searchParams.get("limit") ?? 12);
        const startDate = url.searchParams.get("start_date");
        const endDate = url.searchParams.get("end_date");
        let query = supabase.from("weekly_checkins").select("*").eq("user_id", userId);
        if (startDate) query = query.gte("date", startDate);
        if (endDate) query = query.lte("date", endDate);
        const { data, error } = await query.order("date", { ascending: false }).limit(limit);
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ checkins: data ?? [] });
      }

      if (method === "POST" && segments.length === 1) {
        const userId = url.searchParams.get("user_id");
        if (!userId) throw new HttpError(400, "user_id is required");
        const checkinDate = url.searchParams.get("checkin_date") ?? todayIso();
        const payload = await parseJson<Record<string, unknown>>(req);
        const adherence = payload.adherence as Record<string, unknown> | undefined;
        if (!adherence) throw new HttpError(400, "adherence is required");
        const photoUrls = Array.isArray(payload.photo_urls) ? payload.photo_urls : [];
        const promptInput = { adherence, photo_urls: photoUrls };
        const aiOutput = await runPrompt("weekly_checkin_analysis", userId, promptInput);
        await supabase.from("weekly_checkins").insert({
          user_id: userId,
          date: checkinDate,
          weight: adherence.current_weight ?? null,
          adherence,
          photos: photoUrls.map((url) => ({ url })),
          ai_summary: { raw: aiOutput },
          macro_update: { suggested: true },
          cardio_update: { suggested: true },
        });
        return jsonResponse({ status: "complete", ai_result: aiOutput });
      }
    }

    if (segments[0] === "ai" && segments[1] === "prompt" && method === "POST") {
      const name = url.searchParams.get("name") ?? "";
      return jsonResponse({ prompt: name, result: "Pending" });
    }

    return jsonResponse({ detail: "Not Found" }, 404);
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ detail: error.message }, error.status);
    }
    return jsonResponse({ detail: "Internal Server Error" }, 500);
  }
});
