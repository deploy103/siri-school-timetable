import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import HomePage from "@/app/page";
import { STORAGE_KEY } from "@/hooks/use-school-settings";
import type { SchoolSettings } from "@/types/client";

const settings: SchoolSettings = {
  school: {
    officeCode: "B10",
    schoolCode: "7011234",
    name: "테스트중학교",
    kind: "중학교",
    region: "서울특별시",
    address: "서울특별시 중구 테스트로 2",
  },
  grade: 2,
  className: "3",
};

const timetable = {
  date: "2026-09-22",
  school: { name: "테스트중학교", kind: "중학교" },
  grade: 2,
  className: "3",
  lessons: [
    { period: 2, subject: "영어" },
    { period: 1, subject: "수학" },
  ],
};

describe("HomePage", () => {
  beforeEach(() => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  });

  it("restores the existing v1 settings and renders today's timetable in period order", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify(timetable), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    render(<HomePage />);

    expect(screen.getByText("저장된 설정을 확인하고 있어요.")).toBeVisible();
    expect(await screen.findByRole("heading", { name: "테스트중학교" })).toBeVisible();
    expect(await screen.findByText("수학")).toBeVisible();
    const lessons = screen.getAllByRole("listitem");
    expect(lessons[0]).toHaveTextContent("1교시수학");
    expect(lessons[1]).toHaveTextContent("2교시영어");
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/timetable/today?officeCode=B10&schoolCode=7011234&kind=%EC%A4%91%ED%95%99%EA%B5%90&grade=2&className=3",
      { cache: "no-store" },
    );
  });

  it("migrates the numeric class value stored by the original v1 schema", async () => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...settings, className: 3 }));
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify(timetable), { status: 200 })));
    render(<HomePage />);

    expect(await screen.findByRole("heading", { name: "테스트중학교" })).toBeVisible();
    expect(screen.getByText("2학년 3반")).toBeVisible();
  });

  it("opens settings editing and can cancel without losing the saved settings", async () => {
    const user = userEvent.setup();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify(timetable), { status: 200 })));
    render(<HomePage />);

    await user.click(await screen.findByRole("button", { name: "설정 변경" }));
    expect(screen.getByRole("heading", { name: "학교 설정 변경" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "테스트중학교" })).toBeVisible();
    await user.click(screen.getByRole("button", { name: "취소" }));
    expect(await screen.findByRole("heading", { name: "오늘 수업" })).toBeVisible();
    expect(JSON.parse(window.localStorage.getItem(STORAGE_KEY) ?? "null")).toEqual(settings);
  });

  it("uses the same saved school when switching from timetable to meals", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.startsWith("/api/meal/today")) {
        return new Response(JSON.stringify({
          date: "2026-09-22",
          school: { name: settings.school.name },
          meals: [{ code: "2", name: "중식", dishes: ["쌀밥"], calories: "700 Kcal", nutrition: "", origin: "" }],
        }), { status: 200 });
      }
      return new Response(JSON.stringify(timetable), { status: 200 });
    });
    vi.stubGlobal("fetch", fetchMock);
    render(<HomePage />);
    await screen.findByText("수학");

    await user.click(screen.getByRole("button", { name: /^급식$/ }));
    expect(await screen.findByRole("heading", { name: "중식" })).toBeVisible();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/meal/today?officeCode=B10&schoolCode=7011234",
      { cache: "no-store" },
    );
    expect(JSON.parse(window.localStorage.getItem(STORAGE_KEY) ?? "null")).toEqual(settings);
  });

  it("persists a newly selected school", async () => {
    window.localStorage.clear();
    const user = userEvent.setup();
    const school = { ...settings.school, name: "새학교" };
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ schools: [school] }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ classes: [
        { grade: 3, className: "4" },
      ] }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ ...timetable, school: { name: "새학교", kind: "중학교" } }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    render(<HomePage />);

    await user.selectOptions(await screen.findByLabelText("지역"), "B10");
    await user.type(await screen.findByLabelText("학교 이름"), "새학교");
    await user.click(screen.getByRole("button", { name: "검색" }));
    await user.click(await screen.findByRole("button", { name: /새학교/ }));
    await waitFor(() => expect(screen.getByLabelText("학년")).toHaveValue("3"));
    await user.selectOptions(screen.getByLabelText("반"), "4");
    await user.click(screen.getByRole("button", { name: "설정 저장하고 시간표 보기" }));

    await waitFor(() => expect(JSON.parse(window.localStorage.getItem(STORAGE_KEY) ?? "null")).toEqual({ school, grade: 3, className: "4" }));
    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/schools?name=%EC%83%88%ED%95%99%EA%B5%90&officeCode=B10");
  });

  it("shows the onboarding banner when no settings are saved and hides it once dismissed", async () => {
    window.localStorage.clear();
    const user = userEvent.setup();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({ schools: [] }), { status: 200 })));
    render(<HomePage />);

    expect(await screen.findByRole("heading", { name: "처음 쓰는 경우 여기부터 따라하면 됨" })).toBeVisible();
    await user.click(screen.getByRole("button", { name: "이미 설정했어요" }));
    expect(screen.queryByRole("heading", { name: "처음 쓰는 경우 여기부터 따라하면 됨" })).not.toBeInTheDocument();
  });

  it("opens the Siri dialog automatically right after the very first setup save", async () => {
    window.localStorage.clear();
    const user = userEvent.setup();
    const school = { ...settings.school, name: "새학교" };
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ schools: [school] }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ classes: [
        { grade: 3, className: "4" },
      ] }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ ...timetable, school: { name: "새학교", kind: "중학교" } }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    render(<HomePage />);

    await user.selectOptions(await screen.findByLabelText("지역"), "B10");
    await user.type(await screen.findByLabelText("학교 이름"), "새학교");
    await user.click(screen.getByRole("button", { name: "검색" }));
    await user.click(await screen.findByRole("button", { name: /새학교/ }));
    await waitFor(() => expect(screen.getByLabelText("학년")).toHaveValue("3"));
    await user.selectOptions(screen.getByLabelText("반"), "4");
    await user.click(screen.getByRole("button", { name: "설정 저장하고 시간표 보기" }));

    expect(await screen.findByRole("dialog", { name: "Siri로 학교 정보 듣기" })).toBeVisible();
  });

  it("lets the student reopen the onboarding guide from the timetable header", async () => {
    const user = userEvent.setup();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify(timetable), { status: 200 })));
    render(<HomePage />);

    await user.click(await screen.findByRole("button", { name: "가이드 다시 보기" }));
    expect(await screen.findByRole("heading", { name: "처음 쓰는 경우 여기부터 따라하면 됨" })).toBeVisible();
  });
});
