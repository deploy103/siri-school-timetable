import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { parseDateRange } from "@/lib/date-range";
import { getSchoolEvents } from "@/lib/neis";
import { enforceJsonRateLimit } from "@/lib/request-guard";
import { mealQuerySchema, searchParamsToRecord } from "@/lib/schemas";
import type { SchoolEventsResponse } from "@/lib/types";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;
  try {
    const params = new URL(request.url).searchParams;
    const query = mealQuerySchema.parse(searchParamsToRecord(params));
    const { from, to, dates } = parseDateRange(params);
    const days: SchoolEventsResponse[] = [];
    // Bound upstream concurrency; publish only a complete range.
    for (const date of dates) days.push(await getSchoolEvents(query, date));
    return jsonResponse({ from, to, days }, {
      status: 200,
      headers: { "Cache-Control": "private, max-age=60" },
    });
  } catch (error) {
    logServerError("calendar-range", error);
    return errorResponse(error);
  }
}
