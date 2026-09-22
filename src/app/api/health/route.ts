import { jsonResponse } from "@/lib/api-response";
import { getNeisRuntimeStatus } from "@/lib/neis";

export const dynamic = "force-dynamic";

export function GET(): Response {
  const neis = getNeisRuntimeStatus();
  return jsonResponse(
    {
      status: neis.mode === "unconfigured" ? "degraded" : "ok",
      neis,
      timestamp: new Date().toISOString(),
    },
    { status: 200, headers: { "Cache-Control": "no-store" } },
  );
}
