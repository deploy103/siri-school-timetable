import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { TEACHER_AUTO_REFRESH_MS, TeacherPage } from "@/components/teacher-page";
import { TEACHER_STORAGE_KEY } from "@/hooks/use-teacher-settings";
import { decodeTeacherProfile } from "@/lib/teacher-profile";
import type { TeacherSettings, TeacherTimetable } from "@/types/teacher";

const storedSettings: TeacherSettings = {
  v: 1,
  assignments: [{
    subject: "클라우드 보안",
    department: "클라우드보안과",
    grade: 2,
    className: "1",
  }],
  includeSubject: false,
};

const timetable: TeacherTimetable = {
  date: "2026-09-23",
  queriedAt: "2026-09-23T00:23:00.000Z",
  queriedAtLabel: "9월 23일 오전 9시 23분",
  schoolName: "한세사이버보안고등학교",
  lessons: [{
    period: 2,
    subject: "클라우드 보안",
    department: "클라우드보안과",
    departmentDisplay: "클라우드 보안과",
    departmentSpeech: "클보",
    grade: 2,
    className: "1",
  }],
  ambiguousPeriods: [],
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function setupFetch() {
  return vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input);
    if (url === "/api/hansei-t/subjects") {
      return json({ subjects: ["네트워크 보안", "클라우드 보안"], range: { from: "2026-09-01", to: "2026-10-27" } });
    }
    if (url.startsWith("/api/hansei-t/assignment-candidates?")) {
      return json({
        subject: "클라우드 보안",
        range: { from: "2026-09-01", to: "2026-10-27" },
        candidates: [{
          subject: "클라우드 보안",
          department: "클라우드보안과",
          departmentDisplay: "클라우드 보안과",
          departmentSpeech: "클보",
          grade: 2,
          className: "1",
        }],
      });
    }
    if (url.startsWith("/api/hansei-t/timetable?")) return json(timetable);
    return json({ error: { message: "unexpected request" } }, 500);
  });
}

describe("Hansei teacher page", () => {
  it("renders the private teacher setup and never preselects candidate classes", async () => {
    const user = userEvent.setup();
    vi.stubGlobal("fetch", setupFetch());
    render(<TeacherPage />);

    expect(await screen.findByRole("heading", { name: "한세 교사용 시간표" })).toBeVisible();
    expect(screen.getByText("서울특별시교육청 · 고등학교")).toBeVisible();
    const subject = await screen.findByRole("checkbox", { name: "클라우드 보안" });
    expect(subject).not.toBeChecked();
    await user.click(subject);
    const candidate = await screen.findByRole("checkbox", { name: /클보 2학년 1반/ });
    expect(candidate).not.toBeChecked();
  });

  it("selects a subject and class, then saves a separate localStorage profile", async () => {
    const user = userEvent.setup();
    vi.stubGlobal("fetch", setupFetch());
    render(<TeacherPage />);

    await user.click(await screen.findByRole("checkbox", { name: "클라우드 보안" }));
    await user.click(await screen.findByRole("checkbox", { name: /클보 2학년 1반/ }));
    await user.click(screen.getByRole("button", { name: "설정 저장" }));

    expect(await screen.findByText("1개 수업")).toBeVisible();
    expect(screen.getByText("클보 2학년 1반")).toBeVisible();
    expect(JSON.parse(window.localStorage.getItem(TEACHER_STORAGE_KEY) ?? "null")).toEqual(storedSettings);
    expect(window.localStorage.getItem("time-siri.school-settings.v1")).toBeNull();
  });

  it("removes malformed stored JSON and safely returns to setup", async () => {
    window.localStorage.setItem(TEACHER_STORAGE_KEY, "{broken");
    vi.stubGlobal("fetch", setupFetch());
    render(<TeacherPage />);
    expect(await screen.findByRole("heading", { name: "한세 교사용 시간표" })).toBeVisible();
    expect(window.localStorage.getItem(TEACHER_STORAGE_KEY)).toBeNull();
  });

  it("restores settings, edits them, and resets them", async () => {
    const user = userEvent.setup();
    window.localStorage.setItem(TEACHER_STORAGE_KEY, JSON.stringify(storedSettings));
    vi.stubGlobal("fetch", setupFetch());
    render(<TeacherPage />);

    expect(await screen.findByText("클보 2학년 1반")).toBeVisible();
    await user.click(screen.getAllByRole("button", { name: "설정 변경" })[0]!);
    expect(await screen.findByRole("heading", { name: "교사용 설정 변경" })).toBeVisible();
    expect(await screen.findByRole("checkbox", { name: /클보 2학년 1반/ })).toBeChecked();
    await user.click(screen.getByRole("button", { name: "취소" }));
    await screen.findByText("클보 2학년 1반");
    await user.click(screen.getByRole("button", { name: "설정 초기화" }));
    expect(await screen.findByRole("heading", { name: "한세 교사용 시간표" })).toBeVisible();
    expect(window.localStorage.getItem(TEACHER_STORAGE_KEY)).toBeNull();
  });

  it("creates and copies a validated compact Siri URL", async () => {
    const user = userEvent.setup();
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true });
    window.localStorage.setItem(TEACHER_STORAGE_KEY, JSON.stringify(storedSettings));
    vi.stubGlobal("fetch", setupFetch());
    render(<TeacherPage />);
    await screen.findByText("클보 2학년 1반");

    await user.click(screen.getByRole("button", { name: "Siri 설정" }));
    const dialog = screen.getByRole("dialog", { name: "교사용 Siri 설정" });
    expect(within(dialog).getByText(/시리야, 학교 수업/)).toBeVisible();
    const input = within(dialog).getByLabelText("교사용 시간표 주소") as HTMLInputElement;
    const profile = new URL(input.value).searchParams.get("p");
    expect(profile).toBeTruthy();
    expect(decodeTeacherProfile(profile ?? "")).toEqual(storedSettings);
    expect(input.value).not.toContain("NEIS_API_KEY");
    await user.click(within(dialog).getByRole("button", { name: "교사용 URL 복사" }));
    await waitFor(() => expect(writeText).toHaveBeenCalledWith(input.value));
  });

  it("refreshes an open teacher timetable every 30 minutes", async () => {
    vi.useFakeTimers();
    let unmount: () => void = () => undefined;
    try {
      window.localStorage.setItem(TEACHER_STORAGE_KEY, JSON.stringify(storedSettings));
      const fetchMock = setupFetch();
      vi.stubGlobal("fetch", fetchMock);
      ({ unmount } = render(<TeacherPage />));

      await act(() => vi.advanceTimersByTimeAsync(1));
      await act(() => vi.advanceTimersByTimeAsync(1));
      expect(fetchMock.mock.calls.filter(([url]) => String(url).startsWith("/api/hansei-t/timetable?"))).toHaveLength(1);
      await act(() => vi.advanceTimersByTimeAsync(TEACHER_AUTO_REFRESH_MS));
      expect(fetchMock.mock.calls.filter(([url]) => String(url).startsWith("/api/hansei-t/timetable?"))).toHaveLength(2);
    } finally {
      unmount();
      vi.useRealTimers();
    }
  });
});
