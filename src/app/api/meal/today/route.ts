import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { getKstDate } from "@/lib/date";
import { getTodayMeals } from "@/lib/neis";
import { enforceJsonRateLimit } from "@/lib/request-guard";
import { mealQuerySchema, searchParamsToRecord } from "@/lib/schemas";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;

  try {
    const params = new URL(request.url).searchParams;
    const query = mealQuerySchema.parse(searchParamsToRecord(params));
    const meals = await getTodayMeals(query, getKstDate());
    return jsonResponse(meals, {
      status: 200,
      headers: { "Cache-Control": "private, max-age=60" },
    });
  } catch (error) {
    logServerError("meal", error);
    return errorResponse(error);
  }
}
