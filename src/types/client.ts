export const SCHOOL_KINDS = ["초등학교", "중학교", "고등학교", "특수학교"] as const;

export type SchoolKind = (typeof SCHOOL_KINDS)[number];

export interface School {
  officeCode: string;
  schoolCode: string;
  name: string;
  kind: SchoolKind;
  address: string;
  region: string;
  locality?: string;
}

export interface SchoolSettings {
  school: School;
  grade: number;
  className: string;
  department?: string;
}

export interface Lesson {
  period: number;
  subject: string;
  ambiguous?: boolean;
}

export interface SchoolClass {
  grade: number;
  className: string;
  department?: string;
}

export interface Timetable {
  date: string;
  school: Pick<School, "name" | "kind">;
  grade: number;
  className: string;
  lessons: Lesson[];
}

export interface SchoolsResponse {
  schools: School[];
}

export interface ClassesResponse {
  classes: SchoolClass[];
}

export interface ApiErrorBody {
  error?: {
    code?: string;
    message?: string;
  };
  message?: string;
}
