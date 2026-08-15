/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */
import React, { useEffect, useMemo, useState } from "react";
import { continueLearningGraph, getLearningGraph } from "./api";
import type {
  LearningGraphEdge,
  LearningGraphNode,
  LearningGraphState,
} from "./types";

const NODE_WIDTH = 216;
const NODE_HEIGHT = 104;
const COLUMN_GAP = 74;
const ROW_GAP = 34;
const CANVAS_PADDING = 28;

type PositionedNode = LearningGraphNode & {
  x: number;
  y: number;
  depth: number;
};

export function layoutLearningGraph(
  nodes: LearningGraphNode[],
  edges: LearningGraphEdge[]
) {
  const depths = new Map(nodes.map((node) => [node.id, 0]));
  for (let iteration = 0; iteration < nodes.length; iteration++) {
    let changed = false;
    edges.forEach((edge) => {
      const source = depths.get(edge.source_node_id);
      const target = depths.get(edge.target_node_id);
      if (source === undefined || target === undefined) return;
      if (target < source + 1) {
        depths.set(edge.target_node_id, source + 1);
        changed = true;
      }
    });
    if (!changed) break;
  }
  const groups = new Map<number, LearningGraphNode[]>();
  nodes.forEach((node) => {
    const depth = depths.get(node.id) || 0;
    groups.set(depth, [...(groups.get(depth) || []), node]);
  });
  const positioned: PositionedNode[] = [];
  groups.forEach((group, depth) => {
    group.forEach((node, row) => {
      positioned.push({
        ...node,
        depth,
        x: CANVAS_PADDING + depth * (NODE_WIDTH + COLUMN_GAP),
        y: CANVAS_PADDING + row * (NODE_HEIGHT + ROW_GAP),
      });
    });
  });
  const maxDepth = Math.max(0, ...positioned.map((node) => node.depth));
  const maxRows = Math.max(
    1,
    ...Array.from(groups.values()).map((group) => group.length)
  );
  return {
    nodes: positioned,
    width:
      CANVAS_PADDING * 2 + (maxDepth + 1) * NODE_WIDTH + maxDepth * COLUMN_GAP,
    height:
      CANVAS_PADDING * 2 + maxRows * NODE_HEIGHT + (maxRows - 1) * ROW_GAP,
  };
}

const stateLabels: Record<LearningGraphNode["verification_state"], string> = {
  exploration: "探索记录",
  pending: "待验证 Evidence",
  verified: "已验证 Evidence",
  unresolved: "未解决误区",
};

const kindLabels: Record<LearningGraphNode["kind"], string> = {
  learning_goal: "学习目标",
  student_question: "学生问题",
  diagnosis: "诊断候选",
  intervention: "提示 / 干预",
  verification: "验证",
  transfer_task: "迁移任务",
  verification_result: "验证结果",
};

