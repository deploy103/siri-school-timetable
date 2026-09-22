import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { getKstDate } from "@/lib/date";
import { getTodayTimetable } from "@/lib/neis";
import { enforceJsonRateLimit } from "@/lib/request-guard";
import { searchParamsToRecord, timetableQuerySchema } from "@/lib/schemas";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;

  try {
    const params = new URL(request.url).searchParams;
    const query = timetableQuerySchema.parse(searchParamsToRecord(params));
    const timetable = await getTodayTimetable(query, getKstDate());
    return jsonResponse(timetable, {
      status: 200,
      headers: { "Cache-Control": "private, max-age=60" },
    });
  } catch (error) {
    logServerError("timetable", error);
    return errorResponse(error);
  }
}
