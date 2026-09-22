import { expect, test } from "@playwright/test";

test("mobile-first setup, timetable, persistence, and Siri flow", async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "내 학교를 알려주세요" })).toBeVisible();

  await page.getByLabel("학교 이름").fill("한세");
  await page.getByRole("button", { name: "검색" }).click();
  await page.getByRole("button", { name: /한세사이버보안고등학교/ }).click();
  await page.getByLabel("학년").selectOption("2");
  await page.getByLabel("반").selectOption("1");
  await page.getByRole("button", { name: "설정 저장하고 시간표 보기" }).click();

  await expect(page.getByRole("heading", { name: "한세사이버보안고등학교" })).toBeVisible();
  await expect(page.getByText("자료구조", { exact: true })).toBeVisible();
  await expect(page.getByRole("listitem").first()).toContainText("1교시");

  await page.reload();
  await expect(page.getByRole("heading", { name: "한세사이버보안고등학교" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "오늘 수업" })).toBeVisible();

  await page.getByRole("button", { name: "Siri 설정" }).click();
  const dialog = page.getByRole("dialog", { name: "Siri로 시간표 듣기" });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByLabel("내 시간표 주소")).toHaveValue(/\/api\/voice\/timetable\?.*officeCode=B10/);
  await expect(dialog).toContainText("URL 콘텐츠 가져오기");
  await expect(dialog).toContainText("텍스트 말하기");
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();

  const hasHorizontalOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
  );
  expect(hasHorizontalOverflow).toBe(false);
  expect(consoleErrors).toEqual([]);
});
