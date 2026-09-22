"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { RefreshIcon, SettingsIcon } from "@/components/icons";
import { SiriDialog } from "@/components/siri-dialog";
import type { ApiErrorBody, MealsToday, SchoolSettings } from "@/types/client";

interface Props {
  settings: SchoolSettings;
  onChangeSettings: () => void;
  onShowTimetable: () => void;
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
    return new Error(body.error?.message ?? body.message ?? "급식을 불러오지 못했습니다.");
  } catch {
    return new Error("급식을 불러오지 못했습니다.");
  }
}

export function MealView({ settings, onChangeSettings, onShowTimetable }: Props) {
  const [data, setData] = useState<MealsToday | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [siriOpen, setSiriOpen] = useState(false);
  const query = useMemo(() => new URLSearchParams({
    officeCode: settings.school.officeCode,
    schoolCode: settings.school.schoolCode,
  }).toString(), [settings.school.officeCode, settings.school.schoolCode]);

  const loadMeals = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch(`/api/meal/today?${query}`, { cache: "no-store" });
      if (!response.ok) throw await apiError(response);
      const meals = (await response.json()) as MealsToday;
      setData({ ...meals, meals: [...meals.meals].sort((a, b) => Number(a.code) - Number(b.code)) });
    } catch (reason) {
      setData(null);
      if (typeof navigator !== "undefined" && !navigator.onLine) {
        setError("인터넷 연결을 확인한 뒤 다시 시도해 주세요.");
      } else {
        setError(reason instanceof Error ? reason.message : "급식을 불러오지 못했습니다.");
      }
    } finally {
      setIsLoading(false);
    }
  }, [query]);

  useEffect(() => {
    const loadTimer = window.setTimeout(() => void loadMeals(), 0);
    return () => window.clearTimeout(loadTimer);
  }, [loadMeals]);

  return (
    <main className="page-shell timetable-page">
      <header className="app-header">
        <a className="brand" href="#main-content" aria-label="오늘의 급식 홈">오늘의 시간표</a>
        <button className="button header-settings" type="button" onClick={onChangeSettings}><SettingsIcon />설정 변경</button>
      </header>

      <nav className="view-tabs" aria-label="오늘 학교 정보">
        <button type="button" onClick={onShowTimetable}>시간표</button>
        <button type="button" className="active" aria-current="page">급식</button>
      </nav>

      <section id="main-content" className="hero-card meal-hero">
        <div>
          <p className="date-line">{data ? formatDate(data.date) : "오늘 급식"}</p>
          <h1>{data?.school.name || settings.school.name}</h1>
          <p>학교에서 제공하는 오늘의 식단</p>
        </div>
        {!isLoading && !error && <span className="today-badge">오늘</span>}
      </section>

      <div className="section-title-row">
        <h2>오늘 급식</h2>
        {!isLoading && !error && data && <span>{data.meals.length}개 식사</span>}
      </div>

      {isLoading && <MealSkeleton />}

      {!isLoading && error && (
        <section className="state-card" role="alert">
          <span className="state-icon" aria-hidden="true">!</span>
          <h2>급식을 불러오지 못했어요</h2>
          <p>{error}</p>
          <div className="state-actions">
            <button className="button primary" type="button" onClick={() => void loadMeals()}>다시 시도</button>
            <button className="button secondary" type="button" onClick={onChangeSettings}>설정 변경</button>
          </div>
        </section>
      )}

      {!isLoading && !error && data?.meals.length === 0 && (
        <section className="state-card empty-state">
          <span className="state-icon moon" aria-hidden="true">☾</span>
          <h2>오늘 등록된 급식이 없습니다.</h2>
          <p>주말·공휴일·방학이거나 학교에서 급식을 제공하지 않는 날일 수 있습니다.</p>
          <button className="button secondary" type="button" onClick={() => void loadMeals()}><RefreshIcon />새로고침</button>
        </section>
      )}

      {!isLoading && !error && data && data.meals.length > 0 && (
        <div className="meal-list">
          {data.meals.map((meal) => (
            <article className="meal-card" key={`${meal.code}:${meal.name}`}>
              <div className="meal-card-heading">
                <h3>{meal.name}</h3>
              </div>
              <ul>
                {meal.dishes.map((dish, index) => <li key={`${index}:${dish}`}>{dish}</li>)}
              </ul>
            </article>
          ))}
        </div>
      )}

      <section className="action-grid meal-actions" aria-label="급식 동작">
        <button type="button" className="button secondary" disabled={isLoading} onClick={() => void loadMeals()}><RefreshIcon />새로고침</button>
      </section>

      <section className="siri-card">
        <div className="siri-symbol" aria-hidden="true">✦</div>
        <div><p className="eyebrow">Siri와 함께</p><h2>말 한마디로 급식 확인</h2><p>“시리야, 오늘 학교 급식 뭐야?”</p></div>
        <button type="button" className="button siri-button" onClick={() => setSiriOpen(true)}>Siri 설정</button>
      </section>

      <SiriDialog open={siriOpen} settings={settings} onClose={() => setSiriOpen(false)} />
    </main>
  );
}

function MealSkeleton() {
  return (
    <div className="meal-list" aria-live="polite" aria-busy="true">
      <span className="sr-only">급식을 불러오는 중입니다.</span>
      {[1, 2].map((item) => <div className="meal-card meal-skeleton" key={item}><span /><i /><i /><i /></div>)}
    </div>
  );
}
