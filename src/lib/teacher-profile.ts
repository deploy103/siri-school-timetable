import { z } from "zod";
import { teacherProfileSchema, teacherSettingsSchema } from "@/lib/schemas";
import type { TeacherSettings } from "@/types/teacher";

export const MAX_TEACHER_PROFILE_BYTES = 6_144;

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const padding = "=".repeat((4 - value.length % 4) % 4);
  const binary = atob(value.replaceAll("-", "+").replaceAll("_", "/") + padding);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function normalizeTeacherSettings(value: unknown): TeacherSettings | null {
  const result = teacherSettingsSchema.safeParse(value);
  if (!result.success) return null;
  const unique = new Map<string, TeacherSettings["assignments"][number]>();
  for (const assignment of result.data.assignments) {
    const key = [assignment.subject, assignment.department, assignment.grade, assignment.className].join("\u0000");
    unique.set(key, assignment);
  }
  if (unique.size === 0) return null;
  const normalized = { ...result.data, assignments: [...unique.values()] };
  if (new TextEncoder().encode(JSON.stringify(toCompactProfile(normalized))).byteLength > MAX_TEACHER_PROFILE_BYTES) {
    return null;
  }
  return normalized;
}

export function encodeTeacherProfile(settings: TeacherSettings): string {
  const normalized = normalizeTeacherSettings(settings);
  if (!normalized) throw new TypeError("교사용 시간표 설정이 올바르지 않습니다.");
  const bytes = new TextEncoder().encode(JSON.stringify(toCompactProfile(normalized)));
  return bytesToBase64(bytes).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function toCompactProfile(settings: TeacherSettings) {
  return {
    v: 1 as const,
    assignments: settings.assignments.map(({ subject, department, grade, className }) =>
      [subject, department, grade, className] as const),
    includeSubject: settings.includeSubject,
  };
}

export function decodeTeacherProfile(encoded: string): TeacherSettings {
  if (!/^[A-Za-z0-9_-]{1,8192}$/u.test(encoded)) throw new z.ZodError([]);
  let bytes: Uint8Array;
  try {
    bytes = base64ToBytes(encoded);
  } catch {
    throw new z.ZodError([]);
  }
  if (bytes.byteLength > MAX_TEACHER_PROFILE_BYTES) throw new z.ZodError([]);
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) as unknown;
  } catch {
    throw new z.ZodError([]);
  }
  const profile = teacherProfileSchema.parse(parsed);
  const settings = normalizeTeacherSettings({
    v: profile.v,
    assignments: profile.assignments.map(([subject, department, grade, className]) => ({
      subject,
      department,
      grade,
      className,
    })),
    includeSubject: profile.includeSubject,
  });
  if (!settings) throw new z.ZodError([]);
  return settings;
}
