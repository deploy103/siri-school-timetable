import type {
  TeacherAssignment,
  TeacherAssignmentCandidate,
  TeacherLesson,
  TeacherTimetable,
} from "@/types/teacher";

export const HANSEI_SCHOOL = {
  name: "한세사이버보안고등학교",
  officeCode: "B10",
  schoolCode: "7010911",
  kind: "고등학교",
} as const;

export const HANSEI_DEPARTMENTS = [
  "클라우드 보안과",
  "메타버스 게임과",
  "지능형 소프트웨어과",
] as const;

const DEPARTMENT_ALIASES = new Map<string, (typeof HANSEI_DEPARTMENTS)[number]>([
  ["클라우드보안과", "클라우드 보안과"],
  ["클라우드보안", "클라우드 보안과"],
  ["메타버스게임과", "메타버스 게임과"],
  ["메타버스게임", "메타버스 게임과"],
  ["지능형소프트웨어과", "지능형 소프트웨어과"],
  ["지능형소프트웨어", "지능형 소프트웨어과"],
]);

const DEPARTMENT_SPEECH = new Map<string, string>([
  ["클라우드 보안과", "클보"],
  ["메타버스 게임과", "게임과"],
  ["지능형 소프트웨어과", "지소과"],
]);

export interface HanseiTimetableRow {
  period: number;
  subject: string;
  rawSubject: string;
  department: string;
  rawDepartment: string;
  grade: number;
  className: string;
}

function normalizeText(value: string): string {
  return value.normalize("NFC").trim().replace(/\s+/gu, " ");
}

export function normalizeSubjectName(value: string): string {
  return normalizeText(value);
}

export function normalizeDepartmentName(value: string): string {
  const normalized = normalizeText(value);
  const aliasKey = normalized.replace(/[\s·._-]+/gu, "");
  return DEPARTMENT_ALIASES.get(aliasKey) ?? normalized;
}

export function getDepartmentSpeechName(value: string): string {
  const normalized = normalizeDepartmentName(value);
  return DEPARTMENT_SPEECH.get(normalized) ?? normalized;
}

export function departmentOrder(value: string): number {
  const normalized = normalizeDepartmentName(value);
  const index = HANSEI_DEPARTMENTS.indexOf(normalized as (typeof HANSEI_DEPARTMENTS)[number]);
  return index < 0 ? HANSEI_DEPARTMENTS.length : index;
}

function normalizedClassName(value: string): string {
  return normalizeText(value);
}

export function assignmentMatchesRow(assignment: TeacherAssignment, row: HanseiTimetableRow): boolean {
  return normalizeSubjectName(assignment.subject) === normalizeSubjectName(row.subject) &&
    normalizeDepartmentName(assignment.department) === normalizeDepartmentName(row.department) &&
    assignment.grade === row.grade &&
    normalizedClassName(assignment.className) === normalizedClassName(row.className);
}

export function collectTeacherSubjects(rows: readonly HanseiTimetableRow[]): string[] {
  const subjects = new Set<string>();
  for (const row of rows) {
    const subject = normalizeSubjectName(row.subject);
    if (subject && subject.length <= 100) subjects.add(subject);
  }
  return [...subjects].sort((left, right) => left.localeCompare(right, "ko-KR", { numeric: true }));
}

export function collectAssignmentCandidates(
  rows: readonly HanseiTimetableRow[],
  requestedSubject: string,
): TeacherAssignmentCandidate[] {
  const subject = normalizeSubjectName(requestedSubject);
  const unique = new Map<string, TeacherAssignmentCandidate>();
  for (const row of rows) {
    if (normalizeSubjectName(row.subject) !== subject) continue;
    const departmentDisplay = normalizeDepartmentName(row.department);
    const candidate: TeacherAssignmentCandidate = {
      subject,
      department: row.rawDepartment,
      departmentDisplay,
      departmentSpeech: getDepartmentSpeechName(row.department),
      grade: row.grade,
      className: row.className,
    };
    const key = [subject, departmentDisplay, row.grade, normalizedClassName(row.className)].join("\u0000");
    if (!unique.has(key)) unique.set(key, candidate);
  }
  return [...unique.values()].sort((left, right) =>
    departmentOrder(left.department) - departmentOrder(right.department) ||
    left.departmentDisplay.localeCompare(right.departmentDisplay, "ko-KR") ||
    left.grade - right.grade ||
    left.className.localeCompare(right.className, "ko-KR", { numeric: true }),
  );
}

