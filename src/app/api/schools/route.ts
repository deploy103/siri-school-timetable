import { errorResponse, jsonResponse, logServerError } from "@/lib/api-response";
import { searchSchools } from "@/lib/neis";
import { enforceJsonRateLimit } from "@/lib/request-guard";
import { schoolSearchSchema } from "@/lib/schemas";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const limited = enforceJsonRateLimit(request);
  if (limited) return limited;

  try {
    const params = new URL(request.url).searchParams;
    const query = schoolSearchSchema.parse({ name: params.get("name") ?? undefined });
    const schools = await searchSchools(query.name);
    return jsonResponse(
      { schools },
      { status: 200, headers: { "Cache-Control": "private, max-age=60" } },
    );
  } catch (error) {
    logServerError("schools", error);
    return errorResponse(error);
  }
}
