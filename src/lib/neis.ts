import { MemoryCache } from "@/lib/cache";
import { AppError } from "@/lib/errors";
import type { Lesson, School, SchoolKind, TimetableResponse } from "@/lib/types";
import type { TimetableQuery } from "@/lib/schemas";

export const NEIS_BASE_URL = "https://open.neis.go.kr/hub";

const DATASETS: Readonly<Record<SchoolKind, string>> = {
  초등학교: "elsTimetable",
  중학교: "misTimetable",
  고등학교: "hisTimetable",
  특수학교: "spsTimetable",
};

const MOCK_SCHOOLS: readonly School[] = [
  {
    officeCode: "B10",
    schoolCode: "7010911",
    name: "한세사이버보안고등학교",
    kind: "고등학교",
    address: "서울특별시 마포구 마포대로11길 44-80",
    region: "서울특별시교육청",
  },
  {
    officeCode: "B10",
    schoolCode: "7041131",
    name: "서울미래초등학교",
    kind: "초등학교",
    address: "서울특별시 구로구 새말로 73",
    region: "서울특별시교육청",
  },
] as const;

const MOCK_LESSONS: readonly Lesson[] = [
  { period: 1, subject: "자료구조" },
  { period: 2, subject: "영어" },
  { period: 3, subject: "체육" },
  { period: 4, subject: "웹 프로그래밍" },
] as const;

const schoolCache = new MemoryCache<School[]>(200);
const timetableCache = new MemoryCache<TimetableResponse>(500);

export function timetableDataset(kind: SchoolKind): string {
  return DATASETS[kind];
}

type JsonRecord = Record<string, unknown>;

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringField(row: JsonRecord, key: string): string {
  return typeof row[key] === "string" ? row[key].trim() : "";
}

function resultFrom(value: unknown): { code: string; message: string } | undefined {
  if (!isRecord(value)) return undefined;
  const code = stringField(value, "CODE");
  if (!code) return undefined;
  return { code, message: stringField(value, "MESSAGE") };
}

function responseResult(payload: JsonRecord, dataset: unknown[]): { code: string; message: string } | undefined {
  const direct = resultFrom(payload.RESULT);
  if (direct) return direct;

  for (const section of dataset) {
    if (!isRecord(section) || !Array.isArray(section.head)) continue;
    for (const item of section.head) {
      if (!isRecord(item)) continue;
      const result = resultFrom(item.RESULT);
      if (result) return result;
    }
  }
  return undefined;
}

export function extractNeisRows(payload: unknown, datasetName: string): JsonRecord[] {
  if (!isRecord(payload)) {
    throw new AppError("NEIS_ERROR", 502, "교육정보 응답 형식이 올바르지 않습니다.");
  }

  const datasetValue = payload[datasetName];
  const dataset = Array.isArray(datasetValue) ? datasetValue : [];
  const result = responseResult(payload, dataset);

  if (result?.code === "INFO-200") return [];
  if (result && result.code !== "INFO-000" && result.code !== "INFO-100") {
    throw new AppError("NEIS_ERROR", 502, "교육정보 서비스가 요청을 처리하지 못했습니다.");
  }
  if (!Array.isArray(datasetValue)) {
    throw new AppError("NEIS_ERROR", 502, "교육정보 응답 형식이 올바르지 않습니다.");
  }

  for (const section of dataset) {
    if (!isRecord(section) || !Array.isArray(section.row)) continue;
    return section.row.filter(isRecord);
  }
  return [];
}

function parseSchoolKind(value: string): SchoolKind | undefined {
  if (value.includes("초등학교")) return "초등학교";
  if (value.includes("중학교")) return "중학교";
  if (value.includes("고등학교")) return "고등학교";
  if (value.includes("특수학교")) return "특수학교";
  return undefined;
}

export function parseSchools(payload: unknown): School[] {
  const unique = new Map<string, School>();
  for (const row of extractNeisRows(payload, "schoolInfo")) {
    const officeCode = stringField(row, "ATPT_OFCDC_SC_CODE");
    const schoolCode = stringField(row, "SD_SCHUL_CODE");
    const name = stringField(row, "SCHUL_NM");
    const kind = parseSchoolKind(stringField(row, "SCHUL_KND_SC_NM"));
    if (!officeCode || !schoolCode || !name || !kind) continue;

    const school: School = {
      officeCode,
      schoolCode,
      name,
      kind,
      address: stringField(row, "ORG_RDNMA"),
      region: stringField(row, "ATPT_OFCDC_SC_NM"),
    };
    unique.set(`${officeCode}:${schoolCode}`, school);
  }

  return [...unique.values()].sort((left, right) =>
    left.name.localeCompare(right.name, "ko-KR") || left.region.localeCompare(right.region, "ko-KR"),
  );
}

