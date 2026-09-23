"use client";

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CheckIcon, RefreshIcon, SearchIcon, SettingsIcon } from "@/components/icons";
import { TeacherSiriDialog } from "@/components/teacher-siri-dialog";
import { useTeacherSettings } from "@/hooks/use-teacher-settings";
import { encodeTeacherProfile } from "@/lib/teacher-profile";
import {
  HANSEI_SCHOOL,
  getDepartmentSpeechName,
  normalizeDepartmentName,
  normalizeSubjectName,
} from "@/lib/teacher-timetable";
import type {
  TeacherAssignment,
  TeacherAssignmentCandidate,
  TeacherCandidatesResponse,
  TeacherSettings,
  TeacherSubjectsResponse,
  TeacherTimetable,
} from "@/types/teacher";
import type { ApiErrorBody } from "@/types/client";

export const TEACHER_AUTO_REFRESH_MS = 30 * 60_000;

async function readApiError(response: Response, fallback: string): Promise<string> {
  try {
    const body = (await response.json()) as ApiErrorBody;
    return body.error?.message ?? body.message ?? fallback;
  } catch {
    return fallback;
  }
}

function assignmentKey(assignment: TeacherAssignment): string {
  return [
    normalizeSubjectName(assignment.subject),
    normalizeDepartmentName(assignment.department),
    assignment.grade,
    assignment.className.normalize("NFC").trim().replace(/\s+/gu, " "),
  ].join("\u0000");
}

function toCandidate(assignment: TeacherAssignment): TeacherAssignmentCandidate {
  return {
    ...assignment,
    departmentDisplay: normalizeDepartmentName(assignment.department),
    departmentSpeech: getDepartmentSpeechName(assignment.department),
  };
}

export function TeacherPage() {
  const { settings, isRestoring, saveSettings, clearSettings } = useTeacherSettings();
  const [isEditing, setIsEditing] = useState(false);

  if (isRestoring) {
    return <main className="page-shell restoring" aria-busy="true"><span className="spinner large" aria-hidden="true" /><p>교사용 설정을 확인하고 있어요.</p></main>;
  }
  if (!settings || isEditing) {
    return (
      <TeacherSetup
        initialSettings={settings}
        onSave={(next) => {
          saveSettings(next);
          setIsEditing(false);
        }}
        onCancel={settings ? () => setIsEditing(false) : undefined}
      />
    );
  }
  return (
    <TeacherDashboard
      settings={settings}
      onEdit={() => setIsEditing(true)}
      onReset={clearSettings}
    />
  );
}

interface SetupProps {
  initialSettings: TeacherSettings | null;
  onSave: (settings: TeacherSettings) => void;
  onCancel?: () => void;
}

