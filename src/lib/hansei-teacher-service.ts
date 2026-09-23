import { getSchoolTermWindow } from "@/lib/date";
import { getHanseiCatalogRows, getHanseiTodaySnapshot } from "@/lib/neis";
import {
  HANSEI_SCHOOL,
  collectAssignmentCandidates,
  collectTeacherSubjects,
  matchTeacherLessons,
} from "@/lib/teacher-timetable";
import type {
  TeacherCandidatesResponse,
  TeacherSettings,
  TeacherSubjectsResponse,
  TeacherTimetable,
} from "@/types/teacher";

export async function getTeacherSubjects(date: string): Promise<TeacherSubjectsResponse> {
  const range = getSchoolTermWindow(date);
  const rows = await getHanseiCatalogRows(range.from, range.to);
  return { subjects: collectTeacherSubjects(rows), range };
}

export async function getTeacherAssignmentCandidates(
  subject: string,
  date: string,
): Promise<TeacherCandidatesResponse> {
  const range = getSchoolTermWindow(date);
  const rows = await getHanseiCatalogRows(range.from, range.to);
  return { subject, candidates: collectAssignmentCandidates(rows, subject), range };
}

export async function getTeacherTimetable(
  settings: TeacherSettings,
  date: string,
): Promise<TeacherTimetable> {
  const snapshot = await getHanseiTodaySnapshot(date);
  const matched = matchTeacherLessons(snapshot.rows, settings.assignments);
  return {
    date,
    queriedAt: snapshot.queriedAt,
    queriedAtLabel: snapshot.queriedAtLabel,
    schoolName: HANSEI_SCHOOL.name,
    ...matched,
  };
}
