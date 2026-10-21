import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { GET } from "@/app/api/calendar/range/route";
import { clearNeisCaches, getSchoolEvents, NeisClient, parseSchoolEvents } from "@/lib/neis";
import { clearRateLimits } from "@/lib/request-guard";

const query = { officeCode: "B10" as const, schoolCode: "7010911" };
const date = "2026-03-03";
const row = {
  ATPT_OFCDC_SC_CODE: "B10", SD_SCHUL_CODE: "7010911", AA_YMD: "20260303",
  SCHUL_NM: "학교", EVENT_NM: "입학식", EVENT_CNTNT: "안내<br/>둘째 줄",
  SBTR_DD_SC_NM: "해당없음", DGHT_CRSE_SC_NM: "주간", SCHUL_CRSE_SC_NM: "고등학교",
  ONE_GRADE_EVENT_YN: "Y", TW_GRADE_EVENT_YN: "Y", THREE_GRADE_EVENT_YN: "Y",
  FR_GRADE_EVENT_YN: "*", FIV_GRADE_EVENT_YN: "*", SIX_GRADE_EVENT_YN: "*",
};
function payload(rows: Record<string, unknown>[], total = rows.length) {
  return { SchoolSchedule: [{ head: [{ list_total_count: total }, { RESULT: { CODE: "INFO-000" } }] }, { row: rows }] };
}
const json = (value: unknown) => new Response(JSON.stringify(value));
const result = (code: string) => ({ RESULT: { CODE: code, MESSAGE: "calendar-secret" } });
function request(from = date, to = from, school = "7010911") {
  return new Request(`http://localhost/api/calendar/range?officeCode=B10&schoolCode=${school}&from=${from}&to=${to}`);
}
beforeEach(() => {
  clearNeisCaches();
  clearRateLimits();
  vi.stubEnv("NEIS_API_KEY", "calendar-secret");
  vi.stubEnv("NEIS_MOCK_MODE", "false");
  vi.spyOn(console, "error").mockImplementation(() => undefined);
});
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

it("preserves raw grade flags, null/empty details, distinct names and course scopes", () => {
  const events = parseSchoolEvents(payload([row, { ...row, EVENT_NM: "개학식", EVENT_CNTNT: null },
    { ...row, DGHT_CRSE_SC_NM: "야간", EVENT_CNTNT: "" }, { ...row, EVENT_NM: "" }]));
  expect(events).toEqual([
    { name: "입학식", content: "안내\n둘째 줄", lessonDayType: "해당없음", dayNightCourse: "주간", schoolCourse: "고등학교", gradeFlags: ["Y", "Y", "Y", "*", "*", "*"] },
    { name: "개학식", content: "", lessonDayType: "해당없음", dayNightCourse: "주간", schoolCourse: "고등학교", gradeFlags: ["Y", "Y", "Y", "*", "*", "*"] },
    { name: "입학식", content: "", lessonDayType: "해당없음", dayNightCourse: "야간", schoolCourse: "고등학교", gradeFlags: ["Y", "Y", "Y", "*", "*", "*"] },
  ]);
});

it("uses exact AA_YMD and filters mismatched or missing identities and dates", async () => {
  const upstream = vi.fn(async (input: RequestInfo | URL) => {
    const url = new URL(String(input));
    expect(url.pathname).toBe("/hub/SchoolSchedule");
    expect(url.searchParams.get("AA_YMD")).toBe("20260303");
    expect(url.searchParams.has("AA_FROM_YMD")).toBe(false);
    return json(payload([row, { ...row, ATPT_OFCDC_SC_CODE: "C10" }, { ...row, SD_SCHUL_CODE: "wrong" },
      { ...row, AA_YMD: "20260304" }, { ...row, AA_YMD: "" }]));
  });
  const client = new NeisClient({ fetchImplementation: upstream });
  expect((await client.getSchoolEvents(query, date)).events).toHaveLength(1);
});

it("loads all schedule pages without combining events", async () => {
  const upstream = vi.fn(async (input: RequestInfo | URL) => {
    const page = new URL(String(input)).searchParams.get("pIndex");
    return json(payload(page === "1" ? Array.from({ length: 1000 }, () => row) : [{ ...row, EVENT_NM: "마지막" }], 1001));
  });
  const response = await new NeisClient({ fetchImplementation: upstream }).getSchoolEvents(query, date);
  expect(response.events).toHaveLength(1001);
  expect(response.events[1000]?.name).toBe("마지막");
});

