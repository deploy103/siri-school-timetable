export const KST_TIME_ZONE = "Asia/Seoul";

export function getKstDate(now: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: KST_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);

  const value = (type: Intl.DateTimeFormatPartTypes): string =>
    parts.find((part) => part.type === type)?.value ?? "";

  return `${value("year")}-${value("month")}-${value("day")}`;
}

export function toNeisDate(date: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new TypeError("날짜 형식이 올바르지 않습니다.");
  }
  return date.replaceAll("-", "");
}

export function formatKstLookupTime(now: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat("ko-KR", {
    timeZone: KST_TIME_ZONE,
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).formatToParts(now);
  const value = (type: Intl.DateTimeFormatPartTypes): string =>
    parts.find((part) => part.type === type)?.value ?? "";
  const dayPeriod = value("dayPeriod") || (Number(value("hour")) < 12 ? "오전" : "오후");
  return `${value("month")}월 ${value("day")}일 ${dayPeriod} ${value("hour")}시 ${value("minute")}분`;
}

function calendarDate(value: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new TypeError("날짜 형식이 올바르지 않습니다.");
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw new TypeError("날짜 형식이 올바르지 않습니다.");
  }
  return parsed;
}

function addCalendarDays(value: string, days: number): string {
  const date = calendarDate(value);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** 현재 학기 안에서 최소 8주 분량을 확보하는 과목/학급 후보 조회 범위. */
export function getSchoolTermWindow(date: string): { from: string; to: string } {
  calendarDate(date);
  const year = Number(date.slice(0, 4));
  const month = Number(date.slice(5, 7));
  const fromTerm = month >= 3 && month <= 8 ? `${year}-03-01` : `${month <= 2 ? year - 1 : year}-09-01`;
  const toTerm = month >= 3 && month <= 8 ? `${year}-08-31` : `${month <= 2 ? year : year + 1}-02-${isLeapYear(month <= 2 ? year : year + 1) ? "29" : "28"}`;

  let from = addCalendarDays(date, -28);
  let to = addCalendarDays(date, 28);
  if (from < fromTerm) {
    from = fromTerm;
    to = addCalendarDays(from, 56);
  }
  if (to > toTerm) {
    to = toTerm;
    from = addCalendarDays(to, -56);
  }
  return { from, to };
}

function isLeapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}
