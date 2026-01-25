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

const weeklyCheckinTemplate = `You are a blunt but constructive strength coach. Give the user a straight-take check-in based on the inputs and any progress photos. No fluff, no emojis, no sugar-coating. Be specific and practical.

Return ONLY valid JSON with these keys:
- improvements: array of short strings (3-6 items)
- needs_work: array of short strings (3-6 items)
- photo_notes: array of short strings about visible changes (empty if no photos)
- photo_focus: array of focus areas (3-5 items if photos exist)
- targets: array of actionable next-week focus points (3-6 items)
- summary: a direct trainer-style paragraph, 120-220 words, similar in tone to a coach giving honest feedback
- macro_delta: object { calories, protein, carbs, fats } as integers (use 0s if no change)
- new_macros: object { calories, protein, carbs, fats } or null
- update_macros: boolean
- cardio_recommendation: short string or null
- cardio_plan: array of strings (sessions or plan) or empty array

If the user is already lean with visible abs, acknowledge it. Call out gaps (chest thickness, lat width, rear delts, etc.) when appropriate. Keep the summary in a tough-love coach voice.`;

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

async function resolveUserId(userId?: string | null) {
  const normalized = await normalizeUserId(userId);
  if (!normalized) throw new HttpError(400, "user_id is required");
  return normalized;
}

async function ensureUserExists(userId: string) {
  const { data: existing } = await supabase.from("users").select("id").eq("id", userId).limit(1);
  if (!existing || existing.length === 0) {
    await supabase.from("users").insert({
      id: userId,
      email: `user-${userId}@placeholder.local`,
      hashed_password: "placeholder",
      role: "user",
    });
  }
}

async function sha256Hex(value: string) {
  const data = new TextEncoder().encode(value);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function cleanPhotoUrl(value: unknown) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length ? trimmed : null;
}

function extractPhotoUrls(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const urls: string[] = [];
  for (const item of value) {
    if (typeof item === "string") {
      const cleaned = cleanPhotoUrl(item);
      if (cleaned) urls.push(cleaned);
      continue;
    }
    if (item && typeof item === "object") {
      const cleaned = cleanPhotoUrl((item as Record<string, unknown>).url);
      if (cleaned) urls.push(cleaned);
    }
  }
  return urls;
}

function extractStartingPhotoUrls(value: unknown): string[] {
  if (!value || typeof value !== "object") return [];
  const record = value as Record<string, unknown>;
  const urls: string[] = [];
  for (const key of ["front", "side", "back"]) {
    const entry = record[key];
    if (!entry || typeof entry !== "object") continue;
    const cleaned = cleanPhotoUrl((entry as Record<string, unknown>).url);
    if (cleaned) urls.push(cleaned);
  }
  return urls;
}

