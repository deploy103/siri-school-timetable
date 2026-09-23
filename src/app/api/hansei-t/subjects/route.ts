import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { getKstDate } from "@/lib/date";
import { getTeacherSubjects } from "@/lib/hansei-teacher-service";
import { enforceJsonRateLimit } from "@/lib/request-guard";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;
  try {
    const result = await getTeacherSubjects(getKstDate());
    return jsonResponse(result, {
      status: 200,
      headers: { "Cache-Control": "private, max-age=300" },
    });
  } catch (error) {
    logServerError("hansei-teacher-subjects", error);
    return errorResponse(error);
  }
}
