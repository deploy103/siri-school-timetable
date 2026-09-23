import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { getKstDate } from "@/lib/date";
import { getTeacherAssignmentCandidates } from "@/lib/hansei-teacher-service";
import { enforceJsonRateLimit } from "@/lib/request-guard";
import { teacherSubjectQuerySchema } from "@/lib/schemas";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;
  try {
    const params = new URL(request.url).searchParams;
    const { subject } = teacherSubjectQuerySchema.parse({
      subject: params.get("subject") ?? undefined,
    });
    const result = await getTeacherAssignmentCandidates(subject, getKstDate());
    return jsonResponse(result, {
      status: 200,
      headers: { "Cache-Control": "private, max-age=300" },
    });
  } catch (error) {
    logServerError("hansei-teacher-candidates", error);
    return errorResponse(error);
  }
}
