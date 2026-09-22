"use client";

import { useCallback, useEffect, useState } from "react";
import { isEducationOfficeCode } from "@/lib/education-offices";
import { SCHOOL_KINDS, type SchoolSettings } from "@/types/client";

const STORAGE_KEY = "time-siri.school-settings.v1";

function normalizeSchoolSettings(value: unknown): SchoolSettings | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<SchoolSettings> & { className?: unknown };
  const school = candidate.school;
  const kind = school?.kind;
  const maxGrade = kind === "초등학교" || kind === "특수학교" ? 6 : 3;
  const storedClassName = candidate.className;
  const className = typeof storedClassName === "number" && Number.isInteger(storedClassName)
    ? String(storedClassName)
    : typeof storedClassName === "string"
      ? storedClassName.trim()
      : "";
  const valid = Boolean(
    school &&
      typeof school.officeCode === "string" &&
      isEducationOfficeCode(school.officeCode) &&
      typeof school.schoolCode === "string" &&
      typeof school.name === "string" &&
      SCHOOL_KINDS.some((item) => item === kind) &&
      typeof school.address === "string" &&
      typeof school.region === "string" &&
      (school.locality === undefined || typeof school.locality === "string") &&
      Number.isInteger(candidate.grade) &&
      Number(candidate.grade) >= 1 &&
      Number(candidate.grade) <= maxGrade &&
      className.length >= 1 &&
      className.length <= 20 &&
      !/[\u0000-\u001f\u007f]/.test(className),
  );
  if (!valid || !school || !candidate.grade) return null;
  return { school, grade: candidate.grade, className } as SchoolSettings;
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
          const normalized = normalizeSchoolSettings(parsed);
          if (normalized) setSettings(normalized);
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