function requestId() {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto)
    return crypto.randomUUID();
  return `graph-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function activePath(graph: LearningGraphState) {
  const active = new Set<string>();
  if (!graph.current_node_id) return active;
  const incoming = new Map<string, string[]>();
  graph.edges.forEach((edge) => {
    incoming.set(edge.target_node_id, [
      ...(incoming.get(edge.target_node_id) || []),
      edge.source_node_id,
    ]);
  });
  const queue = [graph.current_node_id];
  while (queue.length) {
    const id = queue.shift()!;
    if (active.has(id)) continue;
    active.add(id);
    queue.push(...(incoming.get(id) || []));
  }
  return active;
}

export function LearningGraph({
  assignmentId,
  assignmentTitle,
}: {
  assignmentId: string;
  assignmentTitle: string;
}) {
  const [graph, setGraph] = useState<LearningGraphState | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [question, setQuestion] = useState("");
  const [branching, setBranching] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    let active = true;
    setError(null);
    getLearningGraph(assignmentId)
      .then((next) => {
        if (!active) return;
        setGraph(next);
        setSelectedId(next.current_node_id || next.nodes[0]?.id || null);
      })
      .catch(
        (reason) =>
          active &&
          setError(reason instanceof Error ? reason.message : String(reason))
      );
    return () => {
      active = false;
    };
  }, [assignmentId, reloadToken]);

  const layout = useMemo(
    () => layoutLearningGraph(graph?.nodes || [], graph?.edges || []),
    [graph?.edges, graph?.nodes]
  );
  const positions = useMemo(
    () => new Map(layout.nodes.map((node) => [node.id, node])),
    [layout.nodes]
  );
  const path = useMemo(
    () => (graph ? activePath(graph) : new Set<string>()),
    [graph]
  );
  const selected = graph?.nodes.find((node) => node.id === selectedId) || null;

  const createBranch = async () => {
    if (!graph || !selected || question.trim().length < 2 || busy) return;
    setBusy(true);
    setError(null);
    try {
      const next = await continueLearningGraph({
        assignmentId,
        parentNodeId: selected.id,
        question: question.trim(),
        requestId: requestId(),
      });
      setGraph(next);
      setSelectedId(next.current_node_id);
      setQuestion("");
      setBranching(false);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason));
    } finally {
      setBusy(false);
    }
  };

  if (!graph && !error)
    return (
      <section className="memury-graph-loading" aria-live="polite">
        正在整理真实 Session、Step 与 Evidence…
      </section>
    );

  if (!graph?.nodes.length)
    return (
      <section className="memury-graph-empty">
        <p className="memury-kicker">LEARNING GRAPH</p>
        <h2>尚未形成学习路径</h2>
        <p>
          当前 Assignment 还没有学习
          Session。先使用原有“启动可选验证”，路径会在真实 Step 与 Evidence
          写入后出现；这里不会生成假节点。
        </p>
        {error && <p role="alert">{error}</p>}
        <button
          type="button"
          onClick={() => setReloadToken((value) => value + 1)}
        >
          重新检查
        </button>
      </section>
    );

  return (
    <section
      className="memury-learning-graph"
      aria-labelledby="learning-graph-title"
    >
      <header className="memury-graph-header">
        <div>
          <p className="memury-kicker">LEARNING GRAPH</p>
          <h2 id="learning-graph-title">非线性学习空间</h2>
          <p>{assignmentTitle} · 图结构来自真实 Session、Step 与 Evidence。</p>
        </div>
        <div className="memury-graph-legend" aria-label="验证状态图例">
          {Object.entries(stateLabels).map(([state, label]) => (
            <span key={state} className={`is-${state}`}>
              {label}
            </span>
          ))}
        </div>
      </header>
      {error && (
        <p className="memury-graph-error" role="alert">
          {error}
        </p>
      )}
      <div className="memury-graph-layout">
        <div className="memury-graph-scroll" aria-label="学习路径画布">
          <div
            className="memury-graph-canvas"
            style={{ width: layout.width, height: layout.height }}
          >
            <svg
              className="memury-graph-edges"
              viewBox={`0 0 ${layout.width} ${layout.height}`}
              aria-label={`${graph.edges.length} 条学习关系`}
            >
              <defs>
                <marker
                  id="memury-graph-arrow"
                  markerWidth="8"
                  markerHeight="8"
                  refX="7"
                  refY="4"
                  orient="auto"
                >
                  <path d="M0,0 L8,4 L0,8 Z" />
                </marker>
              </defs>
              {graph.edges.map((edge) => {
                const source = positions.get(edge.source_node_id);
                const target = positions.get(edge.target_node_id);
                if (!source || !target) return null;
                const sx = source.x + NODE_WIDTH;
                const sy = source.y + NODE_HEIGHT / 2;
                const tx = target.x;
                const ty = target.y + NODE_HEIGHT / 2;
                const bend = Math.max(28, (tx - sx) / 2);
                return (
                  <path
                    key={edge.id}
                    data-edge-relation={edge.relation}
                    className={
                      edge.relation === "branch" ? "is-branch" : undefined
                    }
                    d={`M ${sx} ${sy} C ${sx + bend} ${sy}, ${
                      tx - bend
                    } ${ty}, ${tx} ${ty}`}
                    markerEnd="url(#memury-graph-arrow)"
                  >
                    <title>{edge.label}</title>
                  </path>
                );
              })}
            </svg>
            {layout.nodes.map((node) => {
              const isCurrent = node.id === graph.current_node_id;
              const isSelected = node.id === selectedId;
              const offPath = path.size > 0 && !path.has(node.id);
              return (
                <button
                  type="button"
                  key={node.id}
                  className={`memury-graph-node is-${node.verification_state}${
                    isCurrent ? " is-current" : ""
                  }${isSelected ? " is-selected" : ""}${
                    offPath ? " is-off-path" : ""
                  }`}
                  style={{ left: node.x, top: node.y }}
                  aria-current={isCurrent ? "step" : undefined}
                  aria-pressed={isSelected}
                  onClick={() => {
                    setSelectedId(node.id);
                    setBranching(false);
                  }}
                >
                  <span>{kindLabels[node.kind]}</span>
                  <strong>{node.title}</strong>
                  <small>
                    {isCurrent ? "当前节点 · " : ""}
                    {stateLabels[node.verification_state]}
                  </small>
                </button>
              );
            })}
          </div>
        </div>
        <aside className="memury-graph-detail" aria-live="polite">
          {selected && (
            <>
              <p className="memury-kicker">NODE DETAIL</p>
              <span
                className={`memury-graph-state is-${selected.verification_state}`}
              >
                {stateLabels[selected.verification_state]}
              </span>
              <h3>{selected.title}</h3>
              <dl>
                <div>
                  <dt>节点类型</dt>
                  <dd>{kindLabels[selected.kind]}</dd>
                </div>
                <div>
                  <dt>创建时间</dt>
                  <dd>
                    {new Date(selected.created_at).toLocaleString("zh-CN")}
                  </dd>
                </div>
                <div>
                  <dt>关系</dt>
                  <dd>{selected.relationship}</dd>
                </div>
                <div>
                  <dt>Evidence</dt>
                  <dd>
                    {selected.evidence_refs.length
                      ? selected.evidence_refs
                          .map((item) => `#${item.id}`)
                          .join("、")
                      : "无"}
                  </dd>
                </div>
              </dl>
              <p>{selected.summary}</p>
              <div className="memury-graph-actions">
                <button
                  type="button"
                  onClick={() => setSelectedId(graph.current_node_id)}
                  disabled={!graph.current_node_id}
                >
                  返回当前节点
                </button>
                {graph.writable && (
                  <button
                    type="button"
                    className="is-primary"
                    onClick={() => setBranching((value) => !value)}
                  >
                    从这里继续
                  </button>
                )}
              </div>
              {branching && (
                <div className="memury-graph-branch-form">
                  <label htmlFor="memury-branch-question">新分支问题</label>
                  <textarea
                    id="memury-branch-question"
                    value={question}
                    maxLength={240}
                    placeholder="用一个清晰问题继续这条路径"
                    onChange={(event) => setQuestion(event.target.value)}
                  />
                  <button
                    type="button"
                    className="is-primary"
                    disabled={busy || question.trim().length < 2}
                    onClick={createBranch}
                  >
                    {busy ? "正在建立真实分支…" : "建立分支"}
                  </button>
                </div>
              )}
              <p className="memury-graph-memory-note">
                探索记录不会直接改变风险；只有可信验证形成 AcademicEvidence
                后，才进入 Learning Memory。后续教学 Step 会沿当前分支留痕，
                但该分支不会建立独立的模型上下文。
              </p>
            </>
          )}
        </aside>
      </div>
    </section>
  );
}
