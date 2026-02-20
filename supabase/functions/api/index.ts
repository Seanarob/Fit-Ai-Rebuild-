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

// Coach chat should feel like iMessage texting: natural, short, and unformatted.
const MAX_COACH_WORDS = 120;
const MAX_COACH_SENTENCES = 5;
const workoutKeywords = ["workout", "routine", "session"];
const workoutActions = ["build", "create", "make", "generate", "design", "plan"];
const muscleKeywords: Record<string, string> = {
  glute: "glutes",
  glutes: "glutes",
  booty: "glutes",
  hamstring: "hamstrings",
  hamstrings: "hamstrings",
  quad: "quads",
  quads: "quads",
  leg: "legs",
  legs: "legs",
  calf: "calves",
  calves: "calves",
  chest: "chest",
  pec: "chest",
  pecs: "chest",
  back: "back",
  lat: "back",
  lats: "back",
  shoulder: "shoulders",
  shoulders: "shoulders",
  delt: "shoulders",
  delts: "shoulders",
  biceps: "biceps",
  triceps: "triceps",
  arms: "arms",
  core: "core",
  abs: "core",
  upper: "upper body",
  lower: "lower body",
  push: "push",
  pull: "pull",
  "full body": "full body",
  hiit: "hiit",
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

If input includes physique_priority and optional secondary_priority or secondary_goals, anchor the recap on those areas first.
- improvements and needs_work should mention those priorities when possible
- photo_notes and photo_focus should evaluate those areas
- targets should prioritize extra training volume for those areas

If input includes physique_goal_description (user's custom goal in their own words):
- Reference their specific goal throughout the feedback
- Use their language and acknowledge their exact targets
- Make feedback feel deeply personalized to what they wrote
- Quote or paraphrase their goal when giving recommendations

If the user is already lean with visible abs, acknowledge it. Call out gaps (chest thickness, lat width, rear delts, etc.) when appropriate. Keep the summary in a tough-love coach voice.`;

const coachChatStyleAppendix = `You are replying inside a 1:1 text thread like a real coach.

VOICE:
- Casual, direct, supportive.
- Sound human, not like a report.

FORMAT:
- Plain text only.
- No markdown, no asterisks, no bullets, no numbered lists, no section labels.
- Do not write label-style lines such as "Nutrition:" or "Consistency:".

LENGTH:
- Default to 2-5 short sentences in one message.
- Keep it concise unless the user asks for more detail.

COACHING STYLE:
- Use contractions and natural wording.
- Give practical advice the user can apply today.
- Ask at most one short follow-up question if needed.
`;

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders },
  });
}

function isMissingColumnError(error: unknown, columnName: string) {
  const message =
    typeof (error as { message?: unknown })?.message === "string" ? (error as { message: string }).message : "";
  const details =
    typeof (error as { details?: unknown })?.details === "string" ? (error as { details: string }).details : "";
  const hint = typeof (error as { hint?: unknown })?.hint === "string" ? (error as { hint: string }).hint : "";
  const code = typeof (error as { code?: unknown })?.code === "string" ? (error as { code: string }).code : "";
  const combined = `${message} ${details} ${hint}`.toLowerCase();
  const col = columnName.toLowerCase();
  if (!combined.includes(col) || !combined.includes("column")) return false;

  // Postgres-style missing column errors.
  if (combined.includes("does not exist")) return true;

  // PostgREST schema cache errors (common on Supabase when migrations are pending).
  if (combined.includes("could not find") && combined.includes("schema cache")) return true;

  // PostgREST error code for missing column (best-effort; depends on client version).
  if (code.toLowerCase() === "pgrst204") return true;

  // Postgres undefined_column.
  if (code === "42703") return true;

  return false;
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

function sanitizeCoachText(value: string) {
  let text = (value ?? "").replace(/\r\n/g, "\n");

  // Remove common markdown formatting that can look "robotic" in a chat bubble.
  // Keep the text content, drop the formatting characters.
  text = text.replace(/```[\s\S]*?```/g, (block) => block.replace(/```/g, ""));
  text = text.replace(/\*\*([^*]+)\*\*/g, "$1");
  text = text.replace(/__([^_]+)__/g, "$1");
  text = text.replace(/`([^`]+)`/g, "$1");
  // Catch any unmatched formatting tokens.
  text = text.replace(/\*\*/g, "");
  text = text.replace(/__/g, "");
  text = text.replace(/`/g, "");
  text = text.replace(/^\s{0,3}#{1,6}\s+/gm, "");

  // Remove list markers (bullets / numbering) so it reads like a text, not a document.
  text = text.replace(/^\s*[-*•]\s+/gm, "");
  text = text.replace(/^\s*\d+\s*[.)]\s+/gm, "");

  // Trim whitespace per line and collapse excessive blank lines.
  text = text
    .split("\n")
    .map((line) => line.replace(/\s+/g, " ").trim())
    .join("\n");
  text = text.replace(/\n{3,}/g, "\n\n").trim();

  // Prefer a single flowing message bubble.
  return text.replace(/\s+/g, " ").trim();
}

function trimCoachReply(value: string, maxWords = MAX_COACH_WORDS) {
  const cleaned = sanitizeCoachText(value);
  if (!cleaned) return cleaned;

  const sentences = cleaned.split(/(?<=[.!?])\s+/);
  let trimmed = sentences.slice(0, MAX_COACH_SENTENCES).join(" ").trim();

  const words = trimmed.split(" ").filter(Boolean);
  if (words.length > maxWords) {
    trimmed = words.slice(0, maxWords).join(" ").replace(/[.,!?]+$/, "");
  }
  return trimmed;
}

function isWorkoutRequest(text: string) {
  const lowered = text.toLowerCase();
  const hasWorkout = workoutKeywords.some((keyword) => lowered.includes(keyword));
  const hasAction = workoutActions.some((action) => lowered.includes(action));
  const hasMuscle = Object.keys(muscleKeywords).some((keyword) => lowered.includes(keyword));
  if ((hasWorkout && hasAction) || (hasWorkout && hasMuscle) || (hasAction && hasMuscle)) {
    return true;
  }
  return false;
}

function parseWorkoutRequest(text: string) {
  const lowered = text.toLowerCase();
  let durationMinutes = 45;
  const durationMatch = lowered.match(/(\d{2,3})\s*(min|mins|minute|minutes)/);
  if (durationMatch) {
    const parsed = Number(durationMatch[1]);
    if (!Number.isNaN(parsed)) {
      durationMinutes = Math.min(120, Math.max(10, parsed));
    }
  }

  const muscleGroups: string[] = [];
  Object.entries(muscleKeywords).forEach(([keyword, group]) => {
    if (lowered.includes(keyword) && !muscleGroups.includes(group)) {
      muscleGroups.push(group);
    }
  });

  if (muscleGroups.length === 0) {
    muscleGroups.push("full body");
  }

  const focus = text.trim() || "custom workout";
  return { focus, muscleGroups, durationMinutes };
}

function parseJsonOutput(rawOutput: string) {
  let text = (rawOutput ?? "").trim();
  if (!text) throw new HttpError(500, "AI output empty");

  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  }

  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // continue to substring parsing
  }

  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) {
    try {
      const parsed = JSON.parse(text.slice(start, end + 1));
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // fall through
    }
  }

  throw new HttpError(500, "AI output did not contain valid JSON.");
}

function normalizeReps(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string") {
    const cleaned = value.split("-")[0]?.trim();
    const parsed = Number.parseInt(cleaned ?? "", 10);
    if (!Number.isNaN(parsed)) return parsed;
  }
  return 10;
}

function normalizePositiveInt(value: unknown, fallback: number) {
  if (typeof value === "number" && Number.isFinite(value)) return Math.max(1, Math.round(value));
  if (typeof value === "string") {
    const parsed = Number.parseInt(value.trim(), 10);
    if (!Number.isNaN(parsed)) return Math.max(1, parsed);
  }
  return fallback;
}

function normalizeStringArray(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter((item) => item.length > 0);
}

type NormalizedCoachExercise = {
  name: string;
  sets: number;
  reps: number;
  restSeconds: number;
  notes: string | null;
  muscleGroups: string[];
  equipment: string[];
};

async function createCoachWorkout(
  userId: string,
  focus: string,
  muscleGroups: string[],
  durationMinutes: number,
) {
  const promptInput = {
    muscle_groups: muscleGroups,
    workout_type: focus,
    duration_minutes: durationMinutes,
  };

  const result = await runPrompt("workout_generation", userId, promptInput);
  const workoutData = parseJsonOutput(result);

  const generatedTitleRaw = typeof workoutData.title === "string" ? workoutData.title.trim() : "";
  const generatedTitle = generatedTitleRaw || focus;
  const title = `Coaches Pick: ${generatedTitle}`;

  const rawExercises = Array.isArray(workoutData.exercises) ? workoutData.exercises : [];
  const normalizedExercises: NormalizedCoachExercise[] = rawExercises
    .filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object")
    .map((exercise, index) => {
      const rawName = typeof exercise.name === "string" ? exercise.name.trim() : "";
      const name = rawName || `Exercise ${index + 1}`;
      const sets = normalizePositiveInt(exercise.sets, 3);
      const reps = normalizeReps(exercise.reps);
      const restSeconds = normalizePositiveInt(exercise.rest_seconds, 60);
      const notesRaw = typeof exercise.notes === "string" ? exercise.notes.trim() : "";
      const exerciseMuscleGroups = normalizeStringArray(exercise.muscle_groups);
      const equipment = normalizeStringArray(exercise.equipment);
      return {
        name,
        sets,
        reps,
        restSeconds,
        notes: notesRaw || null,
        muscleGroups: exerciseMuscleGroups.length ? exerciseMuscleGroups : muscleGroups,
        equipment,
      };
    });

  if (normalizedExercises.length === 0) {
    throw new HttpError(500, "Workout generation returned no exercises.");
  }

  let templateId: string | null = null;
  try {
    const { data: templateRows, error: templateError } = await supabase
      .from("workout_templates")
      .insert({
        user_id: userId,
        title,
        description: `AI-generated ${focus}`,
        mode: "coach",
      })
      .select()
      .limit(1);
    if (templateError) throw new HttpError(500, templateError.message);
    if (!templateRows || templateRows.length === 0) throw new HttpError(500, "Failed to create template");
    templateId = String(templateRows[0].id);
    if (!templateId) throw new HttpError(500, "Failed to create template");
    const createdTemplateId = templateId;

    const uniqueExerciseNames = Array.from(new Set(normalizedExercises.map((exercise) => exercise.name)));
    const { data: existingExercises, error: existingExercisesError } = await supabase
      .from("exercises")
      .select("id,name")
      .in("name", uniqueExerciseNames);
    if (existingExercisesError) throw new HttpError(500, existingExercisesError.message);

    const exerciseIdByName = new Map<string, string>();
    for (const row of existingExercises ?? []) {
      const record = row as Record<string, unknown>;
      const id = String(record.id ?? "");
      const name = String(record.name ?? "");
      if (id && name && !exerciseIdByName.has(name)) {
        exerciseIdByName.set(name, id);
      }
    }

    const missingNames = uniqueExerciseNames.filter((name) => !exerciseIdByName.has(name));
    if (missingNames.length > 0) {
      const missingPayload = missingNames.map((name) => {
        const source = normalizedExercises.find((exercise) => exercise.name === name);
        return {
          name,
          muscle_groups: source?.muscleGroups ?? muscleGroups,
          equipment: source?.equipment ?? [],
        };
      });
      const { data: createdExercises, error: createExerciseError } = await supabase
        .from("exercises")
        .insert(missingPayload)
        .select("id,name");
      if (createExerciseError) throw new HttpError(500, createExerciseError.message);

      for (const row of createdExercises ?? []) {
        const record = row as Record<string, unknown>;
        const id = String(record.id ?? "");
        const name = String(record.name ?? "");
        if (id && name && !exerciseIdByName.has(name)) {
          exerciseIdByName.set(name, id);
        }
      }
    }

    const templateExercisePayload = normalizedExercises.map((exercise, index) => {
      const exerciseId = exerciseIdByName.get(exercise.name);
      if (!exerciseId) {
        throw new HttpError(500, `Failed to resolve exercise "${exercise.name}".`);
      }
      return {
        template_id: createdTemplateId,
        exercise_id: exerciseId,
        position: index,
        sets: exercise.sets,
        reps: exercise.reps,
        rest_seconds: exercise.restSeconds,
        notes: exercise.notes,
      };
    });

    const { error: templateExerciseError } = await supabase
      .from("workout_template_exercises")
      .insert(templateExercisePayload);
    if (templateExerciseError) throw new HttpError(500, templateExerciseError.message);

    return {
      success: true,
      template_id: createdTemplateId,
      title,
      exercise_count: normalizedExercises.length,
    };
  } catch (error) {
    if (templateId) {
      await supabase.from("workout_templates").delete().eq("id", templateId);
    }
    throw error;
  }
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

function extractTagValue(tags: unknown, prefix: string): string | null {
  if (!Array.isArray(tags)) return null;
  for (const tag of tags) {
    if (typeof tag !== "string" || !tag.startsWith(prefix)) continue;
    const value = tag.slice(prefix.length).trim();
    if (value.length) return value;
  }
  return null;
}

function pickPreferenceString(
  preferences: Record<string, unknown> | null | undefined,
  keys: string[],
): string | null {
  if (!preferences) return null;
  for (const key of keys) {
    const value = preferences[key];
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed) return trimmed;
    }
  }
  return null;
}

