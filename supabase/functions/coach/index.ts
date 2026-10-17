// Supabase Edge Function: the cloud AI coach.
//
// The iPhone app sends the chat history plus a snapshot of today's scores and
// recent workouts; this function asks Claude and returns the reply. The
// Anthropic API key stays here as a secret and never ships in the app.
//
// Deploy:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy coach
//
// Supabase checks the caller's JWT before this code runs (verify_jwt = true in
// supabase/config.toml). The app signs in anonymously to get one.

import Anthropic from "npm:@anthropic-ai/sdk@0.135.0";

const client = new Anthropic(); // reads ANTHROPIC_API_KEY

const MODEL = "claude-opus-5-5";
const MAX_HISTORY = 20;
const MAX_MESSAGE_CHARS = 4000;

type IncomingMessage = { role: "user" | "assistant"; content: string };

const SYSTEM_PROMPT = `You are the AI coach inside a strength-training and recovery app, similar to Whoop or Bevel. You help one person decide how hard to train, how to recover, and how to program their gym sessions.

How the app's scores work:
- Strain (0-21): daily exertion. Cardio load comes from heart-rate time in zones (Banister TRIMP). Lifting load comes from session RPE x minutes, because heart rate undercounts lifting. The scale saturates, so 18+ is a very hard day.
- Recovery (0-100%): overnight HRV and resting heart rate compared with the person's 30-day baseline, plus sleep. Under 34% is low, 34-66% moderate, 67%+ high.
- Target strain is a suggested range for today based on recovery.
- Sleep score (0-100): time asleep vs. need (need rises after high-strain days), efficiency, deep + REM share, and interruptions.
- Calories burned: estimated from Mifflin-St Jeor or Katch-McArdle resting energy, the Keytel heart-rate equation for exercise, steps, and 10% for digestion. calorieBalance is food eaten minus projected burn (negative = deficit).
- Gym: the snapshot's "gym" field lists the user's equipment, plates and weight increments. Only suggest exercises they can do there, and loads they can actually make with those plates/dumbbells/stacks.
- suggestedWorkout: when present, the app shows this planned session as a card with a Start button (weights already rounded to the user's equipment). Explain why it suits today and how to adjust it; don't repeat the whole list.
- Nutrition: daily calories and macros the user logs in Cronometer, read from Apple Health. Today's numbers may be partial if the day isn't over. Protein target is 1.6 g/kg body weight. Relate food to training and recovery (e.g. low protein or calories after a hard day), without moralizing about food.

How to answer:
- Ground every answer in the numbers you are given. Quote the specific values that drove your advice.
- Be direct and practical. Lead with the recommendation, then the reason. Keep most replies under 200 words unless asked for a plan.
- For workout plans, give exercises with sets x reps and a target RPE, and build on what they actually did recently (progressive overload, muscle groups they haven't trained).
- If data is missing or the baseline is still calibrating, say so and give advice that doesn't depend on it.
- You are not a doctor. For pain, injury, illness, or unusual symptoms, suggest seeing a professional.`;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  let payload: { messages?: IncomingMessage[]; snapshot?: unknown };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON." }, 400);
  }

  const messages: Anthropic.Beta.Messages.BetaMessageParam[] = (payload.messages ?? [])
    .filter((m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-MAX_HISTORY)
    .map((m) => ({ role: m.role, content: m.content.slice(0, MAX_MESSAGE_CHARS) }));

  // The API needs the conversation to start with a user turn.
  while (messages.length > 0 && messages[0].role !== "user") messages.shift();
  if (messages.length === 0) return json({ error: "No message to answer." }, 400);

  const snapshot = JSON.stringify(payload.snapshot ?? {}, null, 2).slice(0, 20_000);

  try {
    const response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      // Chat replies don't need deep reasoning; raise to "medium" for better plans.
      output_config: { effort: "low" },
      // If a safety classifier declines, retry on Anthropic's recommended fallback model.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: [
        { type: "text", text: SYSTEM_PROMPT },
        { type: "text", text: `The user's current data (JSON):\n${snapshot}` },
      ],
      messages,
    });

    if (response.stop_reason === "refusal") {
      return json({ reply: "I can't help with that one. Try asking about your training, recovery or sleep." });
    }

    const reply = response.content
      .filter((block): block is Anthropic.Beta.Messages.BetaTextBlock => block.type === "text")
      .map((block) => block.text)
      .join("\n")
      .trim();

    return json({ reply: reply || "I didn't get an answer back. Please try again." });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) {
      return json({ error: "The coach is busy. Try again in a minute." }, 429);
    }
    if (error instanceof Anthropic.AuthenticationError) {
      console.error("Anthropic auth failed - check the ANTHROPIC_API_KEY secret.");
      return json({ error: "The coach server isn't configured yet." }, 500);
    }
    if (error instanceof Anthropic.APIError) {
      console.error("Anthropic API error", error.status, error.message);
      return json({ error: "The coach had a problem answering. Try again." }, 502);
    }
    console.error("Unexpected error", error);
    return json({ error: "Something went wrong." }, 500);
  }
});
