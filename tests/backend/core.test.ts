import { describe, expect, it } from "vitest";
import { getKstDate, toNeisDate } from "@/lib/date";
import { MemoryCache } from "@/lib/cache";
import { clientIdentifier, MemoryRateLimiter } from "@/lib/rate-limit";
import { schoolSearchSchema, timetableQuerySchema } from "@/lib/schemas";
import { timetableToSpeech, voiceErrorMessage } from "@/lib/voice";

describe("KST dates", () => {
  it("uses the Korean calendar day across a UTC boundary", () => {
    expect(getKstDate(new Date("2026-09-21T15:05:00.000Z"))).toBe("2026-09-22");
    expect(toNeisDate("2026-09-22")).toBe("20260922");
  });

  it("rejects an invalid date format", () => {
    expect(() => toNeisDate("20260922")).toThrow(TypeError);
  });
});

describe("input validation", () => {
  const valid = {
    officeCode: "B10",
    schoolCode: "7010911",
    kind: "고등학교",
    grade: "2",
    className: "1",
  };

  it("normalizes valid timetable query strings", () => {
    expect(timetableQuerySchema.parse(valid)).toEqual({ ...valid, grade: 2, className: 1 });
    expect(
      timetableQuerySchema.parse({ ...valid, kind: "특수학교", grade: "6" }),
    ).toMatchObject({ kind: "특수학교", grade: 6 });
  });

  it.each([
    [{ ...valid, officeCode: "https://evil.test" }, "external URL"],
    [{ ...valid, grade: "4" }, "high-school grade"],
    [{ ...valid, className: "21" }, "class range"],
    [{ ...valid, kind: "대학교" }, "school kind"],
  ])("rejects invalid %s", (input) => {
    expect(timetableQuerySchema.safeParse(input).success).toBe(false);
  });

  it("trims school names and rejects missing, short, or oversized input", () => {
    expect(schoolSearchSchema.parse({ name: "  미래초등학교 " })).toEqual({ name: "미래초등학교" });
    expect(schoolSearchSchema.safeParse({}).success).toBe(false);
    expect(schoolSearchSchema.safeParse({ name: "학" }).success).toBe(false);
    expect(schoolSearchSchema.safeParse({ name: "가".repeat(51) }).success).toBe(false);
  });
});

describe("speech generation", () => {
  const base = {
    date: "2026-09-22",
    school: { name: "테스트고등학교", kind: "고등학교" as const },
    grade: 2,
    className: 1,
  };

  it("reads lessons in period order", () => {
    expect(
      timetableToSpeech({
        ...base,
        lessons: [
          { period: 2, subject: " 영어 " },
          { period: 1, subject: "자료구조" },
        ],
      }),
    ).toBe("오늘 시간표는 1교시 자료구조, 2교시 영어입니다.");
  });

  it("gives a natural empty-day explanation", () => {
    expect(timetableToSpeech({ ...base, lessons: [] })).toContain("오늘 등록된 시간표가 없습니다");
  });

  it("reads a merged elective period without losing its guidance", () => {
    expect(
      timetableToSpeech({
        ...base,
        lessons: [{ period: 3, subject: "음악 또는 체육 (선택·이동 수업 가능)" }],
      }),
    ).toBe("오늘 시간표는 3교시 음악 또는 체육 (선택·이동 수업 가능)입니다.");
  });

  it("guides Siri users back to settings when a school no longer exists", () => {
    expect(voiceErrorMessage("NOT_FOUND")).toContain("학교 설정이 올바르지 않습니다");
  });
});

describe("rate limiter", () => {
  it("limits within a window and resets afterward", () => {
    const limiter = new MemoryRateLimiter(2, 1_000);
    expect(limiter.check("client", 0).allowed).toBe(true);
    expect(limiter.check("client", 1).allowed).toBe(true);
    expect(limiter.check("client", 2)).toMatchObject({ allowed: false, remaining: 0 });
    expect(limiter.check("client", 1_001).allowed).toBe(true);
  });

  it("does not trust spoofable proxy headers by default", () => {
    const request = new Request("http://localhost", {
      headers: { "x-forwarded-for": "203.0.113.1", "x-real-ip": "203.0.113.2" },
    });
    expect(clientIdentifier(request)).toBe("untrusted-client");
  });

  it("uses validated client IPs only when a trusted proxy is explicitly configured", () => {
    process.env.TRUST_PROXY_HEADERS = "true";
    const valid = new Request("http://localhost", { headers: { "x-forwarded-for": "203.0.113.1, 10.0.0.1" } });
    const invalid = new Request("http://localhost", { headers: { "x-forwarded-for": "attacker-value" } });
    expect(clientIdentifier(valid)).toBe("203.0.113.1");
    expect(clientIdentifier(invalid)).toBe("unknown-client");
    delete process.env.TRUST_PROXY_HEADERS;
  });
});

describe("memory cache", () => {
  it("coalesces concurrent loads and expires cached values", async () => {
    const cache = new MemoryCache<number>();
    let loads = 0;
    const load = async (): Promise<number> => {
      loads += 1;
      return 42;
    };
    const [first, second] = await Promise.all([
      cache.getOrLoad("same", 1_000, load),
      cache.getOrLoad("same", 1_000, load),
    ]);
    expect([first, second]).toEqual([42, 42]);
    expect(loads).toBe(1);
    expect(cache.get("same", Date.now() + 1_001)).toBeUndefined();
  });
});
