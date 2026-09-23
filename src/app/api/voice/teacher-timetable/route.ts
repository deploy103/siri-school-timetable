import { SECURITY_HEADERS, logServerError } from "@/lib/api-response";
import { getKstDate } from "@/lib/date";
import { safeError } from "@/lib/errors";
import { getTeacherTimetable } from "@/lib/hansei-teacher-service";
import { clientIdentifier, MemoryRateLimiter } from "@/lib/rate-limit";
import { teacherProfileQuerySchema } from "@/lib/schemas";
import { decodeTeacherProfile } from "@/lib/teacher-profile";
import { teacherTimetableToSpeech, teacherVoiceErrorMessage } from "@/lib/teacher-timetable";
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
  const rateLimit = limiter.check(`teacher:${clientIdentifier(request)}`);
  if (!rateLimit.allowed) {
    return textResponse(
      teacherVoiceErrorMessage("RATE_LIMITED"),
      429,
      rateLimit.retryAfterSeconds,
    );
  }
  try {
    const params = new URL(request.url).searchParams;
    const { p } = teacherProfileQuerySchema.parse({ p: params.get("p") ?? undefined });
    const settings = decodeTeacherProfile(p);
    const timetable = await getTeacherTimetable(settings, getKstDate());
    return textResponse(teacherTimetableToSpeech(timetable, settings.includeSubject));
  } catch (error) {
    logServerError("voice-teacher-timetable", error);
    if (error instanceof ZodError) {
      return textResponse(teacherVoiceErrorMessage("INVALID_INPUT"), 400);
    }
    const appError = safeError(error);
    return textResponse(teacherVoiceErrorMessage(appError.code), appError.status);
  }
}

export function clearTeacherVoiceRateLimit(): void {
  limiter.clear();
}
