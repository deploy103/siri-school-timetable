import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { TimetableView } from "@/components/timetable-view";
import type { SchoolSettings } from "@/types/client";

const settings: SchoolSettings = {
  school: {
    officeCode: "B10",
    schoolCode: "7011234",
    name: "테스트초등학교",
    kind: "초등학교",
    region: "서울특별시",
    address: "서울특별시 강남구 테스트로 3",
  },
  grade: 4,
  className: "2",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

describe("TimetableView", () => {
  it("shows a skeleton and then an empty timetable state", async () => {
    let resolveFetch: ((response: Response) => void) | undefined;
    vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>((resolve) => { resolveFetch = resolve; })));
    render(<TimetableView settings={settings} onChangeSettings={vi.fn()} />);

    expect(screen.getByText("시간표를 불러오는 중입니다.")).toBeInTheDocument();
    await waitFor(() => expect(resolveFetch).toBeTypeOf("function"));
    resolveFetch?.(jsonResponse({
      date: "2026-09-22",
      school: { name: settings.school.name, kind: settings.school.kind },
      grade: 4,
      className: "2",
      lessons: [],
    }));
    expect(await screen.findByText("오늘 등록된 시간표가 없습니다.")).toBeVisible();
    expect(screen.getByText(/주말·휴업일/)).toBeVisible();
  });

  it("explains when NEIS starts the returned timetable after first period", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({
      date: "2026-09-22",
      school: { name: settings.school.name, kind: settings.school.kind },
      grade: 4,
      className: "2",
      lessons: [{ period: 3, subject: "국어" }],
    })));
    render(<TimetableView settings={settings} onChangeSettings={vi.fn()} />);

    expect(await screen.findByText(/1~2교시 수업 정보가 없어 3교시부터 표시/)).toBeVisible();
    expect(screen.queryByText("1교시", { exact: true })).not.toBeInTheDocument();
  });

  it("shows a safe error and retries the request", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonResponse({ error: { code: "NEIS_UNAVAILABLE", message: "나이스 서비스가 잠시 불안정합니다." } }, 503))
      .mockResolvedValueOnce(jsonResponse({
        date: "2026-09-22",
        school: { name: settings.school.name, kind: settings.school.kind },
        grade: 4,
        className: "2",
        lessons: [{ period: 1, subject: "국어" }],
      }));
    vi.stubGlobal("fetch", fetchMock);
    render(<TimetableView settings={settings} onChangeSettings={vi.fn()} />);

    expect(await screen.findByRole("alert")).toHaveTextContent("나이스 서비스가 잠시 불안정합니다.");
    await user.click(screen.getByRole("button", { name: "다시 시도" }));
    expect(await screen.findByText("국어")).toBeVisible();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("opens Siri instructions, builds the configured URL, and copies it", async () => {
    const user = userEvent.setup();
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({
      date: "2026-09-22",
      school: { name: settings.school.name, kind: settings.school.kind },
      grade: 4,
      className: "2",
      lessons: [{ period: 1, subject: "국어" }],
    })));
    render(<TimetableView settings={settings} onChangeSettings={vi.fn()} />);
    await screen.findByText("국어");

    await user.click(screen.getByRole("button", { name: "Siri 설정" }));
    const dialog = screen.getByRole("dialog", { name: "Siri로 학교 정보 듣기" });
    expect(within(dialog).getByText("‘URL 콘텐츠 가져오기’ 추가")).toBeVisible();
    expect(within(dialog).getByText("‘텍스트 말하기’ 추가")).toBeVisible();
    const input = within(dialog).getByLabelText("내 시간표 주소");
    expect((input as HTMLInputElement).value).toContain("/api/voice/timetable?officeCode=B10&schoolCode=7011234");

    expect((within(dialog).getByLabelText("내 급식 주소") as HTMLInputElement).value).toContain(
      "/api/voice/meal?officeCode=B10&schoolCode=7011234",
    );
    expect((within(dialog).getByLabelText("내 급식 주소") as HTMLInputElement).value).not.toContain("grade=");
    await user.click(within(dialog).getByRole("button", { name: "시간표 URL 복사" }));
    expect(writeText).toHaveBeenCalledWith((input as HTMLInputElement).value);
    expect(within(dialog).getByRole("button", { name: "시간표 URL 복사" })).toHaveTextContent("복사됨");
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });
});