it.each([true, false])("empty dataset resolves school fallback (known=%s)", async (known) => {
  vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
    if (String(input).includes("/SchoolSchedule?")) return json(result("INFO-200"));
    return json({ schoolInfo: [{ row: known ? [{ ...row, SCHUL_KND_SC_NM: "고등학교" }] : [] }] });
  }));
  const response = await GET(request());
  expect(response.status).toBe(known ? 200 : 404);
  if (known) expect(await response.json()).toEqual({ from: date, to: date, days: [{ date, school: { name: "학교" }, events: [] }] });
});

it("requires configuration and only returns labeled examples in explicit mock mode", async () => {
  await expect(new NeisClient({ apiKey: "", mockMode: false }).getSchoolEvents(query, date)).rejects.toMatchObject({ code: "NEIS_NOT_CONFIGURED" });
  expect((await new NeisClient({ apiKey: "", mockMode: true }).getSchoolEvents(query, date)).events[0]?.name).toContain("예시");
});

it("isolates cache by office, school and date and expires after ten minutes", async () => {
  vi.useFakeTimers();
  const upstream = vi.fn(async (input: RequestInfo | URL) => {
    const params = new URL(String(input)).searchParams;
    return json(payload([{ ...row, ATPT_OFCDC_SC_CODE: params.get("ATPT_OFCDC_SC_CODE"), SD_SCHUL_CODE: params.get("SD_SCHUL_CODE"), AA_YMD: params.get("AA_YMD") }]));
  });
  vi.stubGlobal("fetch", upstream);
  await getSchoolEvents(query, date);
  await getSchoolEvents(query, date);
  await getSchoolEvents({ ...query, officeCode: "C10" }, date);
  await getSchoolEvents({ ...query, schoolCode: "7010999" }, date);
  await getSchoolEvents(query, "2026-03-04");
  expect(upstream).toHaveBeenCalledTimes(4);
  vi.advanceTimersByTime(600_001);
  await getSchoolEvents(query, date);
  expect(upstream).toHaveBeenCalledTimes(5);
});

it.each([[date, date], ["2026-03-01", "2026-03-07"], ["2028-02-28", "2028-03-01"]])("returns inclusive bounded range %s–%s", async (from, to) => {
  vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => json(payload([{ ...row, AA_YMD: new URL(String(input)).searchParams.get("AA_YMD") }]))));
  const response = await GET(request(from, to));
  expect(response.status).toBe(200);
  expect(response.headers.get("cache-control")).toBe("private, max-age=60");
  const body = await response.json();
  expect(body.days[0].date).toBe(from);
  expect(body.days.at(-1).date).toBe(to);
  expect(body.days).toHaveLength((Date.parse(to) - Date.parse(from)) / 86400000 + 1);
  expect(JSON.stringify(body)).not.toContain("calendar-secret");
});

it.each([["2026-03-01", "2026-03-08", "7010911"], [date, "2026-03-02", "7010911"], ["2026-02-30", date, "7010911"], [date, date, "bad/url"], ["", date, "7010911"]])("rejects invalid input before upstream %s %s %s", async (from, to, school) => {
  const upstream = vi.fn(); vi.stubGlobal("fetch", upstream);
  expect((await GET(request(from, to, school))).status).toBe(400);
  expect(upstream).not.toHaveBeenCalled();
});

it("returns a safe atomic error rather than successful partial days and does not cache failures", async () => {
  const upstream = vi.fn(async (input: RequestInfo | URL) => new URL(String(input)).searchParams.get("AA_YMD") === "20260303"
    ? json(payload([row])) : json(result("ERROR-290")));
  vi.stubGlobal("fetch", upstream);
  const response = await GET(request(date, "2026-03-04"));
  expect(response.status).toBe(502);
  const body = await response.json();
  expect(body.error.code).toBe("NEIS_AUTH_ERROR");
  expect(body.days).toBeUndefined();
  expect(JSON.stringify(body)).not.toContain("calendar-secret");
  upstream.mockImplementation(async () => json(payload([{ ...row, AA_YMD: "20260304" }])));
  expect((await GET(request("2026-03-04"))).status).toBe(200);
});

it("enforces the shared 60-request limit before validation", async () => {
  const upstream = vi.fn(); vi.stubGlobal("fetch", upstream);
  for (let index = 0; index < 60; index++) expect((await GET(request("bad"))).status).toBe(400);
  expect((await GET(request("bad"))).status).toBe(429);
  expect(upstream).not.toHaveBeenCalled();
});
