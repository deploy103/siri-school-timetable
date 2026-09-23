import { afterEach, describe, expect, it, vi } from "vitest";
import { GET as teacherVoiceRoute, clearTeacherVoiceRateLimit } from "@/app/api/voice/teacher-timetable/route";
import { GET as teacherTimetableRoute } from "@/app/api/hansei-t/timetable/route";
import { formatKstLookupTime, getKstDate, getSchoolTermWindow } from "@/lib/date";
import { NeisClient, clearNeisCaches, parseHanseiTimetableRows } from "@/lib/neis";
import { decodeTeacherProfile, encodeTeacherProfile } from "@/lib/teacher-profile";
import {
  assignmentMatchesRow,
  collectAssignmentCandidates,
  getDepartmentSpeechName,
  matchTeacherLessons,
  normalizeDepartmentName,
  normalizeSubjectName,
  teacherTimetableToSpeech,
  type HanseiTimetableRow,
} from "@/lib/teacher-timetable";
import type { TeacherAssignment, TeacherSettings, TeacherTimetable } from "@/types/teacher";

const assignment: TeacherAssignment = {
  subject: "클라우드 보안",
  department: "클라우드보안과",
  grade: 2,
  className: "1",
};

function row(overrides: Partial<HanseiTimetableRow> = {}): HanseiTimetableRow {
  return {
    period: 2,
    subject: "클라우드 보안",
    rawSubject: "클라우드 보안",
    department: "클라우드보안과",
    rawDepartment: "클라우드보안과",
    grade: 2,
    className: "1",
    ...overrides,
  };
}

function settings(assignments: TeacherAssignment[] = [assignment]): TeacherSettings {
  return { v: 1, assignments, includeSubject: false };
}

function request(path: string, ip = "198.51.100.20"): Request {
  return new Request(`http://localhost${path}`, { headers: { "x-forwarded-for": ip } });
}

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  clearNeisCaches();
  clearTeacherVoiceRateLimit();
});

describe("teacher normalization and matching", () => {
  it("maps department aliases to display and Siri speech names", () => {
    expect(normalizeDepartmentName(" 클라우드보안과 ")).toBe("클라우드 보안과");
    expect(getDepartmentSpeechName("클라우드 보안")).toBe("클보");
    expect(getDepartmentSpeechName("메타버스게임과")).toBe("게임과");
    expect(getDepartmentSpeechName("지능형 소프트웨어과")).toBe("지소과");
  });

  it("normalizes Unicode and whitespace without aggressive fuzzy merging", () => {
    expect(normalizeSubjectName("  웹\t 프로그래밍  ")).toBe("웹 프로그래밍");
    expect(normalizeSubjectName("ＡＢＣ")).toBe("ＡＢＣ");
    expect(normalizeSubjectName("클라우드보안")).not.toBe(normalizeSubjectName("클라우드 보안"));
  });

  it("requires subject, department, grade, and class to all match", () => {
    expect(assignmentMatchesRow(assignment, row())).toBe(true);
    expect(assignmentMatchesRow(assignment, row({ subject: "네트워크 보안" }))).toBe(false);
    expect(assignmentMatchesRow(assignment, row({ department: "메타버스게임과" }))).toBe(false);
    expect(assignmentMatchesRow(assignment, row({ grade: 1 }))).toBe(false);
    expect(assignmentMatchesRow(assignment, row({ className: "2" }))).toBe(false);
  });

  it("excludes another teacher's class even when the subject is identical", () => {
    const result = matchTeacherLessons([row(), row({ period: 3, className: "2" })], [assignment]);
    expect(result.lessons).toHaveLength(1);
    expect(result.lessons[0]).toMatchObject({ period: 2, className: "1" });
  });

  it("sorts periods and removes exact duplicate rows", () => {
    const result = matchTeacherLessons([row({ period: 6 }), row({ period: 2 }), row({ period: 2 })], [assignment]);
    expect(result.lessons.map(({ period }) => period)).toEqual([2, 6]);
    expect(result.ambiguousPeriods).toEqual([]);
  });

  it("returns an empty lesson list when no complete assignment matches", () => {
    expect(matchTeacherLessons([row({ grade: 1 })], [assignment])).toEqual({
      lessons: [],
      ambiguousPeriods: [],
    });
  });

  it("supports multiple subjects and departments", () => {
    const second: TeacherAssignment = {
      subject: "네트워크 보안",
      department: "메타버스 게임과",
      grade: 1,
      className: "2",
    };
    const result = matchTeacherLessons([
      row(),
      row({ period: 4, subject: second.subject, rawSubject: second.subject, department: "메타버스게임과", rawDepartment: "메타버스게임과", grade: 1, className: "2" }),
    ], [assignment, second]);
    expect(result.lessons).toHaveLength(2);
    expect(result.lessons.map(({ departmentSpeech }) => departmentSpeech)).toEqual(["클보", "게임과"]);
  });

  it("marks different assigned classes in the same period as ambiguous", () => {
    const second = { ...assignment, className: "2" };
    const result = matchTeacherLessons([row(), row({ className: "2" })], [assignment, second]);
    expect(result.ambiguousPeriods).toEqual([2]);
    expect(result.lessons).toHaveLength(2);
    expect(result.lessons.every((lesson) => lesson.ambiguous)).toBe(true);
  });

  it("builds candidates by subject and preserves the raw NEIS department", () => {
    const candidates = collectAssignmentCandidates([
      row({ rawDepartment: "클라우드보안과", department: "클라우드보안과" }),
      row({ rawDepartment: "클라우드 보안과", department: "클라우드 보안과" }),
      row({ subject: "다른 과목" }),
    ], " 클라우드  보안 ");
    expect(candidates).toHaveLength(1);
    expect(candidates[0]).toMatchObject({
      department: "클라우드보안과",
      departmentDisplay: "클라우드 보안과",
    });
  });
});

