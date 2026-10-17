import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { parseDateRange } from "@/lib/date-range";
import { getTodayTimetable } from "@/lib/neis";
import { enforceJsonRateLimit } from "@/lib/request-guard";
import { searchParamsToRecord, timetableQuerySchema } from "@/lib/schemas";
import type { TimetableResponse } from "@/lib/types";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;

  try {
    const params = new URL(request.url).searchParams;
    const query = timetableQuerySchema.parse(searchParamsToRecord(params));
    const { from, to, dates } = parseDateRange(params);
    const days: TimetableResponse[] = [];
    // Sequential daily wrappers bound upstream concurrency and retain cache reuse.
    // Do not publish a partial range if any day fails.
    for (const date of dates) days.push(await getTodayTimetable(query, date));
    return jsonResponse({ from, to, days }, {
      status: 200,
      headers: { "Cache-Control": "private, max-age=60" },
    });
  } catch (error) {
    logServerError("timetable-range", error);
    return errorResponse(error);
  }
}
