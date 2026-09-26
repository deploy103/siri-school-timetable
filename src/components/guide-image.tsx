"use client";

import { useEffect, useRef, useState } from "react";
import { CloseIcon } from "@/components/icons";

interface Props {
  src: string;
  alt: string;
  caption: string;
}

export function GuideImage({ src, alt, caption }: Props) {
  const [open, setOpen] = useState(false);
  const closeButton = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    closeButton.current?.focus();
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("keydown", onKeyDown);
    document.body.classList.add("dialog-open");
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.classList.remove("dialog-open");
    };
  }, [open]);

  return (
    <>
      <button
        type="button"
        className="guide-image-button"
        onClick={() => setOpen(true)}
        aria-label={`${alt}, 눌러서 크게 보기`}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={src} alt={alt} loading="lazy" />
        <span className="guide-image-zoom-hint">눌러서 크게 보기</span>
      </button>
      {open && (
        <div
          className="dialog-backdrop"
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setOpen(false);
          }}
        >
          <section className="dialog-panel guide-lightbox" role="dialog" aria-modal="true" aria-label={alt}>
            <div className="guide-lightbox-header">
              <p>{caption}</p>
              <button ref={closeButton} className="icon-button" type="button" onClick={() => setOpen(false)} aria-label="이미지 닫기">
                <CloseIcon />
              </button>
            </div>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={src} alt={alt} className="guide-lightbox-image" />
          </section>
        </div>
      )}
    </>
  );
}
