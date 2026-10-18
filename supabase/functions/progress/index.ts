// Supabase Edge Function: weekly progress-photo analysis.
//
// The app sends up to 6 front/side photos (baseline, about a week ago, latest)
// plus a short text summary of the user's goal and data. This function asks
// Claude to compare them and returns plain-text observations and suggestions.
// Photos are only held in memory for the request; nothing is stored here.
//
// Deploy (after the coach function is set up):
//   supabase functions deploy progress
//
// verify_jwt = true in supabase/config.toml: callers must be signed in
// (the app signs in anonymously, as for the coach).

import Anthropic from "npm:@anthropic-ai/sdk@0.135.0";

const client = new Anthropic(); // reads ANTHROPIC_API_KEY

const MODEL = "claude-opus-5-5";
const MAX_PHOTOS = 6;
// About 2 MB of JPEG per photo; the app sends ~1024 px images well under this.
const MAX_BASE64_CHARS = 2_800_000;
const MAX_CONTEXT_CHARS = 6000;

type IncomingPhoto = { label?: string; data?: string };

const SYSTEM_PROMPT = `You review a person's progress photos for a fitness app and give a short, practical weekly update.

You get front and side photos from up to three dates (labelled), plus their goal and data (weight trend, calories, protein, training volume per muscle). Compare the photos and relate what you see to the goal and the data.

Rules:
- Describe visible changes neutrally and specifically: waist and midsection, shoulder and upper-back width, arm and leg fullness, posture. Never comment on attractiveness, and never shame or praise a body type.
- Photos vary with lighting, pump, time of day, food and pose. Say when differences could be due to that, and don't over-read small changes. If the photos are too different to compare (angle, distance, clothing), say so and suggest how to retake them.
- If you estimate body fat, give a range (e.g. "roughly 16-19%") and say it's a visual estimate.
- Ground suggestions in their numbers: e.g. if the waist looks smaller while weight is steady and protein is on target, the recomposition is working; if nothing changed in several weeks and weight is flat while the goal is to lose, suggest a modest calorie change.
- You are not a doctor. If something looks medically concerning (e.g. a skin change or swelling), suggest seeing a doctor without diagnosing.

Format (plain text, no markdown headings, under 220 words):
What changed: 2-3 sentences.
How it fits your data: 1-2 sentences.
Suggestions: 2-3 short bullet points starting with "- ".`;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  let payload: { photos?: IncomingPhoto[]; context?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON." }, 400);
  }

  const photos = (payload.photos ?? []).filter(
    (p) => typeof p.data === "string" && p.data.length > 0 && p.data.length <= MAX_BASE64_CHARS,
  ).slice(0, MAX_PHOTOS);
  if (photos.length < 2) return json({ error: "Need at least two photos to compare." }, 400);

  const content: Anthropic.Beta.Messages.BetaContentBlockParam[] = [];
  for (const photo of photos) {
    content.push({ type: "text", text: (photo.label ?? "Photo").slice(0, 80) });
    content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: photo.data! } });
  }
  const context = (payload.context ?? "").slice(0, MAX_CONTEXT_CHARS);
  content.push({ type: "text", text: `The user's goal and data:\n${context}\n\nGive this week's progress update.` });

  try {
    const response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      output_config: { effort: "medium" },
      // If a safety classifier declines, retry on Anthropic's recommended fallback model.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content }],
    });

    if (response.stop_reason === "refusal") {
      return json({ reply: "I couldn't analyse these photos. Try retaking them in fitted clothing with even lighting." });
    }

    const reply = response.content
      .filter((block): block is Anthropic.Beta.Messages.BetaTextBlock => block.type === "text")
      .map((block) => block.text)
      .join("\n")
      .trim();

    return json({ reply: reply || "I didn't get an answer back. Please try again." });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) {
      return json({ error: "The analysis service is busy. Try again in a minute." }, 429);
    }
    if (error instanceof Anthropic.AuthenticationError) {
      console.error("Anthropic auth failed - check the ANTHROPIC_API_KEY secret.");
      return json({ error: "The analysis server isn't configured yet." }, 500);
    }
    if (error instanceof Anthropic.BadRequestError) {
      console.error("Bad request", error.message);
      return json({ error: "The photos couldn't be read. Try retaking them." }, 400);
    }
    if (error instanceof Anthropic.APIError) {
      console.error("Anthropic API error", error.status, error.message);
      return json({ error: "The analysis had a problem. Try again." }, 502);
    }
    console.error("Unexpected error", error);
    return json({ error: "Something went wrong." }, 500);
  }
});
