import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { getKstDate } from "@/lib/date";
import { getTeacherTimetable } from "@/lib/hansei-teacher-service";
import { enforceJsonRateLimit } from "@/lib/request-guard";
import { teacherProfileQuerySchema } from "@/lib/schemas";
import { decodeTeacherProfile } from "@/lib/teacher-profile";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;
  try {
    const params = new URL(request.url).searchParams;
    const { p } = teacherProfileQuerySchema.parse({ p: params.get("p") ?? undefined });
    const settings = decodeTeacherProfile(p);
    const result = await getTeacherTimetable(settings, getKstDate());
    return jsonResponse(result, {
      status: 200,
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    logServerError("hansei-teacher-timetable", error);
    return errorResponse(error);
  }
}
