"use client";

import { useEffect, useRef, useState } from "react";
import { CheckIcon, CloseIcon, CopyIcon } from "@/components/icons";
import { encodeTeacherProfile } from "@/lib/teacher-profile";
import type { TeacherSettings } from "@/types/teacher";

interface Props {
  open: boolean;
  settings: TeacherSettings;
  onClose: () => void;
}

export function makeTeacherVoiceUrl(origin: string, settings: TeacherSettings): string {
  const params = new URLSearchParams({ p: encodeTeacherProfile(settings) });
  return `${origin}/api/voice/teacher-timetable?${params.toString()}`;
}

export function TeacherSiriDialog({ open, settings, onClose }: Props) {
  const [copied, setCopied] = useState(false);
  const closeButton = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLElement>(null);
  const previousFocus = useRef<HTMLElement | null>(null);
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  const voiceUrl = makeTeacherVoiceUrl(origin, settings);

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
      await navigator.clipboard.writeText(voiceUrl);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2_000);
    } catch {
      (document.getElementById("teacher-voice-api-url") as HTMLInputElement | null)?.select();
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={(event) => {
      if (event.target === event.currentTarget) onClose();
    }}>
      <section ref={panel} className="dialog-panel" role="dialog" aria-modal="true" aria-labelledby="teacher-siri-title">
        <div className="dialog-header">
          <div>
            <p className="eyebrow">아이폰에서 한 번만 설정</p>
            <h2 id="teacher-siri-title">교사용 Siri 설정</h2>
          </div>
          <button ref={closeButton} className="icon-button" type="button" onClick={onClose} aria-label="Siri 설정 닫기"><CloseIcon /></button>
        </div>
        <p className="dialog-intro">내 담당 학급 설정을 단축어에 연결하면 오늘 수업을 바로 들을 수 있습니다.</p>

        <div className="url-box">
          <label htmlFor="teacher-voice-api-url">교사용 시간표 API URL</label>
          <div>
            <input id="teacher-voice-api-url" aria-label="교사용 시간표 주소" value={voiceUrl} readOnly />
            <button className="button copy-button" type="button" onClick={() => void copyUrl()} aria-label="교사용 URL 복사" aria-live="polite">
              {copied ? <><CheckIcon />복사됨</> : <><CopyIcon />복사</>}
            </button>
          </div>
          <small>추천 단축어 이름: 학교 수업</small>
        </div>
        <p className="url-security-note">주소에는 담당 수업 설정만 포함되며 교사 이름이나 NEIS API 키는 포함되지 않습니다.</p>

        <ol className="shortcut-steps">
          <li><span>1</span><div><strong>단축어 앱 열기</strong><p>아이폰의 <b>단축어</b> 앱에서 새 단축어를 만드세요.</p></div></li>
          <li><span>2</span><div><strong>‘URL’ 동작 추가</strong><p>위에서 복사한 교사용 API URL을 붙여 넣으세요.</p></div></li>
          <li><span>3</span><div><strong>‘URL 콘텐츠 가져오기’ 추가</strong><p>메서드는 <b>GET</b>으로 둡니다.</p></div></li>
          <li><span>4</span><div><strong>‘텍스트 말하기’ 추가</strong><p>앞 단계의 URL 콘텐츠를 말하도록 설정하세요.</p></div></li>
          <li><span>5</span><div><strong>이름을 “학교 수업”으로 저장</strong><p>저장 후 Siri로 바로 호출할 수 있습니다.</p></div></li>
        </ol>

        <div className="siri-callout">
          <span aria-hidden="true">✦</span>
          <p><small>이렇게 말해 보세요</small><strong>“시리야, 학교 수업”</strong></p>
        </div>
        <button type="button" className="button primary full-width" onClick={onClose}>설정 안내 확인했어요</button>
      </section>
    </div>
  );
}
