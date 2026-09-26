"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { GuideIcon, RefreshIcon, SettingsIcon, SpeakerIcon } from "@/components/icons";
import { SiriDialog } from "@/components/siri-dialog";
import type { ApiErrorBody, SchoolSettings, Timetable } from "@/types/client";

interface Props {
  settings: SchoolSettings;
  onChangeSettings: () => void;
  onShowMeal?: () => void;
  onShowGuide?: () => void;
  openSiriOnMount?: boolean;
  onSiriAutoOpened?: () => void;
}

const koreanDate = new Intl.DateTimeFormat("ko-KR", {
  timeZone: "Asia/Seoul",
  month: "long",
  day: "numeric",
  weekday: "long",
});

function formatDate(date: string): string {
  const parsed = new Date(`${date}T12:00:00+09:00`);
  return Number.isNaN(parsed.getTime()) ? date : koreanDate.format(parsed);
}

async function apiError(response: Response): Promise<Error> {
  try {
    const body = (await response.json()) as ApiErrorBody;
    return new Error(body.error?.message ?? body.message ?? "시간표를 불러오지 못했습니다.");
  } catch {
    return new Error("시간표를 불러오지 못했습니다.");
  }
}

export function TimetableView({ settings, onChangeSettings, onShowMeal, onShowGuide, openSiriOnMount, onSiriAutoOpened }: Props) {
  const [timetable, setTimetable] = useState<Timetable | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [siriOpen, setSiriOpen] = useState(() => Boolean(openSiriOnMount));
  const [isSpeaking, setIsSpeaking] = useState(false);

  useEffect(() => {
    if (openSiriOnMount) onSiriAutoOpened?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const query = useMemo(() => {
    const params = new URLSearchParams({
    officeCode: settings.school.officeCode,
    schoolCode: settings.school.schoolCode,
    kind: settings.school.kind,
    grade: String(settings.grade),
    className: String(settings.className),
    });
    if (settings.department) params.set("department", settings.department);
    return params.toString();
  }, [settings]);

  const loadTimetable = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch(`/api/timetable/today?${query}`, { cache: "no-store" });
      if (!response.ok) throw await apiError(response);
      const data = (await response.json()) as Timetable;
      setTimetable({ ...data, lessons: [...data.lessons].sort((a, b) => a.period - b.period) });
    } catch (reason) {
      setTimetable(null);
      if (typeof navigator !== "undefined" && !navigator.onLine) setError("인터넷 연결을 확인한 뒤 다시 시도해 주세요.");
      else setError(reason instanceof Error ? reason.message : "시간표를 불러오지 못했습니다.");
    } finally {
      setIsLoading(false);
    }
  }, [query]);

  useEffect(() => {
    const loadTimer = window.setTimeout(() => void loadTimetable(), 0);
    return () => window.clearTimeout(loadTimer);
  }, [loadTimetable]);
  useEffect(() => () => window.speechSynthesis?.cancel(), []);

  function speak() {
    if (!timetable?.lessons.length || !("speechSynthesis" in window)) return;
    if (isSpeaking) {
      window.speechSynthesis.cancel();
      setIsSpeaking(false);
      return;
    }
    const text = `오늘 시간표는 ${timetable.lessons.map((lesson) =>
      `${lesson.period}교시 ${lesson.ambiguous ? "선택 수업" : lesson.subject}`
    ).join(", ")}입니다.`;
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = "ko-KR";
    utterance.rate = 0.95;
    utterance.onend = () => setIsSpeaking(false);
    utterance.onerror = () => setIsSpeaking(false);
    window.speechSynthesis.cancel();
    window.speechSynthesis.speak(utterance);
    setIsSpeaking(true);
  }

  return (
    <main className="page-shell timetable-page">
      <header className="app-header">
        <a className="brand" href="#main-content" aria-label="오늘의 시간표 홈">오늘의 시간표</a>
        <div className="app-header-actions">
          {onShowGuide && (
            <button className="button header-settings" type="button" onClick={onShowGuide}><GuideIcon />가이드 다시 보기</button>
          )}
          <button className="button header-settings" type="button" onClick={onChangeSettings}><SettingsIcon />설정 변경</button>
        </div>
      </header>

      <nav className="view-tabs" aria-label="오늘 학교 정보">
        <button type="button" className="active" aria-current="page">시간표</button>
        <button type="button" onClick={onShowMeal}>급식</button>
      </nav>

      <section id="main-content" className="hero-card">
        <div>
          <p className="date-line">{timetable ? formatDate(timetable.date) : "오늘 시간표"}</p>
          <h1>{settings.school.name}</h1>
          <p>{settings.department ? `${settings.department} · ` : ""}{settings.grade}학년 {settings.className}반</p>
        </div>
        {!isLoading && !error && <span className="today-badge">오늘</span>}
      </section>

      <div className="section-title-row">
        <h2>오늘 수업</h2>
        {!isLoading && !error && timetable && <span>{timetable.lessons.length}개 수업</span>}
      </div>

      {isLoading && <TimetableSkeleton />}

      {!isLoading && error && (
        <section className="state-card error-state" role="alert">
          <span className="state-icon" aria-hidden="true">!</span>
          <h2>시간표를 불러오지 못했어요</h2>
          <p>{error}</p>
          <div className="state-actions">
            <button className="button primary" type="button" onClick={() => void loadTimetable()}>다시 시도</button>
            <button className="button secondary" type="button" onClick={onChangeSettings}>설정 변경</button>
          </div>
        </section>
      )}

      {!isLoading && !error && timetable?.lessons.length === 0 && (
        <section className="state-card empty-state">
          <span className="state-icon moon" aria-hidden="true">☾</span>
          <h2>오늘 등록된 시간표가 없습니다.</h2>
          <p>주말·휴업일이거나 학교에서 아직 시간표를 제공하지 않았을 수 있습니다.</p>
          <button className="button secondary" type="button" onClick={() => void loadTimetable()}><RefreshIcon />새로고침</button>
        </section>
      )}

      {!isLoading && !error && timetable && timetable.lessons.length > 0 && (
        <>
          {(timetable.lessons[0]?.period ?? 1) > 1 && (
            <p className="period-gap-notice">
              NEIS에 1~{(timetable.lessons[0]?.period ?? 1) - 1}교시 수업 정보가 없어 {(timetable.lessons[0]?.period ?? 1)}교시부터 표시합니다.
            </p>
          )}
          <ol className="lesson-list">
            {timetable.lessons.map((lesson) => (
              <li key={lesson.period}>
                <span className="period-number">{lesson.period}</span>
                <div><small>{lesson.period}교시</small><strong>{lesson.subject}</strong></div>
              </li>
            ))}
          </ol>
        </>
      )}

      <section className="action-grid" aria-label="시간표 동작">
        <button type="button" className="button secondary" disabled={isLoading} onClick={() => void loadTimetable()}><RefreshIcon />새로고침</button>
        <button type="button" className="button secondary" disabled={!timetable?.lessons.length || isLoading || !(typeof window !== "undefined" && "speechSynthesis" in window)} onClick={speak}><SpeakerIcon />{isSpeaking ? "읽기 중지" : "소리내어 읽기"}</button>
      </section>

      <section className="siri-card">
        <div className="siri-symbol" aria-hidden="true">✦</div>
        <div><p className="eyebrow">Siri와 함께</p><h2>말 한마디로 학교 정보 확인</h2><p>시간표와 급식을 각각 물어보세요.</p></div>
        <button type="button" className="button siri-button" onClick={() => setSiriOpen(true)}>Siri 설정</button>
      </section>

      <SiriDialog open={siriOpen} settings={settings} onClose={() => setSiriOpen(false)} />
    </main>
  );
}

function TimetableSkeleton() {
  return (
    <div className="lesson-list skeleton-list" aria-live="polite" aria-busy="true">
      <span className="sr-only">시간표를 불러오는 중입니다.</span>
      {[1, 2, 3, 4].map((item) => <div className="skeleton-row" key={item}><span /><div><i /><b /></div></div>)}
    </div>
  );
}
