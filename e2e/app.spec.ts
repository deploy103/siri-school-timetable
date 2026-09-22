import { expect, test } from "@playwright/test";

test("mobile-first setup, timetable, persistence, and Siri flow", async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "내 학교를 알려주세요" })).toBeVisible();
  await expect(page.getByLabel("지역", { exact: true })).toHaveValue("");

  await page.getByLabel("지역", { exact: true }).selectOption("C10");
  await page.getByLabel("학교 이름").fill("미래");
  await page.getByRole("button", { name: "검색" }).click();
  await expect(page.getByRole("button", { name: /부산미래중학교/ })).toContainText("부산광역시");
  await page.getByRole("button", { name: /부산미래중학교/ }).click();
  await page.getByLabel("학년", { exact: true }).selectOption("2");
  await page.getByLabel("반", { exact: true }).selectOption("1");
  await page.getByRole("button", { name: "설정 저장하고 시간표 보기" }).click();

  await expect(page.getByRole("heading", { name: "부산미래중학교" })).toBeVisible();
  await expect(page.getByText("자료구조", { exact: true })).toBeVisible();
  await expect(page.getByRole("listitem").first()).toContainText("1교시");

  await page.reload();
  await expect(page.getByRole("heading", { name: "부산미래중학교" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "오늘 수업" })).toBeVisible();

  await page.getByRole("button", { name: "설정 변경" }).click();
  await expect(page.getByRole("heading", { name: "학교 설정 변경" })).toBeVisible();
  await expect(page.getByLabel("지역", { exact: true })).toHaveValue("C10");
  await page.getByLabel("학년", { exact: true }).selectOption("3");
  await page.getByLabel("반", { exact: true }).selectOption("2");
  await page.getByRole("button", { name: "설정 저장하고 시간표 보기" }).click();
  await expect(page.getByText("3학년 2반")).toBeVisible();

  await page.getByRole("button", { name: "Siri 설정" }).click();
  const dialog = page.getByRole("dialog", { name: "Siri로 학교 정보 듣기" });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByLabel("내 시간표 주소")).toHaveValue(/\/api\/voice\/timetable\?.*officeCode=C10/);
  await expect(dialog.getByLabel("내 급식 주소")).toHaveValue(/\/api\/voice\/meal\?.*officeCode=C10/);
  await expect(dialog).toContainText("URL 콘텐츠 가져오기");
  await expect(dialog).toContainText("텍스트 말하기");
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();

  await page.getByRole("button", { name: "급식", exact: true }).click();
  await expect(page.getByRole("heading", { name: "오늘 급식" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "중식" })).toBeVisible();
  await expect(page.getByText("제육볶음 (5.6.10)")).toBeVisible();
  await page.reload();
  await expect(page.getByRole("heading", { name: "오늘 수업" })).toBeVisible();

  const hasHorizontalOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
  );
  expect(hasHorizontalOverflow).toBe(false);
  expect(consoleErrors).toEqual([]);
});

test("vocational schools keep same-number classes separated by department", async ({ page }) => {
  await page.goto("/");
  await page.getByLabel("지역", { exact: true }).selectOption("B10");
  await page.getByLabel("학교 이름").fill("한세");
  await page.getByRole("button", { name: "검색" }).click();
  await page.getByRole("button", { name: /한세사이버보안고등학교/ }).click();

  await expect(page.getByLabel("학과", { exact: true })).toBeVisible();
  await page.getByLabel("학과", { exact: true }).selectOption("콘텐츠과");
  await page.getByLabel("학년", { exact: true }).selectOption("2");
  await page.getByLabel("반", { exact: true }).selectOption("3");
  await page.getByRole("button", { name: "설정 저장하고 시간표 보기" }).click();

  await expect(page.getByText("콘텐츠과 · 2학년 3반")).toBeVisible();
  await page.getByRole("button", { name: "Siri 설정" }).click();
  await expect(page.getByLabel("내 시간표 주소")).toHaveValue(/department=%EC%BD%98%ED%85%90%EC%B8%A0%EA%B3%BC/);
});
