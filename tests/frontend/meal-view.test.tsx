import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { MealView } from "@/components/meal-view";
import type { SchoolSettings } from "@/types/client";

const settings: SchoolSettings = {
  school: {
    officeCode: "B10",
    schoolCode: "7010911",
    name: "한세사이버보안고등학교",
    kind: "고등학교",
    region: "서울특별시교육청",
    address: "서울특별시 마포구",
  },
  department: "클라우드보안과",
  grade: 2,
  className: "3",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

const meals = {
  date: "2026-09-22",
  school: { name: settings.school.name },
  meals: [
    { code: "3", name: "석식", dishes: ["볶음밥 (5.6)"], calories: "700 Kcal", nutrition: "", origin: "" },
    { code: "1", name: "조식", dishes: ["죽 (1)", "우유 (2)"], calories: "400 Kcal", nutrition: "단백질", origin: "쌀 : 국내산" },
    { code: "2", name: "중식", dishes: ["쌀밥", "제육볶음 (5.6.10)"], calories: "782.3 Kcal", nutrition: "", origin: "" },
  ],
};

describe("MealView", () => {
  it("reuses the saved school and renders every meal in code order", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(meals));
    vi.stubGlobal("fetch", fetchMock);
    render(<MealView settings={settings} onChangeSettings={vi.fn()} onShowTimetable={vi.fn()} />);

    expect(screen.getByText("급식을 불러오는 중입니다.")).toBeInTheDocument();
    expect(await screen.findByRole("heading", { name: "한세사이버보안고등학교" })).toBeVisible();
    const cards = screen.getAllByRole("article");
    expect(within(cards[0]!).getByRole("heading", { name: "조식" })).toBeVisible();
    expect(within(cards[1]!).getByRole("heading", { name: "중식" })).toBeVisible();
    expect(within(cards[2]!).getByRole("heading", { name: "석식" })).toBeVisible();
    expect(screen.getByText("제육볶음 (5.6.10)")).toBeVisible();
    expect(screen.queryByText("영양정보 보기")).not.toBeInTheDocument();
    expect(screen.queryByText("782.3 Kcal")).not.toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/meal/today?officeCode=B10&schoolCode=7010911",
      { cache: "no-store" },
    );
  });

  it("shows a normal empty-day message", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({ ...meals, meals: [] })));
    render(<MealView settings={settings} onChangeSettings={vi.fn()} onShowTimetable={vi.fn()} />);
    expect(await screen.findByText("오늘 등록된 급식이 없습니다.")).toBeVisible();
  });

  it("shows a safe error and retries", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonResponse({ error: { message: "교육정보 서비스에 연결할 수 없습니다." } }, 503))
      .mockResolvedValueOnce(jsonResponse(meals));
    vi.stubGlobal("fetch", fetchMock);
    render(<MealView settings={settings} onChangeSettings={vi.fn()} onShowTimetable={vi.fn()} />);

    expect(await screen.findByRole("alert")).toHaveTextContent("교육정보 서비스에 연결할 수 없습니다.");
    await user.click(screen.getByRole("button", { name: "다시 시도" }));
    expect(await screen.findByText("제육볶음 (5.6.10)")).toBeVisible();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("opens the shared Siri setup and copies a key-free meal URL", async () => {
    const user = userEvent.setup();
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(meals)));
    render(<MealView settings={settings} onChangeSettings={vi.fn()} onShowTimetable={vi.fn()} />);
    await screen.findByText("제육볶음 (5.6.10)");

    await user.click(screen.getAllByRole("button", { name: "Siri 설정" })[0]!);
    const dialog = screen.getByRole("dialog", { name: "Siri로 학교 정보 듣기" });
    const input = within(dialog).getByLabelText("내 급식 주소") as HTMLInputElement;
    expect(input.value).toContain("/api/voice/meal?officeCode=B10&schoolCode=7010911");
    expect(input.value).not.toContain("NEIS_API_KEY");
    expect(input.value).not.toContain("grade=");
    await user.click(within(dialog).getByRole("button", { name: "급식 URL 복사" }));
    expect(writeText).toHaveBeenCalledWith(input.value);
  });

  it("switches back to the timetable", async () => {
    const user = userEvent.setup();
    const onShowTimetable = vi.fn();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(meals)));
    render(<MealView settings={settings} onChangeSettings={vi.fn()} onShowTimetable={onShowTimetable} />);
    await waitFor(() => expect(screen.getByRole("button", { name: "시간표" })).toBeEnabled());
    await user.click(screen.getByRole("button", { name: "시간표" }));
    expect(onShowTimetable).toHaveBeenCalledOnce();
  });
});
