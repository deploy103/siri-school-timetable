"use client";

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CheckIcon, SearchIcon } from "@/components/icons";
import { EDUCATION_OFFICES } from "@/lib/education-offices";
import type {
  ApiErrorBody,
  ClassesResponse,
  School,
  SchoolClass,
  SchoolSettings,
  SchoolsResponse,
} from "@/types/client";

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
  const [department, setDepartment] = useState(initialSettings?.department ?? "");
  const [classOptions, setClassOptions] = useState<SchoolClass[] | null>(null);
  const [isLoadingClasses, setIsLoadingClasses] = useState(false);
  const [classError, setClassError] = useState<string | null>(null);
  const [isSearching, setIsSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const resultsHeading = useRef<HTMLHeadingElement>(null);

  const departmentOptions = useMemo(
    () => [...new Set((classOptions ?? []).map((item) => item.department).filter(Boolean))] as string[],
    [classOptions],
  );
  const classesForDepartment = useMemo(
    () => (classOptions ?? []).filter((item) => (item.department ?? "") === department),
    [classOptions, department],
  );
  const grades = useMemo(() => {
    if (classesForDepartment.length > 0) {
      return [...new Set(classesForDepartment.map((item) => item.grade))].sort((a, b) => a - b);
    }
    return Array.from({ length: selected ? gradeLimit(selected) : 3 }, (_, index) => index + 1);
  }, [classesForDepartment, selected]);
  const classNames = useMemo(
    () => [...new Set(classesForDepartment
      .filter((item) => item.grade === grade)
      .map((item) => item.className))]
      .sort((left, right) => left.localeCompare(right, "ko-KR", { numeric: true })),
    [classesForDepartment, grade],
  );

  const loadClasses = useCallback(async (school: School, preferred?: Partial<SchoolSettings>) => {
    setIsLoadingClasses(true);
    setClassError(null);
    setClassOptions(null);
    try {
      const params = new URLSearchParams({
        officeCode: school.officeCode,
        schoolCode: school.schoolCode,
      });
      const response = await fetch(`/api/classes?${params.toString()}`);
      if (!response.ok) throw new Error(await readError(response));
      const body = (await response.json()) as ClassesResponse;
      const classes = Array.isArray(body.classes) ? body.classes : [];
      setClassOptions(classes);
      const matched = classes.find((item) =>
        item.grade === preferred?.grade &&
        item.className === preferred.className &&
        (item.department ?? "") === (preferred.department ?? ""),
      ) ?? classes[0];
      if (matched) {
        setDepartment(matched.department ?? "");
        setGrade(matched.grade);
        setClassName(matched.className);
      } else {
        setClassError("NEIS에서 확인된 학급이 없어 직접 입력해야 합니다.");
      }
    } catch (reason) {
      setClassOptions([]);
      setClassError(
        reason instanceof Error
          ? `${reason.message} 학급을 직접 입력할 수 있습니다.`
          : "학급 정보를 불러오지 못했습니다. 직접 입력해 주세요.",
      );
    } finally {
      setIsLoadingClasses(false);
    }
  }, []);

  useEffect(() => {
    if (!initialSettings?.school) return;
    const timer = window.setTimeout(
      () => void loadClasses(initialSettings.school, initialSettings),
      0,
    );
    return () => window.clearTimeout(timer);
  }, [initialSettings, loadClasses]);

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
    setDepartment("");
    setGrade(1);
    setClassName("1");
    void loadClasses(school, { grade: 1, className: "1" });
  }

  function changeDepartment(nextDepartment: string) {
    const first = (classOptions ?? []).find(
      (item) => (item.department ?? "") === nextDepartment,
    );
    setDepartment(nextDepartment);
    if (first) {
      setGrade(first.grade);
      setClassName(first.className);
    }
  }

  function changeGrade(nextGrade: number) {
    const first = classesForDepartment.find((item) => item.grade === nextGrade);
    setGrade(nextGrade);
    if (first) setClassName(first.className);
  }

  function changeOffice(nextOfficeCode: string) {
    setOfficeCode(nextOfficeCode);
    setResults([]);
    setHasSearched(false);
    setError(null);
    if (selected?.officeCode !== nextOfficeCode) {
      setSelected(null);
      setClassOptions(null);
      setDepartment("");
    }
  }

  function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedClassName = className.trim();
    if (selected && normalizedClassName) {
      onSave({
        school: selected,
        grade,
        className: normalizedClassName,
        ...(department ? { department } : {}),
      });
    }
  }

  return (
    <main className="page-shell setup-page">
      <header className="setup-heading">
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
            {isLoadingClasses && <p className="searching-message">NEIS에서 학과와 학급을 확인하고 있어요.</p>}
            {classError && <p className="inline-error">{classError}</p>}
            <div className="select-grid">
              {departmentOptions.length > 0 && (
                <div className="full-grid-field">
                  <label htmlFor="school-department">학과</label>
                  <select
                    id="school-department"
                    value={department}
                    onChange={(event) => changeDepartment(event.target.value)}
                    disabled={isLoadingClasses}
                  >
                    {departmentOptions.map((item) => <option key={item} value={item}>{item}</option>)}
                  </select>
                </div>
              )}
              <div>
                <label htmlFor="school-grade">학년</label>
                <select
                  id="school-grade"
                  value={grade}
                  onChange={(event) => changeGrade(Number(event.target.value))}
                  disabled={isLoadingClasses}
                >
                  {grades.map((item) => <option key={item} value={item}>{item}학년</option>)}
                </select>
              </div>
              <div>
                <label htmlFor="school-class">반</label>
                {classNames.length > 0 ? (
                  <select
                    id="school-class"
                    value={className}
                    onChange={(event) => setClassName(event.target.value)}
                    disabled={isLoadingClasses}
                  >
                    {classNames.map((item) => <option key={item} value={item}>{item}반</option>)}
                  </select>
                ) : (
                  <input
                    id="school-class"
                    value={className}
                    onChange={(event) => setClassName(event.target.value)}
                    maxLength={20}
                    placeholder="예: 1 또는 난초"
                    required
                  />
                )}
                <p className="field-help">
                  {classNames.length > 0 ? "NEIS에서 확인된 반만 표시합니다." : "숫자 또는 학교에서 사용하는 반 이름을 입력하세요."}
                </p>
              </div>
            </div>
            {(selected.kind === "고등학교" || selected.kind === "특수학교") && (
              <p className="course-notice">
                {selected.kind === "고등학교"
                  ? "특성화고는 학과까지 선택해 다른 학과의 같은 학년·반과 구분합니다."
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
