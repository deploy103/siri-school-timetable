import { afterEach, describe, expect, it, vi } from "vitest";
import { AppError } from "@/lib/errors";
import type { TimetableQuery } from "@/lib/schemas";
import {
  NeisClient,
  clearNeisCaches,
  extractNeisRows,
  parseLessons,
  parseSchools,
  timetableDataset,
  searchSchools,
} from "@/lib/neis";

const query: TimetableQuery = {
  officeCode: "B10",
  schoolCode: "7010911",
  kind: "고등학교" as const,
  grade: 2,
  className: "1",
};

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  clearNeisCaches();
});

describe("NEIS dataset mapping", () => {
  it.each([
    ["초등학교", "elsTimetable"],
    ["중학교", "misTimetable"],
    ["고등학교", "hisTimetable"],
    ["특수학교", "spsTimetable"],
  ] as const)("maps %s to %s", (kind, expected) => {
    expect(timetableDataset(kind)).toBe(expected);
  });
});

describe("NEIS parsing", () => {
  it("parses, deduplicates, and sorts supported schools", () => {
    const row = {
      ATPT_OFCDC_SC_CODE: "B10",
      SD_SCHUL_CODE: "7010911",
      SCHUL_NM: " 한세사이버보안고등학교 ",
      SCHUL_KND_SC_NM: "고등학교",
      ORG_RDNMA: "서울특별시 마포구",
      ATPT_OFCDC_SC_NM: "서울특별시교육청",
    };
    const payload = {
      schoolInfo: [
        { head: [{ RESULT: { CODE: "INFO-000", MESSAGE: "정상 처리되었습니다." } }] },
        { row: [row, row, { ...row, SD_SCHUL_CODE: "", SCHUL_NM: "무효" }] },
      ],
    };
    expect(parseSchools(payload)).toEqual([
      {
        officeCode: "B10",
        schoolCode: "7010911",
        name: "한세사이버보안고등학교",
        kind: "고등학교",
        address: "서울특별시 마포구",
        region: "서울특별시교육청",
      },
    ]);
  });

  it("treats the documented no-data result as an empty dataset", () => {
    expect(extractNeisRows({ RESULT: { CODE: "INFO-200", MESSAGE: "해당하는 데이터가 없습니다." } }, "schoolInfo")).toEqual([]);
  });

  it("accepts documented INFO-100 responses when row data is present", () => {
    const rows = extractNeisRows(
      {
        schoolInfo: [
          { head: [{ RESULT: { CODE: "INFO-100", MESSAGE: "인증키 없이 호출" } }] },
          { row: [{ SCHUL_NM: "서울미래초등학교" }] },
        ],
      },
      "schoolInfo",
    );
    expect(rows).toEqual([{ SCHUL_NM: "서울미래초등학교" }]);
  });

  it("does not disguise a NEIS error as an empty result", () => {
    expect(() =>
      extractNeisRows({ RESULT: { CODE: "ERROR-300", MESSAGE: "KEY 오류" } }, "schoolInfo"),
    ).toThrowError(AppError);
  });

  it.each([
    ["ERROR-290", "NEIS_AUTH_ERROR", 502],
    ["ERROR-337", "NEIS_QUOTA_EXCEEDED", 503],
    ["INFO-300", "NEIS_AUTH_ERROR", 502],
    ["ERROR-300", "NEIS_ERROR", 502],
    ["ERROR-310", "NEIS_ERROR", 502],
    ["ERROR-333", "NEIS_ERROR", 502],
    ["ERROR-336", "NEIS_ERROR", 502],
    ["ERROR-500", "NEIS_UNAVAILABLE", 503],
    ["ERROR-600", "NEIS_UNAVAILABLE", 503],
    ["ERROR-601", "NEIS_UNAVAILABLE", 503],
  ])("maps logical result %s to %s", (upstreamCode, expectedCode, status) => {
    expect(() =>
      extractNeisRows({ RESULT: { CODE: upstreamCode, MESSAGE: "sensitive upstream text" } }, "schoolInfo"),
    ).toThrowError(
      expect.objectContaining({ code: expectedCode, status }),
    );
  });

  it("returns every distinct same-name school", () => {
    const base = {
      SCHUL_NM: "미래초등학교",
      SCHUL_KND_SC_NM: "초등학교",
      ORG_RDNMA: "테스트로 1",
      LCTN_SC_NM: "테스트시",
    };
    const schools = parseSchools({
      schoolInfo: [
        { head: [{ RESULT: { CODE: "INFO-000", MESSAGE: "정상" } }] },
        {
          row: [
            { ...base, ATPT_OFCDC_SC_CODE: "B10", ATPT_OFCDC_SC_NM: "서울특별시교육청", SD_SCHUL_CODE: "1" },
            { ...base, ATPT_OFCDC_SC_CODE: "C10", ATPT_OFCDC_SC_NM: "부산광역시교육청", SD_SCHUL_CODE: "2" },
          ],
        },
      ],
    });
    expect(schools).toHaveLength(2);
    expect(new Set(schools.map(({ officeCode }) => officeCode))).toEqual(new Set(["B10", "C10"]));
    expect(schools[0]).toMatchObject({ locality: "테스트시" });
  });

  it("sorts periods, collapses exact duplicates, and surfaces elective alternatives", () => {
    expect(
      parseLessons([
        { PERIO: "3", ITRT_CNTNT: " 체육 " },
        { PERIO: "1", ITRT_CNTNT: "  자료구조  " },
        { PERIO: "1", ITRT_CNTNT: "자료구조" },
        { PERIO: "3", ITRT_CNTNT: "음악" },
        { PERIO: "x", ITRT_CNTNT: "무효" },
        { PERIO: "21", ITRT_CNTNT: "무효" },
        { PERIO: "2", ITRT_CNTNT: "  " },
      ]),
    ).toEqual([
      { period: 1, subject: "자료구조" },
      { period: 3, subject: "음악 또는 체육 (선택·이동 수업 가능)" },
    ]);
  });

  it("bounds the merged elective description", () => {
    const lessons = parseLessons(
      Array.from({ length: 10 }, (_, index) => ({
        PERIO: "1",
        ITRT_CNTNT: `매우 긴 선택 과목 이름 ${String(index).padStart(2, "0")} ${"가".repeat(60)}`,
      })),
    );
    expect(lessons[0]?.subject.length).toBeLessThanOrEqual(100);
    expect(lessons[0]?.subject).toContain("외");
    expect(lessons[0]?.subject).toContain("선택·이동 수업 가능");
  });
});

