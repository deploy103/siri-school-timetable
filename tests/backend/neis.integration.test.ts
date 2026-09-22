import { describe, expect, it } from "vitest";
import { NeisClient } from "@/lib/neis";
import type { EducationOfficeCode } from "@/lib/education-offices";

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
});
