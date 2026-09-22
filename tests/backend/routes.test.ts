import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET as healthRoute } from "@/app/api/health/route";
import { GET as classesRoute } from "@/app/api/classes/route";
import { GET as schoolsRoute } from "@/app/api/schools/route";
import { GET as timetableRoute } from "@/app/api/timetable/today/route";
import { clearVoiceRateLimit, GET as voiceRoute } from "@/app/api/voice/timetable/route";
import { clearNeisCaches } from "@/lib/neis";
import { clearRateLimits } from "@/lib/request-guard";

const validQuery = "officeCode=B10&schoolCode=7010911&kind=%EA%B3%A0%EB%93%B1%ED%95%99%EA%B5%90&grade=2&className=1";

function request(path: string, ip = "127.0.0.1"): Request {
  return new Request(`http://localhost${path}`, { headers: { "x-forwarded-for": ip } });
}

function neisResponse(dataset: string, rows: ReadonlyArray<Record<string, string>>): Response {
  return new Response(
    JSON.stringify({
      [dataset]: [
        { head: [{ RESULT: { CODE: "INFO-000", MESSAGE: "정상" } }] },
        { row: rows },
      ],
    }),
  );
}

beforeEach(() => {
  clearNeisCaches();
  clearRateLimits();
  clearVoiceRateLimit();
  vi.stubEnv("NEIS_API_KEY", "route-test-key");
  vi.stubEnv("NEIS_MOCK_MODE", "false");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("API routes", () => {
  it("reports health without revealing configuration secrets", async () => {
    const response = healthRoute();
    const copy = response.clone();
    expect(response.status).toBe(200);
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(await response.json()).toMatchObject({
      status: "ok",
      neis: { configured: true, mode: "live" },
    });
    expect(await copy.text()).not.toContain("route-test-key");
  });

  it.each([
    ["", "true", "ok", false, "mock"],
    ["", "false", "degraded", false, "unconfigured"],
    ["present", "true", "ok", false, "mock"],
  ] as const)(
    "reports key=%s mock=%s as %s/%s",
    async (apiKey, mockMode, status, configured, mode) => {
      vi.stubEnv("NEIS_API_KEY", apiKey);
      vi.stubEnv("NEIS_MOCK_MODE", mockMode);
      const response = healthRoute();
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({ status, neis: { configured, mode } });
    },
  );

  it("searches schools and never returns the upstream API key", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        neisResponse("schoolInfo", [
          {
            ATPT_OFCDC_SC_CODE: "B10",
            SD_SCHUL_CODE: "7010911",
            SCHUL_NM: "한세사이버보안고등학교",
            SCHUL_KND_SC_NM: "고등학교",
            ORG_RDNMA: "서울특별시 마포구",
            ATPT_OFCDC_SC_NM: "서울특별시교육청",
          },
        ]),
      ),
    );
    const response = await schoolsRoute(request("/api/schools?name=한세사이버보안고"));
    const text = await response.text();
    expect(response.status).toBe(200);
    expect(JSON.parse(text)).toMatchObject({ schools: [{ schoolCode: "7010911" }] });
    expect(text).not.toContain("route-test-key");
  });

  it("passes an allowlisted office to NEIS schoolInfo", async () => {
    let requestedUrl: URL | undefined;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input) => {
        requestedUrl = new URL(String(input));
        return new Response(JSON.stringify({ RESULT: { CODE: "INFO-200", MESSAGE: "없음" } }));
      }),
    );
    const response = await schoolsRoute(request("/api/schools?officeCode=C10&name=미래학교"));
    expect(response.status).toBe(200);
    expect(requestedUrl?.pathname).toBe("/hub/schoolInfo");
    expect(requestedUrl?.searchParams.get("ATPT_OFCDC_SC_CODE")).toBe("C10");
  });

  it("returns NEIS-confirmed classes separated by department", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => neisResponse("classInfo", [
        { GRADE: "2", CLASS_NM: "1", DDDEP_NM: "클라우드보안과" },
        { GRADE: "2", CLASS_NM: "1", DDDEP_NM: "메타버스게임과" },
      ])),
    );
    const response = await classesRoute(
      request("/api/classes?officeCode=B10&schoolCode=7010911", "127.0.0.9"),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      classes: [
        { grade: 2, className: "1", department: "메타버스게임과" },
        { grade: 2, className: "1", department: "클라우드보안과" },
      ],
    });
  });

  it("does not force an office into an all-region school search", async () => {
    let requestedUrl: URL | undefined;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input) => {
        requestedUrl = new URL(String(input));
        return new Response(JSON.stringify({ RESULT: { CODE: "INFO-200", MESSAGE: "없음" } }));
      }),
    );
    const response = await schoolsRoute(request("/api/schools?name=미래학교"));
    expect(response.status).toBe(200);
    expect(requestedUrl?.searchParams.has("ATPT_OFCDC_SC_CODE")).toBe(false);
  });

  it("rejects an unknown education office before calling upstream", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await schoolsRoute(request("/api/schools?officeCode=Z10&name=미래학교"));
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: { code: "INVALID_INPUT" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("returns a configuration error instead of silently using mock data", async () => {
    vi.stubEnv("NEIS_API_KEY", "");
    vi.stubEnv("NEIS_MOCK_MODE", "false");
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await schoolsRoute(request("/api/schools?name=테스트학교"));
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: { code: "NEIS_NOT_CONFIGURED" } });
  });

  it("returns mock data only when mock mode is explicitly enabled", async () => {
    vi.stubEnv("NEIS_API_KEY", "");
    vi.stubEnv("NEIS_MOCK_MODE", "true");
    const response = await schoolsRoute(request("/api/schools?officeCode=C10&name=부산미래"));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      schools: [{ officeCode: "C10", name: "부산미래중학교" }],
    });
  });

  it("rejects a missing school search query", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await schoolsRoute(request("/api/schools"));
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: { code: "INVALID_INPUT" } });
  });

  it("returns a sorted, deduplicated timetable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        neisResponse("hisTimetable", [
          { SCHUL_NM: "한세사이버보안고등학교", PERIO: "2", ITRT_CNTNT: "영어" },
          { SCHUL_NM: "한세사이버보안고등학교", PERIO: "1", ITRT_CNTNT: "자료구조" },
          { SCHUL_NM: "한세사이버보안고등학교", PERIO: "1", ITRT_CNTNT: "자료구조" },
        ]),
      ),
    );
    const response = await timetableRoute(request(`/api/timetable/today?${validQuery}`));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      school: { name: "한세사이버보안고등학교", kind: "고등학교" },
      grade: 2,
      className: "1",
      lessons: [
        { period: 1, subject: "자료구조" },
        { period: 2, subject: "영어" },
      ],
    });
  });

  it("rejects upstream rows that contradict the requested class", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input) => {
        const url = new URL(String(input));
        if (url.pathname.endsWith("/schoolInfo")) {
          return neisResponse("schoolInfo", [
            {
              ATPT_OFCDC_SC_CODE: "B10",
              SD_SCHUL_CODE: "7010911",
              SCHUL_NM: "한세사이버보안고등학교",
              SCHUL_KND_SC_NM: "고등학교",
            },
          ]);
        }
        return neisResponse("hisTimetable", [
          {
            ATPT_OFCDC_SC_CODE: "B10",
            SD_SCHUL_CODE: "7010911",
            ALL_TI_YMD: "20260922",
            GRADE: "2",
            CLASS_NM: "9",
            SCHUL_NM: "한세사이버보안고등학교",
            PERIO: "1",
            ITRT_CNTNT: "다른 반 수업",
          },
        ]);
      }),
    );

    const response = await timetableRoute(request(`/api/timetable/today?${validQuery}`));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ lessons: [] });
  });

  it("rejects invalid grade and class input before an upstream request", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await timetableRoute(
      request(`/api/timetable/today?${validQuery.replace("grade=2", "grade=4")}`),
    );
    expect(response.status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });

  it("keeps a documented empty timetable distinct from an error", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input) => {
        const url = new URL(String(input));
        if (url.pathname.endsWith("/schoolInfo")) {
          return neisResponse("schoolInfo", [
            {
              ATPT_OFCDC_SC_CODE: "B10",
              SD_SCHUL_CODE: "7010911",
              SCHUL_NM: "한세사이버보안고등학교",
              SCHUL_KND_SC_NM: "고등학교",
              ORG_RDNMA: "서울특별시 마포구",
              ATPT_OFCDC_SC_NM: "서울특별시교육청",
            },
          ]);
        }
        return new Response(JSON.stringify({ RESULT: { CODE: "INFO-200", MESSAGE: "데이터 없음" } }));
      }),
    );
    const response = await timetableRoute(request(`/api/timetable/today?${validQuery}`));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      school: { name: "한세사이버보안고등학교" },
      lessons: [],
    });
  });

  it("distinguishes an unknown school setting from an empty school day", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(JSON.stringify({ RESULT: { CODE: "INFO-200", MESSAGE: "데이터 없음" } })),
      ),
    );
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await timetableRoute(
      request(`/api/timetable/today?${validQuery.replace("7010911", "9999999")}`, "127.0.0.8"),
    );
    expect(response.status).toBe(404);
    expect(await response.json()).toMatchObject({ error: { code: "NOT_FOUND" } });
  });

  it("returns a safe gateway error when NEIS reports an error", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(JSON.stringify({ RESULT: { CODE: "ERROR-300", MESSAGE: "bad route-test-key" } })),
      ),
    );
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await timetableRoute(request(`/api/timetable/today?${validQuery}`));
    const text = await response.text();
    expect(response.status).toBe(502);
    expect(text).toContain("NEIS_ERROR");
    expect(text).not.toContain("route-test-key");
  });

  it("reports an invalid upstream API key distinctly and safely", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(JSON.stringify({ RESULT: { CODE: "ERROR-290", MESSAGE: "bad route-test-key" } })),
      ),
    );
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await schoolsRoute(request("/api/schools?name=테스트학교"));
    const text = await response.text();
    expect(response.status).toBe(502);
    expect(text).toContain("NEIS_AUTH_ERROR");
    expect(text).not.toContain("route-test-key");
  });

  it("returns a safe timeout response when NEIS does not respond", async () => {
    vi.useFakeTimers();
    vi.stubGlobal(
      "fetch",
      vi.fn((_input: RequestInfo | URL, init?: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () =>
            reject(new DOMException("The operation was aborted", "AbortError")),
          );
        }),
      ),
    );
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const assertion = expect(
      timetableRoute(request(`/api/timetable/today?${validQuery}`, "127.0.0.7")),
    ).resolves.toMatchObject({ status: 504 });
    await vi.runAllTimersAsync();
    await assertion;
    vi.useRealTimers();
  });

  it("returns UTF-8 plain text from the voice endpoint", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        neisResponse("hisTimetable", [
          { SCHUL_NM: "한세사이버보안고등학교", PERIO: "1", ITRT_CNTNT: "자료구조" },
        ]),
      ),
    );
    const response = await voiceRoute(request(`/api/voice/timetable?${validQuery}`, "127.0.0.2"));
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    expect(await response.text()).toBe("오늘 시간표는 1교시 자료구조입니다.");
  });

  it("returns a natural plain-text error for an invalid voice URL", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await voiceRoute(request("/api/voice/timetable?officeCode=bad%2Furl", "127.0.0.3"));
    expect(response.status).toBe(400);
    expect(response.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    expect(await response.text()).toContain("학교 설정이 올바르지 않습니다");
  });

  it("rate limits excessive school search requests", async () => {
    vi.stubEnv("NEIS_API_KEY", "");
    vi.stubEnv("NEIS_MOCK_MODE", "true");
    const ip = "127.0.0.4";
    for (let index = 0; index < 60; index += 1) {
      const allowed = await schoolsRoute(request("/api/schools?name=테스트학교", ip));
      expect(allowed.status).toBe(200);
    }
    const response = await schoolsRoute(request("/api/schools?name=테스트학교", ip));
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBeTruthy();
  });
});