export function parseLessons(rows: readonly JsonRecord[]): Lesson[] {
  const subjectsByPeriod = new Map<number, Set<string>>();
  for (const row of rows) {
    const periodText = stringField(row, "PERIO");
    const subject = stringField(row, "ITRT_CNTNT").replace(/\s+/g, " ");
    if (!/^\d{1,2}$/.test(periodText) || !subject) continue;
    const period = Number(periodText);
    if (period < 1 || period > 20) continue;
    const subjects = subjectsByPeriod.get(period) ?? new Set<string>();
    subjects.add(subject.slice(0, 100));
    subjectsByPeriod.set(period, subjects);
  }
  return [...subjectsByPeriod.entries()]
    .map(([period, subjects]) => ({ period, subject: combineSubjects([...subjects]) }))
    .sort((left, right) => left.period - right.period);
}

function combineSubjects(subjects: string[]): string {
  const ordered = subjects.sort((left, right) => left.localeCompare(right, "ko-KR"));
  if (ordered.length === 1) return ordered[0] ?? "";

  const suffix = " (선택·이동 수업 가능)";
  const limit = 100 - suffix.length;
  const selected: string[] = [];
  for (const subject of ordered) {
    const candidate = [...selected, subject].join(" 또는 ");
    if (candidate.length > limit || selected.length >= 4) {
      if (selected.length === 0) selected.push(subject.slice(0, limit));
      break;
    }
    selected.push(subject);
  }
  const omitted = ordered.length - selected.length;
  const choices = selected.join(" 또는 ");
  if (omitted === 0) return `${choices}${suffix}`;

  const omittedLabel = ` 외 ${omitted}개 과목`;
  const available = Math.max(1, limit - omittedLabel.length);
  return `${choices.slice(0, available)}${omittedLabel}${suffix}`;
}

function matchesTimetableRequest(row: JsonRecord, query: TimetableQuery, date: string): boolean {
  const expectedFields: ReadonlyArray<readonly [string, string]> = [
    ["ATPT_OFCDC_SC_CODE", query.officeCode],
    ["SD_SCHUL_CODE", query.schoolCode],
    ["ALL_TI_YMD", date.replaceAll("-", "")],
    ["GRADE", String(query.grade)],
    ["CLASS_NM", String(query.className)],
  ];
  return expectedFields.every(([field, expected]) => {
    const actual = stringField(row, field);
    return actual.length === 0 || actual === expected;
  });
}

export interface NeisClientOptions {
  apiKey?: string;
  timeoutMs?: number;
  maxAttempts?: number;
  retryDelayMs?: number;
  fetchImplementation?: typeof fetch;
}

export class NeisClient {
  private readonly apiKey: string;
  private readonly timeoutMs: number;
  private readonly maxAttempts: number;
  private readonly retryDelayMs: number;
  private readonly fetchImplementation: typeof fetch;

  constructor(options: NeisClientOptions = {}) {
    this.apiKey = (options.apiKey ?? process.env.NEIS_API_KEY ?? "").trim();
    this.timeoutMs = Math.max(1, Math.min(options.timeoutMs ?? 5_000, 15_000));
    this.maxAttempts = Math.max(1, Math.min(options.maxAttempts ?? 2, 3));
    this.retryDelayMs = Math.max(0, Math.min(options.retryDelayMs ?? 120, 1_000));
    this.fetchImplementation = options.fetchImplementation ?? fetch;
  }

  get isMockMode(): boolean {
    return this.apiKey.length === 0 || process.env.NEIS_MOCK_MODE === "true";
  }

  async searchSchools(name: string): Promise<School[]> {
    if (this.isMockMode) {
      const needle = name.replace(/\s+/g, "").toLocaleLowerCase("ko-KR");
      return MOCK_SCHOOLS.filter((school) =>
        school.name.replace(/\s+/g, "").toLocaleLowerCase("ko-KR").includes(needle),
      ).map((school) => ({ ...school }));
    }
    const payload = await this.request("schoolInfo", { SCHUL_NM: name, pIndex: "1", pSize: "50" });
    return parseSchools(payload);
  }

