import { SECURITY_HEADERS, logServerError } from "@/lib/api-response";
import { getKstDate } from "@/lib/date";
import { safeError } from "@/lib/errors";
import { getTodayMeals } from "@/lib/neis";
import { clientIdentifier, MemoryRateLimiter } from "@/lib/rate-limit";
import { mealQuerySchema, searchParamsToRecord } from "@/lib/schemas";
import { mealToSpeech, mealVoiceErrorMessage } from "@/lib/voice";
import { ZodError } from "zod";

export const dynamic = "force-dynamic";

const limiter = new MemoryRateLimiter(30, 60_000);

function textResponse(message: string, status = 200, retryAfter?: number): Response {
  const headers = new Headers({
    ...SECURITY_HEADERS,
    "Content-Type": "text/plain; charset=utf-8",
    "Cache-Control": "no-store",
  });
  if (retryAfter !== undefined) headers.set("Retry-After", String(retryAfter));
  return new Response(message, { status, headers });
}

export async function GET(request: Request): Promise<Response> {
  const rateLimit = limiter.check(clientIdentifier(request));
  if (!rateLimit.allowed) {
    return textResponse(mealVoiceErrorMessage("RATE_LIMITED"), 429, rateLimit.retryAfterSeconds);
  }

  try {
    const params = new URL(request.url).searchParams;
    const query = mealQuerySchema.parse(searchParamsToRecord(params));
    const meals = await getTodayMeals(query, getKstDate());
    return textResponse(mealToSpeech(meals));
  } catch (error) {
    logServerError("voice-meal", error);
    if (error instanceof ZodError) return textResponse(mealVoiceErrorMessage("INVALID_INPUT"), 400);
    const appError = safeError(error);
    return textResponse(mealVoiceErrorMessage(appError.code), appError.status);
  }
}

export function clearMealVoiceRateLimit(): void {
  limiter.clear();
}
