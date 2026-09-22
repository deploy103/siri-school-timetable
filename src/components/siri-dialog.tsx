"use client";

import { useEffect, useRef, useState } from "react";
import { CheckIcon, CloseIcon, CopyIcon } from "@/components/icons";
import type { SchoolSettings } from "@/types/client";

interface Props {
  open: boolean;
  settings: SchoolSettings;
  onClose: () => void;
}

export function makeVoiceUrl(origin: string, settings: SchoolSettings): string {
  const params = new URLSearchParams({
    officeCode: settings.school.officeCode,
    schoolCode: settings.school.schoolCode,
    kind: settings.school.kind,
    grade: String(settings.grade),
    className: String(settings.className),
  });
  return `${origin}/api/voice/timetable?${params.toString()}`;
}

export function SiriDialog({ open, settings, onClose }: Props) {
  const [copied, setCopied] = useState(false);
  const closeButton = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLElement>(null);
  const previousFocus = useRef<HTMLElement | null>(null);
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  const url = makeVoiceUrl(origin, settings);

  useEffect(() => {
    if (!open) return;
    previousFocus.current = document.activeElement as HTMLElement;
    closeButton.current?.focus();
    document.body.classList.add("dialog-open");
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
      if (event.key !== "Tab") return;
      const focusable = panel.current?.querySelectorAll<HTMLElement>(
        "button:not(:disabled), input:not(:disabled), [href], [tabindex]:not([tabindex='-1'])",
      );
      if (!focusable?.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    }
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.classList.remove("dialog-open");
      previousFocus.current?.focus();
    };
  }, [open, onClose]);

  if (!open) return null;

  async function copyUrl() {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      const input = document.getElementById("voice-api-url") as HTMLInputElement | null;
      input?.select();
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={(event) => {
      if (event.target === event.currentTarget) onClose();
    }}>
      <section ref={panel} className="dialog-panel" role="dialog" aria-modal="true" aria-labelledby="siri-title">
        <div className="dialog-header">
          <div>
            <p className="eyebrow">아이폰에서 한 번만 설정</p>
            <h2 id="siri-title">Siri로 시간표 듣기</h2>
          </div>
          <button ref={closeButton} className="icon-button" type="button" onClick={onClose} aria-label="Siri 설정 닫기"><CloseIcon /></button>
        </div>

        <p className="dialog-intro">아래 주소를 단축어에 연결하면 “시리야, 오늘 학교 시간표 뭐야?”라고 물어볼 수 있어요.</p>

        <div className="url-box">
          <label htmlFor="voice-api-url">내 시간표 주소</label>
          <div>
            <input id="voice-api-url" value={url} readOnly />
            <button className="button copy-button" type="button" onClick={copyUrl} aria-live="polite">
              {copied ? <><CheckIcon />복사됨</> : <><CopyIcon />복사</>}
            </button>
          </div>
          <small>학교 코드와 학년·반만 포함되며, API 키나 개인정보는 포함되지 않습니다.</small>
        </div>

        <ol className="shortcut-steps">
          <li><span>1</span><div><strong>단축어 앱에서 새 단축어 만들기</strong><p>아이폰의 <b>단축어</b> 앱을 열고 오른쪽 위 <b>+</b>를 눌러 주세요.</p></div></li>
          <li><span>2</span><div><strong>‘URL’ 동작 추가</strong><p>동작 추가에서 <b>URL</b>을 검색하고, 위에서 복사한 주소를 붙여 넣으세요.</p></div></li>
          <li><span>3</span><div><strong>‘URL 콘텐츠 가져오기’ 추가</strong><p>메서드는 기본값인 <b>GET</b>으로 두면 됩니다.</p></div></li>
          <li><span>4</span><div><strong>‘텍스트 말하기’ 추가</strong><p>말할 텍스트로 앞 단계의 <b>URL 콘텐츠</b>를 선택하세요.</p></div></li>
          <li><span>5</span><div><strong>단축어 이름 정하기</strong><p><b>오늘 학교 시간표 뭐야</b>로 저장하면 Siri에게 같은 이름으로 말해 실행할 수 있어요.</p></div></li>
        </ol>

        <div className="siri-callout">
          <span aria-hidden="true">✦</span>
          <p><small>이렇게 말해 보세요</small><strong>“시리야, 오늘 학교 시간표 뭐야?”</strong></p>
        </div>
        <button type="button" className="button primary full-width" onClick={onClose}>설정 안내 확인했어요</button>
      </section>
    </div>
  );
}
