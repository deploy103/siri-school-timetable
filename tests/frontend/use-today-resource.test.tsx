import { act, cleanup, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useTodayResource } from "@/hooks/use-today-resource";

function json(value: string) {
  return new Response(JSON.stringify({ value }));
}

function deferred() {
  let resolve!: (response: Response) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<Response>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-08T14:59:00Z")); // 23:59 KST, not UTC midnight.
  vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
  vi.spyOn(navigator, "onLine", "get").mockReturnValue(true);
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

function renderResource(url = "/api/timetable/today?className=1") {
  return renderHook(({ url }) => useTodayResource<{ value: string }>(url, "조회 실패"), { initialProps: { url } });
}

describe("today resource lifecycle", () => {
  it.each(["success", "failure"])("ignores an older %s without ending a newer loading state", async (outcome) => {
    const old = deferred();
    const latest = deferred();
    const fetchMock = vi.fn().mockReturnValueOnce(old.promise).mockReturnValueOnce(latest.promise);
    vi.stubGlobal("fetch", fetchMock);
    const { result } = renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    act(() => { void result.current.reload(); });
    expect(fetchMock.mock.calls[0]![1].signal.aborted).toBe(true);
    await act(async () => {
      if (outcome === "success") old.resolve(json("old"));
      else old.reject(new Error("old error"));
    });
    expect(result.current).toMatchObject({ data: null, isLoading: true, error: null });
    await act(async () => { latest.resolve(json("latest")); });
    expect(result.current).toMatchObject({ data: { value: "latest" }, isLoading: false, error: null });
  });

  it("does not overwrite a completed newer result with a late old response", async () => {
    const old = deferred();
    vi.stubGlobal("fetch", vi.fn().mockReturnValueOnce(old.promise).mockResolvedValueOnce(json("new")));
    const { result } = renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    await act(() => result.current.reload());
    await act(async () => { old.resolve(json("old")); });
    expect(result.current.data).toEqual({ value: "new" });
  });

  it("clears the previous school's data and aborts work on URL change and unmount", async () => {
    const pending = deferred();
    const fetchMock = vi.fn().mockResolvedValueOnce(json("school one")).mockReturnValueOnce(pending.promise);
    vi.stubGlobal("fetch", fetchMock);
    const { result, rerender, unmount } = renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    expect(result.current.data).toEqual({ value: "school one" });
    rerender({ url: "/api/timetable/today?className=2" });
    expect(result.current).toMatchObject({ data: null, isLoading: true });
    await act(() => vi.advanceTimersByTimeAsync(1));
    unmount();
    expect(fetchMock.mock.calls[1]![1].signal.aborted).toBe(true);
    await act(async () => { pending.resolve(json("unmounted")); });
  });

  it("refreshes at KST midnight even though 30 minutes have not elapsed", async () => {
    const fetchMock = vi.fn().mockImplementation(() => Promise.resolve(json("today")));
    vi.stubGlobal("fetch", fetchMock);
    renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    await act(() => vi.advanceTimersByTimeAsync(59_998));
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await act(() => vi.advanceTimersByTimeAsync(1));
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("requeries rather than showing a request that finishes across midnight", async () => {
    const oldDay = deferred();
    const fetchMock = vi.fn().mockReturnValueOnce(oldDay.promise).mockResolvedValueOnce(json("next day"));
    vi.stubGlobal("fetch", fetchMock);
    const { result } = renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    vi.setSystemTime(new Date("2026-10-08T15:00:01Z"));
    await act(async () => { oldDay.resolve(json("yesterday")); });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(result.current.data).toEqual({ value: "next day" });
  });

  it("skips hidden/offline background requests and refreshes on return and reconnection", async () => {
    vi.setSystemTime(new Date("2026-10-08T03:00:00Z"));
    const visibility = vi.spyOn(document, "visibilityState", "get");
    const online = vi.spyOn(navigator, "onLine", "get");
    const fetchMock = vi.fn().mockImplementation(() => Promise.resolve(json("today")));
    vi.stubGlobal("fetch", fetchMock);
    renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    visibility.mockReturnValue("hidden");
    await act(() => vi.advanceTimersByTimeAsync(30 * 60_000));
    expect(fetchMock).toHaveBeenCalledTimes(1);
    visibility.mockReturnValue("visible");
    await act(async () => { document.dispatchEvent(new Event("visibilitychange")); });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    online.mockReturnValue(false);
    await act(() => vi.advanceTimersByTimeAsync(30 * 60_000));
    expect(fetchMock).toHaveBeenCalledTimes(2);
    online.mockReturnValue(true);
    await act(async () => { window.dispatchEvent(new Event("online")); });
    expect(fetchMock).toHaveBeenCalledTimes(3);
    await act(async () => { document.dispatchEvent(new Event("visibilitychange")); });
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("uses a safe fallback for non-JSON errors and retries a failed lookup on return", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(new Response("<html>proxy failure</html>", { status: 502 }))
      .mockResolvedValueOnce(json("recovered"));
    vi.stubGlobal("fetch", fetchMock);
    const { result } = renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    expect(result.current.error).toBe("조회 실패");
    await act(async () => { document.dispatchEvent(new Event("visibilitychange")); });
    expect(result.current.data).toEqual({ value: "recovered" });
  });

  it("removes yesterday's data at midnight even when offline without making a request", async () => {
    const fetchMock = vi.fn().mockImplementation(() => Promise.resolve(json("previous day")));
    vi.stubGlobal("fetch", fetchMock);
    const { result } = renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    vi.spyOn(navigator, "onLine", "get").mockReturnValue(false);
    await act(() => vi.advanceTimersByTimeAsync(60_000));
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(result.current).toMatchObject({ data: null, isLoading: false, error: "인터넷 연결을 확인한 뒤 다시 시도해 주세요." });
  });

  it("defers a hidden reconnection until return even within the freshness interval", async () => {
    const fetchMock = vi.fn().mockImplementation(() => Promise.resolve(json("today")));
    vi.stubGlobal("fetch", fetchMock);
    renderResource();
    await act(() => vi.advanceTimersByTimeAsync(1));
    const visibility = vi.spyOn(document, "visibilityState", "get").mockReturnValue("hidden");
    await act(async () => { window.dispatchEvent(new Event("online")); });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    visibility.mockReturnValue("visible");
    await act(async () => { document.dispatchEvent(new Event("visibilitychange")); });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
