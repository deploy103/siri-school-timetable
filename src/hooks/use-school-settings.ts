"use client";

import { useCallback, useEffect, useState } from "react";
import { SCHOOL_KINDS, type SchoolSettings } from "@/types/client";

const STORAGE_KEY = "time-siri.school-settings.v1";

function isSchoolSettings(value: unknown): value is SchoolSettings {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<SchoolSettings>;
  const school = candidate.school;
  const kind = school?.kind;
  const maxGrade = kind === "초등학교" || kind === "특수학교" ? 6 : 3;
  return Boolean(
    school &&
      typeof school.officeCode === "string" &&
      typeof school.schoolCode === "string" &&
      typeof school.name === "string" &&
      SCHOOL_KINDS.some((item) => item === kind) &&
      typeof school.address === "string" &&
      typeof school.region === "string" &&
      Number.isInteger(candidate.grade) &&
      Number(candidate.grade) >= 1 &&
      Number(candidate.grade) <= maxGrade &&
      Number.isInteger(candidate.className) &&
      Number(candidate.className) >= 1 &&
      Number(candidate.className) <= 20,
  );
}

export function useSchoolSettings() {
  const [settings, setSettings] = useState<SchoolSettings | null>(null);
  const [isRestoring, setIsRestoring] = useState(true);

  useEffect(() => {
    const restoreTimer = window.setTimeout(() => {
      try {
        const stored = window.localStorage.getItem(STORAGE_KEY);
        if (stored) {
          const parsed: unknown = JSON.parse(stored);
          if (isSchoolSettings(parsed)) setSettings(parsed);
          else window.localStorage.removeItem(STORAGE_KEY);
        }
      } catch {
        window.localStorage.removeItem(STORAGE_KEY);
      } finally {
        setIsRestoring(false);
      }
    }, 0);
    return () => window.clearTimeout(restoreTimer);
  }, []);

  const saveSettings = useCallback((next: SchoolSettings) => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
    setSettings(next);
  }, []);

  return { settings, isRestoring, saveSettings };
}

export { STORAGE_KEY };