  async getTodayTimetable(query: TimetableQuery, date: string): Promise<TimetableResponse> {
    const dataset = timetableDataset(query.kind);
    if (this.isMockMode) {
      const school = MOCK_SCHOOLS.find((item) => item.schoolCode === query.schoolCode);
      if (!school || school.officeCode !== query.officeCode || school.kind !== query.kind) {
        throw new AppError(
          "NOT_FOUND",
          404,
          "학교 설정을 찾을 수 없습니다. 학교를 다시 검색해 설정해 주세요.",
        );
      }
      return {
        date,
        school: { name: school.name, kind: query.kind },
        grade: query.grade,
        className: query.className,
        lessons: MOCK_LESSONS.map((lesson) => ({ ...lesson })),
      };
    }

    const payload = await this.request(dataset, {
      ATPT_OFCDC_SC_CODE: query.officeCode,
      SD_SCHUL_CODE: query.schoolCode,
      ALL_TI_YMD: date.replaceAll("-", ""),
      GRADE: String(query.grade),
      CLASS_NM: String(query.className),
      pIndex: "1",
      pSize: "100",
    });
    const rows = extractNeisRows(payload, dataset).filter((row) =>
      matchesTimetableRequest(row, query, date),
    );
    let schoolName = rows.length > 0 ? stringField(rows[0] ?? {}, "SCHUL_NM") : "";
    if (!schoolName) {
      const schoolPayload = await this.request("schoolInfo", {
        ATPT_OFCDC_SC_CODE: query.officeCode,
        SD_SCHUL_CODE: query.schoolCode,
        pIndex: "1",
        pSize: "5",
      });
      const matchingSchool = parseSchools(schoolPayload).find(
        (school) =>
          school.officeCode === query.officeCode &&
          school.schoolCode === query.schoolCode &&
          school.kind === query.kind,
      );
      if (!matchingSchool) {
        throw new AppError(
          "NOT_FOUND",
          404,
          "학교 설정을 찾을 수 없습니다. 학교를 다시 검색해 설정해 주세요.",
        );
      }
      schoolName = matchingSchool.name;
    }
    return {
      date,
      school: {
        name: schoolName,
        kind: query.kind,
      },
      grade: query.grade,
      className: query.className,
      lessons: parseLessons(rows),
    };
  }

  private async request(dataset: string, parameters: Readonly<Record<string, string>>): Promise<unknown> {
    if (!Object.values(DATASETS).includes(dataset) && dataset !== "schoolInfo") {
      throw new AppError("INVALID_INPUT", 400, "지원하지 않는 교육정보 요청입니다.");
    }
    const url = new URL(`${NEIS_BASE_URL}/${dataset}`);
    url.searchParams.set("KEY", this.apiKey);
    url.searchParams.set("Type", "json");
    for (const [name, value] of Object.entries(parameters)) url.searchParams.set(name, value);

    let lastError: unknown;
    for (let attempt = 1; attempt <= this.maxAttempts; attempt += 1) {
      try {
        return await this.fetchJson(url);
      } catch (error) {
        lastError = error;
        const retryable =
          error instanceof AppError &&
          (error.code === "NEIS_TIMEOUT" || error.code === "NEIS_UNAVAILABLE");
        if (!retryable || attempt >= this.maxAttempts) throw error;
        await new Promise<void>((resolve) => setTimeout(resolve, this.retryDelayMs * attempt));
      }
    }
    throw lastError;
  }

  private async fetchJson(url: URL): Promise<unknown> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImplementation(url, {
        method: "GET",
        signal: controller.signal,
        headers: { Accept: "application/json" },
        cache: "no-store",
      });
      if (response.status === 429 || response.status >= 500) {
        throw new AppError("NEIS_UNAVAILABLE", 503, "교육정보 서비스에 일시적으로 연결할 수 없습니다.");
      }
      if (!response.ok) {
        throw new AppError("NEIS_ERROR", 502, "교육정보 서비스가 요청을 처리하지 못했습니다.");
      }
      const text = await response.text();
      if (text.length > 2_000_000) {
        throw new AppError("NEIS_ERROR", 502, "교육정보 응답이 허용된 크기를 초과했습니다.");
      }
      try {
        return JSON.parse(text) as unknown;
      } catch (error) {
        throw new AppError("NEIS_ERROR", 502, "교육정보 응답 형식이 올바르지 않습니다.", { cause: error });
      }
    } catch (error) {
      if (error instanceof AppError) throw error;
      if (isRecord(error) && error.name === "AbortError") {
        throw new AppError("NEIS_TIMEOUT", 504, "교육정보 서비스 응답이 지연되고 있습니다.", { cause: error });
      }
      throw new AppError("NEIS_UNAVAILABLE", 503, "교육정보 서비스에 일시적으로 연결할 수 없습니다.", {
        cause: error,
      });
    } finally {
      clearTimeout(timer);
    }
  }
}

export async function searchSchools(name: string): Promise<School[]> {
  const key = name.trim().replace(/\s+/g, " ").toLocaleLowerCase("ko-KR");
  return schoolCache.getOrLoad(key, 10 * 60_000, () => new NeisClient().searchSchools(name));
}

export async function getTodayTimetable(query: TimetableQuery, date: string): Promise<TimetableResponse> {
  const key = [date, query.officeCode, query.schoolCode, query.kind, query.grade, query.className].join(":");
  return timetableCache.getOrLoad(key, 5 * 60_000, () => new NeisClient().getTodayTimetable(query, date));
}

export function clearNeisCaches(): void {
  schoolCache.clear();
  timetableCache.clear();
}
