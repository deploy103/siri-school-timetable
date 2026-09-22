import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET as mealRoute } from "@/app/api/meal/today/route";
import { clearMealVoiceRateLimit, GET as mealVoiceRoute } from "@/app/api/voice/meal/route";
import { AppError } from "@/lib/errors";
import { clearNeisCaches, getTodayMeals, NeisClient, parseMeals } from "@/lib/neis";
import { clearRateLimits } from "@/lib/request-guard";
import { mealToSpeech, stripAllergenNotation } from "@/lib/voice";

const mealQuery = { officeCode: "B10" as const, schoolCode: "7010911" };

function neisPayload(rows: ReadonlyArray<Record<string, string>>) {
  return {
    mealServiceDietInfo: [
      { head: [{ RESULT: { CODE: "INFO-000", MESSAGE: "정상" } }] },
      { row: rows },
    ],
  };
}

function response(rows: ReadonlyArray<Record<string, string>>): Response {
  return new Response(JSON.stringify(neisPayload(rows)));
}

function request(path: string): Request {
  return new Request(`http://localhost${path}`);
}

const lunchRow = {
  ATPT_OFCDC_SC_CODE: "B10",
  SD_SCHUL_CODE: "7010911",
  SCHUL_NM: "한세사이버보안고등학교",
  MMEAL_SC_CODE: "2",
  MMEAL_SC_NM: "중식",
  MLSV_YMD: "20260922",
  DDISH_NM: "쌀밥<br/>미역국 (5.6)<br />제육볶음5.6.10.<BR>배추김치 (9)",
  CAL_INFO: "782.3 Kcal",
  NTR_INFO: "탄수화물(g) : 100<br/>단백질(g) : 30",
  ORPLC_INFO: "쌀 : 국내산<br />돼지고기 : 국내산",
};

beforeEach(() => {
  clearNeisCaches();
  clearRateLimits();
  clearMealVoiceRateLimit();
  vi.stubEnv("NEIS_API_KEY", "meal-test-key");
  vi.stubEnv("NEIS_MOCK_MODE", "false");
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-09-21T15:05:00.000Z"));
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("NEIS meal parsing", () => {
  it("parses safe dish text, calories, nutrition, and origin", () => {
    expect(parseMeals(neisPayload([lunchRow]))).toEqual([{
      code: "2",
      name: "중식",
      dishes: ["쌀밥", "미역국 (5.6)", "제육볶음5.6.10.", "배추김치 (9)"],
      calories: "782.3 Kcal",
      nutrition: "탄수화물(g) : 100\n단백질(g) : 30",
      origin: "쌀 : 국내산\n돼지고기 : 국내산",
    }]);
  });

  it("preserves and orders breakfast, lunch, and dinner", () => {
    const rows = [
      { ...lunchRow, MMEAL_SC_CODE: "3", MMEAL_SC_NM: "석식", DDISH_NM: "볶음밥" },
      { ...lunchRow, MMEAL_SC_CODE: "1", MMEAL_SC_NM: "조식", DDISH_NM: "죽" },
      lunchRow,
    ];
    expect(parseMeals(neisPayload(rows)).map(({ code, name }) => ({ code, name }))).toEqual([
      { code: "1", name: "조식" },
      { code: "2", name: "중식" },
      { code: "3", name: "석식" },
    ]);
  });

  it("treats INFO-200 as an empty meal day", () => {
    expect(parseMeals({ RESULT: { CODE: "INFO-200", MESSAGE: "자료 없음" } })).toEqual([]);
  });

  it("maps an invalid key to the existing authentication error", () => {
    expect(() => parseMeals({ RESULT: { CODE: "ERROR-290", MESSAGE: "secret" } })).toThrowError(
      expect.objectContaining({ code: "NEIS_AUTH_ERROR", status: 502 }),
    );
  });
});

describe("meal client policy", () => {
  it("requires a key when mock mode is off", async () => {
    const client = new NeisClient({ apiKey: "", mockMode: false });
    await expect(client.getTodayMeals(mealQuery, "2026-09-22")).rejects.toMatchObject({
      code: "NEIS_NOT_CONFIGURED",
      status: 503,
    } satisfies Partial<AppError>);
  });

  it("returns deterministic meals only in explicit mock mode", async () => {
    const client = new NeisClient({ apiKey: "", mockMode: true });
    const meals = await client.getTodayMeals(mealQuery, "2026-09-22");
    expect(meals).toMatchObject({
      date: "2026-09-22",
      school: { name: "한세사이버보안고등학교" },
      meals: [{ code: "2", name: "중식", dishes: ["쌀밥", "된장찌개 (5.6)", "제육볶음 (5.6.10)", "배추김치 (9)"] }],
    });
  });

  it("sends the KST date and existing school codes to the fixed meal endpoint", async () => {
    let requestedUrl: URL | undefined;
    const fetchImplementation = vi.fn(async (input: RequestInfo | URL) => {
      requestedUrl = new URL(String(input));
      return response([lunchRow]);
    });
    const client = new NeisClient({ apiKey: "test", mockMode: false, fetchImplementation });
    await client.getTodayMeals(mealQuery, "2026-09-22");
    expect(requestedUrl?.pathname).toBe("/hub/mealServiceDietInfo");
    expect(requestedUrl?.searchParams.get("ATPT_OFCDC_SC_CODE")).toBe("B10");
    expect(requestedUrl?.searchParams.get("SD_SCHUL_CODE")).toBe("7010911");
    expect(requestedUrl?.searchParams.get("MLSV_YMD")).toBe("20260922");
  });

  it("caches meals independently by date and school", async () => {
    const upstream = vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      const schoolCode = url.searchParams.get("SD_SCHUL_CODE") ?? "";
      const date = url.searchParams.get("MLSV_YMD") ?? "";
      return response([{ ...lunchRow, SD_SCHUL_CODE: schoolCode, MLSV_YMD: date }]);
    });
    vi.stubGlobal("fetch", upstream);

    await getTodayMeals(mealQuery, "2026-09-22");
    await getTodayMeals(mealQuery, "2026-09-22");
    await getTodayMeals(mealQuery, "2026-09-23");
    await getTodayMeals({ ...mealQuery, schoolCode: "7010999" }, "2026-09-22");
    expect(upstream).toHaveBeenCalledTimes(3);
  });
});

