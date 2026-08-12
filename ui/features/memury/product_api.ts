/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */
import doFetchApi from "@canvas/do-fetch-api-effect";
import type { MemuryState } from "./types";

async function request(
  path: string,
  method: "POST" | "PATCH" | "DELETE",
  body?: Record<string, unknown>
) {
  const { json } = await doFetchApi<MemuryState>({ path, method, body });
  if (!json) throw new Error("Memury returned no state");
  return json;
}

export const replan = () => request("/memury/replan", "POST");
export const createCalendarEvent = (body: Record<string, unknown>) =>
  request("/memury/events", "POST", body);
export const updateCalendarEvent = (
  id: string,
  body: Record<string, unknown>
) => request(`/memury/events/${id}`, "PATCH", body);
export const deleteCalendarEvent = (id: string) =>
  request(`/memury/events/${id}`, "DELETE");
export const updatePlanBlock = (id: string, body: Record<string, unknown>) =>
  request(`/memury/plan_blocks/${id}`, "PATCH", body);
export const focusCommand = (
  command: string,
  body: Record<string, unknown> = {}
) => request(`/memury/focus/${command}`, "POST", body);
export const createQuestion = (body: Record<string, unknown>) =>
  request("/memury/questions", "POST", body);
export const updateQuestion = (id: string, body: Record<string, unknown>) =>
  request(`/memury/questions/${id}`, "PATCH", body);
