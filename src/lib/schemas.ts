import { z } from "zod";
import { EDUCATION_OFFICE_CODES } from "@/lib/education-offices";
import { SCHOOL_KINDS } from "@/lib/types";

const compactCode = z
  .string()
  .trim()
  .min(1)
  .max(20)
  .regex(/^[A-Za-z0-9]+$/, "코드 형식이 올바르지 않습니다.");

const positiveInteger = (label: string, max: number) =>
  z
    .string()
    .trim()
    .regex(/^\d{1,2}$/, `${label}은 숫자여야 합니다.`)
    .transform(Number)
    .refine((value) => value >= 1 && value <= max, {
      message: `${label}은 1부터 ${max} 사이여야 합니다.`,
    });

const className = z
  .string({ message: "반을 입력해 주세요." })
  .trim()
  .min(1, "반을 입력해 주세요.")
  .max(20, "반 이름은 20자 이하로 입력해 주세요.")
  .refine((value) => !/[\u0000-\u001f\u007f]/.test(value), {
    message: "반 이름에 사용할 수 없는 문자가 있습니다.",
  });

const optionalNeisLabel = z
  .string()
  .trim()
  .min(1)
  .max(100)
  .refine((value) => !/[\u0000-\u001f\u007f]/.test(value), {
    message: "사용할 수 없는 문자가 있습니다.",
  })
  .optional();

export const schoolSearchSchema = z.object({
  officeCode: z.enum(EDUCATION_OFFICE_CODES, {
    message: "지원하지 않는 지역 코드입니다.",
  }).optional(),
  name: z
    .string({ message: "학교 이름을 입력해 주세요." })
    .trim()
    .min(2, "학교 이름은 두 글자 이상 입력해 주세요.")
    .max(50, "학교 이름은 50자 이하로 입력해 주세요.")
    .refine((value) => !/[\u0000-\u001f\u007f]/.test(value), {
      message: "학교 이름에 사용할 수 없는 문자가 있습니다.",
    }),
});

export const timetableQuerySchema = z
  .object({
    officeCode: z.enum(EDUCATION_OFFICE_CODES, {
      message: "지원하지 않는 지역 코드입니다.",
    }),
    schoolCode: compactCode,
    kind: z.enum(SCHOOL_KINDS, {
      message: "지원하지 않는 학교 유형입니다.",
    }),
    grade: positiveInteger("학년", 6),
    className,
    department: optionalNeisLabel,
  })
  .superRefine(({ kind, grade }, context) => {
    if ((kind === "중학교" || kind === "고등학교") && grade > 3) {
      context.addIssue({
        code: "custom",
        path: ["grade"],
        message: `${kind} 학년은 1부터 3 사이여야 합니다.`,
      });
    }
  });

export type TimetableQuery = z.infer<typeof timetableQuerySchema>;

export const mealQuerySchema = z.object({
  officeCode: z.enum(EDUCATION_OFFICE_CODES, {
    message: "지원하지 않는 지역 코드입니다.",
  }),
  schoolCode: compactCode,
});

export type MealQuery = z.infer<typeof mealQuerySchema>;

export const classQuerySchema = z.object({
  officeCode: z.enum(EDUCATION_OFFICE_CODES, {
    message: "지원하지 않는 지역 코드입니다.",
  }),
  schoolCode: compactCode,
});

export function searchParamsToRecord(params: URLSearchParams): Record<string, string | undefined> {
  return {
    officeCode: params.get("officeCode") ?? undefined,
    schoolCode: params.get("schoolCode") ?? undefined,
    kind: params.get("kind") ?? undefined,
    grade: params.get("grade") ?? undefined,
    className: params.get("className") ?? undefined,
    department: params.get("department") ?? undefined,
  };
}
