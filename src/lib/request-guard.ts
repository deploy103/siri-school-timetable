import { rateLimitResponse } from "@/lib/api-response";
import { clientIdentifier, MemoryRateLimiter } from "@/lib/rate-limit";

const jsonLimiter = new MemoryRateLimiter(60, 60_000);

export function enforceJsonRateLimit(request: Request): Response | undefined {
  const result = jsonLimiter.check(`json:${clientIdentifier(request)}`);
  return result.allowed ? undefined : rateLimitResponse(result.retryAfterSeconds);
}

export function clearRateLimits(): void {
  jsonLimiter.clear();
}
