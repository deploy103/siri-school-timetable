import { jsonResponse } from "@/lib/api-response";

export const dynamic = "force-dynamic";

export function GET(): Response {
  return jsonResponse(
    {
      status: "ok",
      mode:
        process.env.NEIS_API_KEY?.trim() && process.env.NEIS_MOCK_MODE !== "true"
          ? "live"
          : "mock",
      timestamp: new Date().toISOString(),
    },
    { status: 200, headers: { "Cache-Control": "no-store" } },
  );
}
