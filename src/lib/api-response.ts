import { NextResponse } from "next/server";
import { ZodError } from "zod";
import { AppError, safeError } from "@/lib/errors";
import type { ApiErrorBody } from "@/lib/types";

export const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
} as const;

export function jsonResponse<T>(body: T, init?: ResponseInit): NextResponse<T> {
  const headers = new Headers(init?.headers);
  Object.entries(SECURITY_HEADERS).forEach(([name, value]) => headers.set(name, value));
  return NextResponse.json(body, { ...init, headers });
}

export function errorResponse(error: unknown): NextResponse<ApiErrorBody> {
  if (error instanceof ZodError) {
    return jsonResponse(
      {
        error: {
          code: "INVALID_INPUT",
          message: error.issues[0]?.message ?? "입력값을 확인해 주세요.",
        },
      },
      { status: 400, headers: { "Cache-Control": "no-store" } },
    );
  }

  const appError = safeError(error);
  return jsonResponse(
    { error: { code: appError.code, message: appError.message } },
    { status: appError.status, headers: { "Cache-Control": "no-store" } },
  );
}

export function rateLimitResponse(retryAfterSeconds: number): NextResponse<ApiErrorBody> {
  return jsonResponse(
    { error: { code: "RATE_LIMITED", message: "요청이 너무 많습니다. 잠시 후 다시 시도해 주세요." } },
    {
      status: 429,
      headers: {
        "Cache-Control": "no-store",
        "Retry-After": String(retryAfterSeconds),
      },
    },
  );
}

export function logServerError(context: string, error: unknown): void {
  const safeDescription =
    error instanceof AppError ? `${error.code}: ${error.message}` : "unexpected internal error";
  console.error(`[${context}] ${safeDescription}`);
}
