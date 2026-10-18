"use client";

import { useCallback, useEffect, useState } from "react";
import { normalizeTeacherSettings } from "@/lib/teacher-profile";
import type { TeacherSettings } from "@/types/teacher";

export const TEACHER_STORAGE_KEY = "time-siri.teacher-settings.v1";

export function useTeacherSettings() {
  const [settings, setSettings] = useState<TeacherSettings | null>(null);
  const [isRestoring, setIsRestoring] = useState(true);
  const [storageUnavailable, setStorageUnavailable] = useState(false);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const stored = window.localStorage.getItem(TEACHER_STORAGE_KEY);
        if (stored) {
          const normalized = normalizeTeacherSettings(JSON.parse(stored) as unknown);
          if (normalized) setSettings(normalized);
          else window.localStorage.removeItem(TEACHER_STORAGE_KEY);
        }
      } catch (error) {
        if (error instanceof SyntaxError) {
          try {
            window.localStorage.removeItem(TEACHER_STORAGE_KEY);
          } catch {
            setStorageUnavailable(true);
          }
        } else {
          setStorageUnavailable(true);
        }
      } finally {
        setIsRestoring(false);
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  const saveSettings = useCallback((next: TeacherSettings) => {
    const normalized = normalizeTeacherSettings(next);
    if (!normalized) throw new TypeError("교사용 시간표 설정이 올바르지 않습니다.");
    try {
      window.localStorage.setItem(TEACHER_STORAGE_KEY, JSON.stringify(normalized));
      setStorageUnavailable(false);
    } catch {
      setStorageUnavailable(true);
    }
    setSettings(normalized);
  }, []);

  const clearSettings = useCallback(() => {
    try {
      window.localStorage.removeItem(TEACHER_STORAGE_KEY);
    } catch {
      setStorageUnavailable(true);
    }
    setSettings(null);
  }, []);

  return { settings, isRestoring, saveSettings, clearSettings, storageUnavailable };
}