function pickPreferenceStringArray(
  preferences: Record<string, unknown> | null | undefined,
  keys: string[],
): string[] {
  if (!preferences) return [];
  for (const key of keys) {
    const value = preferences[key];
    if (!Array.isArray(value)) continue;
    const cleaned = value
      .map((item) => (typeof item === "string" ? item.trim() : ""))
      .filter((item) => item.length > 0);
    if (cleaned.length > 0) {
      return cleaned;
    }
  }
  return [];
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

function resolveSystemTemplate(name: string, baseTemplate: string) {
  if (name === "weekly_checkin_analysis") {
    return weeklyCheckinTemplate;
  }
  if (name === "coach_chat") {
    return `${baseTemplate}\n\n${coachChatStyleAppendix}`;
  }
  return baseTemplate;
}

function resolveModelForPrompt(name: string) {
  if (name === "meal_photo_parse") {
    return "gpt-4.1-mini";
  }
  return "gpt-4o-mini";
}

function promptRequiresJsonObject(name: string) {
  return name === "workout_generation";
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
  const systemTemplate = resolveSystemTemplate(name, prompt.template);
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

  const requestBody: Record<string, unknown> = {
    model: resolveModelForPrompt(name),
    messages: [
      { role: "system", content: systemTemplate },
      { role: "user", content: userContent },
    ],
  };
  if (promptRequiresJsonObject(name)) {
    requestBody.response_format = { type: "json_object" };
  }

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${key}`,
    },
    body: JSON.stringify(requestBody),
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

async function runPromptStream(
  name: string,
  userId: string | null,
  inputs: Record<string, unknown>,
  options: {
    signal?: AbortSignal;
    onDelta?: (delta: string) => void;
  } = {},
) {
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
  const systemTemplate = resolveSystemTemplate(name, prompt.template);
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
      stream: true,
      messages: [
        { role: "system", content: systemTemplate },
        { role: "user", content: userContent },
      ],
    }),
    signal: options.signal,
  });

  if (!response.ok) {
    let payload: unknown = null;
    try {
      payload = await response.json();
    } catch {
      payload = await response.text().catch(() => null);
    }
    if (jobId) {
      await supabase.from("ai_jobs").update({ status: "failed", metadata: { error: payload } }).eq("id", jobId);
    }
    throw new HttpError(502, "AI request failed");
  }

  if (!response.body) {
    if (jobId) {
      await supabase.from("ai_jobs").update({ status: "failed", metadata: { error: "Empty stream body" } }).eq(
        "id",
        jobId,
      );
    }
    throw new HttpError(502, "AI stream unavailable");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let output = "";
  let sawDone = false;

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      while (true) {
        const newlineIndex = buffer.indexOf("\n");
        if (newlineIndex < 0) break;
        const rawLine = buffer.slice(0, newlineIndex);
        buffer = buffer.slice(newlineIndex + 1);

        const line = rawLine.trimEnd().replace(/\r$/, "");
        if (!line.startsWith("data:")) continue;
        const data = line.slice(5).trimStart();
        if (!data) continue;
        if (data === "[DONE]") {
          sawDone = true;
          break;
        }
        let payload: any = null;
        try {
          payload = JSON.parse(data);
        } catch {
          continue;
        }
        const delta = payload?.choices?.[0]?.delta?.content;
        if (typeof delta === "string" && delta.length) {
          output += delta;
          options.onDelta?.(delta);
        }
      }

      if (sawDone) break;
    }
  } catch (error) {
    if (jobId) {
      await supabase.from("ai_jobs").update({ status: "failed", metadata: { error: String(error) } }).eq("id", jobId);
    }
    throw error;
  } finally {
    try {
      await reader.cancel();
    } catch {
      // ignore
    }
  }

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
    let data: Record<string, unknown>[] | null = null;
    let error: unknown = null;
    ({ data, error } = await supabase
      .from("exercise_logs")
      .select("session_id,exercise_name,sets,reps,weight,duration_minutes,notes,created_at")
      .in("session_id", sessionIds)
      .order("created_at", { ascending: false })
      .limit(30));
    if (error && isMissingColumnError(error, "duration_minutes")) {
      ({ data, error } = await supabase
        .from("exercise_logs")
        .select("session_id,exercise_name,sets,reps,weight,notes,created_at")
        .in("session_id", sessionIds)
        .order("created_at", { ascending: false })
        .limit(30));
    }
    if (error) throw new HttpError(500, (error as { message?: string })?.message ?? "Failed to load workout logs");
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
  let { error } = await supabase
    .from("chat_threads")
    .update({ updated_at: now, last_message_at: now })
    .eq("id", threadId);
  if (error && isMissingColumnError(error, "last_message_at")) {
    ({ error } = await supabase.from("chat_threads").update({ updated_at: now }).eq("id", threadId));
  }
  if (error) {
    const message = (error as { message?: string })?.message ?? "Failed to update chat thread";
    throw new HttpError(500, message);
  }
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
      model: "gpt-4.1-mini",
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

async function detectMealItemsFromPhoto(photoUrl: string) {
  const key = ensureEnv(openaiApiKey, "OPENAI_API_KEY");
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model: "gpt-4.1-mini",
      messages: [
        {
          role: "system",
          content:
            'You extract foods and estimated portions from meal photos. Return JSON only: {"items":[{"name":"...", "portion_grams":123}]}. portion_grams must be a number (grams) and should be your best estimate. No extra keys.',
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
  const parsed = parseAiJsonOutput(content);
  if (!parsed) return [];
  const itemsRaw = parsed.items;
  const itemsList = Array.isArray(itemsRaw) ? itemsRaw : [];
  const result: string[] = [];
  for (const entry of itemsList) {
    if (!isRecord(entry)) continue;
    const name = typeof entry.name === "string" ? entry.name.trim() : "";
    if (!name) continue;
    const grams = toOptionalNumber(entry.portion_grams);
    if (grams !== null && grams > 0) {
      result.push(`${name} (${Math.round(grams)} g)`);
    } else {
      result.push(name);
    }
  }
  return result;
}

type FatsecretServingOption = {
  id: string | null;
  description: string;
  metric_grams: number | null;
  number_of_units: number;
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
};

const fatsecretItemServingKeywords = [
  "item",
  "each",
  "sandwich",
  "burger",
  "wrap",
  "burrito",
  "taco",
  "piece",
  "bar",
  "packet",
  "pack",
  "package",
  "container",
  "bottle",
  "can",
  "cookie",
  "muffin",
  "slice",
  "serving",
];

const fatsecretIngredientServingKeywords = [
  "egg",
  "tbsp",
  "tablespoon",
  "tsp",
  "teaspoon",
  "cup",
  "scoop",
  "leaf",
  "clove",
];

const foodSearchStopwords = new Set([
  "a",
  "an",
  "and",
  "the",
  "with",
  "of",
  "for",
  "to",
  "in",
  "on",
  "at",
  "by",
  "from",
  "style",
]);

const brandAliasTable: Record<string, string[]> = {
  "chick fil a": ["chick fil a", "chickfila", "chick-fil-a", "chick fil-a"],
  "mcdonalds": ["mcdonalds", "mc donalds", "mcdonald's", "mc d"],
  "burger king": ["burger king", "burgerking", "bk"],
  "taco bell": ["taco bell", "tacobell"],
  "wendys": ["wendys", "wendy's"],
  "kfc": ["kfc", "kentucky fried chicken"],
  "subway": ["subway"],
  "chipotle": ["chipotle", "chipotle mexican grill"],
  "starbucks": ["starbucks", "star bucks"],
};

function normalizeFoodSearchText(text: string) {
  return text
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function normalizeFoodSearchKey(text: string) {
  return normalizeFoodSearchText(text).replace(/\s+/g, "");
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const brandAliasIndex = (() => {
  const index = new Map<string, string>();
  for (const [canonical, aliases] of Object.entries(brandAliasTable)) {
    const canonicalNormalized = normalizeFoodSearchText(canonical);
    index.set(canonicalNormalized, canonicalNormalized);
    for (const alias of aliases) {
      const normalized = normalizeFoodSearchText(alias);
      if (normalized) {
        index.set(normalized, canonicalNormalized);
      }
    }
  }
  return index;
})();

type BrandMatch = {
  canonical: string;
  matchedAlias: string;
};

function detectBrandMatch(normalizedQuery: string): BrandMatch | null {
  if (!normalizedQuery) return null;
  const normalizedKey = normalizeFoodSearchKey(normalizedQuery);
  const candidates = Array.from(brandAliasIndex.entries())
    .sort((a, b) => b[0].length - a[0].length);
  for (const [alias, canonical] of candidates) {
    const pattern = new RegExp(`\\b${escapeRegExp(alias)}\\b`, "i");
    if (pattern.test(normalizedQuery)) {
      return {
        canonical,
        matchedAlias: alias,
      };
    }
  }
  for (const [alias, canonical] of candidates) {
    const aliasKey = alias.replace(/\s+/g, "");
    if (aliasKey && normalizedKey.includes(aliasKey)) {
      return {
        canonical,
        matchedAlias: alias,
      };
    }
  }
  return null;
}

function analyzeFoodSearchQuery(rawQuery: string) {
  const normalized = normalizeFoodSearchText(rawQuery);
  const brandMatch = detectBrandMatch(normalized);
  const tokens = normalized
    .split(" ")
    .map((token) => token.trim())
    .filter((token) => token.length > 0 && !foodSearchStopwords.has(token));
  const brandTokens = brandMatch ? brandMatch.matchedAlias.split(" ").filter(Boolean) : [];
  const tokensWithoutBrand = tokens.filter((token) => !brandTokens.includes(token));
  const searchExpression = brandMatch
    ? normalized.replace(brandMatch.matchedAlias, brandMatch.canonical)
    : normalized;
  return {
    normalized,
    searchExpression,
    tokens,
    tokensWithoutBrand: tokensWithoutBrand.length > 0 ? tokensWithoutBrand : tokens,
    brandMatch,
  };
}

function resolveFoodBrand(item: Record<string, unknown>) {
  const directBrand = typeof item.brand === "string" ? item.brand : null;
  if (directBrand && directBrand.trim()) return directBrand.trim();
  const metadata = (item.metadata as Record<string, unknown> | undefined) ?? {};
  const metadataBrand = typeof metadata.brand === "string" ? metadata.brand : null;
  if (metadataBrand && metadataBrand.trim()) return metadataBrand.trim();
  return null;
}

function resolveFoodType(item: Record<string, unknown>) {
  const directType = typeof item.food_type === "string" ? item.food_type : null;
  if (directType && directType.trim()) return directType.trim();
  const metadata = (item.metadata as Record<string, unknown> | undefined) ?? {};
  const metadataType = typeof metadata.food_type === "string" ? metadata.food_type : null;
  if (metadataType && metadataType.trim()) return metadataType.trim();
  return null;
}

function scoreFoodSearchResult(item: Record<string, unknown>, queryInfo: ReturnType<typeof analyzeFoodSearchQuery>) {
  const name = typeof item.name === "string" ? item.name : "";
  const brand = resolveFoodBrand(item) ?? "";
  const foodType = resolveFoodType(item)?.toLowerCase() ?? "";
  const normalizedName = normalizeFoodSearchText(name);
  const normalizedBrand = normalizeFoodSearchText(brand);
  const normalizedBrandKey = normalizeFoodSearchKey(brand);

  let score = 0;
  if (queryInfo.brandMatch) {
    const canonical = queryInfo.brandMatch.canonical;
    const canonicalKey = canonical.replace(/\s+/g, "");
    const brandMatches = normalizedBrand && (normalizedBrand.includes(canonical) ||
      (normalizedBrandKey && normalizedBrandKey.includes(canonicalKey)));
    score += brandMatches ? 1000 : -200;
  }

  let matchCount = 0;
  for (const token of queryInfo.tokensWithoutBrand) {
    if (normalizedName.includes(token) || normalizedBrand.includes(token)) {
      matchCount += 1;
    }
  }
  score += matchCount * 40;

  if (normalizedBrand) score += 15;
  if (foodType.includes("restaurant")) score += 8;
  if (foodType.includes("brand")) score += 6;
  if (toNumber(item.calories) > 0) score += 2;

  return score;
}

function isWeightBasedServingDescription(text: string) {
  return /\b(?:g|gram|grams|oz|ounce|ounces|ml|milliliter|milliliters|lb|pound|pounds|kg)\b/i.test(text);
}

function scoreFatsecretServingDescription(description: string, isBranded: boolean) {
  const lowered = description.toLowerCase();
  let score = 0;

  if (isWeightBasedServingDescription(lowered)) score -= 120;
  if (lowered.startsWith("1 ")) score += 14;
  if (lowered.includes("serving")) score += isBranded ? 24 : 8;

  for (const keyword of fatsecretItemServingKeywords) {
    if (lowered.includes(keyword)) {
      score += isBranded ? 70 : 25;
    }
  }
  for (const keyword of fatsecretIngredientServingKeywords) {
    if (lowered.includes(keyword)) {
      score += isBranded ? -90 : -12;
    }
  }

  return score;
}

function parseFatsecretServingOptions(detail: Record<string, unknown>): FatsecretServingOption[] {
  const servings = detail.servings;
  const servingEntry = (servings as Record<string, unknown> | undefined)?.serving;
  const servingList = Array.isArray(servingEntry) ? servingEntry : servingEntry ? [servingEntry] : [];
  const parsed: FatsecretServingOption[] = [];

  for (const raw of servingList) {
    if (!isRecord(raw)) continue;

    const metricAmount = toOptionalNumber(raw.metric_serving_amount);
    const metricUnit = String(raw.metric_serving_unit ?? "").trim().toLowerCase();
    let metricGrams: number | null = null;
    if (metricAmount !== null) {
      if (["g", "gram", "grams"].includes(metricUnit)) {
        metricGrams = metricAmount;
      } else if (["oz", "ounce", "ounces"].includes(metricUnit)) {
        metricGrams = metricAmount * 28.3495;
      }
    }

    const servingDescription =
      (typeof raw.serving_description === "string" ? raw.serving_description : "").trim() ||
      (typeof raw.measurement_description === "string" ? raw.measurement_description : "").trim();
    const description =
      servingDescription || (metricAmount !== null && metricUnit ? `${metricAmount} ${metricUnit}` : "1 serving");

    const option: FatsecretServingOption = {
      id: raw.serving_id === undefined || raw.serving_id === null ? null : String(raw.serving_id),
      description,
      metric_grams: metricGrams,
      number_of_units: toOptionalNumber(raw.number_of_units) ?? 1,
      calories: toNumber(raw.calories),
      protein: toNumber(raw.protein),
      carbs: toNumber(raw.carbohydrate),
      fats: toNumber(raw.fat),
    };

    const hasDuplicate = parsed.some((existing) => {
      const sameDescription = existing.description.toLowerCase() === option.description.toLowerCase();
      const existingMetric = existing.metric_grams ?? -1;
      const nextMetric = option.metric_grams ?? -1;
      return sameDescription && Math.abs(existingMetric - nextMetric) < 0.01;
    });
    if (!hasDuplicate) {
      parsed.push(option);
    }
  }

  if (parsed.length === 0) {
    parsed.push({
      id: null,
      description: "1 serving",
      metric_grams: null,
      number_of_units: 1,
      calories: toNumber(detail.calories),
      protein: toNumber(detail.protein),
      carbs: toNumber(detail.carbohydrate),
      fats: toNumber(detail.fat),
    });
  }

  return parsed;
}

function chooseDefaultFatsecretServing(
  options: FatsecretServingOption[],
  isBranded: boolean,
): FatsecretServingOption {
  let bestOption = options[0];
  let bestScore = Number.NEGATIVE_INFINITY;

  for (const option of options) {
    const score = scoreFatsecretServingDescription(option.description, isBranded);
    if (score > bestScore) {
      bestOption = option;
      bestScore = score;
    }
  }
  return bestOption;
}

function normalizeFatsecretFood(detail: Record<string, unknown>, fallbackId?: string) {
  const foodId = String(detail.food_id ?? fallbackId ?? "");
  const brand = typeof detail.brand_name === "string" && detail.brand_name.trim().length > 0
    ? detail.brand_name.trim()
    : null;
  const foodTypeRaw = typeof detail.food_type === "string" ? detail.food_type.trim() : null;
  const foodType = foodTypeRaw ? foodTypeRaw.toLowerCase() : "";
  const isRestaurant = foodType.includes("restaurant");
  const isBranded = !!brand || foodType.includes("brand") || isRestaurant;
  const restaurant = isRestaurant ? brand : null;
  const servingOptions = parseFatsecretServingOptions(detail);
  const defaultServing = chooseDefaultFatsecretServing(servingOptions, isBranded);

  return {
    id: foodId,
    source: "fatsecret",
    name: (detail.food_name ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
    serving: defaultServing.description,
    protein: defaultServing.protein,
    carbs: defaultServing.carbs,
    fats: defaultServing.fats,
    calories: defaultServing.calories,
    serving_options: servingOptions,
    brand,
    restaurant,
    food_type: foodTypeRaw,
    is_branded: isBranded,
    metadata: {
      food_id: foodId,
      brand,
      restaurant,
      food_type: foodTypeRaw,
    },
    food_id: foodId,
  };
}

function extractFatsecretSummaryServing(food: Record<string, unknown>) {
  const servingDescription = typeof food.serving_description === "string" ? food.serving_description.trim() : "";
  if (servingDescription) return servingDescription;

  const description = typeof food.food_description === "string" ? food.food_description.trim() : "";
  if (!description) return "1 serving";

  const perMatch = description.match(/per\s+(.+?)\s*-\s*calories/i);
  if (perMatch && perMatch[1]) {
    const extracted = perMatch[1].trim();
    if (extracted) return extracted;
  }

  return "1 serving";
}

function normalizeFatsecretSearchFallback(food: Record<string, unknown>, fallbackId?: string) {
  const foodId = String(food.food_id ?? fallbackId ?? "");
  const serving = extractFatsecretSummaryServing(food);
  const name = (food.food_name ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase());
  const brand = typeof food.brand_name === "string" && food.brand_name.trim().length > 0 ? food.brand_name.trim() : null;
  const foodTypeRaw = typeof food.food_type === "string" ? food.food_type.trim() : null;
  const foodType = foodTypeRaw ? foodTypeRaw.toLowerCase() : "";
  const isRestaurant = foodType.includes("restaurant");
  const isBranded = !!brand || foodType.includes("brand") || isRestaurant;
  const restaurant = isRestaurant ? brand : null;

  return {
    id: foodId,
    source: "fatsecret",
    name,
    serving,
    protein: 0,
    carbs: 0,
    fats: 0,
    calories: 0,
    serving_options: [
      {
        id: null,
        description: serving,
        metric_grams: null,
        number_of_units: 1,
        calories: 0,
        protein: 0,
        carbs: 0,
        fats: 0,
      },
    ],
    brand,
    restaurant,
    food_type: foodTypeRaw,
    is_branded: isBranded,
    metadata: {
      food_id: foodId,
      brand,
      restaurant,
      food_type: foodTypeRaw,
    },
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

function extractMealItems(parsedOutput: Record<string, unknown> | null) {
  if (!parsedOutput) return [];
  const candidates = [
    parsedOutput.items,
    parsedOutput.foods,
    parsedOutput.detected_items,
    parsedOutput.recognized_items,
    parsedOutput.meal_items,
    parsedOutput.food_items,
    parsedOutput.ingredients,
  ];

  const normalizeString = (value: string) => value.trim().replace(/\s+/g, " ");

  const items: string[] = [];
  const seen = new Set<string>();

  const pushValue = (value: unknown) => {
    if (typeof value === "string") {
      const normalized = normalizeString(value);
      if (!normalized) return;
      const key = normalized.toLowerCase();
      if (seen.has(key)) return;
      seen.add(key);
      items.push(normalized);
      return;
    }
    if (isRecord(value)) {
      const nameRaw = value.name ?? value.item ?? value.food;
      const portionRaw = value.portion ?? value.amount ?? value.quantity ?? value.serving;
      const name = typeof nameRaw === "string" ? normalizeString(nameRaw) : "";
      const portion = typeof portionRaw === "string" ? normalizeString(portionRaw) : "";
      const combined = name && portion ? `${name} - ${portion}` : name;
      if (!combined) return;
      const key = combined.toLowerCase();
      if (seen.has(key)) return;
      seen.add(key);
      items.push(combined);
      return;
    }
  };

  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      for (const entry of candidate) {
        pushValue(entry);
      }
    } else {
      pushValue(candidate);
    }
  }

  return items;
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

type VoiceParsedTranscriptItem = {
  query: string;
  qty: number;
  unit: string;
  assumptions: string[];
};

type VoiceMacroTotals = {
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
};

const voiceNumberWords: Record<string, number> = {
  a: 1,
  an: 1,
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
  half: 0.5,
  quarter: 0.25,
};

const voiceUnitAliases: Record<string, string> = {
  serving: "serving",
  servings: "serving",
  count: "count",
  counts: "count",
  item: "count",
  items: "count",
  piece: "count",
  pieces: "count",
  each: "count",
  g: "g",
  gram: "g",
  grams: "g",
  oz: "oz",
  ounce: "oz",
  ounces: "oz",
  lb: "lb",
  lbs: "lb",
  pound: "lb",
  pounds: "lb",
  cup: "cup",
  cups: "cup",
  tbsp: "tbsp",
  tablespoon: "tbsp",
  tablespoons: "tbsp",
  tsp: "tsp",
  teaspoon: "tsp",
  teaspoons: "tsp",
  slice: "slice",
  slices: "slice",
};

function parseVoiceNumberToken(raw: string) {
  const trimmed = raw.trim().toLowerCase();
  if (!trimmed) return null;
  if (trimmed.includes("/")) {
    const parts = trimmed.split("/").map((part) => part.trim());
    if (parts.length === 2) {
      const numerator = Number(parts[0]);
      const denominator = Number(parts[1]);
      if (Number.isFinite(numerator) && Number.isFinite(denominator) && denominator !== 0) {
        return numerator / denominator;
      }
    }
  }
  if (voiceNumberWords[trimmed] !== undefined) {
    return voiceNumberWords[trimmed];
  }
  const numeric = Number(trimmed);
  if (Number.isFinite(numeric)) {
    return numeric;
  }
  return null;
}

function normalizeVoiceUnit(raw: string | null | undefined, hasExplicitQuantity = false) {
  if (!raw) {
    return hasExplicitQuantity ? "count" : "serving";
  }
  const lowered = raw.trim().toLowerCase();
  if (!lowered) return hasExplicitQuantity ? "count" : "serving";
  return voiceUnitAliases[lowered] ?? lowered;
}

const voiceProtectedAndPhrases = [
  "mac and cheese",
  "peanut butter and jelly",
  "fish and chips",
  "ham and cheese",
  "cookies and cream",
  "salt and pepper",
  "biscuits and gravy",
  "beans and rice",
];

const voiceWithSplitSingleTokenFoods = new Set([
  "fries",
  "chips",
  "rice",
  "beans",
  "salad",
  "lemonade",
  "soda",
  "cola",
  "coke",
  "sprite",
  "water",
  "juice",
]);

const voiceWithLikelyModifierWords = new Set([
  "sauce",
  "gravy",
  "dressing",
  "mayo",
  "mayonnaise",
  "ketchup",
  "mustard",
  "cheese",
  "onion",
  "onions",
  "pickle",
  "pickles",
  "skin",
  "bone",
  "bones",
  "butter",
  "syrup",
  "cream",
  "sugar",
  "salt",
  "pepper",
]);

function stripVoiceLeadPhrases(value: string) {
  return value
    .replace(/^(?:i\s+(?:had|ate|drank)\s+)/i, "")
    .replace(/^(?:had|ate|drank)\s+/i, "")
    .replace(/\bfor\s+(?:breakfast|lunch|dinner|snack)\b/gi, "")
    .trim();
}

function isLikelyVoiceModifierChunk(value: string) {
  const lowered = value.trim().toLowerCase();
  return /^(?:no|without|extra|light|easy|hold|less|more|add|minus|sub(?:stitute)?)\b/.test(lowered);
}

function splitVoiceChunkByConnector(
  value: string,
  connectorPattern: RegExp,
  connectorJoin: string,
  shouldSplit: (left: string, right: string) => boolean = () => true,
) {
  const pieces = value
    .split(connectorPattern)
    .map((piece) => piece.trim())
    .filter(Boolean);
  if (pieces.length <= 1) return [value.trim()];

  const merged: string[] = [pieces[0]];
  for (const piece of pieces.slice(1)) {
    const previous = merged[merged.length - 1];
    if (shouldSplit(previous, piece)) {
      merged.push(piece);
      continue;
    }
    merged[merged.length - 1] = `${previous} ${connectorJoin} ${piece}`.replace(/\s+/g, " ").trim();
  }
  return merged;
}

function shouldSplitVoiceAndChunk(left: string, right: string) {
  if (!left.trim() || !right.trim()) return false;
  if (isLikelyVoiceModifierChunk(right)) return false;
  const leftClean = cleanFoodQuery(left).toLowerCase();
  const rightClean = cleanFoodQuery(right).toLowerCase();
  if (!leftClean || !rightClean) return false;
  for (const phrase of voiceProtectedAndPhrases) {
    const parts = phrase.split(" and ");
    if (parts.length !== 2) continue;
    const phraseLeft = parts[0];
    const phraseRight = parts[1];
    if (!phraseLeft || !phraseRight) continue;
    const rightMatches = rightClean === phraseRight || rightClean.startsWith(`${phraseRight} `);
    if (leftClean === phraseLeft && rightMatches) {
      return false;
    }
  }
  return true;
}

function shouldSplitVoiceWithChunk(left: string, right: string) {
  const leftQuery = cleanFoodQuery(stripVoiceLeadPhrases(left));
  const rightRaw = stripVoiceLeadPhrases(right);
  const rightQuery = cleanFoodQuery(rightRaw);
  if (!leftQuery || !rightQuery) return false;
  if (isLikelyVoiceModifierChunk(rightRaw)) return false;

  const tokens = rightQuery.toLowerCase().split(" ").filter(Boolean);
  if (tokens.length >= 2) return true;
  const token = tokens[0] ?? "";
  if (voiceWithLikelyModifierWords.has(token)) return false;
  return voiceWithSplitSingleTokenFoods.has(token);
}

function splitVoiceCompositeChunk(chunk: string) {
  let segments = [chunk.trim()].filter(Boolean);
  if (segments.length === 0) return [];

  segments = segments.flatMap((segment) =>
    splitVoiceChunkByConnector(segment, /\s+(?:and then|then|plus)\s+/gi, "and"),
  );
  segments = segments.flatMap((segment) =>
    splitVoiceChunkByConnector(segment, /\s+(?:\+|&)\s+/g, "and"),
  );
  segments = segments.flatMap((segment) =>
    splitVoiceChunkByConnector(segment, /\s+and\s+/gi, "and", shouldSplitVoiceAndChunk),
  );
  segments = segments.flatMap((segment) =>
    splitVoiceChunkByConnector(segment, /\s+with\s+/gi, "with", shouldSplitVoiceWithChunk),
  );

  return segments
    .map((segment) => segment.trim())
    .filter(Boolean);
}

function parseVoiceTranscriptItems(transcript: string): VoiceParsedTranscriptItem[] {
  const normalized = transcript
    .replace(/\r\n/g, "\n")
    .replace(/[;|\n]+/g, ",");
  const chunks = normalized
    .split(",")
    .map((chunk) => chunk.trim())
    .filter(Boolean)
    .flatMap((chunk) => splitVoiceCompositeChunk(chunk));
  const results: VoiceParsedTranscriptItem[] = [];
  const seen = new Set<string>();
  const quantityPattern =
    /^((?:\d+(?:\.\d+)?)|(?:\d+\s*\/\s*\d+)|(?:a|an|one|two|three|four|five|six|seven|eight|nine|ten|half|quarter))\s*(cups?|servings?|counts?|items?|pieces?|each|g|grams?|oz|ounces?|lbs?|pounds?|tbsp|tablespoons?|tsp|teaspoons?|slices?)?\s*(?:of\s+)?(.+)$/i;

  for (const chunk of chunks) {
    const assumptions: string[] = [];
    const withoutLead = stripVoiceLeadPhrases(chunk);
    if (!withoutLead) continue;

    const quantityMatch = withoutLead.match(quantityPattern);
    let qty = 1;
    let unit = "serving";
    let querySource = withoutLead;

    if (quantityMatch) {
      const parsedQty = parseVoiceNumberToken(quantityMatch[1]);
      if (parsedQty !== null && parsedQty > 0) {
        qty = parsedQty;
      } else {
        assumptions.push(`Assumed 1 serving for "${cleanFoodQuery(withoutLead)}".`);
      }
      unit = normalizeVoiceUnit(quantityMatch[2], true);
      querySource = quantityMatch[3] ?? withoutLead;
    } else {
      assumptions.push(`Assumed 1 serving for "${cleanFoodQuery(withoutLead)}".`);
    }

    const query = cleanFoodQuery(querySource);
    if (!query) continue;
    const key = `${query.toLowerCase()}|${unit}|${qty.toFixed(3)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    results.push({
      query,
      qty: Math.max(0.01, qty),
      unit,
      assumptions,
    });
  }

  if (results.length === 0) {
    const fallback = cleanFoodQuery(transcript);
    if (fallback) {
      results.push({
        query: fallback,
        qty: 1,
        unit: "serving",
        assumptions: [`Assumed 1 serving for "${fallback}".`],
      });
    }
  }

  return results;
}

function parseVoiceMacroTotals(raw: unknown): VoiceMacroTotals {
  if (!isRecord(raw)) {
    return { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0 };
  }
  return {
    calories: toNumber(raw.calories),
    protein_g: toNumber(raw.protein_g ?? raw.protein),
    carbs_g: toNumber(raw.carbs_g ?? raw.carbs),
    fat_g: toNumber(raw.fat_g ?? raw.fats ?? raw.fat),
  };
}

function hasVoiceTotals(totals: VoiceMacroTotals) {
  return totals.calories > 0 || totals.protein_g > 0 || totals.carbs_g > 0 || totals.fat_g > 0;
}

function voiceProviderForSource(source: string) {
  const lowered = source.toLowerCase();
  if (lowered.includes("fatsecret")) return "fatsecret";
  if (lowered.includes("nutritionix")) return "nutritionix";
  return "usda";
}

function servingGramsFromText(text: string) {
  const match = text.match(/([0-9]+(?:\.[0-9]+)?)\s*(g|gram|grams|oz|ounce|ounces)\b/i);
  if (!match) return null;
  const value = Number(match[1]);
  if (!Number.isFinite(value) || value <= 0) return null;
  const unit = match[2].toLowerCase();
  if (unit === "g" || unit === "gram" || unit === "grams") return value;
  if (unit === "oz" || unit === "ounce" || unit === "ounces") return value * 28.3495;
  return null;
}

function resolveVoiceBaseServingGrams(food: Record<string, unknown>) {
  const serving = typeof food.serving === "string" ? food.serving.trim().toLowerCase() : "";
  const options = Array.isArray(food.serving_options) ? food.serving_options : [];
  let firstMetric: number | null = null;

  for (const option of options) {
    if (!isRecord(option)) continue;
    const metricGrams = toOptionalNumber(option.metric_grams);
    if (metricGrams === null || metricGrams <= 0) continue;
    if (firstMetric === null) firstMetric = metricGrams;

    const description = typeof option.description === "string" ? option.description.trim().toLowerCase() : "";
    if (!serving || !description) continue;
    if (description === serving || description.includes(serving) || serving.includes(description)) {
      return metricGrams;
    }
  }

  if (firstMetric !== null) return firstMetric;
  if (serving) return servingGramsFromText(serving);
  return null;
}

function scaleVoiceMacrosForFood(food: Record<string, unknown>, qty: number, unit: string) {
  const normalizedQty = Math.max(0.01, qty);
  const normalizedUnit = normalizeVoiceUnit(unit, true);
  const baseGrams = resolveVoiceBaseServingGrams(food);
  let multiplier = normalizedQty;
  let gramsResolved: number | null = null;

  if (normalizedUnit === "g") {
    gramsResolved = normalizedQty;
    if (baseGrams && baseGrams > 0) {
      multiplier = normalizedQty / baseGrams;
    }
  } else if (normalizedUnit === "oz") {
    gramsResolved = normalizedQty * 28.3495;
    if (baseGrams && baseGrams > 0) {
      multiplier = gramsResolved / baseGrams;
    }
  } else if (normalizedUnit === "lb") {
    gramsResolved = normalizedQty * 453.592;
    if (baseGrams && baseGrams > 0) {
      multiplier = gramsResolved / baseGrams;
    }
  } else if (baseGrams && baseGrams > 0) {
    gramsResolved = baseGrams * normalizedQty;
  }

  return {
    gramsResolved,
    macros: {
      calories: toNumber(food.calories) * multiplier,
      protein_g: toNumber(food.protein) * multiplier,
      carbs_g: toNumber(food.carbs) * multiplier,
      fat_g: toNumber(food.fats) * multiplier,
    } satisfies VoiceMacroTotals,
  };
}

function buildVoiceMealItemFromFood(food: Record<string, unknown>, parsed: VoiceParsedTranscriptItem, confidence = 0.82) {
  const scaled = scaleVoiceMacrosForFood(food, parsed.qty, parsed.unit);
  const source = typeof food.source === "string" ? food.source : "usda";
  const provider = voiceProviderForSource(source);
  const sourceFoodId = String(food.food_id ?? food.fdc_id ?? food.id ?? "").trim();
  return {
    id: crypto.randomUUID(),
    display_name: typeof food.name === "string" && food.name.trim().length > 0 ? food.name : parsed.query,
    qty: parsed.qty,
    unit: parsed.unit,
    grams_resolved: scaled.gramsResolved,
    raw_cooked: null,
    source: {
      provider,
      food_id: sourceFoodId || crypto.randomUUID(),
      label: source.toUpperCase(),
    },
    macros: scaled.macros,
    confidence,
    assumptions_used: parsed.assumptions,
  };
}

function buildUnknownVoiceMealItem(parsed: VoiceParsedTranscriptItem) {
  return {
    id: crypto.randomUUID(),
    display_name: parsed.query,
    qty: parsed.qty,
    unit: parsed.unit,
    grams_resolved: null,
    raw_cooked: null,
    source: {
      provider: "usda",
      food_id: `unknown-${crypto.randomUUID()}`,
      label: "MANUAL",
    },
    macros: {
      calories: 0,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
    },
    confidence: 0.25,
    assumptions_used: parsed.assumptions,
  };
}

function voiceTotalsFromItems(items: Record<string, unknown>[]): VoiceMacroTotals {
  return items.reduce<VoiceMacroTotals>(
    (acc, item) => {
      const macros = parseVoiceMacroTotals((item as Record<string, unknown>).macros);
      return {
        calories: acc.calories + macros.calories,
        protein_g: acc.protein_g + macros.protein_g,
        carbs_g: acc.carbs_g + macros.carbs_g,
        fat_g: acc.fat_g + macros.fat_g,
      };
    },
    { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
  );
}

function usdaNutrientValue(nutrients: unknown, names: string[]) {
  const list = Array.isArray(nutrients) ? nutrients : [];
  for (const nutrient of list) {
    if (!isRecord(nutrient)) continue;
    const name = String(nutrient.nutrientName ?? (nutrient.nutrient as Record<string, unknown> | undefined)?.name ?? "")
      .toLowerCase();
    if (names.some((match) => name.includes(match))) {
      return toNumber(nutrient.value ?? nutrient.amount);
    }
  }
  return 0;
}

function normalizeUsdaFoodResult(food: Record<string, unknown>) {
  const nutrients = food.foodNutrients ?? [];
  return {
    id: String(food.fdcId ?? ""),
    source: "usda",
    name: (food.description ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
    serving: food.servingSize && food.servingSizeUnit ? `${food.servingSize} ${food.servingSizeUnit}` : "100 g",
    protein: usdaNutrientValue(nutrients, ["protein"]),
    carbs: usdaNutrientValue(nutrients, ["carbohydrate"]),
    fats: usdaNutrientValue(nutrients, ["total lipid", "fat"]),
    calories: usdaNutrientValue(nutrients, ["energy"]),
    metadata: { fdc_id: String(food.fdcId ?? ""), source: "usda" },
    fdc_id: String(food.fdcId ?? ""),
  };
}

function normalizeUsdaFoodDetail(payload: Record<string, unknown>) {
  const nutrients = payload.foodNutrients ?? [];
  return {
    id: String(payload.fdcId ?? ""),
    source: "usda",
    name: (payload.description ?? "Food").toString().toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
    serving: payload.servingSize && payload.servingSizeUnit ? `${payload.servingSize} ${payload.servingSizeUnit}` : "100 g",
    protein: usdaNutrientValue(nutrients, ["protein"]),
    carbs: usdaNutrientValue(nutrients, ["carbohydrate"]),
    fats: usdaNutrientValue(nutrients, ["total lipid", "fat"]),
    calories: usdaNutrientValue(nutrients, ["energy"]),
    metadata: { fdc_id: String(payload.fdcId ?? ""), source: "usda" },
    fdc_id: String(payload.fdcId ?? ""),
  };
}

async function searchFatsecretFoodByQuery(query: string) {
  const queryInfo = analyzeFoodSearchQuery(query);
  const expression = queryInfo.searchExpression || query;
  const payload = await fatsecretRequest("/foods/search/v3", {
    search_expression: expression,
    max_results: 5,
    page_number: 0,
  });
  const foodsPayload = payload.foods_search?.results?.food ?? payload.foods?.food ?? [];
  const list = Array.isArray(foodsPayload) ? foodsPayload : [foodsPayload];
  const ranked = list
    .map((entry, index) => {
      if (!isRecord(entry)) return null;
      const foodId = String(entry.food_id ?? "").trim();
      if (!foodId) return null;
      const fallback = normalizeFatsecretSearchFallback(entry, foodId);
      return {
        foodId,
        index,
        score: scoreFoodSearchResult(fallback, queryInfo),
      };
    })
    .filter((entry): entry is { foodId: string; index: number; score: number } => !!entry)
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return a.index - b.index;
    });
  const best = ranked[0];
  if (!best) return null;
  const detailPayload = await fatsecretRequest("/food/v5", { food_id: best.foodId });
  const detail = isRecord(detailPayload.food) ? detailPayload.food : {};
  return normalizeFatsecretFood(detail, best.foodId);
}

async function searchUsdaFoodByQuery(query: string) {
  if (!usdaApiKey) return null;
  const response = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?${new URLSearchParams({
    api_key: usdaApiKey,
    query,
    pageSize: "3",
  })}`);
  if (!response.ok) return null;
  const payload = await response.json();
  const foods = Array.isArray(payload.foods) ? payload.foods : [];
  const first = foods.find((entry: unknown) => isRecord(entry));
  if (!first || !isRecord(first)) return null;
  const normalized = normalizeUsdaFoodResult(first);
  if (!normalized.id) return null;
  return normalized;
}

async function fetchUsdaFoodById(fdcId: string) {
  if (!usdaApiKey) return null;
  const response = await fetch(`https://api.nal.usda.gov/fdc/v1/food/${fdcId}?${new URLSearchParams({ api_key: usdaApiKey })}`);
  if (!response.ok) return null;
  const payload = await response.json();
  if (!isRecord(payload)) return null;
  const normalized = normalizeUsdaFoodDetail(payload);
  if (!normalized.id) return null;
  return normalized;
}

async function fetchVoiceFoodBySource(provider: string, foodId: string) {
  const normalizedProvider = provider.toLowerCase();
  if (normalizedProvider === "fatsecret") {
    const detailPayload = await fatsecretRequest("/food/v5", { food_id: foodId });
    const detail = isRecord(detailPayload.food) ? detailPayload.food : {};
    return normalizeFatsecretFood(detail, foodId);
  }
  if (normalizedProvider === "usda") {
    return await fetchUsdaFoodById(foodId);
  }
  return null;
}

function logDateFromTimestamp(value: string | null | undefined) {
  if (!value) return todayIso();
  const trimmed = value.trim();
  const match = trimmed.match(/^(\d{4}-\d{2}-\d{2})/);
  if (match && match[1]) {
    return match[1];
  }
  const date = new Date(trimmed);
  if (!Number.isNaN(date.getTime())) {
    return date.toISOString().slice(0, 10);
  }
  return todayIso();
}

type CoachMacroTargetPayload = {
  calories?: number;
  protein?: number;
  carbs?: number;
  fats?: number;
};

const coachMacroKeywords = ["calorie", "kcal", "macro", "protein", "carb", "fat"];
const coachMacroUpdateVerbs = ["set", "update", "change", "adjust", "increase", "decrease", "lower", "raise", "bump"];

function isMacroUpdateIntentMessage(text: string) {
  const lowered = text.trim().toLowerCase();
  const hasKeyword = coachMacroKeywords.some((keyword) => lowered.includes(keyword));
  if (!hasKeyword) return false;
  const hasVerb = coachMacroUpdateVerbs.some((verb) => lowered.includes(verb));
  if (!hasVerb) return false;
  return /\d{2,5}/.test(lowered);
}

function firstRegexInt(text: string, patterns: RegExp[]) {
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (!match || !match[1]) continue;
    const parsed = Number.parseInt(match[1], 10);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function extractCoachMacroTargets(text: string): CoachMacroTargetPayload | null {
  const lowered = text.toLowerCase();
  const calories = firstRegexInt(lowered, [
    /\b(?:calories|kcal)\b[^\d]{0,12}(\d{3,5})\b/i,
    /\b(\d{3,5})\b[^\d]{0,6}\b(?:kcal|calories)\b/i,
  ]);
  const protein = firstRegexInt(lowered, [
    /\bprotein\b[^\d]{0,12}(\d{2,4})\b/i,
    /\b(\d{2,4})\b\s*g?\s*protein\b/i,
  ]);
  const carbs = firstRegexInt(lowered, [
    /\b(?:carbs?|carbohydrates?)\b[^\d]{0,12}(\d{2,4})\b/i,
    /\b(\d{2,4})\b\s*g?\s*(?:carbs?|carbohydrates?)\b/i,
  ]);
  const fats = firstRegexInt(lowered, [
    /\b(?:fats?|fat)\b[^\d]{0,12}(\d{2,4})\b/i,
    /\b(\d{2,4})\b\s*g?\s*(?:fats?|fat)\b/i,
  ]);

  const result: CoachMacroTargetPayload = {};
  if (calories !== null && calories > 0) result.calories = calories;
  if (protein !== null && protein >= 0) result.protein = protein;
  if (carbs !== null && carbs >= 0) result.carbs = carbs;
  if (fats !== null && fats >= 0) result.fats = fats;

  return Object.keys(result).length > 0 ? result : null;
}

function maybeBuildCoachMacroAction(userMessage: string, assistantText: string) {
  const targets = extractCoachMacroTargets(assistantText);
  if (!targets) return null;

  const userIntent = isMacroUpdateIntentMessage(userMessage);
  const assistantLowered = assistantText.toLowerCase();
  const assistantIntent = assistantLowered.includes("macro") &&
    (assistantLowered.includes("target") || assistantLowered.includes("updated") || assistantLowered.includes("set"));

  if (!userIntent && !assistantIntent) return null;

  return {
    id: crypto.randomUUID(),
    action_type: "update_macros",
    title: "Update macro targets",
    description: "Apply the macro targets from your coach message in the app.",
    confirmation_prompt: null,
    macros: targets,
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

    if (segments[0] === "onboarding" && method === "GET" && segments[1] === "state") {
      const userId = url.searchParams.get("user_id");
      if (!userId) throw new HttpError(400, "user_id is required.");
      const { data, error } = await supabase
        .from("onboarding_states")
        .select("step_index,is_complete,data,updated_at")
        .eq("user_id", userId)
        .order("updated_at", { ascending: false })
        .limit(1);
      if (error) throw new HttpError(500, error.message);
      if (!data || data.length === 0) throw new HttpError(404, "Onboarding state not found");
      return jsonResponse({ state: data[0] });
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

      const genderValue =
        (typeof payload.gender === "string" && payload.gender) ||
        (typeof payload.sex === "string" && payload.sex) ||
        null;
      const macroCandidates: Record<string, number | null> = {
        calories: parseIntSafe(payload.macro_calories as string),
        protein: parseIntSafe(payload.macro_protein as string),
        carbs: parseIntSafe(payload.macro_carbs as string),
        fats: parseIntSafe(payload.macro_fats as string),
      };
      const macros = Object.fromEntries(
        Object.entries(macroCandidates).filter(([, value]) => typeof value === "number" && value > 0)
      );
      const preferences: Record<string, unknown> = {
        training_level: payload.training_level,
        workout_days_per_week: payload.workout_days_per_week,
        workout_duration_minutes: payload.workout_duration_minutes,
        equipment: payload.equipment,
        food_allergies: payload.food_allergies,
        food_dislikes: payload.food_dislikes,
        diet_style: payload.diet_style,
        checkin_day: payload.checkin_day,
        gender: genderValue,
        sex: genderValue,
        activity_level: payload.activity_level,
        goal_weight_lbs: payload.goal_weight_lbs,
        target_date_timestamp: payload.target_date_timestamp,
        birthday_timestamp: payload.birthday_timestamp,
        special_considerations: payload.special_considerations_array ?? payload.special_considerations,
        additional_notes: payload.additional_notes,
        height_unit: payload.height_unit,
      };
      for (const key of Object.keys(preferences)) {
        const value = preferences[key];
        if (value === null || value === undefined) {
          delete preferences[key];
        } else if (typeof value === "string" && value.trim() === "") {
          delete preferences[key];
        } else if (Array.isArray(value) && value.length === 0) {
          delete preferences[key];
        }
      }

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

      const profilePayload: Record<string, unknown> = {
        user_id: userId,
        full_name: payload.full_name,
        age: parseIntSafe(payload.age as string),
        height_cm: heightCm(payload.height_feet as string, payload.height_inches as string),
        weight_kg: weightKg(payload.weight_lbs as string),
        goal: payload.goal,
        preferences,
      };
      if (Object.keys(macros).length > 0) {
        profilePayload.macros = macros;
      }

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
        const userId = await resolveUserId(payload.user_id);
        await ensureUserExists(userId);
        const { data, error } = await supabase
          .from("chat_threads")
          .insert({ user_id: userId, title: payload.title ?? null })
          .select()
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        return jsonResponse({ thread: data?.[0] });
      }

      if (method === "GET" && segments[1] === "threads") {
        const userId = await resolveUserId(url.searchParams.get("user_id"));
        let data: Record<string, unknown>[] | null = null;
        let error: unknown = null;
        ({ data, error } = await supabase
          .from("chat_threads")
          .select("*")
          .eq("user_id", userId)
          .order("last_message_at", { ascending: false, nullsFirst: false })
          .order("updated_at", { ascending: false }));
        if (error && isMissingColumnError(error, "last_message_at")) {
          ({ data, error } = await supabase
            .from("chat_threads")
            .select("*")
            .eq("user_id", userId)
            .order("updated_at", { ascending: false }));
        }
        if (error) throw new HttpError(500, (error as { message?: string })?.message ?? "Failed to load threads");
        return jsonResponse({ threads: data ?? [] });
      }

      if (method === "GET" && segments[1] === "thread" && segments[2]) {
        const userId = await resolveUserId(url.searchParams.get("user_id"));
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
        const payload = await parseJson<{
          user_id?: string;
          thread_id?: string;
          content?: string;
          stream?: boolean;
          local_workout_snapshot?: Record<string, unknown> | null;
        }>(req);
        const userId = await resolveUserId(payload.user_id);
        const threadId = payload.thread_id ?? "";
        const content = payload.content?.trim() ?? "";
        const stream = payload.stream ?? true;
        if (!threadId || !content) throw new HttpError(400, "user_id, thread_id, and content are required");
        await ensureUserExists(userId);

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

        const workoutRequest = isWorkoutRequest(content);
        if (workoutRequest) {
          const { focus, muscleGroups, durationMinutes } = parseWorkoutRequest(content);

          if (stream) {
            const encoder = new TextEncoder();
            const streamBody = new ReadableStream({
              async start(controller) {
                let assistantText = "One moment while I build your workout.";
                controller.enqueue(encoder.encode(`data: ${assistantText}\n\n`));
                let keepAliveTimer: number | null = setInterval(() => {
                  try {
                    controller.enqueue(encoder.encode(": keep-alive\n\n"));
                  } catch {
                    if (keepAliveTimer !== null) {
                      clearInterval(keepAliveTimer);
                      keepAliveTimer = null;
                    }
                  }
                }, 10000);

                let workoutResult: Record<string, unknown> | null = null;
                let tail = " Workout failed. Tell me your goal and equipment.";
                try {
                  workoutResult = await createCoachWorkout(userId, focus, muscleGroups, durationMinutes);
                  tail = " It's live in your workout view. Go check it out.";
                } catch (error) {
                  const message = error instanceof Error ? error.message : "Workout failed.";
                  workoutResult = { success: false, error: message };
                } finally {
                  if (keepAliveTimer !== null) {
                    clearInterval(keepAliveTimer);
                    keepAliveTimer = null;
                  }
                }

                assistantText += tail;
                controller.enqueue(encoder.encode(`data: ${tail}\n\n`));

                const { error: insertAssistantError } = await supabase.from("chat_messages").insert({
                  thread_id: threadId,
                  user_id: userId,
                  role: "assistant",
                  content: assistantText,
                  model: "gpt-4o-mini",
                  metadata: workoutResult ? { workout_created: workoutResult } : null,
                });
                if (insertAssistantError) {
                  controller.error(new Error(insertAssistantError.message));
                  return;
                }
                await touchChatThread(threadId);

                controller.enqueue(encoder.encode("data: [DONE]\n\n"));
                controller.close();
              },
            });

            return new Response(streamBody, {
              status: 200,
              headers: {
                "content-type": "text/event-stream",
                "cache-control": "no-cache",
                ...corsHeaders,
              },
            });
          }

          let workoutResult: Record<string, unknown> | null = null;
          let assistantText = "One moment while I build your workout. Workout failed. Tell me your goal and equipment.";
          try {
            workoutResult = await createCoachWorkout(userId, focus, muscleGroups, durationMinutes);
            assistantText = "One moment while I build your workout. It's live in your workout view. Go check it out.";
          } catch (error) {
            const message = error instanceof Error ? error.message : "Workout failed.";
            workoutResult = { success: false, error: message };
          }
          assistantText = trimCoachReply(assistantText);

          const { error: insertAssistantError } = await supabase.from("chat_messages").insert({
            thread_id: threadId,
            user_id: userId,
            role: "assistant",
            content: assistantText,
            model: "gpt-4o-mini",
            metadata: workoutResult ? { workout_created: workoutResult } : null,
          });
          if (insertAssistantError) throw new HttpError(500, insertAssistantError.message);
          await touchChatThread(threadId);
          return jsonResponse({ reply: assistantText, workout_created: workoutResult });
	        }
	
	        const profile = await getChatProfile(userId);
	        const latestCheckin = await getChatLatestCheckin(userId);
	        const recentWorkouts = await getChatRecentWorkouts(userId);
	        const history = await getChatRecentMessages(threadId, 12);
	        const promptInputs = {
	          message: content,
	          history,
	          profile: profile ?? {},
	          macros: profile?.macros ?? null,
	          latest_checkin: latestCheckin,
	          recent_workouts: recentWorkouts,
	          device_active_workout: payload.local_workout_snapshot ?? null,
	        };
	
	        if (stream) {
	          const encoder = new TextEncoder();
	          const abortController = new AbortController();
	          const streamBody = new ReadableStream({
	            async start(controller) {
	              let rawOutput = "";
	              let lastDisplay = "";
	
		              const emit = (
		                event:
		                  | { type: "delta"; text: string }
		                  | { type: "replace"; text: string }
		                  | { type: "coach_action"; action: Record<string, unknown> },
		              ) => {
		                controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
		              };
	
	              const emitDisplay = (nextDisplay: string) => {
	                if (nextDisplay === lastDisplay) return;
	                if (nextDisplay.startsWith(lastDisplay)) {
	                  emit({ type: "delta", text: nextDisplay.slice(lastDisplay.length) });
	                } else {
	                  emit({ type: "replace", text: nextDisplay });
	                }
	                lastDisplay = nextDisplay;
	              };
	
	              try {
	                await runPromptStream("coach_chat", userId, promptInputs, {
	                  signal: abortController.signal,
	                  onDelta(delta) {
	                    rawOutput += delta;
	                    const display = trimCoachReply(rawOutput);
	                    emitDisplay(display);
	                  },
	                });
	
		                const assistantText = trimCoachReply(rawOutput);
		                emitDisplay(assistantText);
		                const coachAction = maybeBuildCoachMacroAction(content, assistantText);
		                if (coachAction) {
		                  emit({ type: "coach_action", action: coachAction });
		                }
		
		                const { error: insertAssistantError } = await supabase.from("chat_messages").insert({
		                  thread_id: threadId,
		                  user_id: userId,
		                  role: "assistant",
		                  content: assistantText,
		                  model: "gpt-4o-mini",
		                  metadata: coachAction ? { coach_action: coachAction } : null,
		                });
	                if (insertAssistantError) {
	                  controller.error(new Error(insertAssistantError.message));
	                  return;
	                }
	                await touchChatThread(threadId);
	
	                controller.enqueue(encoder.encode("data: [DONE]\n\n"));
	                controller.close();
	              } catch (error) {
	                controller.error(error);
	              }
	            },
	            cancel() {
	              abortController.abort();
	            },
	          });
	          return new Response(streamBody, {
	            status: 200,
	            headers: {
	              "content-type": "text/event-stream",
	              "cache-control": "no-cache",
	              ...corsHeaders,
	            },
	          });
	        }
	
		        const assistantTextRaw = await runPrompt("coach_chat", userId, promptInputs);
		        const assistantText = trimCoachReply(assistantTextRaw ?? "");
		        const coachAction = maybeBuildCoachMacroAction(content, assistantText);
		
		        const { error: insertAssistantError } = await supabase.from("chat_messages").insert({
		          thread_id: threadId,
		          user_id: userId,
		          role: "assistant",
		          content: assistantText,
		          model: "gpt-4o-mini",
		          metadata: coachAction ? { coach_action: coachAction } : null,
		        });
		        if (insertAssistantError) throw new HttpError(500, insertAssistantError.message);
		        await touchChatThread(threadId);
		
		        return jsonResponse({ reply: assistantText, coach_action: coachAction });
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

      if (segments[1] === "sessions" && segments[3] === "logs" && method === "GET") {
        const sessionId = segments[2];
        let logs: Record<string, unknown>[] | null = null;
        let error: unknown = null;
        ({ data: logs, error } = await supabase
          .from("exercise_logs")
          .select("id,exercise_name,sets,reps,weight,duration_minutes,notes,created_at")
          .eq("session_id", sessionId)
          .order("created_at", { ascending: true }));
        if (error && isMissingColumnError(error, "duration_minutes")) {
          ({ data: logs, error } = await supabase
            .from("exercise_logs")
            .select("id,exercise_name,sets,reps,weight,notes,created_at")
            .eq("session_id", sessionId)
            .order("created_at", { ascending: true }));
        }
        if (error) throw new HttpError(500, error.message);
        const normalizedLogs = (logs ?? []).map((log) => ({
          ...log,
          sets: Number(log.sets ?? 0),
          reps: Number(log.reps ?? 0),
          weight: Number(log.weight ?? 0),
          duration_minutes: Number((log as { duration_minutes?: unknown }).duration_minutes ?? 0),
        }));
        return jsonResponse({ session_id: sessionId, logs: normalizedLogs });
      }

      if (segments[1] === "sessions" && segments[3] === "log" && method === "POST") {
        const sessionId = segments[2];
        const payload = await parseJson<Record<string, unknown>>(req);
        const durationMinutes = toNumber(payload.duration_minutes);
        const hasDuration = durationMinutes > 0;
        const sets = hasDuration ? 0 : toNumber(payload.sets ?? 1);
        const reps = hasDuration ? 0 : toNumber(payload.reps ?? 0);
        const weight = hasDuration ? 0 : toNumber(payload.weight ?? 0);
        const baseInsert: Record<string, unknown> = {
          session_id: sessionId,
          exercise_name: payload.exercise_name,
          sets,
          reps,
          weight,
          notes: payload.notes ?? null,
        };
        let rows: Record<string, unknown>[] | null = null;
        let error: unknown = null;
        ({ data: rows, error } = await supabase
          .from("exercise_logs")
          .insert({
            ...baseInsert,
            duration_minutes: hasDuration ? durationMinutes : 0,
          })
          .select());
        if (error && isMissingColumnError(error, "duration_minutes")) {
          // Back-compat: older schemas may not have `duration_minutes`.
          // Store cardio duration in `reps` so the client can still render minutes.
          ({ data: rows, error } = await supabase
            .from("exercise_logs")
            .insert({
              ...baseInsert,
              reps: hasDuration ? durationMinutes : reps,
            })
            .select());
        }
        if (error) throw new HttpError(500, error.message);
        if (!rows || rows.length === 0) throw new HttpError(500, "Failed to log exercise");
        return jsonResponse({ log_id: rows[0].id });
      }

      if (segments[1] === "sessions" && segments[3] === "complete" && method === "POST") {
        const sessionId = segments[2];
        const payload = await parseJson<Record<string, unknown>>(req);
        const { data: sessions, error } = await supabase
          .from("workout_sessions")
          .select("id,user_id,started_at")
          .eq("id", sessionId)
          .limit(1);
        if (error) throw new HttpError(500, error.message);
        if (!sessions || sessions.length === 0) throw new HttpError(404, "Session not found");
        const session = sessions[0];

        const providedDuration = toNumber(payload.duration_seconds);
        let durationSeconds = providedDuration > 0 ? providedDuration : 0;
        if (durationSeconds === 0 && session.started_at) {
          const startedAt = Date.parse(session.started_at);
          if (!Number.isNaN(startedAt)) {
            durationSeconds = Math.max(0, Math.floor((Date.now() - startedAt) / 1000));
          }
        }

        await supabase.from("workout_sessions").update({
          status: payload.status ?? "completed",
          duration_seconds: durationSeconds,
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
          duration_seconds: durationSeconds,
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
        const queryInfo = analyzeFoodSearchQuery(query);
        const searchExpression = queryInfo.searchExpression || query;
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
        let payload: Record<string, unknown> = {};
        try {
          payload = await fatsecretRequest("/foods/search/v3", {
            search_expression: searchExpression,
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
          if (!isRecord(food)) continue;
          const foodId = String(food.food_id ?? "");
          if (!foodId) continue;
          try {
            const detailPayload = await fatsecretRequest("/food/v5", { food_id: foodId });
            const detail = isRecord(detailPayload.food) ? detailPayload.food : {};
            results.push(normalizeFatsecretFood(detail, foodId));
          } catch {
            results.push(normalizeFatsecretSearchFallback(food, foodId));
          }
        }
        const rankedResults = results
          .map((result, index) => ({
            result,
            index,
            score: scoreFoodSearchResult(result, queryInfo),
          }))
          .sort((a, b) => {
            if (b.score !== a.score) return b.score - a.score;
            return a.index - b.index;
          })
          .map((entry) => entry.result);
        if (userId) {
          await ensureUserExists(userId);
          await supabase.from("search_history").insert({ user_id: userId, query, source: "fatsecret" });
        }
        return jsonResponse({ query, results: rankedResults });
      }

      if (method === "GET" && segments[1] === "fatsecret" && segments[2] === "barcode") {
        const barcode = url.searchParams.get("barcode") ?? "";
        const userId = await normalizeUserId(url.searchParams.get("user_id"));
        const payload = await fatsecretRequest("/food/barcode/v3", { barcode });
        const foodId = payload.food_id ?? payload.food?.food_id;
        if (!foodId) throw new HttpError(404, "No food found for barcode.");
        const detailPayload = await fatsecretRequest("/food/v5", { food_id: String(foodId) });
        const detail = isRecord(detailPayload.food) ? detailPayload.food : {};
        const normalized = normalizeFatsecretFood(detail, String(foodId));
        if (userId) {
          await ensureUserExists(userId);
          await supabase.from("search_history").insert({ user_id: userId, query: barcode, source: "fatsecret_barcode" });
        }
        return jsonResponse(normalized);
      }

      if (method === "GET" && segments[1] === "fatsecret" && segments[2] === "food" && segments[3]) {
        const foodId = segments[3];
        const detailPayload = await fatsecretRequest("/food/v5", { food_id: foodId });
        const detail = isRecord(detailPayload.food) ? detailPayload.food : {};
        const normalized = normalizeFatsecretFood(detail, foodId);
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
          photo_urls: photoUrl ? [photoUrl] : [],
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
              brand: item.brand ?? null,
              restaurant: item.restaurant ?? null,
              food_type: item.food_type ?? null,
              source: item.source ?? null,
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

    if (segments[0] === "meal") {
      if (method === "POST" && segments[1] === "voice" && segments[2] === "analyze") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const userId = await resolveUserId(payload.user_id as string | undefined);
        const transcript = typeof payload.transcript === "string" ? payload.transcript.trim() : "";
        if (!transcript) throw new HttpError(400, "transcript is required");
        await ensureUserExists(userId);

        const parsedItems = parseVoiceTranscriptItems(transcript).slice(0, 8);
        const items: Record<string, unknown>[] = [];
        const assumptions: Record<string, string>[] = [];
        const seenAssumptions = new Set<string>();

        for (const parsed of parsedItems) {
          let match: Record<string, unknown> | null = null;
          try {
            match = await searchFatsecretFoodByQuery(parsed.query);
          } catch {
            match = null;
          }

          if (!match) {
            try {
              match = await searchUsdaFoodByQuery(parsed.query);
            } catch {
              match = null;
            }
          }

          if (match) {
            items.push(buildVoiceMealItemFromFood(match, parsed, 0.82));
          } else {
            items.push(buildUnknownVoiceMealItem(parsed));
            const unmatchedDetail = `Couldn't confidently match "${parsed.query}".`;
            if (!seenAssumptions.has(unmatchedDetail)) {
              seenAssumptions.add(unmatchedDetail);
              assumptions.push({ type: "unmatched_item", detail: unmatchedDetail });
            }
          }

          for (const detail of parsed.assumptions) {
            if (!seenAssumptions.has(detail)) {
              seenAssumptions.add(detail);
              assumptions.push({ type: "portion_default", detail });
            }
          }
        }

        return jsonResponse({
          transcript_original: transcript,
          assumptions,
          totals: voiceTotalsFromItems(items),
          items,
          questions_needed: [],
        });
      }

      if (method === "POST" && segments[1] === "voice" && segments[2] === "reprice") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const userId = await resolveUserId(payload.user_id as string | undefined);
        await ensureUserExists(userId);

        const rawItems = Array.isArray(payload.items) ? payload.items : [];
        const repricedItems: Record<string, unknown>[] = [];

        for (const entry of rawItems) {
          if (!isRecord(entry)) continue;

          const qty = Math.max(0.01, toOptionalNumber(entry.qty) ?? 1);
          const unit = normalizeVoiceUnit(typeof entry.unit === "string" ? entry.unit : null, true);
          const source = isRecord(entry.source) ? entry.source : {};
          const provider = typeof source.provider === "string" ? source.provider.toLowerCase() : "usda";
          const sourceFoodId = String(source.food_id ?? "").trim();
          const displayName = typeof entry.display_name === "string" && entry.display_name.trim().length > 0
            ? entry.display_name.trim()
            : "Food";
          const confidence = toOptionalNumber(entry.confidence) ?? 0.7;
          const assumptionsUsed = Array.isArray(entry.assumptions_used)
            ? entry.assumptions_used.filter((value): value is string => typeof value === "string")
            : [];
          const rawCooked = typeof entry.raw_cooked === "string" ? entry.raw_cooked : null;

          let macros = parseVoiceMacroTotals(entry.macros);
          let gramsResolved = toOptionalNumber(entry.grams_resolved);

          if (sourceFoodId) {
            try {
              const matchedFood = await fetchVoiceFoodBySource(provider, sourceFoodId);
              if (matchedFood) {
                const scaled = scaleVoiceMacrosForFood(matchedFood, qty, unit);
                macros = scaled.macros;
                gramsResolved = scaled.gramsResolved;
              }
            } catch {
              // fall back to client-provided macros
            }
          }

          repricedItems.push({
            id: typeof entry.id === "string" && entry.id.trim().length > 0 ? entry.id : crypto.randomUUID(),
            display_name: displayName,
            qty,
            unit,
            grams_resolved: gramsResolved,
            raw_cooked: rawCooked,
            source: {
              provider: provider === "fatsecret" ? "fatsecret" : provider === "nutritionix" ? "nutritionix" : "usda",
              food_id: sourceFoodId || `unknown-${crypto.randomUUID()}`,
              label: typeof source.label === "string" && source.label.trim().length > 0
                ? source.label.trim()
                : provider.toUpperCase(),
            },
            macros,
            confidence,
            assumptions_used: assumptionsUsed,
          });
        }

        return jsonResponse({
          transcript_original: typeof payload.transcript_original === "string" ? payload.transcript_original : "",
          assumptions: Array.isArray(payload.assumptions) ? payload.assumptions : [],
          totals: voiceTotalsFromItems(repricedItems),
          items: repricedItems,
          questions_needed: [],
        });
      }

      if (method === "POST" && segments[1] === "log") {
        const payload = await parseJson<Record<string, unknown>>(req);
        const userId = await resolveUserId(payload.user_id as string | undefined);
        await ensureUserExists(userId);

        const mealType = typeof payload.meal_type === "string" && payload.meal_type.trim().length > 0
          ? payload.meal_type.trim()
          : "snack";
        const logDate = logDateFromTimestamp(typeof payload.timestamp === "string" ? payload.timestamp : null);
        const rawItems = Array.isArray(payload.items) ? payload.items : [];
        const mappedItems: Record<string, unknown>[] = [];
        let computedTotals: VoiceMacroTotals = { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0 };

        for (const rawItem of rawItems) {
          if (!isRecord(rawItem)) continue;
          const macros = parseVoiceMacroTotals(rawItem.macros);
          const qty = Math.max(0.01, toOptionalNumber(rawItem.qty) ?? 1);
          const unit = normalizeVoiceUnit(typeof rawItem.unit === "string" ? rawItem.unit : null, true);
          const displayName = typeof rawItem.display_name === "string" && rawItem.display_name.trim().length > 0
            ? rawItem.display_name.trim()
            : "Food";

          mappedItems.push({
            name: displayName,
            portion_value: qty,
            portion_unit: unit,
            serving: `${qty} ${unit}`,
            calories: macros.calories,
            protein: macros.protein_g,
            carbs: macros.carbs_g,
            fats: macros.fat_g,
          });

          computedTotals = {
            calories: computedTotals.calories + macros.calories,
            protein_g: computedTotals.protein_g + macros.protein_g,
            carbs_g: computedTotals.carbs_g + macros.carbs_g,
            fat_g: computedTotals.fat_g + macros.fat_g,
          };
        }

        const requestedTotals = parseVoiceMacroTotals(payload.totals);
        const finalTotals = hasVoiceTotals(requestedTotals) ? requestedTotals : computedTotals;

        const { error: insertError } = await supabase.from("nutrition_logs").insert({
          user_id: userId,
          date: logDate,
          meal_type: mealType,
          items: mappedItems,
          totals: {
            calories: finalTotals.calories,
            protein: finalTotals.protein_g,
            carbs: finalTotals.carbs_g,
            fats: finalTotals.fat_g,
          },
        });
        if (insertError) throw new HttpError(500, insertError.message);

        return jsonResponse({ success: true, date: logDate });
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
      let items: string[] = [];
      try {
        items = await detectMealItemsFromPhoto(publicUrl.publicUrl);
        if (items.length) {
          query = cleanFoodQuery(items[0]);
        }
      } catch {
        query = "";
      }
      if (!query) {
        try {
          query = await detectFoodQueryFromPhoto(publicUrl.publicUrl);
        } catch {
          query = "";
        }
      }
      if (!query) {
        query = "meal";
      }
      if (items.length === 0 && query && query !== "meal") {
        items = [query];
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
          items,
          message: "No match found. Try another photo.",
        });
      }
      return jsonResponse({ status: "scanned", photo_url: publicUrl.publicUrl, query, items, match });
    }

    if (segments[0] === "progress") {
      if (segments[1] === "photos" && method === "POST") {
        const form = await req.formData();
        const userId = await resolveUserId(form.get("user_id")?.toString() ?? "");
        const photo = form.get("photo");
        const photoType = form.get("photo_type")?.toString() ?? null;
        const photoCategory = form.get("photo_category")?.toString() ?? null;
        const checkinDate = form.get("checkin_date")?.toString() ?? todayIso();
        const persistPhoto = parseBoolean(form.get("persist_photo")) ?? true;
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
        if (persistPhoto) {
          let insertError: unknown = null;
          ({ error: insertError } = await supabase.from("progress_photos").insert({
            user_id: userId,
            url: publicUrl.publicUrl,
            photo_type: photoType ?? "checkin",
            type: photoType ?? "checkin",
            category: photoCategory,
            date: checkinDate,
            tags: tags.length ? tags : null,
          }));
          if (
            insertError &&
            (isMissingColumnError(insertError, "type") ||
              isMissingColumnError(insertError, "category") ||
              isMissingColumnError(insertError, "date"))
          ) {
            ({ error: insertError } = await supabase.from("progress_photos").insert({
              user_id: userId,
              url: publicUrl.publicUrl,
              photo_type: photoType ?? "checkin",
              tags: tags.length ? tags : null,
            }));
          }
          if (insertError) {
            const message =
              typeof (insertError as { message?: unknown })?.message === "string"
                ? (insertError as { message: string }).message
                : "Failed to save progress photo.";
            throw new HttpError(500, message);
          }
        }
        return jsonResponse({
          status: "uploaded",
          photo_url: publicUrl.publicUrl,
          photo_type: photoType ?? "checkin",
          photo_category: photoCategory,
          date: checkinDate,
          persisted: persistPhoto,
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
          const categoryTag = extractTagValue(tags, "category:");
          const dateTag = extractTagValue(tags, "date:");
          const categoryValue =
            typeof row.category === "string" && row.category.trim().length > 0 ? row.category.trim() : categoryTag;
          const typeValue =
            typeof row.type === "string" && row.type.trim().length > 0
              ? row.type.trim()
              : (typeof row.photo_type === "string" ? row.photo_type : null);
          const dateValue =
            typeof row.date === "string" && row.date.trim().length > 0
              ? row.date.trim()
              : (dateTag ?? (typeof row.created_at === "string" ? logDateFromTimestamp(row.created_at) : null));
          return {
            ...row,
            category: categoryValue ?? null,
            type: typeValue,
            date: dateValue,
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
        const preferences = isRecord(profile?.preferences)
          ? (profile?.preferences as Record<string, unknown>)
          : null;
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
        const legacyPhysiqueFocus = pickPreferenceStringArray(preferences, ["physique_focus", "physiqueFocus"]);
        const physiquePriority =
          pickPreferenceString(preferences, ["physiquePriority", "physique_priority"]) ??
          legacyPhysiqueFocus[0] ??
          null;
        if (physiquePriority) {
          promptInput.physique_priority = physiquePriority;
        }

        const secondaryGoalsRaw = pickPreferenceStringArray(preferences, ["secondaryGoals", "secondary_goals"]);
        const secondaryGoalsMerged = [...secondaryGoalsRaw, ...legacyPhysiqueFocus.slice(1)].filter(
          (goal) => goal && goal !== physiquePriority,
        );
        const uniqueSecondaryGoals = Array.from(new Set(secondaryGoalsMerged));
        if (uniqueSecondaryGoals.length > 0) {
          promptInput.secondary_goals = uniqueSecondaryGoals;
        }

        const physiqueGoalDescription = pickPreferenceString(preferences, [
          "physiqueGoalDescription",
          "physique_goal_description",
        ]);
        if (physiqueGoalDescription) {
          promptInput.physique_goal_description = physiqueGoalDescription;
        }

        const secondaryPriority =
          pickPreferenceString(preferences, ["secondaryPriority", "secondary_priority"]) ??
          uniqueSecondaryGoals[0] ??
          null;
        if (secondaryPriority && secondaryPriority !== physiquePriority) {
          promptInput.secondary_priority = secondaryPriority;
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
