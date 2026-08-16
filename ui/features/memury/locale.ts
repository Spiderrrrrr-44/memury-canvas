/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */

export type MemuryLocale = "zh-CN" | "en";

type CanvasEnvironment = {
  LOCALE?: string;
  BIGEASY_LOCALE?: string;
};

export function normalizeMemuryLocale(value?: string | null): MemuryLocale {
  return String(value || "").toLowerCase().startsWith("zh") ? "zh-CN" : "en";
}

export function canvasPreferredLocale(): MemuryLocale {
  if (typeof window === "undefined") return "en";
  const environment = (window as Window & { ENV?: CanvasEnvironment }).ENV;
  const preference =
    environment?.LOCALE ||
    environment?.BIGEASY_LOCALE ||
    document.documentElement.lang ||
    window.navigator.language;
  return normalizeMemuryLocale(preference);
}

export function localeCopy(
  locale: MemuryLocale,
  chinese: string,
  english: string,
) {
  return locale === "zh-CN" ? chinese : english;
}

export function dateTimeLocale(locale = canvasPreferredLocale()) {
  return locale === "zh-CN" ? "zh-CN" : "en-US";
}
