export type AppErrorCode =
  | "INVALID_INPUT"
  | "RATE_LIMITED"
  | "NEIS_TIMEOUT"
  | "NEIS_UNAVAILABLE"
  | "NEIS_NOT_CONFIGURED"
  | "NEIS_AUTH_ERROR"
  | "NEIS_QUOTA_EXCEEDED"
  | "NEIS_ERROR"
  | "NOT_FOUND"
  | "INTERNAL_ERROR";

export class AppError extends Error {
  constructor(
    public readonly code: AppErrorCode,
    public readonly status: number,
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "AppError";
  }
}

export function safeError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  return new AppError(
    "INTERNAL_ERROR",
    500,
    "요청을 처리하는 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.",
    { cause: error },
  );
}
