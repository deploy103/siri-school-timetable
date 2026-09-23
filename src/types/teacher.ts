export interface TeacherAssignment {
  subject: string;
  /** NEIS가 반환한 원본 학과명. 화면과 음성에서는 별도 정규화 계층을 사용한다. */
  department: string;
  grade: number;
  className: string;
}

export interface TeacherSettings {
  v: 1;
  assignments: TeacherAssignment[];
  includeSubject: boolean;
}

export interface TeacherAssignmentCandidate extends TeacherAssignment {
  departmentDisplay: string;
  departmentSpeech: string;
}

export interface TeacherLesson extends TeacherAssignment {
  period: number;
  departmentDisplay: string;
  departmentSpeech: string;
  ambiguous?: boolean;
}

export interface TeacherTimetable {
  date: string;
  queriedAt: string;
  queriedAtLabel: string;
  schoolName: string;
  lessons: TeacherLesson[];
  ambiguousPeriods: number[];
}

export interface TeacherSubjectsResponse {
  subjects: string[];
  range: { from: string; to: string };
}

export interface TeacherCandidatesResponse {
  subject: string;
  candidates: TeacherAssignmentCandidate[];
  range: { from: string; to: string };
}
