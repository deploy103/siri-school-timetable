"use client";

import { FormEvent, useMemo, useRef, useState } from "react";
import { CheckIcon, SearchIcon } from "@/components/icons";
import type { ApiErrorBody, School, SchoolSettings, SchoolsResponse } from "@/types/client";

interface Props {
  initialSettings?: SchoolSettings | null;
  onSave: (settings: SchoolSettings) => void;
  onCancel?: () => void;
}

function gradeLimit(school: School): number {
  return school.kind === "초등학교" || school.kind === "특수학교" ? 6 : 3;
}

async function readError(response: Response): Promise<string> {
  try {
    const body = (await response.json()) as ApiErrorBody;
    return body.error?.message ?? body.message ?? "학교를 검색하지 못했습니다.";
  } catch {
    return "학교를 검색하지 못했습니다.";
  }
}

export function SchoolSetup({ initialSettings, onSave, onCancel }: Props) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<School[]>([]);
  const [selected, setSelected] = useState<School | null>(initialSettings?.school ?? null);
  const [grade, setGrade] = useState(initialSettings?.grade ?? 1);
  const [className, setClassName] = useState(initialSettings?.className ?? 1);
  const [isSearching, setIsSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const resultsHeading = useRef<HTMLHeadingElement>(null);

  const grades = useMemo(
    () => Array.from({ length: selected ? gradeLimit(selected) : 3 }, (_, index) => index + 1),
    [selected],
  );
  const classes = useMemo(() => Array.from({ length: 20 }, (_, index) => index + 1), []);

  async function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const name = query.trim();
    if (name.length < 2) {
      setError("학교 이름을 두 글자 이상 입력해 주세요.");
      return;
    }

    setIsSearching(true);
    setError(null);
    setHasSearched(true);
    try {
      const response = await fetch(`/api/schools?name=${encodeURIComponent(name)}`);
      if (!response.ok) throw new Error(await readError(response));
      const body = (await response.json()) as SchoolsResponse;
      setResults(body.schools);
      window.setTimeout(() => resultsHeading.current?.focus(), 0);
    } catch (reason) {
      setResults([]);
      setError(reason instanceof Error ? reason.message : "학교를 검색하지 못했습니다.");
    } finally {
      setIsSearching(false);
    }
  }

  function chooseSchool(school: School) {
    setSelected(school);
    setGrade(1);
    setClassName(1);
  }

  function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (selected) onSave({ school: selected, grade, className });
  }

  return (
    <main className="page-shell setup-page">
      <header className="setup-heading">
        <span className="brand-mark" aria-hidden="true">시</span>
        <p className="eyebrow">오늘의 시간표</p>
        <h1>{initialSettings ? "학교 설정 변경" : "내 학교를 알려주세요"}</h1>
        <p>학교와 학년, 반을 한 번만 설정하면 다음부터 바로 오늘 시간표를 볼 수 있어요.</p>
      </header>

      <section className="card setup-card" aria-labelledby="school-search-heading">
        <h2 id="school-search-heading">학교 찾기</h2>
        <form className="search-form" onSubmit={search} role="search">
          <label htmlFor="school-name">학교 이름</label>
          <div className="search-row">
            <div className="input-with-icon">
              <SearchIcon />
              <input
                id="school-name"
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="예: 한세사이버보안고"
                autoComplete="off"
                enterKeyHint="search"
              />
            </div>
            <button className="button primary search-button" disabled={isSearching} type="submit">
              {isSearching ? <><span className="spinner" aria-hidden="true" />검색 중</> : "검색"}
            </button>
          </div>
        </form>

        <div aria-live="polite" className="search-feedback">
          {error && <p className="inline-error" role="alert">{error}</p>}
          {!error && hasSearched && !isSearching && results.length === 0 && (
            <div className="compact-empty">
              <strong>검색 결과가 없어요.</strong>
              <span>학교의 정식 이름이나 지역명을 빼고 다시 검색해 보세요.</span>
            </div>
          )}
        </div>

        {results.length > 0 && (
          <div className="results-section">
            <h3 ref={resultsHeading} tabIndex={-1}>검색 결과 <span>{results.length}</span></h3>
            <ul className="school-results">
              {results.map((school) => {
                const active = selected?.officeCode === school.officeCode && selected.schoolCode === school.schoolCode;
                return (
                  <li key={`${school.officeCode}-${school.schoolCode}`}>
                    <button
                      type="button"
                      className={`school-option${active ? " selected" : ""}`}
                      aria-pressed={active}
                      onClick={() => chooseSchool(school)}
                    >
                      <span className="school-option-main">
                        <strong>{school.name}</strong>
                        <span>{school.region} · {school.kind}</span>
                        <small>{school.address}</small>
                      </span>
                      <span className="selection-indicator" aria-hidden="true">{active && <CheckIcon />}</span>
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
        )}
      </section>

      {selected && (
        <section className="card class-card" aria-labelledby="class-heading">
          <div className="selected-school">
            <span className="selected-badge"><CheckIcon /> 선택한 학교</span>
            <h2 id="class-heading">{selected.name}</h2>
            <p>{selected.region} · {selected.kind}</p>
          </div>
          <form onSubmit={save}>
            <div className="select-grid">
              <label>학년
                <select value={grade} onChange={(event) => setGrade(Number(event.target.value))}>
                  {grades.map((item) => <option key={item} value={item}>{item}학년</option>)}
                </select>
              </label>
              <label>반
                <select value={className} onChange={(event) => setClassName(Number(event.target.value))}>
                  {classes.map((item) => <option key={item} value={item}>{item}반</option>)}
                </select>
              </label>
            </div>
            {(selected.kind === "고등학교" || selected.kind === "특수학교") && (
              <p className="course-notice">
                {selected.kind === "고등학교"
                  ? "선택과목·학과별 이동 수업은 학년과 반만으로 정확히 구분되지 않아 가능한 수업을 함께 표시할 수 있어요."
                  : "학교 과정·강의실이 여러 개인 경우 학년과 반만으로 정확히 구분되지 않아 가능한 수업을 함께 표시할 수 있어요."}
              </p>
            )}
            <div className="form-actions">
              {onCancel && <button type="button" className="button secondary" onClick={onCancel}>취소</button>}
              <button type="submit" className="button primary grow">설정 저장하고 시간표 보기</button>
            </div>
          </form>
        </section>
      )}
      <p className="privacy-note">설정은 이 기기에만 안전하게 저장됩니다.</p>
    </main>
  );
}
