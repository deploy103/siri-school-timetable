import { z } from "zod";

const calendarDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine((value) => {
  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}, "날짜 형식이 올바르지 않습니다.");

const dateRangeSchema = z.object({ from: calendarDate, to: calendarDate }).refine(
  ({ from, to }) => from <= to &&
    (Date.parse(`${to}T00:00:00.000Z`) - Date.parse(`${from}T00:00:00.000Z`)) / 86_400_000 < 7,
  "조회 기간은 시작일부터 종료일까지 1~7일이어야 합니다.",
);

/** Validate the entire range before any upstream work, using UTC calendar days. */
export function parseDateRange(params: URLSearchParams): { from: string; to: string; dates: string[] } {
  const { from, to } = dateRangeSchema.parse({ from: params.get("from"), to: params.get("to") });
  const dates: string[] = [];
  const end = Date.parse(`${to}T00:00:00.000Z`);
  for (let time = Date.parse(`${from}T00:00:00.000Z`); time <= end; time += 86_400_000) {
    dates.push(new Date(time).toISOString().slice(0, 10));
  }
  return { from, to, dates };
}
