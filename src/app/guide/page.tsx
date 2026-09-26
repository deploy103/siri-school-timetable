import type { Metadata } from "next";
import { GuidePage } from "@/components/guide-page";

export const metadata: Metadata = {
  title: "사용 가이드 | 오늘의 시간표",
  description: "학교 설정부터 Siri 단축어 연결까지 따라 하는 가이드",
};

export default function Guide() {
  return <GuidePage />;
}
