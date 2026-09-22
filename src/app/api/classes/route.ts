import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { getKstDate } from "@/lib/date";
import { getSchoolClasses } from "@/lib/neis";
import { enforceJsonRateLimit } from "@/lib/request-guard";
import { classQuerySchema } from "@/lib/schemas";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;

  try {
    const params = new URL(request.url).searchParams;
    const query = classQuerySchema.parse({
      officeCode: params.get("officeCode") ?? undefined,
      schoolCode: params.get("schoolCode") ?? undefined,
    });
    const today = getKstDate();
    const year = Number(today.slice(0, 4));
    let academicYear = year;
    let classes = await getSchoolClasses(query.officeCode, query.schoolCode, academicYear);
    if (classes.length === 0 && Number(today.slice(5, 7)) <= 2) {
      academicYear -= 1;
      classes = await getSchoolClasses(query.officeCode, query.schoolCode, academicYear);
    }
    return jsonResponse(
      { academicYear, classes },
      { status: 200, headers: { "Cache-Control": "private, max-age=300" } },
    );
  } catch (error) {
    logServerError("classes", error);
    return errorResponse(error);
  }
}
