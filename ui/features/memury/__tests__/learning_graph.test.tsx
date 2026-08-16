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
  selectLearningGraphNode: vi.fn(),
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
    document.documentElement.lang = "zh-CN";
    vi.mocked(api.getLearningGraph).mockReset();
    vi.mocked(api.continueLearningGraph).mockReset();
    vi.mocked(api.selectLearningGraphNode).mockReset();
  });

  it("lays out a real directed path without inventing nodes", () => {
    const layout = layoutLearningGraph(graph.nodes, graph.edges);
    expect(layout.nodes).toHaveLength(3);
    expect(layout.nodes.find((node) => node.id === "step-3")!.depth).toBe(2);
    expect(layout.width).toBeGreaterThan(600);
  });

  it("renders current, unresolved, and verified states and inspects an old node", async () => {
    const onOpenEvidence = vi.fn();
    vi.mocked(api.getLearningGraph).mockResolvedValue(graph);
    vi.mocked(api.selectLearningGraphNode).mockResolvedValue({
      ...graph,
      current_node_id: "step-2",
    });
    render(
      <LearningGraph
        assignmentId="assignment-1"
        assignmentTitle="Force analysis"
        onOpenEvidence={onOpenEvidence}
      />,
    );

    expect(
      await screen.findByRole("heading", { name: "Q Graph" }),
    ).toBeVisible();
    expect(
      screen.getByRole("button", {
        name: /Transfer verification/,
        current: "step",
      }),
    ).toHaveAttribute("aria-current", "step");
    expect(screen.getAllByText("未解决误区").length).toBeGreaterThan(0);
    expect(screen.getAllByText("已验证 Evidence").length).toBeGreaterThan(0);

    const diagnosisNode = screen
      .getAllByRole("button", { name: /Concept boundary pending/ })
      .find((button) => button.hasAttribute("aria-pressed"));
    expect(diagnosisNode).toBeDefined();
    fireEvent.keyDown(diagnosisNode!, { key: "Enter" });
    await waitFor(() =>
      expect(api.selectLearningGraphNode).toHaveBeenCalledWith({
        assignmentId: "assignment-1",
        nodeId: "step-2",
      }),
    );
    fireEvent.click(screen.getByText("查看当前节点与来源"));
    expect(
      screen.getByText("This is a candidate diagnosis, not verified mastery."),
    ).toBeVisible();
    expect(screen.getByText("#evidence-6")).toBeVisible();
    expect(screen.getByLabelText("来源")).toHaveTextContent("diagnosis");
    fireEvent.click(
      screen.getByRole("button", { name: /evidence-6/ }),
    );
    expect(onOpenEvidence).toHaveBeenCalledWith("evidence-6");
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
    vi.mocked(api.selectLearningGraphNode).mockResolvedValue({
      ...graph,
      current_node_id: "step-2",
    });
    vi.mocked(api.continueLearningGraph).mockResolvedValue(branched);
    render(
      <LearningGraph
        assignmentId="assignment-1"
        assignmentTitle="Force analysis"
      />,
    );

    const diagnosisButtons = await screen.findAllByRole("button", {
      name: /Concept boundary pending/,
    });
    const diagnosisNode = diagnosisButtons.find((button) =>
      button.hasAttribute("aria-pressed"),
    );
    expect(diagnosisNode).toBeDefined();
    fireEvent.click(diagnosisNode!);
    await waitFor(() => expect(api.selectLearningGraphNode).toHaveBeenCalled());
    fireEvent.change(
      screen.getByLabelText(/从「Concept boundary pending」继续/),
      {
        target: { value: "What changes on an incline?" },
      },
    );
    fireEvent.click(screen.getByRole("button", { name: "发送" }));

    await waitFor(() =>
      expect(api.continueLearningGraph).toHaveBeenCalledWith(
        expect.objectContaining({
          assignmentId: "assignment-1",
          parentNodeId: "step-2",
          question: "What changes on an incline?",
        }),
      ),
    );
    expect(
      await screen.findByRole("button", {
        name: /What changes on an incline/,
        current: "step",
      }),
    ).toHaveAttribute("aria-current", "step");
  });

  it("opens a document-grounded conversation without inventing graph nodes", async () => {
    vi.mocked(api.getLearningGraph).mockResolvedValue({
      ...graph,
      current_node_id: null,
      nodes: [],
      edges: [],
      writable: true,
    });
    render(
      <LearningGraph
        assignmentId="assignment-1"
        assignmentTitle="Force analysis"
      />,
    );

    expect(
      await screen.findByRole("heading", { name: "Q Graph" }),
    ).toBeVisible();
    expect(screen.getByText("从文档开始一段对话")).toBeVisible();
    expect(screen.getByLabelText("问这份文档")).toBeVisible();
    expect(
      screen.queryByText("Understand force balance"),
    ).not.toBeInTheDocument();
  });

  it("shows the full conversation and its generated summary", async () => {
    vi.mocked(api.getLearningGraph).mockResolvedValue({
      ...graph,
      conversation_turns: 1,
      conversation_summary: "讨论了受力对象与平衡条件。",
      conversation_key_points: ["先确认受力对象", "再检查平衡条件"],
      nodes: [
        ...graph.nodes,
        {
          id: "step-4",
          kind: "student_question",
          title: "为什么支持力不做功？",
          summary: "为什么支持力不做功？",
          created_at: "2026-08-15T08:03:00Z",
          verification_state: "pending",
          evidence_refs: [],
          relationship: "branch",
        },
        {
          id: "step-5",
          kind: "tutor_response",
          title: "Q Graph",
          summary: "先比较力的方向与物体的位移。",
          created_at: "2026-08-15T08:04:00Z",
          verification_state: "exploration",
          evidence_refs: [],
          relationship: "response",
        },
      ],
    });

    render(
      <LearningGraph
        assignmentId="assignment-1"
        assignmentTitle="Force analysis"
        documentTitle="自由体图说明"
      />,
    );

    expect((await screen.findAllByText("为什么支持力不做功？")).length).toBeGreaterThan(0);
    expect(screen.getByText("先比较力的方向与物体的位移。")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "总结整个对话" }));
    expect(screen.getByText("讨论了受力对象与平衡条件。")).toBeVisible();
    expect(screen.getByText("先确认受力对象")).toBeVisible();
  });
});