describe("NeisClient", () => {
  it("logs explicit mock mode in production without logging an API key", () => {
    vi.stubEnv("NODE_ENV", "production");
    const warning = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    new NeisClient({ apiKey: "must-not-appear", mockMode: true });
    expect(warning).toHaveBeenCalledWith("NEIS mock mode enabled");
    expect(warning.mock.calls.flat().join(" ")).not.toContain("must-not-appear");
  });

  it("adds the selected office to schoolInfo but omits it for an all-region search", async () => {
    const requested: URL[] = [];
    const fetchImplementation: typeof fetch = vi.fn(async (input) => {
      requested.push(new URL(String(input)));
      return new Response(JSON.stringify({ RESULT: { CODE: "INFO-200", MESSAGE: "없음" } }));
    });
    const client = new NeisClient({ apiKey: "secret-key", fetchImplementation, maxAttempts: 1 });

    await client.searchSchools("미래학교", "B10");
    await client.searchSchools("미래학교");

    expect(requested[0]?.searchParams.get("ATPT_OFCDC_SC_CODE")).toBe("B10");
    expect(requested[0]?.searchParams.get("SCHUL_NM")).toBe("미래학교");
    expect(requested[0]?.searchParams.get("pSize")).toBe("100");
    expect(requested[1]?.searchParams.has("ATPT_OFCDC_SC_CODE")).toBe(false);
  });

  it("uses only the fixed HTTPS host and correct timetable parameters", async () => {
    let requestedUrl = "";
    const fetchImplementation: typeof fetch = vi.fn(async (input) => {
      requestedUrl = String(input);
      return new Response(
        JSON.stringify({
          hisTimetable: [
            { head: [{ RESULT: { CODE: "INFO-000", MESSAGE: "정상" } }] },
            { row: [{ SCHUL_NM: "한세사이버보안고등학교", PERIO: "1", ITRT_CNTNT: "자료구조" }] },
          ],
        }),
      );
    });
    const client = new NeisClient({ apiKey: "secret-key", fetchImplementation, maxAttempts: 1 });
    await client.getTodayTimetable(query, "2026-09-22");

    const url = new URL(requestedUrl);
    expect(url.origin).toBe("https://open.neis.go.kr");
    expect(url.pathname).toBe("/hub/hisTimetable");
    expect(url.searchParams.get("ALL_TI_YMD")).toBe("20260922");
    expect(url.searchParams.get("GRADE")).toBe("2");
    expect(url.searchParams.get("CLASS_NM")).toBe("1");
  });

  it("retries a transient failure only up to the configured limit", async () => {
    const fetchImplementation: typeof fetch = vi.fn(async () => new Response("down", { status: 503 }));
    const client = new NeisClient({
      apiKey: "secret-key",
      fetchImplementation,
      maxAttempts: 2,
      retryDelayMs: 0,
    });
    await expect(client.searchSchools("테스트학교")).rejects.toMatchObject({ code: "NEIS_UNAVAILABLE" });
    expect(fetchImplementation).toHaveBeenCalledTimes(2);
  });

  it("retries transient NEIS logical server errors", async () => {
    const fetchImplementation: typeof fetch = vi.fn(async () =>
      new Response(JSON.stringify({ RESULT: { CODE: "ERROR-500", MESSAGE: "server error" } })),
    );
    const client = new NeisClient({
      apiKey: "secret-key",
      fetchImplementation,
      maxAttempts: 2,
      retryDelayMs: 0,
    });
    await expect(client.searchSchools("테스트학교")).rejects.toMatchObject({
      code: "NEIS_UNAVAILABLE",
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(2);
  });

  it("does not retry a non-transient upstream HTTP error", async () => {
    const fetchImplementation: typeof fetch = vi.fn(async () => new Response("bad request", { status: 400 }));
    const client = new NeisClient({
      apiKey: "secret-key",
      fetchImplementation,
      maxAttempts: 3,
      retryDelayMs: 0,
    });
    await expect(client.searchSchools("테스트학교")).rejects.toMatchObject({ code: "NEIS_ERROR" });
    expect(fetchImplementation).toHaveBeenCalledTimes(1);
  });

  it("aborts an upstream request after the timeout", async () => {
    vi.useFakeTimers();
    const fetchImplementation: typeof fetch = vi.fn((_input, init) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () =>
          reject(new DOMException("The operation was aborted", "AbortError")),
        );
      }),
    );
    const client = new NeisClient({
      apiKey: "secret-key",
      fetchImplementation,
      timeoutMs: 50,
      maxAttempts: 1,
    });
    const request = expect(client.searchSchools("테스트학교")).rejects.toMatchObject({
      code: "NEIS_TIMEOUT",
      status: 504,
    });
    await vi.advanceTimersByTimeAsync(51);
    await request;
  });

  it("rejects a missing key unless mock mode is explicitly enabled", async () => {
    const client = new NeisClient({ apiKey: "", mockMode: false });
    await expect(client.searchSchools("한세")).rejects.toMatchObject({
      code: "NEIS_NOT_CONFIGURED",
      status: 503,
    });
  });

  it("provides deterministic mock data only in explicit mock mode", async () => {
    const client = new NeisClient({ apiKey: "", mockMode: true });
    await expect(client.searchSchools("한세")).resolves.toHaveLength(1);
    const timetable = await client.getTodayTimetable(query, "2026-09-22");
    expect(timetable.school.name).toBe("한세사이버보안고등학교");
    expect(timetable.lessons[0]).toEqual({ period: 1, subject: "자료구조" });
  });

  it("keeps mock school searches separated by office", async () => {
    const client = new NeisClient({ mockMode: true });
    const all = await client.searchSchools("미래");
    const busan = await client.searchSchools("미래", "C10");
    expect(all.length).toBeGreaterThan(1);
    expect(busan).toEqual([
      expect.objectContaining({ officeCode: "C10", name: "부산미래중학교" }),
    ]);
  });

  it("distinguishes an invalid API key logical response from no data", async () => {
    const fetchImplementation: typeof fetch = vi.fn(async () =>
      new Response(JSON.stringify({ RESULT: { CODE: "ERROR-290", MESSAGE: "인증키 오류" } })),
    );
    const client = new NeisClient({ apiKey: "invalid", fetchImplementation, maxAttempts: 1 });
    await expect(client.searchSchools("테스트학교")).rejects.toMatchObject({
      code: "NEIS_AUTH_ERROR",
      status: 502,
    });
  });
});

