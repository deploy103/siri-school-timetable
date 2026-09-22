interface WindowState {
  count: number;
  resetsAt: number;
}

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  retryAfterSeconds: number;
}

export class MemoryRateLimiter {
  private readonly windows = new Map<string, WindowState>();

  constructor(
    private readonly limit: number,
    private readonly windowMs: number,
    private readonly maxClients = 10_000,
  ) {}

  check(key: string, now = Date.now()): RateLimitResult {
    let state = this.windows.get(key);
    if (!state || state.resetsAt <= now) {
      if (this.windows.size >= this.maxClients) this.prune(now);
      state = { count: 0, resetsAt: now + this.windowMs };
    }
    state.count += 1;
    this.windows.set(key, state);

    return {
      allowed: state.count <= this.limit,
      remaining: Math.max(0, this.limit - state.count),
      retryAfterSeconds: Math.max(1, Math.ceil((state.resetsAt - now) / 1_000)),
    };
  }

  clear(): void {
    this.windows.clear();
  }

  private prune(now: number): void {
    for (const [key, state] of this.windows) {
      if (state.resetsAt <= now) this.windows.delete(key);
    }
    if (this.windows.size >= this.maxClients) {
      const oldestKey = this.windows.keys().next().value as string | undefined;
      if (oldestKey) this.windows.delete(oldestKey);
    }
  }
}

export function clientIdentifier(request: Request): string {
  if (process.env.TRUST_PROXY_HEADERS !== "true") return "untrusted-client";
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const candidate = forwarded || request.headers.get("x-real-ip")?.trim();
  if (!candidate || !/^[0-9A-Fa-f:.]{3,64}$/.test(candidate)) return "unknown-client";
  return candidate;
}
