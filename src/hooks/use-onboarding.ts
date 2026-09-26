"use client";

import { useCallback, useEffect, useState } from "react";

const STORAGE_KEY = "time-siri.onboarding-dismissed.v1";

export function useOnboarding() {
  const [dismissed, setDismissed] = useState(false);
  const [isRestoring, setIsRestoring] = useState(true);

  useEffect(() => {
    const restoreTimer = window.setTimeout(() => {
      try {
        setDismissed(window.localStorage.getItem(STORAGE_KEY) === "1");
      } finally {
        setIsRestoring(false);
      }
    }, 0);
    return () => window.clearTimeout(restoreTimer);
  }, []);

  const dismiss = useCallback(() => {
    window.localStorage.setItem(STORAGE_KEY, "1");
    setDismissed(true);
  }, []);

  const show = useCallback(() => {
    window.localStorage.removeItem(STORAGE_KEY);
    setDismissed(false);
  }, []);

  return { dismissed, isRestoring, dismiss, show };
}

export { STORAGE_KEY as ONBOARDING_STORAGE_KEY };
