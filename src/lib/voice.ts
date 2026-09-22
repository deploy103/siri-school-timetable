import type { TimetableResponse } from "@/lib/types";

export function timetableToSpeech(timetable: TimetableResponse): string {
  if (timetable.lessons.length === 0) {
    return "오늘 등록된 시간표가 없습니다. 주말이나 휴업일이거나 학교에서 아직 시간표를 제공하지 않았을 수 있습니다.";
  }
  const lessons = timetable.lessons
    .slice()
    .sort((left, right) => left.period - right.period)
    .map((lesson) => `${lesson.period}교시 ${lesson.subject.trim()}`)
    .join(", ");
  return `오늘 시간표는 ${lessons}입니다.`;
}

export function voiceErrorMessage(errorCode: string): string {
  if (errorCode === "INVALID_INPUT" || errorCode === "NOT_FOUND") {
    return "학교 설정이 올바르지 않습니다. 웹사이트에서 학교와 학년, 반 설정을 다시 확인해 주세요.";
  }
  if (errorCode === "RATE_LIMITED") {
    return "요청이 너무 많습니다. 잠시 후 다시 물어봐 주세요.";
  }
  return "지금은 교육정보 서비스에서 시간표를 가져올 수 없습니다. 잠시 후 다시 물어봐 주세요.";
}
