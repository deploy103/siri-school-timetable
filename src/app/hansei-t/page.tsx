import type { Metadata } from "next";
import { TeacherPage } from "@/components/teacher-page";

export const metadata: Metadata = {
  title: "한세 교사용 시간표",
  description: "한세사이버보안고등학교 교사용 오늘 시간표와 Siri 설정",
  robots: { index: false, follow: false, nocache: true },
};

export default function HanseiTeacherPage() {
  return <TeacherPage />;
}