describe("teacher date and speech", () => {
  it("formats the actual KST lookup time", () => {
    expect(formatKstLookupTime(new Date("2026-09-23T00:23:00.000Z"))).toBe("9월 23일 오전 9시 23분");
    expect(getSchoolTermWindow("2026-09-01")).toEqual({ from: "2026-09-01", to: "2026-10-27" });
  });

  it("speaks sorted lessons, an empty day, and optional subject names", () => {
    const timetable: TeacherTimetable = {
      date: "2026-09-23",
      queriedAt: "2026-09-23T00:23:00.000Z",
      queriedAtLabel: "9월 23일 오전 9시 23분",
      schoolName: "한세사이버보안고등학교",
      lessons: matchTeacherLessons([row({ period: 3 }), row({ period: 2 })], [assignment]).lessons,
      ambiguousPeriods: [],
    };
    expect(teacherTimetableToSpeech(timetable, false)).toBe(
      "9월 23일 오전 9시 23분 조회 기준, 2교시 클보 2학년 1반, 3교시 클보 2학년 1반 수업이 배정되어 있습니다.",
    );
    expect(teacherTimetableToSpeech(timetable, true)).toContain("2교시 클보 2학년 1반 클라우드 보안");
    expect(teacherTimetableToSpeech({ ...timetable, lessons: [] }, false)).toBe(
      "9월 23일 오전 9시 23분 조회 기준, 오늘 배정된 수업이 없습니다.",
    );
  });

  it("announces a same-period collision instead of silently dropping a class", () => {
    const matched = matchTeacherLessons([row(), row({ className: "2" })], [assignment, { ...assignment, className: "2" }]);
    const speech = teacherTimetableToSpeech({
      date: "2026-09-23",
      queriedAt: "2026-09-23T00:23:00.000Z",
      queriedAtLabel: "9월 23일 오전 9시 23분",
      schoolName: "한세사이버보안고등학교",
      ...matched,
    }, false);
    expect(speech).toContain("2교시에 서로 다른 담당 학급 수업이 겹쳐 확인이 필요합니다");
  });
});

describe("teacher profile validation", () => {
  it("round-trips a valid compact UTF-8 base64url profile", () => {
    const encoded = encodeTeacherProfile(settings());
    expect(encoded).toMatch(/^[A-Za-z0-9_-]+$/u);
    expect(decodeTeacherProfile(encoded)).toEqual(settings());
  });

  it("rejects malformed profile data", () => {
    expect(() => decodeTeacherProfile("not-json")).toThrow();
  });

  it("rejects more than 40 assignments", () => {
    const oversized = {
      v: 1,
      assignments: Array.from({ length: 41 }, (_, index) => ["과목", "학과", 1, String(index)]),
      includeSubject: false,
    };
    const bytes = new TextEncoder().encode(JSON.stringify(oversized));
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    const encoded = btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
    expect(() => decodeTeacherProfile(encoded)).toThrow();
  });
});

