/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */
import { describe, expect, it } from "vitest";
import {
  currentRoute,
  resolveAssignment,
  workspaceViewForLearningMode,
  zonedDateKey,
  zonedHour,
} from "../product_app";

describe("Memury product routes", () => {
  it("restores three distinct product pages from directly visited URLs", () => {
    expect(currentRoute("/memury/learn/assignment-42")).toEqual({
      name: "learn",
      assignmentId: "assignment-42",
    });
    expect(currentRoute("/memury/risks")).toEqual({ name: "risks" });
    expect(currentRoute("/memury/plan")).toEqual({ name: "plan" });
  });

  it("keeps Learning Memory separate from the three primary routes", () => {
    expect(currentRoute("/memury/memory")).toEqual({ name: "memory" });
    expect(currentRoute("/memury")).toEqual({ name: "home" });
  });

  it("keeps the legacy mechanics demo URL mapped to the current seeded assignment", () => {
    const assignment = {
      id: "81",
      demo_assignment_id: "ME250-HW4",
      course_name: "ME 250",
      title: "Homework 4",
      due_at: "2026-08-15T12:00:00Z",
      risk: 0.8,
      risk_reasons: [],
      source_platform: "Canvas",
      source_object_id: "81",
      last_synced_at: "2026-08-15T08:00:00Z",
      official_or_inferred: "Official" as const,
      confidence: 1,
    };

    expect(resolveAssignment([assignment], "mech-force")).toBe(assignment);
  });

  it("routes the three proposal learning modes into the right workspace", () => {
    expect(workspaceViewForLearningMode("direct")).toBe("evidence");
    expect(workspaceViewForLearningMode("review")).toBe("evidence");
    expect(workspaceViewForLearningMode("continuous")).toBe("graph");
  });

  it("places scheduled blocks in the Canvas user time zone instead of the browser time zone", () => {
    const scheduledAt = "2026-08-15T09:00:00-06:00";

    expect(zonedDateKey(scheduledAt, "America/Denver")).toBe("2026-08-15");
    expect(zonedHour(scheduledAt, "America/Denver")).toBe(9);
    expect(zonedHour(scheduledAt, "Asia/Shanghai")).toBe(23);
  });
});
