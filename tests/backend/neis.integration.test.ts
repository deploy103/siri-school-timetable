import { describe, expect, it } from "vitest";
import { NeisClient } from "@/lib/neis";
import type { EducationOfficeCode } from "@/lib/education-offices";
import { getKstDate } from "@/lib/date";

const apiKey = process.env.NEIS_API_KEY?.trim();

describe.skipIf(!apiKey)("live NEIS integration", () => {
  it.each([
    ["서울", "B10"],
    ["경기", "J10"],
    ["부산", "C10"],
    ["제주", "T10"],
  ] as const)("finds schoolInfo data in %s", async (_region, officeCode) => {
    const client = new NeisClient({ apiKey, mockMode: false, timeoutMs: 8_000, maxAttempts: 2 });
    const schools = await client.searchSchools("초등학교", officeCode as EducationOfficeCode);
    expect(schools.length).toBeGreaterThan(0);
    expect(schools.every((school) => school.officeCode === officeCode)).toBe(true);
    expect(schools[0]?.schoolCode).toBeTruthy();
    expect(schools[0]?.name).toBeTruthy();
  });

  it("parses today's meal response without assuming that a meal exists", async () => {
    const client = new NeisClient({ apiKey, mockMode: false, timeoutMs: 8_000, maxAttempts: 2 });
    const school = (await client.searchSchools("한세사이버보안고등학교", "B10"))[0];
    expect(school).toBeTruthy();
    const date = getKstDate();
    const response = await client.getTodayMeals({
      officeCode: school!.officeCode as EducationOfficeCode,
      schoolCode: school!.schoolCode,
    }, date);
    expect(response.date).toBe(date);
    expect(response.school.name).toBe(school!.name);
    expect(Array.isArray(response.meals)).toBe(true);
    for (const meal of response.meals) {
      expect(meal.dishes.length).toBeGreaterThan(0);
      expect(meal.dishes.every((dish) => !/<br\s*\/?>/iu.test(dish))).toBe(true);
    }
  });
});