describe("teacher NEIS pagination and voice route", () => {
  it("drops foreign-school, empty-period, and oversized catalog rows", () => {
    const valid = {
      ATPT_OFCDC_SC_CODE: "B10",
      SD_SCHUL_CODE: "7010911",
      ALL_TI_YMD: "20260923",
      PERIO: "2",
      ITRT_CNTNT: "  클라우드   보안 ",
      DDDEP_NM: "클라우드보안과",
      GRADE: "2",
      CLASS_NM: "1",
    };
    expect(parseHanseiTimetableRows([
      valid,
      { ...valid, SD_SCHUL_CODE: "other" },
      { ...valid, PERIO: "" },
      { ...valid, ITRT_CNTNT: "가".repeat(101) },
    ], { from: "2026-09-01", to: "2026-10-27" })).toEqual([
      expect.objectContaining({ subject: "클라우드 보안", rawDepartment: "클라우드보안과" }),
    ]);
  });

  it("rejects a malformed route profile before any NEIS request", async () => {
    const upstream = vi.fn();
    vi.stubGlobal("fetch", upstream);
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await teacherTimetableRoute(request("/api/hansei-t/timetable?p=not-json"));
    expect(response.status).toBe(400);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(upstream).not.toHaveBeenCalled();
  });

  it("uses the documented date range and fetches every page", async () => {
    const requested: URL[] = [];
    const fetchImplementation: typeof fetch = vi.fn(async (input) => {
      const url = new URL(String(input));
      requested.push(url);
      const page = url.searchParams.get("pIndex");
      const neisRows = Array.from({ length: page === "1" ? 1_000 : 1 }, (_, index) => ({
        ATPT_OFCDC_SC_CODE: "B10",
        SD_SCHUL_CODE: "7010911",
        ALL_TI_YMD: page === "1" ? "20260901" : "20260902",
        PERIO: String(index % 7 + 1),
        ITRT_CNTNT: "클라우드 보안",
        DDDEP_NM: "클라우드보안과",
        GRADE: "2",
        CLASS_NM: "1",
      }));
      return new Response(JSON.stringify({
        hisTimetable: [
          { head: [{ list_total_count: 1001 }, { RESULT: { CODE: "INFO-000", MESSAGE: "정상" } }] },
          { row: neisRows },
        ],
      }));
    });
    const client = new NeisClient({ apiKey: "secret", fetchImplementation, maxAttempts: 1 });
    await expect(client.getHanseiTimetableRows("2026-09-01", "2026-10-27")).resolves.toHaveLength(1001);
    expect(requested.map((url) => url.searchParams.get("pIndex"))).toEqual(["1", "2"]);
    expect(requested[0]?.searchParams.get("pSize")).toBe("1000");
    expect(requested[0]?.searchParams.get("TI_FROM_YMD")).toBe("20260901");
    expect(requested[0]?.searchParams.get("TI_TO_YMD")).toBe("20261027");
  });

  it("returns the safe NEIS failure voice message", async () => {
    vi.stubEnv("NEIS_API_KEY", "secret");
    vi.stubEnv("NEIS_MOCK_MODE", "false");
    vi.stubGlobal("fetch", vi.fn(async () => new Response("down", { status: 503 })));
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const profile = encodeTeacherProfile(settings());
    const response = await teacherVoiceRoute(request(`/api/voice/teacher-timetable?p=${profile}`));
    expect(response.status).toBe(503);
    expect(await response.text()).toBe("현재 학교 시간표 정보를 확인할 수 없습니다. 잠시 후 다시 확인해 주세요.");
  });

  it("rate limits repeated teacher voice requests", async () => {
    vi.stubEnv("NEIS_MOCK_MODE", "true");
    vi.stubEnv("TRUST_PROXY_HEADERS", "true");
    const profile = encodeTeacherProfile(settings());
    for (let index = 0; index < 30; index += 1) {
      expect((await teacherVoiceRoute(request(`/api/voice/teacher-timetable?p=${profile}`, "198.51.100.30"))).status).toBe(200);
    }
    const limited = await teacherVoiceRoute(request(`/api/voice/teacher-timetable?p=${profile}`, "198.51.100.30"));
    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBeTruthy();
    expect(await limited.text()).toBe("요청이 너무 많습니다. 잠시 후 다시 확인해 주세요.");
  });

  it("uses today's exact-date parameter for the Siri lookup", async () => {
    const requested: URL[] = [];
    vi.stubEnv("NEIS_API_KEY", "secret");
    vi.stubGlobal("fetch", vi.fn(async (input) => {
      requested.push(new URL(String(input)));
      return new Response(JSON.stringify({ RESULT: { CODE: "INFO-200", MESSAGE: "없음" } }));
    }));
    const client = new NeisClient({ apiKey: "secret", fetchImplementation: fetch, maxAttempts: 1 });
    await client.getHanseiTimetableRows(getKstDate(), getKstDate());
    expect(requested[0]?.searchParams.get("ALL_TI_YMD")).toBe(getKstDate().replaceAll("-", ""));
    expect(requested[0]?.searchParams.has("TI_FROM_YMD")).toBe(false);
  });
});