describe("Siri meal speech", () => {
  it.each([
    ["제육볶음 (5.6.10.13.18)", "제육볶음"],
    ["미역국5.6.", "미역국"],
    ["배추김치9.", "배추김치"],
  ])("removes only a trailing allergen group from %s", (dish, expected) => {
    expect(stripAllergenNotation(dish)).toBe(expected);
  });

  it.each(["2색나물", "3종과일", "비타민C음료", "10곡밥", "오징어게임2 떡볶이", "비타민 C 100."])(
    "preserves legitimate digits in %s",
    (dish) => expect(stripAllergenNotation(dish)).toBe(dish),
  );

  it("speaks one meal without allergens or nutrition", () => {
    const speech = mealToSpeech({ date: "2026-09-22", school: { name: "학교" }, meals: parseMeals(neisPayload([lunchRow])) });
    expect(speech).toBe("오늘 급식은 쌀밥, 미역국, 제육볶음, 배추김치입니다.");
    expect(speech).not.toContain("782.3");
  });

  it("names every available meal and handles an empty day", () => {
    const meals = parseMeals(neisPayload([
      { ...lunchRow, MMEAL_SC_CODE: "1", MMEAL_SC_NM: "조식", DDISH_NM: "죽 (1)" },
      lunchRow,
      { ...lunchRow, MMEAL_SC_CODE: "3", MMEAL_SC_NM: "석식", DDISH_NM: "볶음밥 (5.6)" },
    ]));
    expect(mealToSpeech({ date: "2026-09-22", school: { name: "학교" }, meals })).toBe(
      "오늘 조식은 죽, 중식은 쌀밥, 미역국, 제육볶음, 배추김치, 석식은 볶음밥입니다.",
    );
    expect(mealToSpeech({ date: "2026-09-22", school: { name: "학교" }, meals: [] })).toBe(
      "오늘 등록된 급식이 없습니다.",
    );
  });
});

describe("meal routes", () => {
  it("returns today's JSON meal using only the saved school codes", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => response([lunchRow])));
    const routeResponse = await mealRoute(request("/api/meal/today?officeCode=B10&schoolCode=7010911"));
    const text = await routeResponse.text();
    expect(routeResponse.status).toBe(200);
    expect(JSON.parse(text)).toMatchObject({
      date: "2026-09-22",
      school: { name: "한세사이버보안고등학교" },
      meals: [{ name: "중식", calories: "782.3 Kcal" }],
    });
    expect(text).not.toContain("meal-test-key");
  });

  it("returns UTF-8 plain text from the meal voice endpoint", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => response([lunchRow])));
    const routeResponse = await mealVoiceRoute(request("/api/voice/meal?officeCode=B10&schoolCode=7010911"));
    expect(routeResponse.status).toBe(200);
    expect(routeResponse.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    expect(await routeResponse.text()).toBe("오늘 급식은 쌀밥, 미역국, 제육볶음, 배추김치입니다.");
  });

  it("rejects invalid school codes before calling NEIS", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const routeResponse = await mealRoute(request("/api/meal/today?officeCode=Z10&schoolCode=bad/url"));
    expect(routeResponse.status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });
});