function dedupeUrls(urls: string[]) {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const url of urls) {
    if (seen.has(url)) continue;
    seen.add(url);
    result.push(url);
  }
  return result;
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
  const systemTemplate = name === "weekly_checkin_analysis" ? weeklyCheckinTemplate : prompt.template;
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
  const photoUrls = extractPhotoUrls(inputs.photo_urls);
  const comparisonPhotoUrls = extractPhotoUrls(inputs.comparison_photo_urls);
  const allPhotoUrls = dedupeUrls([...photoUrls, ...comparisonPhotoUrls]);

  const userContent = allPhotoUrls.length
    ? [
        { type: "text", text: JSON.stringify(inputs) },
        ...allPhotoUrls.map((url) => ({ type: "image_url", image_url: { url } })),
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
        { role: "system", content: systemTemplate },
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

async function getPreviousCheckinPhotoUrls(userId: string, checkinDate: string) {
  if (!checkinDate) return [];
  const { data } = await supabase
    .from("weekly_checkins")
    .select("photos,date")
    .eq("user_id", userId)
    .lt("date", checkinDate)
    .order("date", { ascending: false })
    .limit(1);
  const photos = data && data[0] ? data[0].photos : [];
  return extractPhotoUrls(photos);
}

async function getStartingPhotoUrls(userId: string) {
  const { data: profiles } = await supabase
    .from("profiles")
    .select("preferences")
    .eq("user_id", userId)
    .limit(1);
  const preferences = profiles && profiles[0] ? profiles[0].preferences : null;
  const startingFromPreferences = extractStartingPhotoUrls(
    preferences && typeof preferences === "object"
      ? (preferences as Record<string, unknown>).starting_photos
      : null,
  );
  if (startingFromPreferences.length) return startingFromPreferences;

  const { data: photos } = await supabase
    .from("progress_photos")
    .select("url")
    .eq("user_id", userId)
    .eq("category", "starting")
    .limit(3);
  return extractPhotoUrls(photos);
}

async function getComparisonPhotoData(
  userId: string,
  checkinDate: string,
  currentPhotoUrls: string[],
) {
  const previous = await getPreviousCheckinPhotoUrls(userId, checkinDate);
  if (previous.length) {
    return {
      urls: previous.filter((url) => !currentPhotoUrls.includes(url)),
      source: "previous_checkin",
    };
  }
  const starting = await getStartingPhotoUrls(userId);
  if (starting.length) {
    return {
      urls: starting.filter((url) => !currentPhotoUrls.includes(url)),
      source: "starting_photos",
    };
  }
  return { urls: [], source: null };
}

async function getChatProfile(userId: string) {
  const { data } = await supabase
    .from("profiles")
    .select("age,goal,macros,preferences,height_cm,weight_kg,units,full_name")
    .eq("user_id", userId)
    .limit(1);
  return data && data[0] ? data[0] : null;
}

async function getChatLatestCheckin(userId: string) {
  const { data } = await supabase
    .from("weekly_checkins")
    .select("date,weight,adherence,ai_summary,macro_update,cardio_update,notes")
    .eq("user_id", userId)
    .order("date", { ascending: false })
    .limit(1);
  return data && data[0] ? data[0] : null;
}

async function getChatRecentWorkouts(userId: string) {
  const { data: sessions } = await supabase
    .from("workout_sessions")
    .select("id,template_id,status,duration_seconds,created_at,completed_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(5);
  const sessionIds = (sessions ?? []).map((session) => session.id).filter(Boolean);
  let logs: Record<string, unknown>[] = [];
  if (sessionIds.length) {
    const { data } = await supabase
      .from("exercise_logs")
      .select("session_id,exercise_name,sets,reps,weight,duration_minutes,notes,created_at")
      .in("session_id", sessionIds)
      .order("created_at", { ascending: false })
      .limit(30);
    logs = data ?? [];
  }
  return { sessions: sessions ?? [], logs };
}

async function getChatRecentMessages(threadId: string, limit = 12) {
  const { data } = await supabase
    .from("chat_messages")
    .select("role,content")
    .eq("thread_id", threadId)
    .order("created_at", { ascending: false })
    .limit(limit);
  return (data ?? []).reverse();
}

async function touchChatThread(threadId: string) {
  const now = new Date().toISOString();
  await supabase
    .from("chat_threads")
    .update({ updated_at: now, last_message_at: now })
    .eq("id", threadId);
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
  return payload;
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function cleanFoodQuery(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return "";
  const cleaned = trimmed
    .replace(/[\r\n]/g, " ")
    .replace(/[^\w\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!cleaned) return "";
  const words = cleaned.split(" ").filter(Boolean);
  if (words.length > 6) {
    return words.slice(0, 6).join(" ");
  }
  return cleaned;
}

async function detectFoodQueryFromPhoto(photoUrl: string) {
  const key = ensureEnv(openaiApiKey, "OPENAI_API_KEY");
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content:
            "You label food photos for nutrition search. Return a short food name (2-6 words). No punctuation, no extra text.",
        },
        {
          role: "user",
          content: [{ type: "image_url", image_url: { url: photoUrl } }],
        },
      ],
    }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new HttpError(500, `OpenAI request failed: ${JSON.stringify(payload)}`);
  }
  const content = payload.choices?.[0]?.message?.content ?? "";
  return cleanFoodQuery(content);
}

