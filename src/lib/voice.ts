import type { MealResponse, TimetableResponse } from "@/lib/types";

export function timetableToSpeech(timetable: TimetableResponse): string {
  if (timetable.lessons.length === 0) {
    return "오늘 등록된 시간표가 없습니다. 주말이나 휴업일이거나 학교에서 아직 시간표를 제공하지 않았을 수 있습니다.";
  }
  const lessons = timetable.lessons
    .slice()
    .sort((left, right) => left.period - right.period)
    .map((lesson) => `${lesson.period}교시 ${lesson.ambiguous ? "선택 수업" : lesson.subject.trim()}`)
    .join(", ");
  return `오늘 시간표는 ${lessons}입니다.`;
}

export function stripAllergenNotation(dish: string): string {
  const withoutParentheses = dish.replace(
    /\s*\(\s*\d{1,2}(?:\s*\.\s*\d{1,2})*\s*\.?\s*\)\s*$/u,
    "",
  ).trim();
  const bareSuffix = withoutParentheses.match(
    /^(.*?\D)\s*\d{1,2}(?:\s*\.\s*\d{1,2})*\s*\.\s*$/u,
  );
  const cleaned = bareSuffix?.[1]?.trim() ?? withoutParentheses;
  return cleaned || dish.trim();
}

export function mealToSpeech(mealResponse: MealResponse): string {
  if (mealResponse.meals.length === 0) return "오늘 등록된 급식이 없습니다.";

  const meals = mealResponse.meals
    .slice()
    .sort((left, right) => Number(left.code) - Number(right.code));
  if (meals.length === 1) {
    const dishes = meals[0]?.dishes.map(stripAllergenNotation).filter(Boolean).slice(0, 12).join(", ") ?? "";
    return `오늘 급식은 ${dishes}입니다.`;
  }
  const summaries = meals.map((meal) =>
    `${meal.name}은 ${meal.dishes.map(stripAllergenNotation).filter(Boolean).slice(0, 8).join(", ")}`,
  );
  return `오늘 ${summaries.join(", ")}입니다.`;
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

export function mealVoiceErrorMessage(errorCode: string): string {
  if (errorCode === "INVALID_INPUT" || errorCode === "NOT_FOUND") {
    return "학교 설정이 올바르지 않습니다. 웹사이트에서 학교 설정을 다시 확인해 주세요.";
  }
  if (errorCode === "RATE_LIMITED") {
    return "요청이 너무 많습니다. 잠시 후 다시 물어봐 주세요.";
  }
  return "지금은 교육정보 서비스에서 급식을 가져올 수 없습니다. 잠시 후 다시 물어봐 주세요.";
}