function TeacherSetup({ initialSettings, onSave, onCancel }: SetupProps) {
  const initialSubjects = useMemo(() => [...new Set(
    (initialSettings?.assignments ?? []).map((assignment) => normalizeSubjectName(assignment.subject)),
  )], [initialSettings]);
  const [subjects, setSubjects] = useState<string[] | null>(null);
  const [subjectSearch, setSubjectSearch] = useState("");
  const [selectedSubjects, setSelectedSubjects] = useState<string[]>(initialSubjects);
  const [candidates, setCandidates] = useState<Record<string, TeacherAssignmentCandidate[]>>({});
  const [selectedAssignments, setSelectedAssignments] = useState<TeacherAssignment[]>(initialSettings?.assignments ?? []);
  const [includeSubject, setIncludeSubject] = useState(initialSettings?.includeSubject ?? false);
  const [subjectsError, setSubjectsError] = useState<string | null>(null);
  const [candidateErrors, setCandidateErrors] = useState<Record<string, string>>({});
  const [loadingCandidates, setLoadingCandidates] = useState<string[]>([]);
  const [validationError, setValidationError] = useState<string | null>(null);

  const loadSubjects = useCallback(async () => {
    setSubjectsError(null);
    try {
      const response = await fetch("/api/hansei-t/subjects", { cache: "no-store" });
      if (!response.ok) throw new Error(await readApiError(response, "과목 목록을 불러오지 못했습니다."));
      const body = (await response.json()) as TeacherSubjectsResponse;
      setSubjects(Array.isArray(body.subjects) ? body.subjects : []);
    } catch (reason) {
      setSubjects([]);
      setSubjectsError(reason instanceof Error ? reason.message : "과목 목록을 불러오지 못했습니다.");
    }
  }, []);

  const loadCandidates = useCallback(async (subject: string) => {
    setLoadingCandidates((current) => current.includes(subject) ? current : [...current, subject]);
    setCandidateErrors((current) => ({ ...current, [subject]: "" }));
    try {
      const params = new URLSearchParams({ subject });
      const response = await fetch(`/api/hansei-t/assignment-candidates?${params.toString()}`, { cache: "no-store" });
      if (!response.ok) throw new Error(await readApiError(response, "담당 학급 후보를 불러오지 못했습니다."));
      const body = (await response.json()) as TeacherCandidatesResponse;
      const originals = (initialSettings?.assignments ?? [])
        .filter((assignment) => normalizeSubjectName(assignment.subject) === subject)
        .map(toCandidate);
      const merged = new Map<string, TeacherAssignmentCandidate>();
      for (const candidate of [...originals, ...(Array.isArray(body.candidates) ? body.candidates : [])]) {
        merged.set(assignmentKey(candidate), candidate);
      }
      setCandidates((current) => ({ ...current, [subject]: [...merged.values()] }));
    } catch (reason) {
      setCandidates((current) => ({ ...current, [subject]: [] }));
      setCandidateErrors((current) => ({
        ...current,
        [subject]: reason instanceof Error ? reason.message : "담당 학급 후보를 불러오지 못했습니다.",
      }));
    } finally {
      setLoadingCandidates((current) => current.filter((item) => item !== subject));
    }
  }, [initialSettings]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadSubjects(), 0);
    return () => window.clearTimeout(timer);
  }, [loadSubjects]);

  useEffect(() => {
    if (initialSubjects.length === 0) return;
    const timer = window.setTimeout(() => {
      for (const subject of initialSubjects) void loadCandidates(subject);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [initialSubjects, loadCandidates]);

  const filteredSubjects = useMemo(() => {
    const query = normalizeSubjectName(subjectSearch).toLocaleLowerCase("ko-KR");
    return (subjects ?? []).filter((subject) => subject.toLocaleLowerCase("ko-KR").includes(query));
  }, [subjectSearch, subjects]);

  function toggleSubject(subject: string) {
    setValidationError(null);
    if (selectedSubjects.includes(subject)) {
      setSelectedSubjects((current) => current.filter((item) => item !== subject));
      setSelectedAssignments((current) => current.filter(
        (assignment) => normalizeSubjectName(assignment.subject) !== subject,
      ));
      return;
    }
    setSelectedSubjects((current) => [...current, subject]);
    if (!candidates[subject]) void loadCandidates(subject);
  }

  function toggleAssignment(candidate: TeacherAssignmentCandidate) {
    setValidationError(null);
    const key = assignmentKey(candidate);
    setSelectedAssignments((current) => current.some((item) => assignmentKey(item) === key)
      ? current.filter((item) => assignmentKey(item) !== key)
      : [...current, {
          subject: candidate.subject,
          department: candidate.department,
          grade: candidate.grade,
          className: candidate.className,
        }]);
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (selectedSubjects.length === 0) {
      setValidationError("담당 과목을 하나 이상 선택해 주세요.");
      return;
    }
    const missing = selectedSubjects.find((subject) => !selectedAssignments.some(
      (assignment) => normalizeSubjectName(assignment.subject) === subject,
    ));
    if (missing) {
      setValidationError(`${missing} 과목의 실제 담당 학급을 하나 이상 선택해 주세요.`);
      return;
    }
    if (selectedAssignments.length > 40) {
      setValidationError("담당 학급은 최대 40개까지 저장할 수 있습니다.");
      return;
    }
    onSave({ v: 1, assignments: selectedAssignments, includeSubject });
  }

  return (
    <main className="page-shell setup-page teacher-page">
      <header className="setup-heading">
        <p className="eyebrow">HANSEI TEACHER</p>
        <h1>{initialSettings ? "교사용 설정 변경" : "한세 교사용 시간표"}</h1>
        <p>과목뿐 아니라 실제 담당 학과·학년·반까지 확인해야 다른 선생님의 수업이 섞이지 않습니다.</p>
      </header>

      <form onSubmit={submit}>
        <section className="card teacher-setup-card" aria-labelledby="teacher-school-heading">
          <div className="setup-section-heading">
            <span className="step-number" aria-hidden="true">1</span>
            <div><h2 id="teacher-school-heading">학교 선택</h2><p>현재는 한세사이버보안고등학교만 지원합니다.</p></div>
          </div>
          <div className="fixed-school-option"><div><strong>{HANSEI_SCHOOL.name}</strong><small>서울특별시교육청 · 고등학교</small></div><span className="selection-indicator"><CheckIcon /></span></div>
        </section>

        <section className="card teacher-setup-card" aria-labelledby="teacher-subject-heading">
          <div className="setup-section-heading">
            <span className="step-number" aria-hidden="true">2</span>
            <div><h2 id="teacher-subject-heading">담당 과목</h2><p>현재 학기 시간표에서 확인된 과목만 표시합니다. 복수 선택할 수 있습니다.</p></div>
          </div>
          <div className="input-with-icon teacher-subject-search">
            <SearchIcon />
            <input aria-label="과목 검색" type="search" value={subjectSearch} onChange={(event) => setSubjectSearch(event.target.value)} placeholder="과목명 검색" />
          </div>
          {subjects === null && <p className="teacher-loading"><span className="spinner" aria-hidden="true" />과목 목록을 불러오는 중입니다.</p>}
          {subjectsError && <div className="inline-error" role="alert">{subjectsError}<button type="button" onClick={() => void loadSubjects()}>다시 시도</button></div>}
          {subjects !== null && !subjectsError && filteredSubjects.length === 0 && <p className="compact-empty">표시할 과목이 없습니다.</p>}
          <div className="teacher-check-list" aria-label="담당 과목 목록">
            {filteredSubjects.map((subject) => (
              <label key={subject} className="teacher-check-option">
                <input type="checkbox" checked={selectedSubjects.includes(subject)} onChange={() => toggleSubject(subject)} />
                <span>{subject}</span>
              </label>
            ))}
          </div>
        </section>

        <section className="card teacher-setup-card" aria-labelledby="teacher-class-heading">
          <div className="setup-section-heading">
            <span className="step-number" aria-hidden="true">3</span>
            <div><h2 id="teacher-class-heading">담당 학급 확인</h2><p>본인이 실제 가르치는 반만 직접 체크하세요. 기본 선택은 없습니다.</p></div>
          </div>
          {selectedSubjects.length === 0 && <p className="compact-empty">먼저 담당 과목을 선택해 주세요.</p>}
          <div className="candidate-groups">
            {selectedSubjects.map((subject) => {
              const values = candidates[subject] ?? [];
              return (
                <fieldset key={subject} className="candidate-group">
                  <legend>{subject}</legend>
                  {loadingCandidates.includes(subject) && <p className="teacher-loading"><span className="spinner" aria-hidden="true" />담당 학급 후보를 분석하는 중입니다.</p>}
                  {candidateErrors[subject] && <div className="inline-error" role="alert">{candidateErrors[subject]}<button type="button" onClick={() => void loadCandidates(subject)}>다시 시도</button></div>}
                  {!loadingCandidates.includes(subject) && !candidateErrors[subject] && values.length === 0 && <p className="compact-empty">이 과목의 학급 후보가 없습니다.</p>}
                  <div className="teacher-check-list">
                    {values.map((candidate) => {
                      const key = assignmentKey(candidate);
                      return (
                        <label key={key} className="teacher-check-option class-option">
                          <input type="checkbox" checked={selectedAssignments.some((item) => assignmentKey(item) === key)} onChange={() => toggleAssignment(candidate)} />
                          <span><strong>{candidate.departmentSpeech}</strong> {candidate.grade}학년 {candidate.className}반<small>{candidate.departmentDisplay}</small></span>
                        </label>
                      );
                    })}
                  </div>
                </fieldset>
              );
            })}
          </div>
          <label className="teacher-toggle">
            <input type="checkbox" checked={includeSubject} onChange={(event) => setIncludeSubject(event.target.checked)} />
            <span><strong>음성에 과목명 포함</strong><small>여러 과목을 담당해 구분이 필요할 때 켜세요. 기본값은 꺼짐입니다.</small></span>
          </label>
          {validationError && <p className="inline-error" role="alert">{validationError}</p>}
          <div className="form-actions">
            {onCancel && <button className="button secondary grow" type="button" onClick={onCancel}>취소</button>}
            <button className="button primary grow" type="submit">설정 저장</button>
          </div>
        </section>
      </form>
      <p className="privacy-note">설정은 이 브라우저에만 저장되며 교사 이름은 수집하지 않습니다.</p>
    </main>
  );
}

interface DashboardProps {
  settings: TeacherSettings;
  onEdit: () => void;
  onReset: () => void;
}

function TeacherDashboard({ settings, onEdit, onReset }: DashboardProps) {
  const [timetable, setTimetable] = useState<TeacherTimetable | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [siriOpen, setSiriOpen] = useState(false);
  const lastRefreshAttempt = useRef(0);
  const profile = useMemo(() => encodeTeacherProfile(settings), [settings]);

  const loadTimetable = useCallback(async () => {
    lastRefreshAttempt.current = Date.now();
    setIsLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams({ p: profile });
      const response = await fetch(`/api/hansei-t/timetable?${params.toString()}`, { cache: "no-store" });
      if (!response.ok) throw new Error(await readApiError(response, "교사용 시간표를 불러오지 못했습니다."));
      const body = (await response.json()) as TeacherTimetable;
      setTimetable({ ...body, lessons: [...body.lessons].sort((left, right) => left.period - right.period) });
    } catch (reason) {
      setTimetable(null);
      setError(reason instanceof Error ? reason.message : "교사용 시간표를 불러오지 못했습니다.");
    } finally {
      setIsLoading(false);
    }
  }, [profile]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadTimetable(), 0);
    const interval = window.setInterval(() => void loadTimetable(), TEACHER_AUTO_REFRESH_MS);
    function refreshAfterReturning() {
      if (
        document.visibilityState === "visible" &&
        Date.now() - lastRefreshAttempt.current >= TEACHER_AUTO_REFRESH_MS
      ) {
        void loadTimetable();
      }
    }
    document.addEventListener("visibilitychange", refreshAfterReturning);
    return () => {
      window.clearTimeout(timer);
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", refreshAfterReturning);
    };
  }, [loadTimetable]);

  return (
    <main className="page-shell timetable-page teacher-page">
      <header className="app-header">
        <a className="brand" href="#teacher-main">한세 교사용 시간표</a>
        <button className="button header-settings" type="button" onClick={onEdit}><SettingsIcon />설정 변경</button>
      </header>
      <section id="teacher-main" className="hero-card teacher-hero">
        <div><p className="date-line">{timetable?.date ?? "오늘 수업"}</p><h1>{HANSEI_SCHOOL.name}</h1><p>{timetable ? `${timetable.queriedAtLabel} 조회` : "담당 학급 기준"}</p></div>
        {!isLoading && !error && <span className="today-badge">교사용</span>}
      </section>
      <div className="section-title-row"><h2>오늘 수업</h2>{timetable && !error && <span>{timetable.lessons.length}개 수업</span>}</div>

      {isLoading && <TeacherSkeleton />}
      {!isLoading && error && (
        <section className="state-card" role="alert"><span className="state-icon" aria-hidden="true">!</span><h2>시간표를 확인하지 못했어요</h2><p>{error}</p><button className="button primary" type="button" onClick={() => void loadTimetable()}>다시 시도</button></section>
      )}
      {!isLoading && !error && timetable?.lessons.length === 0 && (
        <section className="state-card empty-state"><span className="state-icon moon" aria-hidden="true">☾</span><h2>오늘 배정된 수업이 없습니다.</h2><p>주말·휴업일이거나 학교에서 시간표를 아직 게시하지 않았을 수 있습니다.</p><button className="button secondary" type="button" onClick={() => void loadTimetable()}><RefreshIcon />새로고침</button></section>
      )}
      {!isLoading && !error && timetable && timetable.ambiguousPeriods.length > 0 && (
        <p className="teacher-ambiguity" role="alert"><strong>확인이 필요한 교시:</strong> {timetable.ambiguousPeriods.map((period) => `${period}교시`).join(", ")}에 서로 다른 담당 학급이 함께 잡혔습니다. 아래 수업을 모두 표시합니다.</p>
      )}
      {!isLoading && !error && timetable && timetable.lessons.length > 0 && (
        <ol className="lesson-list teacher-lesson-list">
          {timetable.lessons.map((lesson) => (
            <li className={lesson.ambiguous ? "ambiguous" : ""} key={[lesson.period, lesson.subject, lesson.department, lesson.grade, lesson.className].join(":")}>
              <span className="period-number">{lesson.period}</span>
              <div><small>{lesson.period}교시{lesson.ambiguous ? " · 충돌 확인 필요" : ""}</small><strong>{lesson.departmentSpeech} {lesson.grade}학년 {lesson.className}반</strong><span>{lesson.subject}</span></div>
            </li>
          ))}
        </ol>
      )}

      <section className="teacher-actions" aria-label="교사용 시간표 동작">
        <button className="button secondary" type="button" disabled={isLoading} onClick={() => void loadTimetable()}><RefreshIcon />새로고침</button>
        <button className="button primary" type="button" onClick={() => setSiriOpen(true)}>Siri 설정</button>
        <button className="button secondary" type="button" onClick={onEdit}>설정 변경</button>
        <button className="button danger-button" type="button" onClick={onReset}>설정 초기화</button>
      </section>
      <p className="teacher-source-note">화면은 30분마다 자동 새로고침됩니다. 표시 시각은 NEIS 자료를 우리 서버가 조회한 시각이며 NEIS 자체의 최종 수정 시각을 의미하지 않습니다.</p>
      <TeacherSiriDialog open={siriOpen} settings={settings} onClose={() => setSiriOpen(false)} />
    </main>
  );
}

function TeacherSkeleton() {
  return <div className="lesson-list skeleton-list" aria-live="polite" aria-busy="true"><span className="sr-only">교사용 시간표를 불러오는 중입니다.</span>{[1, 2, 3].map((item) => <div className="skeleton-row" key={item}><span /><div><i /><b /></div></div>)}</div>;
}
