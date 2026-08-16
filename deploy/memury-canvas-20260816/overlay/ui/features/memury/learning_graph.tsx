/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */
import React, { useEffect, useMemo, useState } from "react";
import {
  continueLearningGraph,
  getLearningGraph,
  selectLearningGraphNode,
} from "./api";
import type {
  LearningGraphEdge,
  LearningGraphNode,
  LearningGraphState,
} from "./types";
import {
  canvasPreferredLocale,
  dateTimeLocale,
  localeCopy,
} from "./locale";

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
  edges: LearningGraphEdge[],
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
    ...Array.from(groups.values()).map((group) => group.length),
  );
  return {
    nodes: positioned,
    width:
      CANVAS_PADDING * 2 + (maxDepth + 1) * NODE_WIDTH + maxDepth * COLUMN_GAP,
    height:
      CANVAS_PADDING * 2 + maxRows * NODE_HEIGHT + (maxRows - 1) * ROW_GAP,
  };
}

const chineseStateLabels: Record<LearningGraphNode["verification_state"], string> = {
  exploration: "探索记录",
  pending: "待验证 Evidence",
  verified: "已验证 Evidence",
  unresolved: "未解决误区",
};

const englishStateLabels: Record<LearningGraphNode["verification_state"], string> = {
  exploration: "Exploration",
  pending: "Pending evidence",
  verified: "Verified evidence",
  unresolved: "Unresolved",
};

const chineseKindLabels: Record<LearningGraphNode["kind"], string> = {
  learning_goal: "学习目标",
  student_question: "学生问题",
  tutor_response: "Q Graph 回应",
  diagnosis: "诊断候选",
  intervention: "提示 / 干预",
  verification: "验证",
  transfer_task: "迁移任务",
  verification_result: "验证结果",
};