describe("school search cache", () => {
  it("does not collide between all-region, Seoul, and Busan searches", async () => {
    vi.stubEnv("NEIS_API_KEY", "cache-test-key");
    vi.stubEnv("NEIS_MOCK_MODE", "false");
    const upstream = vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      const officeCode = url.searchParams.get("ATPT_OFCDC_SC_CODE") ?? "ALL";
      return new Response(
        JSON.stringify({
          schoolInfo: [
            { head: [{ RESULT: { CODE: "INFO-000", MESSAGE: "정상" } }] },
            {
              row: [{
                ATPT_OFCDC_SC_CODE: officeCode === "ALL" ? "J10" : officeCode,
                ATPT_OFCDC_SC_NM: `${officeCode} 교육청`,
                SD_SCHUL_CODE: `${officeCode}-school`,
                SCHUL_NM: "같은이름학교",
                SCHUL_KND_SC_NM: "고등학교",
              }],
            },
          ],
        }),
      );
    });
    vi.stubGlobal("fetch", upstream);

    const [all, seoul, busan] = await Promise.all([
      searchSchools("같은이름학교"),
      searchSchools("같은이름학교", "B10"),
      searchSchools("같은이름학교", "C10"),
    ]);
    const seoulAgain = await searchSchools("  같은이름학교  ", "B10");

    expect(all[0]?.officeCode).toBe("J10");
    expect(seoul[0]?.officeCode).toBe("B10");
    expect(busan[0]?.officeCode).toBe("C10");
    expect(seoulAgain[0]?.officeCode).toBe("B10");
    expect(upstream).toHaveBeenCalledTimes(3);
  });
});
