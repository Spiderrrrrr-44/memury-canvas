/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */
import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { LearningGraph, layoutLearningGraph } from "../learning_graph";
import * as api from "../api";
import type { LearningGraphState } from "../types";

vi.mock("../api", () => ({
  getLearningGraph: vi.fn(),
  continueLearningGraph: vi.fn(),
}));

const graph: LearningGraphState = {
  learning_session_id: "session-1",
  course_id: "course-1",
  assignment_id: "assignment-1",
  current_node_id: "step-3",
  verified_evidence_id: "evidence-7",
  created_at: "2026-08-15T08:00:00Z",
  writable: true,
  nodes: [
    {
      id: "session-1",
      kind: "learning_goal",
      title: "Understand force balance",
      summary: "Assignment learning goal",
      created_at: "2026-08-15T08:00:00Z",
      verification_state: "exploration",
      evidence_refs: [],
      relationship: "root",
    },
    {
      id: "step-2",
      kind: "diagnosis",
      title: "Concept boundary pending",
      summary: "This is a candidate diagnosis, not verified mastery.",
      created_at: "2026-08-15T08:01:00Z",
      verification_state: "unresolved",
      evidence_refs: [
        {
          id: "evidence-6",
          kind: "diagnosis",
          verified: false,
          observed_at: "2026-08-15T08:01:00Z",
        },
      ],
      relationship: "diagnoses",
      step_id: "2",
    },
    {
      id: "step-3",
      kind: "verification_result",
      title: "Transfer verification",
      summary: "Trusted transfer validation completed.",
      created_at: "2026-08-15T08:02:00Z",
      verification_state: "verified",
      evidence_refs: [
        {
          id: "evidence-7",
          kind: "transfer_validation",
          verified: true,
          observed_at: "2026-08-15T08:02:00Z",
        },
      ],
      relationship: "next step",
      step_id: "3",
    },
  ],
  edges: [
    {
      id: "edge-1",
      source_node_id: "session-1",
      target_node_id: "step-2",
      relation: "sequence",
      label: "next",
    },
    {
      id: "edge-2",
      source_node_id: "step-2",
      target_node_id: "step-3",
      relation: "sequence",
      label: "next",
    },
  ],
};

describe("LearningGraph", () => {
  beforeEach(() => {
    vi.mocked(api.getLearningGraph).mockReset();
    vi.mocked(api.continueLearningGraph).mockReset();
  });

  it("lays out a real directed path without inventing nodes", () => {
    const layout = layoutLearningGraph(graph.nodes, graph.edges);
    expect(layout.nodes).toHaveLength(3);
    expect(layout.nodes.find((node) => node.id === "step-3")!.depth).toBe(2);
    expect(layout.width).toBeGreaterThan(600);
  });

  it("renders current, unresolved, and verified states and inspects an old node", async () => {
    vi.mocked(api.getLearningGraph).mockResolvedValue(graph);
    render(
      <LearningGraph
        assignmentId="assignment-1"
        assignmentTitle="Force analysis"
      />
    );

    expect(
      await screen.findByRole("heading", { name: "非线性学习空间" })
    ).toBeVisible();
    expect(
      screen.getByRole("button", { name: /Transfer verification/ })
    ).toHaveAttribute("aria-current", "step");
    expect(screen.getAllByText("未解决误区").length).toBeGreaterThan(0);
    expect(screen.getAllByText("已验证 Evidence").length).toBeGreaterThan(0);

    fireEvent.click(
      screen.getByRole("button", { name: /Concept boundary pending/ })
    );
    expect(
      screen.getByText("This is a candidate diagnosis, not verified mastery.")
    ).toBeVisible();
    expect(screen.getByText("#evidence-6")).toBeVisible();
  });

  it("persists a real branch from a selected historical node", async () => {
    const branched: LearningGraphState = {
      ...graph,
      current_node_id: "step-4",
      nodes: [
        ...graph.nodes,
        {
          id: "step-4",
          kind: "student_question",
          title: "What changes on an incline?",
          summary: "What changes on an incline?",
          created_at: "2026-08-15T08:03:00Z",
          verification_state: "pending",
          evidence_refs: [],
          relationship: "branch",
          step_id: "4",
        },
      ],
      edges: [
        ...graph.edges,
        {
          id: "edge-3",
          source_node_id: "step-2",
          target_node_id: "step-4",
          relation: "branch",
          label: "continue",
        },
      ],
    };
    vi.mocked(api.getLearningGraph).mockResolvedValue(graph);
    vi.mocked(api.continueLearningGraph).mockResolvedValue(branched);
    render(
      <LearningGraph
        assignmentId="assignment-1"
        assignmentTitle="Force analysis"
      />
    );

    fireEvent.click(
      await screen.findByRole("button", { name: /Concept boundary pending/ })
    );
    fireEvent.click(screen.getByRole("button", { name: "从这里继续" }));
    fireEvent.change(screen.getByLabelText("新分支问题"), {
      target: { value: "What changes on an incline?" },
    });
    fireEvent.click(screen.getByRole("button", { name: "建立分支" }));

    await waitFor(() =>
      expect(api.continueLearningGraph).toHaveBeenCalledWith(
        expect.objectContaining({
          assignmentId: "assignment-1",
          parentNodeId: "step-2",
          question: "What changes on an incline?",
        })
      )
    );
    expect(
      await screen.findByRole("button", { name: /What changes on an incline/ })
    ).toHaveAttribute("aria-current", "step");
  });

  it("shows an honest empty state instead of placeholder graph nodes", async () => {
    vi.mocked(api.getLearningGraph).mockResolvedValue({
      ...graph,
      current_node_id: null,
      nodes: [],
      edges: [],
      writable: false,
    });
    render(
      <LearningGraph
        assignmentId="assignment-1"
        assignmentTitle="Force analysis"
      />
    );

    expect(
      await screen.findByRole("heading", { name: "尚未形成学习路径" })
    ).toBeVisible();
    expect(
      screen.queryByText("Understand force balance")
    ).not.toBeInTheDocument();
  });
});