const englishKindLabels: Record<LearningGraphNode["kind"], string> = {
  learning_goal: "Learning goal",
  student_question: "Your question",
  tutor_response: "Q Graph",
  diagnosis: "Diagnostic candidate",
  intervention: "Hint / intervention",
  verification: "Verification",
  transfer_task: "Transfer task",
  verification_result: "Verification result",
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
  documentTitle,
  documentExcerpt,
  onOpenEvidence,
}: {
  assignmentId: string;
  assignmentTitle: string;
  documentTitle?: string;
  documentExcerpt?: string;
  onOpenEvidence?: (evidenceId: string) => void;
}) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const stateLabels =
    locale === "zh-CN" ? chineseStateLabels : englishStateLabels;
  const kindLabels =
    locale === "zh-CN" ? chineseKindLabels : englishKindLabels;
  const [graph, setGraph] = useState<LearningGraphState | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [question, setQuestion] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [branchCreated, setBranchCreated] = useState<string | null>(null);
  const [showSummary, setShowSummary] = useState(false);
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
          setError(reason instanceof Error ? reason.message : String(reason)),
      );
    return () => {
      active = false;
    };
  }, [assignmentId, reloadToken]);

  const layout = useMemo(
    () => layoutLearningGraph(graph?.nodes || [], graph?.edges || []),
    [graph?.edges, graph?.nodes],
  );
  const positions = useMemo(
    () => new Map(layout.nodes.map((node) => [node.id, node])),
    [layout.nodes],
  );
  const path = useMemo(
    () => (graph ? activePath(graph) : new Set<string>()),
    [graph],
  );
  const selected = graph?.nodes.find((node) => node.id === selectedId) || null;
  const conversationNodes =
    graph?.nodes.filter((node) =>
      ["student_question", "tutor_response"].includes(node.kind),
    ) || [];
  const branchCount =
    graph?.edges.filter((edge) => edge.relation === "branch").length || 0;
  const verifiedCount =
    graph?.nodes.filter((node) => node.verification_state === "verified")
      .length || 0;
  const selectedTrail = useMemo(() => {
    if (!graph || !selectedId) return [];
    const incoming = new Map(
      graph.edges.map((edge) => [edge.target_node_id, edge.source_node_id]),
    );
    const trail: LearningGraphNode[] = [];
    let cursor: string | undefined = selectedId;
    const seen = new Set<string>();
    while (cursor && !seen.has(cursor)) {
      seen.add(cursor);
      const node = graph.nodes.find((item) => item.id === cursor);
      if (node) trail.unshift(node);
      cursor = incoming.get(cursor);
    }
    return trail;
  }, [graph, selectedId]);

  const selectNode = async (node: LearningGraphNode) => {
    setSelectedId(node.id);
    setBranchCreated(null);
    if (!graph || node.id === graph.current_node_id || busy) return;
    setBusy(true);
    setError(null);
    try {
      const next = await selectLearningGraphNode({
        assignmentId,
        nodeId: node.id,
      });
      setGraph(next);
      setSelectedId(next.current_node_id || node.id);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason));
    } finally {
      setBusy(false);
    }
  };

  const createBranch = async () => {
    if (question.trim().length < 2 || busy) return;
    setBusy(true);
    setError(null);
    try {
      const next = await continueLearningGraph({
        assignmentId,
        parentNodeId:
          selected?.id || graph?.current_node_id || "document-root",
        question: question.trim(),
        requestId: requestId(),
        documentTitle: documentTitle || assignmentTitle,
        documentExcerpt,
        locale,
      });
      setGraph(next);
      setSelectedId(next.current_node_id);
      setQuestion("");
      setShowSummary(false);
      setBranchCreated(selected?.title || documentTitle || assignmentTitle);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason));
    } finally {
      setBusy(false);
    }
  };

  if (!graph && !error)
    return (
      <section className="memury-graph-loading" aria-live="polite">
        {copy("正在打开 Q Graph…", "Opening Q Graph…")}
      </section>
    );

  if (!graph)
    return (
      <section className="memury-graph-empty">
        <p className="memury-kicker">Q GRAPH</p>
        <h2>{copy("暂时无法打开", "Unable to open Q Graph")}</h2>
        <p role="alert">{error}</p>
        <button
          type="button"
          onClick={() => setReloadToken((value) => value + 1)}
        >
          {copy("重试", "Try again")}
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
          <p className="memury-kicker">Q GRAPH · DOCUMENT CONVERSATION</p>
          <h2 id="learning-graph-title">Q Graph</h2>
          <p>
            {copy(
              `围绕《${documentTitle || assignmentTitle}》自由追问；每次对话都会保留在原文位置。`,
              `Explore “${documentTitle || assignmentTitle}” in conversation. Every turn stays anchored to the document.`,
            )}
          </p>
        </div>
        <div
          className="memury-graph-legend"
          aria-label={copy("验证状态", "Verification states")}
        >
          {Object.entries(stateLabels).map(([state, label]) => (
            <span key={state} className={`is-${state}`}>
              {label}
            </span>
          ))}
        </div>
      </header>
      <div
        className="memury-graph-summary"
        aria-label={copy("对话概览", "Conversation overview")}
      >
        <span>
          <strong>{graph.conversation_turns || 0}</strong>{" "}
          {copy("轮对话", "turns")}
        </span>
        <span>
          <strong>{branchCount}</strong> {copy("条探索分支", "branches")}
        </span>
        <span>
          <strong>{verifiedCount}</strong>{" "}
          {copy("个可信验证节点", "verified nodes")}
        </span>
      </div>
      {branchCreated && (
        <p className="memury-graph-success" role="status">
          {copy(
            `已从「${branchCreated}」继续对话，并保留原来的位置。`,
            `Conversation continued from “${branchCreated}” with its original anchor preserved.`,
          )}
        </p>
      )}
      {error && (
        <p className="memury-graph-error" role="alert">
          {error}
        </p>
      )}
      <div className="memury-graph-layout">
        <div
          className="memury-graph-scroll"
          aria-label={copy("Q Graph 画布", "Q Graph canvas")}
        >
          {!graph.nodes.length && (
            <div className="memury-qgraph-canvas-empty">
              <span aria-hidden="true">Q</span>
              <strong>{copy("从文档开始一段对话", "Start with the document")}</strong>
              <p>
                {copy(
                  "右侧输入问题，Q Graph 会把回答和后续分支保留在这里。",
                  "Ask a question on the right. Q Graph will keep the answer and every follow-up here.",
                )}
              </p>
            </div>
          )}
          <div
            className="memury-graph-canvas"
            style={{ width: layout.width, height: layout.height }}
          >
            <svg
              className="memury-graph-edges"
              viewBox={`0 0 ${layout.width} ${layout.height}`}
              aria-label={copy(
                `${graph.edges.length} 条学习关系`,
                `${graph.edges.length} learning relationships`,
              )}
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
                  className={`memury-graph-node is-${node.kind} is-${node.verification_state}${
                    isCurrent ? " is-current" : ""
                  }${isSelected ? " is-selected" : ""}${
                    offPath ? " is-off-path" : ""
                  }`}
                  style={{ left: node.x, top: node.y }}
                  aria-current={isCurrent ? "step" : undefined}
                  aria-pressed={isSelected}
                  disabled={busy}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" || event.key === " ") {
                      event.preventDefault();
                      selectNode(node);
                    }
                  }}
                  onClick={() => selectNode(node)}
                >
                  <span>{kindLabels[node.kind]}</span>
                  <strong>{node.title}</strong>
                  <small>
                    {isCurrent ? `${copy("当前", "Current")} · ` : ""}
                    {stateLabels[node.verification_state]}
                  </small>
                </button>
              );
            })}
          </div>
        </div>
        <aside className="memury-graph-detail memury-qgraph-chat" aria-live="polite">
          <header className="memury-qgraph-chat-header">
            <span aria-hidden="true">Q</span>
            <div>
              <strong>Q Graph</strong>
              <small>{copy("基于当前文档", "Grounded in this document")}</small>
            </div>
          </header>

          <div className="memury-qgraph-messages" aria-label={copy("对话", "Conversation")}>
            {!conversationNodes.length && (
              <article className="is-assistant">
                <span>Q Graph</span>
                <p>
                  {copy(
                    `我已经打开《${documentTitle || assignmentTitle}》。你可以问概念、原文依据，或让我换个例子解释。`,
                    `I’ve opened “${documentTitle || assignmentTitle}.” Ask about a concept, a passage, or request another example.`,
                  )}
                </p>
              </article>
            )}
            {conversationNodes.map((node) => (
              <article
                key={node.id}
                className={node.kind === "student_question" ? "is-user" : "is-assistant"}
              >
                <span>
                  {node.kind === "student_question" ? copy("你", "You") : "Q Graph"}
                </span>
                <p>{node.summary}</p>
                <time dateTime={node.created_at}>
                  {new Date(node.created_at).toLocaleTimeString(dateTimeLocale(locale), {
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </time>
              </article>
            ))}
          </div>

          {graph.conversation_summary && (
            <div className="memury-qgraph-summary-actions">
              <button type="button" onClick={() => setShowSummary((value) => !value)}>
                {showSummary
                  ? copy("收起总结", "Hide summary")
                  : copy("总结整个对话", "Summarize conversation")}
              </button>
            </div>
          )}
          {showSummary && graph.conversation_summary && (
            <section className="memury-qgraph-conversation-summary" aria-label={copy("对话总结", "Conversation summary")}>
              <p className="memury-kicker">CONVERSATION SUMMARY</p>
              <p>{graph.conversation_summary}</p>
              {!!graph.conversation_key_points?.length && (
                <ul>
                  {graph.conversation_key_points.map((point) => (
                    <li key={point}>{point}</li>
                  ))}
                </ul>
              )}
            </section>
          )}

          <div className="memury-graph-branch-form memury-qgraph-composer">
            <label htmlFor="memury-branch-question">
              {selected
                ? copy(`从「${selected.title}」继续`, `Continue from “${selected.title}”`)
                : copy("问这份文档", "Ask this document")}
            </label>
            <textarea
              id="memury-branch-question"
              value={question}
              maxLength={240}
              placeholder={copy("输入问题或想继续讨论的观点…", "Ask a question or continue an idea…")}
              onChange={(event) => setQuestion(event.target.value)}
              onKeyDown={(event) => {
                if ((event.metaKey || event.ctrlKey) && event.key === "Enter") createBranch();
              }}
            />
            <button
              type="button"
              className="is-primary"
              disabled={busy || question.trim().length < 2}
              onClick={createBranch}
            >
              {busy ? copy("Q Graph 正在思考…", "Q Graph is thinking…") : copy("发送", "Send")}
            </button>
          </div>

          {selected && (
            <details className="memury-qgraph-node-detail">
              <summary>{copy("查看当前节点与来源", "View node and sources")}</summary>
              <nav className="memury-graph-trail" aria-label={copy("节点路径", "Node path")}>
                {selectedTrail.map((node, index) => (
                  <React.Fragment key={node.id}>
                    {index > 0 && <span aria-hidden="true">›</span>}
                    <button type="button" title={node.title} onClick={() => selectNode(node)}>
                      {node.title}
                    </button>
                  </React.Fragment>
                ))}
              </nav>
              <p>{selected.summary}</p>
              {!!selected.evidence_refs.length && (
                <section className="memury-graph-anchor" aria-label={copy("来源", "Sources")}>
                  {selected.evidence_refs.map((item) => (
                    <button
                      type="button"
                      key={item.id}
                      onClick={() => onOpenEvidence?.(item.id)}
                      disabled={!onOpenEvidence}
                    >
                      <span>{item.kind}</span>
                      <b>#{item.id}</b>
                      <small>{item.verified ? copy("已验证", "Verified") : copy("待验证", "Pending")}</small>
                    </button>
                  ))}
                </section>
              )}
            </details>
          )}
          <p className="memury-graph-memory-note">
            {copy(
              "对话会保留在 Q Graph；只有完成可信验证后，结论才会进入 Learning Memory。",
              "Conversation stays in Q Graph. Only independently verified outcomes enter Learning Memory.",
            )}
          </p>
        </aside>
      </div>
    </section>
  );
}