function normalizeFatsecretFood(detail: Record<string, unknown>, fallbackId?: string) {
  const servings = (detail as Record<string, unknown>).servings;
  const servingEntry = (servings as Record<string, unknown> | undefined)?.serving;
  const serving = Array.isArray(servingEntry) ? servingEntry[0] : servingEntry ?? {};
  const metricAmount = (serving as Record<string, unknown>).metric_serving_amount;
  const metricUnit = (serving as Record<string, unknown>).metric_serving_unit;
  const servingText =
    metricAmount && metricUnit
      ? `${metricAmount} ${metricUnit}`
      : ((serving as Record<string, unknown>).serving_description as string | undefined) ?? "1 serving";
  const foodId = String((detail as Record<string, unknown>).food_id ?? fallbackId ?? "");
  return {
    id: foodId,
    source: "fatsecret",
    name: ((detail as Record<string, unknown>).food_name ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
    serving: servingText,
    protein: toNumber((serving as Record<string, unknown>).protein),
    carbs: toNumber((serving as Record<string, unknown>).carbohydrate),
    fats: toNumber((serving as Record<string, unknown>).fat),
    calories: toNumber((serving as Record<string, unknown>).calories),
    metadata: { food_id: foodId, brand: (detail as Record<string, unknown>).brand_name ?? null },
    food_id: foodId,
  };
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

type MacroValues = {
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
};

function toOptionalNumber(value: unknown) {
  if (value === null || value === undefined) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseBoolean(value: unknown) {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["true", "yes", "1"].includes(normalized)) return true;
    if (["false", "no", "0"].includes(normalized)) return false;
  }
  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function normalizeMacroValues(raw: unknown): MacroValues | null {
  if (!isRecord(raw)) return null;
  const calories = toOptionalNumber(raw.calories);
  const protein = toOptionalNumber(raw.protein);
  const carbs = toOptionalNumber(raw.carbs);
  const fats = toOptionalNumber(raw.fats);
  if (calories === null || protein === null || carbs === null || fats === null) {
    return null;
  }
  return {
    calories: Math.round(calories),
    protein: Math.round(protein),
    carbs: Math.round(carbs),
    fats: Math.round(fats),
  };
}

function normalizeMacroDelta(raw: unknown): MacroValues {
  if (!isRecord(raw)) {
    return { calories: 0, protein: 0, carbs: 0, fats: 0 };
  }
  return {
    calories: Math.round(toOptionalNumber(raw.calories) ?? 0),
    protein: Math.round(toOptionalNumber(raw.protein) ?? 0),
    carbs: Math.round(toOptionalNumber(raw.carbs) ?? 0),
    fats: Math.round(toOptionalNumber(raw.fats) ?? 0),
  };
}

function hasNonZeroDelta(delta: MacroValues) {
  return Object.values(delta).some((value) => value !== 0);
}

function applyMacroDelta(current: MacroValues, delta: MacroValues): MacroValues {
  const updated = {
    calories: Math.max(0, current.calories + delta.calories),
    protein: Math.max(0, current.protein + delta.protein),
    carbs: Math.max(0, current.carbs + delta.carbs),
    fats: Math.max(0, current.fats + delta.fats),
  };
  if (updated.calories < 1200) {
    updated.calories = 1200;
  }
  return updated;
}

function stripJsonFence(text: string) {
  if (!text.startsWith("```")) return text;
  return text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

function parseAiJsonOutput(rawOutput: string) {
  if (!rawOutput) return null;
  let text = rawOutput.trim();
  if (!text) return null;
  text = stripJsonFence(text);
  try {
    const parsed = JSON.parse(text);
    if (isRecord(parsed)) return parsed;
  } catch {
    // fall through to best-effort parse
  }
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start !== -1 && end > start) {
    try {
      const parsed = JSON.parse(text.slice(start, end + 1));
      if (isRecord(parsed)) return parsed;
    } catch {
      return null;
    }
  }
  return null;
}

function pickMacroCandidate(parsed: Record<string, unknown> | null, keys: string[]) {
  if (!parsed) return null;
  for (const key of keys) {
    const value = parsed[key];
    if (isRecord(value)) return value;
  }
  return null;
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

function parseMealPlanOutput(raw: string, macroTargets: Record<string, unknown> | null) {
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    if (parsed && typeof parsed === "object") {
      return parsed;
    }
  } catch {
    // ignore parse errors
  }
  return {
    meals: [],
    totals: macroTargets ?? {},
    notes: raw,
  };
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
        if (error) {
          const message = error.message.toLowerCase();
          if (message.includes("users_email_key") || message.includes("duplicate key")) {
            const { data } = await supabase.from("users").select("id").eq("email", email).limit(1);
            if (data && data.length > 0) {
              userId = data[0].id;
            } else {
              throw new HttpError(500, error.message);
            }
          } else {
            throw new HttpError(500, error.message);
          }
        }
      }

      const onboardingData = { ...payload };
      delete onboardingData.user_id;
      delete onboardingData.email;
      delete onboardingData.password;

      const { data: existingOnboarding, error: onboardingLookupError } = await supabase
        .from("onboarding_states")
        .select("id")
        .eq("user_id", userId)
        .limit(1);
      if (onboardingLookupError) throw new HttpError(500, onboardingLookupError.message);

      if (existingOnboarding && existingOnboarding.length > 0) {
        const { error: onboardingUpdateError } = await supabase
          .from("onboarding_states")
          .update({
            step_index: 5,
            data: onboardingData,
            is_complete: true,
          })
          .eq("user_id", userId);
        if (onboardingUpdateError) throw new HttpError(500, onboardingUpdateError.message);
      } else {
        const { error: onboardingInsertError } = await supabase.from("onboarding_states").insert({
          user_id: userId,
          step_index: 5,
          data: onboardingData,
          is_complete: true,
        });
        if (onboardingInsertError) throw new HttpError(500, onboardingInsertError.message);
      }

      const profilePayload = {
        user_id: userId,
        full_name: payload.full_name,
        age: parseIntSafe(payload.age as string),
        height_cm: heightCm(payload.height_feet as string, payload.height_inches as string),
        weight_kg: weightKg(payload.weight_lbs as string),
        goal: payload.goal,
        macros: {},
        preferences: {
          training_level: payload.training_level,
          workout_days_per_week: payload.workout_days_per_week ?? 0,
          workout_duration_minutes: payload.workout_duration_minutes ?? 0,
          equipment: payload.equipment ?? "gym",
          food_allergies: payload.food_allergies ?? "",
          food_dislikes: payload.food_dislikes ?? "",
          diet_style: payload.diet_style ?? "",
          checkin_day: payload.checkin_day,
          sex: payload.sex,
        },
      };

      const { error: profileError } = await supabase
        .from("profiles")
        .upsert(profilePayload, { onConflict: "user_id" });
      if (profileError) throw new HttpError(500, profileError.message);

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

    if (segments[0] === "chat") {
      if (method === "POST" && segments[1] === "thread") {
        const payload = await parseJson<{ user_id?: string; title?: string }>(req);
        if (!payload.user_id) throw new HttpError(400, "user_id is required");
        const { data, error } = await supabase
          .from("chat_threads")
          .insert({ user_id: payload.user_id, title: payload.title ?? null })
          .select()
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ thread: data?.[0] });
      }

      if (method === "GET" && segments[1] === "threads") {
        const userId = url.searchParams.get("user_id");
        if (!userId) throw new HttpError(400, "user_id is required");
        const { data, error } = await supabase
          .from("chat_threads")
          .select("*")
          .eq("user_id", userId)
          .order("last_message_at", { ascending: false, nullsFirst: false });
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ threads: data ?? [] });
      }

      if (method === "GET" && segments[1] === "thread" && segments[2]) {
        const userId = url.searchParams.get("user_id");
        if (!userId) throw new HttpError(400, "user_id is required");
        const threadId = segments[2];
        const { data: threads, error: threadError } = await supabase
          .from("chat_threads")
          .select("*")
          .eq("id", threadId)
          .eq("user_id", userId)
          .limit(1);
        if (threadError) throw new HttpError(500, threadError.message);
        if (!threads || threads.length === 0) throw new HttpError(404, "Thread not found");
        const { data: messages, error: messageError } = await supabase
          .from("chat_messages")
          .select("id,role,content,created_at")
          .eq("thread_id", threadId)
          .order("created_at", { ascending: true });
        if (messageError) throw new HttpError(500, messageError.message);
        return jsonResponse({ thread: threads[0], messages: messages ?? [], summary: null });
      }

      if (method === "POST" && segments[1] === "message") {
        const payload = await parseJson<{ user_id?: string; thread_id?: string; content?: string; stream?: boolean }>(req);
        const userId = payload.user_id ?? "";
        const threadId = payload.thread_id ?? "";
        const content = payload.content?.trim() ?? "";
        const stream = payload.stream ?? true;
        if (!userId || !threadId || !content) throw new HttpError(400, "user_id, thread_id, and content are required");

        const { data: threadRows, error: threadError } = await supabase
          .from("chat_threads")
          .select("id")
          .eq("id", threadId)
          .eq("user_id", userId)
          .limit(1);
        if (threadError) throw new HttpError(500, threadError.message);
        if (!threadRows || threadRows.length === 0) throw new HttpError(404, "Thread not found");

        const { error: insertUserError } = await supabase.from("chat_messages").insert({
          thread_id: threadId,
          user_id: userId,
          role: "user",
          content,
        });
        if (insertUserError) throw new HttpError(500, insertUserError.message);
        await touchChatThread(threadId);

        const profile = await getChatProfile(userId);
        if (!profile) throw new HttpError(404, "Profile not found");
        const latestCheckin = await getChatLatestCheckin(userId);
        const recentWorkouts = await getChatRecentWorkouts(userId);
        const history = await getChatRecentMessages(threadId, 12);
        const promptInputs = {
          message: content,
          history,
          profile,
          macros: profile.macros ?? null,
          latest_checkin: latestCheckin,
          recent_workouts: recentWorkouts,
        };

        const assistantText = await runPrompt("coach_chat", userId, promptInputs);

        const { error: insertAssistantError } = await supabase.from("chat_messages").insert({
          thread_id: threadId,
          user_id: userId,
          role: "assistant",
          content: assistantText,
          model: "gpt-4o-mini",
        });
        if (insertAssistantError) throw new HttpError(500, insertAssistantError.message);
        await touchChatThread(threadId);

        if (stream) {
          const encoder = new TextEncoder();
          const streamBody = new ReadableStream({
            start(controller) {
              controller.enqueue(encoder.encode(`data: ${assistantText}\n\n`));
              controller.enqueue(encoder.encode("data: [DONE]\n\n"));
              controller.close();
            },
          });
          return new Response(streamBody, {
            status: 200,
            headers: { "content-type": "text/event-stream", ...corsHeaders },
          });
        }

        return jsonResponse({ reply: assistantText });
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
        const durationMinutes = toNumber(payload.duration_minutes);
        const hasDuration = durationMinutes > 0;
        const sets = hasDuration ? 0 : toNumber(payload.sets ?? 1);
        const reps = hasDuration ? 0 : toNumber(payload.reps ?? 0);
        const weight = hasDuration ? 0 : toNumber(payload.weight ?? 0);
        const { data: rows, error } = await supabase
          .from("exercise_logs")
          .insert({
            session_id: sessionId,
            exercise_name: payload.exercise_name,
            sets,
            reps,
            weight,
            duration_minutes: hasDuration ? durationMinutes : 0,
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
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
        const { data, error } = await supabase
          .from("food_items")
          .select("*")
          .ilike("name", `%${query}%`)
          .limit(20);
        if (error) throw new HttpError(500, error.message);
        if (userId) {
          await ensureUserExists(userId);
          await supabase.from("search_history").insert({ user_id: userId, query, source: "search" });
        }
        return jsonResponse({ query, results: data ?? [] });
      }

      if (method === "GET" && segments[1] === "usda" && segments[2] === "search") {
        ensureEnv(usdaApiKey, "USDA_API_KEY");
        const query = url.searchParams.get("query") ?? "";
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
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
          await ensureUserExists(userId);
          await supabase.from("search_history").insert({ user_id: userId, query, source: "usda" });
        }
        return jsonResponse({ query, results });
      }

      if (method === "GET" && segments[1] === "usda" && segments[2] === "food" && segments[3]) {
        ensureEnv(usdaApiKey, "USDA_API_KEY");
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
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
          await ensureUserExists(userId);
          await supabase.from("search_history").insert({ user_id: userId, query: segments[3], source: "usda" });
        }
        return jsonResponse(normalized);
      }

      if (method === "GET" && segments[1] === "fatsecret" && segments[2] === "search") {
        const query = url.searchParams.get("query") ?? "";
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
        let payload: Record<string, unknown> = {};
        try {
          payload = await fatsecretRequest("/foods/search/v3", {
            search_expression: query,
            max_results: 20,
            page_number: 0,
          });
        } catch (error) {
          if (usdaApiKey) {
            const response = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?${new URLSearchParams({
              api_key: usdaApiKey,
              query,
              pageSize: "20",
            })}`);
            const usdaPayload = await response.json();
            const foods = usdaPayload.foods ?? [];
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
              results.push({
                id: String(food.fdcId ?? ""),
                source: "usda",
                name: (food.description ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
                serving: food.servingSize && food.servingSizeUnit ? `${food.servingSize} ${food.servingSizeUnit}` : "100 g",
                protein: nutrientValue(["protein"]),
                carbs: nutrientValue(["carbohydrate"]),
                fats: nutrientValue(["total lipid", "fat"]),
                calories: nutrientValue(["energy"]),
                metadata: { fdc_id: String(food.fdcId ?? ""), source: "usda" },
                fdc_id: String(food.fdcId ?? ""),
              });
            }
            if (userId) {
              await ensureUserExists(userId);
              await supabase.from("search_history").insert({ user_id: userId, query, source: "usda" });
            }
            return jsonResponse({ query, results });
          }
          throw error;
        }
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
          await ensureUserExists(userId);
          await supabase.from("search_history").insert({ user_id: userId, query, source: "fatsecret" });
        }
        return jsonResponse({ query, results });
      }

      if (method === "GET" && segments[1] === "fatsecret" && segments[2] === "barcode") {
        const barcode = url.searchParams.get("barcode") ?? "";
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
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
          await ensureUserExists(userId);
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
        const userId = await resolveUserId(url.searchParams.get("user_id"));
        const mealType = url.searchParams.get("meal_type") ?? "";
        const photoUrl = url.searchParams.get("photo_url");
        const logDate = url.searchParams.get("log_date") ?? todayIso();
        if (!userId || !mealType) throw new HttpError(400, "user_id and meal_type are required");
        await ensureUserExists(userId);
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
        const userId = await resolveUserId(url.searchParams.get("user_id"));
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
        const userId = await resolveUserId(payload.user_id as string | undefined);
        await ensureUserExists(userId);
        const item = payload.item as Record<string, unknown>;
        const logDate = (payload.log_date as string | undefined) ?? todayIso();
        const totals = {
          calories: item.calories ?? 0,
          protein: item.protein ?? 0,
          carbs: item.carbs ?? 0,
          fats: item.fats ?? 0,
        };
        await supabase.from("nutrition_logs").insert({
          user_id: userId,
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
          const userId = await resolveUserId(payload.user_id as string | undefined);
          await ensureUserExists(userId);

          let foodItemId = payload.food_item_id as string | undefined;
          const food = (payload.food as Record<string, unknown> | undefined) ?? payload;

          const source = (food.source as string | undefined) ?? "manual";
          const name = (food.name as string | undefined) ?? "Saved Food";
          const serving = (food.serving as string | undefined) ?? null;
          const protein = toNumber(food.protein);
          const carbs = toNumber(food.carbs);
          const fats = toNumber(food.fats);
          const calories = toNumber(food.calories);

          const rawMetadata = (food.metadata as Record<string, unknown> | undefined) ?? {};
          const externalId = (food.id as string | undefined) ?? (rawMetadata.external_id as string | undefined);
          const fdcId = (food.fdc_id as string | undefined) ?? (food.fdcId as string | undefined) ?? (rawMetadata.fdc_id as string | undefined);
          const foodId = (food.food_id as string | undefined) ?? (rawMetadata.food_id as string | undefined) ?? (source === "fatsecret" ? externalId : undefined);

          const metadata: Record<string, unknown> = { ...rawMetadata, source };
          if (foodId) metadata.food_id = String(foodId);
          if (fdcId) metadata.fdc_id = String(fdcId);
          if (externalId) metadata.external_id = String(externalId);

          if (!foodItemId) {
            const lookupColumn = foodId ? "metadata->>food_id" : fdcId ? "metadata->>fdc_id" : null;
            const lookupValue = foodId ?? fdcId ?? null;
            if (lookupColumn && lookupValue) {
              const { data: existingFood } = await supabase
                .from("food_items")
                .select("id")
                .eq(lookupColumn, String(lookupValue))
                .limit(1);
              foodItemId = existingFood?.[0]?.id as string | undefined;
            }
          }

          if (!foodItemId) {
            const { data: insertedFood, error: insertError } = await supabase
              .from("food_items")
              .insert({
                source,
                name,
                serving,
                protein,
                carbs,
                fats,
                calories,
                metadata,
              })
              .select("id")
              .limit(1);
            if (insertError) throw new HttpError(500, insertError.message);
            foodItemId = insertedFood?.[0]?.id as string | undefined;
          }

          if (!foodItemId) throw new HttpError(500, "Unable to resolve food item.");

          const { data: existingFavorite } = await supabase
            .from("nutrition_favorites")
            .select("*")
            .eq("user_id", userId)
            .eq("food_item_id", foodItemId)
            .limit(1);
          if (existingFavorite && existingFavorite.length > 0) {
            return jsonResponse({ status: "saved", favorite: existingFavorite[0] });
          }

          const { data, error } = await supabase
            .from("nutrition_favorites")
            .insert({ user_id: userId, food_item_id: foodItemId })
            .select();
          if (error) throw new HttpError(500, error.message);
          return jsonResponse({ status: "saved", favorite: data?.[0] ?? { user_id: userId, food_item_id: foodItemId } });
        }
        if (method === "GET") {
          const userId = await resolveUserId(url.searchParams.get("user_id"));
          const limit = Number(url.searchParams.get("limit") ?? 50);
          const { data, error } = await supabase
            .from("nutrition_favorites")
            .select("id, created_at, food_item:food_items(*)")
            .eq("user_id", userId)
            .order("created_at", { ascending: false })
            .limit(limit);
          if (error) throw new HttpError(500, error.message);
          const favorites = (data ?? [])
            .map((entry) => (entry as Record<string, unknown>).food_item)
            .filter((item) => item);
          return jsonResponse({ user_id: userId, favorites });
        }
      }
    }

    if (segments[0] === "mealplan") {
      if (method === "GET" && segments[1] === "active") {
        const userId = await resolveUserId(url.searchParams.get("user_id"));
        const { data, error } = await supabase
          .from("meal_plans")
          .select("*")
          .eq("user_id", userId)
          .order("created_at", { ascending: false })
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        const plan = data?.[0]?.meal_map ?? null;
        const summary = plan && typeof plan === "object" ? (plan as Record<string, unknown>).notes ?? null : null;
        return jsonResponse({ meal_plan: plan, summary });
      }

      if (method === "POST" && segments[1] === "generate") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const userId = await resolveUserId(payload.user_id as string | undefined);
        const macroTargets = payload.macro_targets as Record<string, unknown> | undefined;
        if (!macroTargets) throw new HttpError(400, "user_id and macro_targets are required");
        await ensureUserExists(userId);
        const profile = (
          await supabase
            .from("profiles")
            .select("preferences,goal,full_name")
            .eq("user_id", userId)
            .limit(1)
        ).data?.[0] ?? null;

        const aiOutput = await runPrompt("meal_plan_generation", userId, {
          macro_targets: macroTargets,
          preferences: profile?.preferences ?? {},
          goal: profile?.goal ?? null,
          name: profile?.full_name ?? null,
        });

        const plan = parseMealPlanOutput(aiOutput, macroTargets);
        await supabase.from("meal_plans").insert({
          user_id: userId,
          range_start: todayIso(),
          range_end: todayIso(),
          meal_map: plan,
        });

        const summary = (plan as Record<string, unknown>).notes ?? null;
        return jsonResponse({ meal_plan: plan, summary });
      }
    }

    if (segments[0] === "scan" && segments[1] === "meal-photo" && method === "POST") {
      const form = await req.formData();
      const userId = await resolveUserId(form.get("user_id")?.toString() ?? "");
      const mealType = form.get("meal_type")?.toString() ?? "";
      const photo = form.get("photo");
      if (!mealType || !(photo instanceof File)) {
        throw new HttpError(400, "Photo, user_id, and meal_type are required.");
      }
      await ensureUserExists(userId);
      const bytes = new Uint8Array(await photo.arrayBuffer());
      const filename = `${crypto.randomUUID().replace(/-/g, "")}.jpg`;
      const path = `${userId}/${todayIso()}/${filename}`;
      const { error: uploadError } = await supabase.storage
        .from(mealPhotoBucket)
        .upload(path, bytes, { contentType: photo.type || "image/jpeg" });
      if (uploadError) throw new HttpError(500, uploadError.message);
      const { data: publicUrl } = supabase.storage.from(mealPhotoBucket).getPublicUrl(path);
      let query = "";
      try {
        query = await detectFoodQueryFromPhoto(publicUrl.publicUrl);
      } catch {
        query = "";
      }
      if (!query) {
        query = "meal";
      }

      let match: Record<string, unknown> | null = null;
      try {
        const payload = await fatsecretRequest("/foods/search/v3", {
          search_expression: query,
          max_results: 5,
          page_number: 0,
        });
        const foodsPayload = payload.foods_search?.results?.food ?? payload.foods?.food ?? [];
        const list = Array.isArray(foodsPayload) ? foodsPayload : [foodsPayload];
        const best = list[0] ?? null;
        if (best) {
          const foodId = String(best.food_id ?? "");
          const detailPayload = await fatsecretRequest("/food/v5", { food_id: foodId });
          match = normalizeFatsecretFood(detailPayload.food ?? {}, foodId);
        }
        await supabase.from("search_history").insert({ user_id: userId, query, source: "photo_scan" });
      } catch (error) {
        if (usdaApiKey) {
          const response = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?${new URLSearchParams({
            api_key: usdaApiKey,
            query,
            pageSize: "1",
          })}`);
          const payload = await response.json();
          const food = payload.foods?.[0];
          if (food) {
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
            match = {
              id: String(food.fdcId ?? ""),
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
          }
          await supabase.from("search_history").insert({ user_id: userId, query, source: "photo_scan_usda" });
        } else {
          throw error;
        }
      }

      if (!match) {
        return jsonResponse({
          status: "scanned",
          photo_url: publicUrl.publicUrl,
          query,
          message: "No match found. Try another photo.",
        });
      }
      return jsonResponse({ status: "scanned", photo_url: publicUrl.publicUrl, query, match });
    }

    if (segments[0] === "progress") {
      if (segments[1] === "photos" && method === "POST") {
        const form = await req.formData();
        const userId = await resolveUserId(form.get("user_id")?.toString() ?? "");
        const photo = form.get("photo");
        const photoType = form.get("photo_type")?.toString() ?? null;
        const photoCategory = form.get("photo_category")?.toString() ?? null;
        const checkinDate = form.get("checkin_date")?.toString() ?? todayIso();
        if (!(photo instanceof File)) {
          throw new HttpError(400, "Photo and user_id are required.");
        }
        await ensureUserExists(userId);
        const bytes = new Uint8Array(await photo.arrayBuffer());
        const filename = `${crypto.randomUUID().replace(/-/g, "")}.jpg`;
        const path = `${userId}/${checkinDate}/${filename}`;
        const { error: uploadError } = await supabase.storage
          .from(progressPhotoBucket)
          .upload(path, bytes, { contentType: photo.type || "image/jpeg" });
        if (uploadError) throw new HttpError(500, uploadError.message);
        const { data: publicUrl } = supabase.storage.from(progressPhotoBucket).getPublicUrl(path);
        const tags = [photoCategory ? `category:${photoCategory}` : null, checkinDate ? `date:${checkinDate}` : null]
          .filter(Boolean) as string[];
        const { error: insertError } = await supabase.from("progress_photos").insert({
          user_id: userId,
          url: publicUrl.publicUrl,
          photo_type: photoType ?? "checkin",
          tags: tags.length ? tags : null,
        });
        if (insertError) throw new HttpError(500, insertError.message);
        return jsonResponse({
          status: "uploaded",
          photo_url: publicUrl.publicUrl,
          photo_type: photoType,
          photo_category: photoCategory,
          date: checkinDate,
        });
      }

      if (segments[1] === "photos" && method === "GET") {
        const userId = await resolveUserId(url.searchParams.get("user_id"));
        const category = url.searchParams.get("category");
        const photoType = url.searchParams.get("photo_type");
        const startDate = url.searchParams.get("start_date");
        const endDate = url.searchParams.get("end_date");
        const limit = Number(url.searchParams.get("limit") ?? 60);

        let query = supabase.from("progress_photos").select("*").eq("user_id", userId);
        if (category) query = query.contains("tags", [`category:${category}`]);
        if (photoType) query = query.eq("photo_type", photoType);
        if (startDate) query = query.gte("created_at", startDate);
        if (endDate) query = query.lte("created_at", endDate);
        const { data, error } = await query.order("created_at", { ascending: false }).limit(limit);
        if (error) throw new HttpError(500, error.message);
        const photos = (data ?? []).map((row) => {
          const tags = Array.isArray(row.tags) ? row.tags : [];
          const categoryTag = tags.find((tag) => typeof tag === "string" && tag.startsWith("category:"));
          return {
            ...row,
            category: categoryTag ? categoryTag.replace("category:", "") : null,
            type: row.photo_type ?? null,
          };
        });
        return jsonResponse({ photos });
      }

      if (segments[1] === "macro-adherence" && method === "GET") {
        const userId = await resolveUserId(url.searchParams.get("user_id"));
        const rangeDays = Number(url.searchParams.get("range_days") ?? 30);
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
        const userId = await resolveUserId(url.searchParams.get("user_id"));
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
        const userId = await resolveUserId(url.searchParams.get("user_id"));
        const checkinDate = url.searchParams.get("checkin_date") ?? todayIso();
        const payload = await parseJson<Record<string, unknown>>(req);
        const adherence = payload.adherence as Record<string, unknown> | undefined;
        if (!adherence) throw new HttpError(400, "adherence is required");
        await ensureUserExists(userId);
        let currentPhotoUrls = dedupeUrls(extractPhotoUrls(payload.photo_urls));
        if (currentPhotoUrls.length === 0) {
          const { data: photos } = await supabase
            .from("progress_photos")
            .select("url,tags,created_at")
            .eq("user_id", userId)
            .contains("tags", [`date:${checkinDate}`])
            .order("created_at", { ascending: false });
          currentPhotoUrls = (photos ?? [])
            .map((row) => row.url)
            .filter((urlValue) => typeof urlValue === "string") as string[];
        }
        const comparison = await getComparisonPhotoData(userId, checkinDate, currentPhotoUrls);
        const profile = await getChatProfile(userId);
        const currentMacros = normalizeMacroValues(profile?.macros);
        const promptInput: Record<string, unknown> = {
          adherence,
          photo_urls: currentPhotoUrls,
        };
        if (comparison.urls.length) {
          promptInput.comparison_photo_urls = comparison.urls;
          if (comparison.source) {
            promptInput.comparison_source = comparison.source;
          }
        } else {
          promptInput.comparison_source = "none";
        }
        if (profile?.goal) {
          promptInput.goal = profile.goal;
        }
        if (currentMacros) {
          promptInput.current_macros = currentMacros;
          promptInput.macro_targets = currentMacros;
        }
        const aiOutput = await runPrompt("weekly_checkin_analysis", userId, promptInput);
        const parsedOutput = parseAiJsonOutput(aiOutput);
        const macroUpdatePayload = isRecord(parsedOutput?.macro_update) ? parsedOutput?.macro_update : null;
        const macroDelta = normalizeMacroDelta(
          macroUpdatePayload?.delta ?? parsedOutput?.macro_delta ?? parsedOutput?.macroDelta,
        );
        const hasDelta = hasNonZeroDelta(macroDelta);
        const newMacroCandidate = pickMacroCandidate(parsedOutput, [
          "new_macros",
          "next_week_macros",
          "macro_targets",
          "macros",
        ]);
        const macroUpdateCandidate =
          pickMacroCandidate(macroUpdatePayload, ["new_macros", "macros"]) ?? newMacroCandidate;
        const updateMacrosFlag =
          parseBoolean(
            parsedOutput?.update_macros ??
              parsedOutput?.updateMacros ??
              macroUpdatePayload?.suggested ??
              macroUpdatePayload?.update,
          ) ?? false;
        const updatedMacros =
          normalizeMacroValues(macroUpdateCandidate) ??
          (hasDelta && currentMacros ? applyMacroDelta(currentMacros, macroDelta) : null);
        const macroSuggested = updateMacrosFlag || hasDelta || Boolean(updatedMacros);

        const cardioUpdateSource =
          parsedOutput?.cardio_update ??
          parsedOutput?.cardioUpdate ??
          parsedOutput?.cardio_recommendation ??
          parsedOutput?.cardioRecommendation ??
          parsedOutput?.cardio;
        let cardioSuggested = false;
        let cardioRecommendation: string | null = null;
        let cardioPlan: string[] | null = null;
        if (typeof cardioUpdateSource === "string") {
          const trimmed = cardioUpdateSource.trim();
          if (trimmed) {
            cardioRecommendation = trimmed;
            cardioSuggested = true;
          }
        } else if (Array.isArray(cardioUpdateSource)) {
          cardioPlan = cardioUpdateSource.filter((item) => typeof item === "string") as string[];
          if (cardioPlan.length) {
            cardioSuggested = true;
          }
        } else if (isRecord(cardioUpdateSource)) {
          const recommendation =
            cardioUpdateSource.recommendation ??
            cardioUpdateSource.summary ??
            cardioUpdateSource.change ??
            cardioUpdateSource.notes;
          if (typeof recommendation === "string" && recommendation.trim()) {
            cardioRecommendation = recommendation.trim();
          }
          const plan = cardioUpdateSource.plan ?? cardioUpdateSource.weekly_plan ?? cardioUpdateSource.sessions;
          if (Array.isArray(plan)) {
            const cleaned = plan.filter((item) => typeof item === "string") as string[];
            if (cleaned.length) {
              cardioPlan = cleaned;
            }
          }
          const suggestedFlag = parseBoolean(
            cardioUpdateSource.suggested ?? cardioUpdateSource.recommended ?? cardioUpdateSource.update,
          );
          if (suggestedFlag !== null) {
            cardioSuggested = suggestedFlag;
          }
        }
        if (cardioRecommendation || (cardioPlan && cardioPlan.length)) {
          cardioSuggested = true;
        }
        const summaryMeta = {
          comparison_source: comparison.source ?? "none",
          photo_count: currentPhotoUrls.length,
        };
        const { data: inserted, error: insertError } = await supabase.from("weekly_checkins").insert({
          user_id: userId,
          date: checkinDate,
          weight: adherence.current_weight ?? null,
          adherence,
          photos: currentPhotoUrls.map((url) => ({ url })),
          ai_summary: { raw: aiOutput, parsed: parsedOutput ?? null, meta: summaryMeta },
          macro_update: {
            suggested: macroSuggested,
            delta: macroDelta,
            applied: false,
            new_macros: updatedMacros,
          },
          cardio_update: {
            suggested: cardioSuggested,
            recommendation: cardioRecommendation,
            plan: cardioPlan,
          },
        }).select().single();
        if (insertError) throw new HttpError(500, insertError.message);
        return jsonResponse({ status: "complete", ai_result: aiOutput, checkin: inserted });
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
