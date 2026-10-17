import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET as timetable } from "@/app/api/timetable/range/route";
import { GET as meal } from "@/app/api/meal/range/route";
import { clearNeisCaches } from "@/lib/neis";
import { clearRateLimits } from "@/lib/request-guard";

const base = { officeCode: "B10", schoolCode: "7010911", kind: "고등학교", grade: "2", className: "1" };
function request(from: string, to: string, extra = {}) {
  return new Request(`http://localhost/api/range?${new URLSearchParams({ ...base, from, to, ...extra })}`);
}
function payload(dataset: string, rows: object[]) {
  return Response.json({ [dataset]: [{ row: rows }] });
}

beforeEach(() => {
  clearNeisCaches();
  clearRateLimits();
  vi.stubEnv("NEIS_API_KEY", "range-test-secret");
  vi.stubEnv("NEIS_MOCK_MODE", "false");
  vi.spyOn(console, "error").mockImplementation(() => {});
});
afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe.each([["timetable", timetable, "lessons"], ["meal", meal, "meals"]] as const)("%s range", (_name, route, field) => {
  function upstream(empty = false, failDate = "") {
    let active = 0;
    let maximum = 0;
    const dates: string[] = [];
    const fetcher = vi.fn(async (input: string | URL | Request) => {
      active++;
      maximum = Math.max(maximum, active);
      await Promise.resolve();
      active--;
      const url = new URL(String(input));
      const dataset = url.pathname.split("/").pop()!;
      if (dataset === "schoolInfo") return payload(dataset, [{ ...{
        ATPT_OFCDC_SC_CODE: "B10", SD_SCHUL_CODE: "7010911", SCHUL_NM: "학교", SCHUL_KND_SC_NM: "고등학교",
      } }]);
      const date = url.searchParams.get("ALL_TI_YMD") ?? url.searchParams.get("MLSV_YMD")!;
      dates.push(date);
      if (date === failDate) return Response.json({ RESULT: { CODE: "ERROR-300" } });
      if (empty) return Response.json({ RESULT: { CODE: "INFO-200" } });
      return payload(dataset, [{ SCHUL_NM: "학교", PERIO: "1", ITRT_CNTNT: date,
        MMEAL_SC_CODE: "2", MMEAL_SC_NM: "중식", DDISH_NM: date }]);
    });
    vi.stubGlobal("fetch", fetcher);
    return { fetcher, dates, maximum: () => maximum };
  }

  it.each([
    ["2024-02-28", "2024-03-01", ["2024-02-28", "2024-02-29", "2024-03-01"]],
    ["2026-12-31", "2027-01-02", ["2026-12-31", "2027-01-01", "2027-01-02"]],
    ["2026-01-01", "2026-01-07", Array.from({ length: 7 }, (_, i) => `2026-01-0${i + 1}`)],
  ])("returns every date in order across %s to %s", async (from, to, dates) => {
    const upstreamState = upstream();
    const response = await route(request(from, to));
    expect(response.status).toBe(200);
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    const body = await response.json();
    expect(body).toMatchObject({ from, to });
    expect(body.days.map((day: { date: string }) => day.date)).toEqual(dates);
    expect(body.days.every((day: Record<string, unknown[]>) => day[field]?.length === 1)).toBe(true);
    expect(upstreamState.dates).toEqual(dates.map((date) => date.replaceAll("-", "")));
    expect(upstreamState.maximum()).toBe(1);
  });

  it.each([
    ["2026-03-02", "2026-03-01"], ["2026-01-01", "2026-01-08"],
    ["2026-02-29", "2026-03-01"], ["2024-02-30", "2024-03-01"],
    ["2026-1-01", "2026-01-02"], ["", "2026-01-01"],
    ["2026-01-01", "2026-13-01"],
  ])("rejects invalid range %s/%s before upstream", async (from, to) => {
    const { fetcher } = upstream();
    const response = await route(request(from, to));
    expect(response.status).toBe(400);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toMatchObject({ error: { code: "INVALID_INPUT" } });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("retains known empty days without holiday claims, but rejects a failed day", async () => {
    upstream(true);
    const response = await route(request("2026-01-01", "2026-01-02"));
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.days).toHaveLength(2);
    for (const day of body.days) {
      expect(day[field]).toEqual([]);
      expect(day).not.toHaveProperty("holiday");
    }
    clearNeisCaches();
    const state = upstream(true, "20260102");
    const failed = await route(request("2026-01-01", "2026-01-03"));
    expect(failed.status).toBe(502);
    expect(failed.headers.get("cache-control")).toBe("no-store");
    const error = await failed.json();
    expect(error).toHaveProperty("error.code", "NEIS_ERROR");
    expect(error).not.toHaveProperty("days");
    expect(JSON.stringify(error)).not.toContain("range-test-secret");
    expect(state.dates).toEqual(["20260101", "20260102"]);
  });

  it("reuses daily caches while separating school and date identities", async () => {
    const { fetcher } = upstream();
    await route(request("2026-01-01", "2026-01-02"));
    expect(fetcher).toHaveBeenCalledTimes(2);
    await route(request("2026-01-02", "2026-01-03"));
    expect(fetcher).toHaveBeenCalledTimes(3);
    await route(request("2026-01-01", "2026-01-01", { schoolCode: "9999999" }));
    expect(fetcher).toHaveBeenCalledTimes(4);
    if (field === "lessons") {
      await route(request("2026-01-01", "2026-01-01", { className: "2" }));
      await route(request("2026-01-01", "2026-01-01", { department: "정보보안과" }));
      expect(fetcher).toHaveBeenCalledTimes(6);
      await route(request("2026-01-01", "2026-01-01", { department: "정보보안과" }));
      expect(fetcher).toHaveBeenCalledTimes(6);
    }
  });
});