export function matchTeacherLessons(
  rows: readonly HanseiTimetableRow[],
  assignments: readonly TeacherAssignment[],
): { lessons: TeacherLesson[]; ambiguousPeriods: number[] } {
  const matched = new Map<string, TeacherLesson>();
  for (const row of rows) {
    if (!assignments.some((assignment) => assignmentMatchesRow(assignment, row))) continue;
    const departmentDisplay = normalizeDepartmentName(row.department);
    const lesson: TeacherLesson = {
      period: row.period,
      subject: normalizeSubjectName(row.subject),
      department: row.rawDepartment,
      departmentDisplay,
      departmentSpeech: getDepartmentSpeechName(row.department),
      grade: row.grade,
      className: row.className,
    };
    const key = [lesson.period, lesson.subject, departmentDisplay, lesson.grade, normalizedClassName(lesson.className)].join("\u0000");
    matched.set(key, lesson);
  }

  const byPeriod = new Map<number, TeacherLesson[]>();
  for (const lesson of matched.values()) {
    const values = byPeriod.get(lesson.period) ?? [];
    values.push(lesson);
    byPeriod.set(lesson.period, values);
  }
  const ambiguousPeriods = [...byPeriod.entries()]
    .filter(([, values]) => values.length > 1)
    .map(([period]) => period)
    .sort((left, right) => left - right);
  const ambiguous = new Set(ambiguousPeriods);
  const lessons = [...matched.values()]
    .map((lesson) => ambiguous.has(lesson.period) ? { ...lesson, ambiguous: true as const } : lesson)
    .sort((left, right) =>
      left.period - right.period ||
      departmentOrder(left.department) - departmentOrder(right.department) ||
      left.grade - right.grade ||
      left.className.localeCompare(right.className, "ko-KR", { numeric: true }) ||
      left.subject.localeCompare(right.subject, "ko-KR"),
    );
  return { lessons, ambiguousPeriods };
}

export function teacherTimetableToSpeech(timetable: TeacherTimetable, includeSubject: boolean): string {
  const prefix = `${timetable.queriedAtLabel} 조회 기준`;
  if (timetable.lessons.length === 0) return `${prefix}, 오늘 배정된 수업이 없습니다.`;

  const ambiguous = new Set(timetable.ambiguousPeriods);
  const spoken: string[] = [];
  const handledAmbiguities = new Set<number>();
  for (const lesson of timetable.lessons) {
    if (ambiguous.has(lesson.period)) {
      if (!handledAmbiguities.has(lesson.period)) {
        spoken.push(`${lesson.period}교시에 서로 다른 담당 학급 수업이 겹쳐 확인이 필요합니다`);
        handledAmbiguities.add(lesson.period);
      }
      continue;
    }
    spoken.push(
      `${lesson.period}교시 ${lesson.departmentSpeech} ${lesson.grade}학년 ${lesson.className}반${includeSubject ? ` ${lesson.subject}` : ""}`,
    );
  }
  return `${prefix}, ${spoken.join(", ")}${timetable.ambiguousPeriods.length > 0 ? "." : " 수업이 배정되어 있습니다."}`;
}

export function teacherVoiceErrorMessage(errorCode: string): string {
  if (errorCode === "INVALID_INPUT" || errorCode === "NOT_FOUND") {
    return "교사용 시간표 설정이 올바르지 않습니다. 한세 교사용 설정 페이지에서 다시 설정해 주세요.";
  }
  if (errorCode === "RATE_LIMITED") return "요청이 너무 많습니다. 잠시 후 다시 확인해 주세요.";
  return "현재 학교 시간표 정보를 확인할 수 없습니다. 잠시 후 다시 확인해 주세요.";
}
