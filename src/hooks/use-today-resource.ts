"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getKstDate } from "@/lib/date";
import type { ApiErrorBody } from "@/types/client";

const AUTO_REFRESH_MS = 30 * 60_000;

interface ResourceState<T> {
  url: string;
  data: T | null;
  isLoading: boolean;
  error: string | null;
}

/** A today's-data request belongs to one URL, one KST day and one active load. */
export function useTodayResource<T>(url: string, fallbackMessage: string) {
  const [state, setState] = useState<ResourceState<T>>({ url, data: null, isLoading: true, error: null });
  const activeRequest = useRef<AbortController | null>(null);
  const lastAttempt = useRef(0);
  const attemptedDay = useRef("");
  const hasSucceeded = useRef(false);

  const reload = useCallback(async function load() {
    activeRequest.current?.abort();
    const controller = new AbortController();
    activeRequest.current = controller;
    const day = getKstDate();
    attemptedDay.current = day;
    lastAttempt.current = Date.now();
    hasSucceeded.current = false;
    setState({ url, data: null, isLoading: true, error: null });

    try {
      const response = await fetch(url, { cache: "no-store", signal: controller.signal });
      if (!response.ok) {
        let message = fallbackMessage;
        try {
          const body = (await response.json()) as ApiErrorBody;
          message = body.error?.message ?? body.message ?? fallbackMessage;
        } catch {
          // Non-JSON failures still produce a usable retry state.
        }
        throw new Error(message);
      }
      const data = (await response.json()) as T;
      if (controller.signal.aborted) return;
      if (day !== getKstDate()) {
        void load();
        return;
      }
      hasSucceeded.current = true;
      activeRequest.current = null;
      setState({ url, data, isLoading: false, error: null });
    } catch (reason) {
      if (controller.signal.aborted) return;
      activeRequest.current = null;
      setState({
        url,
        data: null,
        isLoading: false,
        error: !navigator.onLine
          ? "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
          : reason instanceof Error ? reason.message : fallbackMessage,
      });
    }
  }, [url, fallbackMessage]);

  useEffect(() => {
    const initialLoad = window.setTimeout(() => void reload(), 0);
    function refreshIfNeeded(force = false) {
      if (document.visibilityState !== "visible") return;
      const day = getKstDate();
      const dayChanged = attemptedDay.current !== day;
      if (!navigator.onLine) {
        if (dayChanged) {
          activeRequest.current?.abort();
          activeRequest.current = null;
          attemptedDay.current = day;
          hasSucceeded.current = false;
          setState({ url, data: null, isLoading: false, error: "인터넷 연결을 확인한 뒤 다시 시도해 주세요." });
        }
        return;
      }
      if (force || dayChanged || Date.now() - lastAttempt.current >= AUTO_REFRESH_MS) {
        void reload();
      }
    }
    const interval = window.setInterval(() => refreshIfNeeded(), 60_000);
    const onVisible = () => refreshIfNeeded(!hasSucceeded.current && !activeRequest.current);
    const onOnline = () => {
      hasSucceeded.current = false;
      refreshIfNeeded(true);
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", onOnline);
    return () => {
      window.clearTimeout(initialLoad);
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", onOnline);
      activeRequest.current?.abort();
    };
  }, [reload, url]);

  // Do not render the previous school's result while the new effect is starting.
  const current = state.url === url ? state : { data: null, isLoading: true, error: null };
  return { data: current.data, isLoading: current.isLoading, error: current.error, reload };
}
