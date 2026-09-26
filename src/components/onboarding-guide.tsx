"use client";

import Link from "next/link";
import { GuideIcon } from "@/components/icons";

interface Props {
  onDismiss: () => void;
}

export function OnboardingGuide({ onDismiss }: Props) {
  return (
    <section className="card onboarding-card" aria-labelledby="onboarding-heading">
      <div className="setup-section-heading">
        <span className="step-number onboarding-badge" aria-hidden="true"><GuideIcon /></span>
        <div>
          <h2 id="onboarding-heading">처음 쓰는 경우 여기부터 따라하면 됨</h2>
          <p>3단계면 끝나요. 끝나면 말로 물어보면 돼요.</p>
        </div>
      </div>
      <ol className="shortcut-steps onboarding-steps">
        <li><span>1</span><div><strong>학교, 학년, 반 먼저 저장</strong><p>아래에서 학교를 검색하고 학년·반을 골라 저장하세요.</p></div></li>
        <li><span>2</span><div><strong>그 다음 단축어 추가</strong><p>저장하면 뜨는 Siri 설정에서 단축어를 만들어요.</p></div></li>
        <li><span>3</span><div><strong>마지막으로 Siri 문구 등록하면 끝</strong><p>“시리야, 오늘 학교 시간표 뭐야?”라고 말해보세요.</p></div></li>
      </ol>
      <div className="onboarding-actions">
        <Link className="button secondary" href="/guide">자세한 가이드 보기</Link>
        <button type="button" className="button primary" onClick={onDismiss}>이미 설정했어요</button>
      </div>
    </section>
  );
}
