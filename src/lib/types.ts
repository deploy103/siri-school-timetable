export const SCHOOL_KINDS = [
  "초등학교",
  "중학교",
  "고등학교",
  "특수학교",
] as const;

export type SchoolKind = (typeof SCHOOL_KINDS)[number];

export interface School {
  officeCode: string;
  schoolCode: string;
  name: string;
  kind: SchoolKind;
  address: string;
  region: string;
}

export interface Lesson {
  period: number;
  subject: string;
}

export interface TimetableResponse {
  date: string;
  school: {
    name: string;
    kind: SchoolKind;
  };
  grade: number;
  className: number;
  lessons: Lesson[];
}

export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
  };
}
