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
  className: 3,
};

const timetable = {
  date: "2026-09-22",
  school: { name: "테스트중학교", kind: "중학교" },
  grade: 2,
  className: 3,
  lessons: [
    { period: 2, subject: "영어" },
    { period: 1, subject: "수학" },
  ],
};

describe("HomePage", () => {
  beforeEach(() => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  });

  it("restores saved settings and renders today's timetable in period order", async () => {
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

  it("persists a newly selected school", async () => {
    window.localStorage.clear();
    const user = userEvent.setup();
    const school = { ...settings.school, name: "새학교" };
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ schools: [school] }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ ...timetable, school: { name: "새학교", kind: "중학교" } }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    render(<HomePage />);

    await user.type(await screen.findByLabelText("학교 이름"), "새학교");
    await user.click(screen.getByRole("button", { name: "검색" }));
    await user.click(await screen.findByRole("button", { name: /새학교/ }));
    await user.selectOptions(screen.getByLabelText("학년"), "3");
    await user.selectOptions(screen.getByLabelText("반"), "4");
    await user.click(screen.getByRole("button", { name: "설정 저장하고 시간표 보기" }));

    await waitFor(() => expect(JSON.parse(window.localStorage.getItem(STORAGE_KEY) ?? "null")).toEqual({ school, grade: 3, className: 4 }));
  });
});
