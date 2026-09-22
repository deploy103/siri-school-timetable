import { describe, expect, it } from "vitest";
import { NeisClient } from "@/lib/neis";

const apiKey = process.env.NEIS_API_KEY?.trim();

describe.skipIf(!apiKey)("live NEIS integration", () => {
  it("finds a known school through the official service", async () => {
    const client = new NeisClient({ apiKey, timeoutMs: 8_000, maxAttempts: 2 });
    const schools = await client.searchSchools("한세사이버보안고등학교");
    expect(schools).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          officeCode: "B10",
          schoolCode: "7010911",
          kind: "고등학교",
        }),
      ]),
    );
  });
});
