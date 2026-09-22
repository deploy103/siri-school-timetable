"use client";

import { FormEvent, useMemo, useRef, useState } from "react";
import { CheckIcon, SearchIcon } from "@/components/icons";
import { EDUCATION_OFFICES } from "@/lib/education-offices";
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
  const [officeCode, setOfficeCode] = useState(initialSettings?.school.officeCode ?? "");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<School[]>([]);
  const [selected, setSelected] = useState<School | null>(initialSettings?.school ?? null);
  const [grade, setGrade] = useState(initialSettings?.grade ?? 1);
  const [className, setClassName] = useState(initialSettings?.className ?? "1");
  const [isSearching, setIsSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const resultsHeading = useRef<HTMLHeadingElement>(null);

  const grades = useMemo(
    () => Array.from({ length: selected ? gradeLimit(selected) : 3 }, (_, index) => index + 1),
    [selected],
  );

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
      const params = new URLSearchParams({ name });
      if (officeCode) params.set("officeCode", officeCode);
      const response = await fetch(`/api/schools?${params.toString()}`);
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
    setClassName("1");
  }

  function changeOffice(nextOfficeCode: string) {
    setOfficeCode(nextOfficeCode);
    setResults([]);
    setHasSearched(false);
    setError(null);
    if (selected?.officeCode !== nextOfficeCode) setSelected(null);
  }

  function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedClassName = className.trim();
    if (selected && normalizedClassName) {
      onSave({ school: selected, grade, className: normalizedClassName });
    }
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
        <div className="setup-section-heading">
          <span className="step-number" aria-hidden="true">1</span>
          <div>
            <h2 id="school-search-heading">지역과 학교 찾기</h2>
            <p>지역을 고르면 같은 이름의 학교를 더 쉽게 찾을 수 있어요.</p>
          </div>
        </div>
        <form className="search-form" onSubmit={search} role="search">
          <label htmlFor="education-office">지역</label>
          <select
            id="education-office"
            value={officeCode}
            onChange={(event) => changeOffice(event.target.value)}
          >
            <option value="">전체 지역</option>
            {EDUCATION_OFFICES.map((office) => (
              <option key={office.code} value={office.code}>{office.shortName}</option>
            ))}
          </select>
          <p className="field-help">
            {officeCode ? "선택한 지역의 학교만 검색합니다." : "전국 17개 시도교육청의 학교를 검색합니다."}
          </p>
          <label htmlFor="school-name">학교 이름</label>
          <div className="search-row">
            <div className="input-with-icon">
              <SearchIcon />
              <input
                id="school-name"
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="예: 미래초등학교"
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
          {isSearching && <p className="searching-message">학교를 검색하고 있어요.</p>}
          {error && <p className="inline-error" role="alert">{error}</p>}
          {!error && hasSearched && !isSearching && results.length === 0 && (
            <div className="compact-empty">
              <strong>검색 결과가 없어요.</strong>
              <span>학교의 정식 이름을 확인하거나 다른 지역 또는 전체 지역으로 다시 검색해 보세요.</span>
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
                        <span className="school-option-meta">{school.locality ?? school.region} · {school.kind}</span>
                        <strong>{school.name}</strong>
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
          <div className="setup-section-heading selected-school-heading">
            <span className="step-number" aria-hidden="true">2</span>
            <div>
              <span className="selected-badge"><CheckIcon /> 선택한 학교</span>
              <h2 id="class-heading">학년과 반 설정</h2>
            </div>
          </div>
          <div className="selected-school">
            <h3>{selected.name}</h3>
            <p>{selected.locality ?? selected.region} · {selected.kind}</p>
            <small>{selected.address}</small>
          </div>
          <form onSubmit={save}>
            <div className="select-grid">
              <div>
                <label htmlFor="school-grade">학년</label>
                <select id="school-grade" value={grade} onChange={(event) => setGrade(Number(event.target.value))}>
                  {grades.map((item) => <option key={item} value={item}>{item}학년</option>)}
                </select>
              </div>
              <div>
                <label htmlFor="school-class">반</label>
                <input
                  id="school-class"
                  value={className}
                  onChange={(event) => setClassName(event.target.value)}
                  maxLength={20}
                  placeholder="예: 1 또는 난초"
                  required
                />
                <p className="field-help">숫자 또는 학교에서 사용하는 반 이름을 입력하세요.</p>
              </div>
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
              <button type="submit" className="button primary grow" disabled={!className.trim()}>
                설정 저장하고 시간표 보기
              </button>
            </div>
          </form>
        </section>
      )}
      <p className="privacy-note">설정은 이 기기에만 안전하게 저장됩니다.</p>
    </main>
  );
}
