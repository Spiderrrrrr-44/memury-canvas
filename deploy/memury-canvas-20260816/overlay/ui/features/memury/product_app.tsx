/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { getState, sendAction, syncState } from "./api";
import {
  createCalendarEvent,
  createQuestion,
  deleteCalendarEvent,
  focusCommand,
  replan,
  updateCalendarEvent,
  updatePlanBlock,
  updateQuestion,
} from "./product_api";
import type { Assignment, MemuryState } from "./types";
import { LearningGraph } from "./learning_graph";
import {
  canvasPreferredLocale,
  dateTimeLocale,
  localeCopy,
} from "./locale";
import "./product.css";

type Json = Record<string, unknown>;
export type LearningMode = "direct" | "review" | "continuous";
export const workspaceViewForLearningMode = (mode: LearningMode) =>
  mode === "continuous" ? "graph" : "evidence";
type ProductState = MemuryState & {
  time_zone?: string;
  planning_status?: {
    status: "planned" | "no_available_time";
    generated_count: number;
    unscheduled: Array<{
      assignment_id: string;
      title: string;
      reason: string;
    }>;
    updated_at: string;
  };
  demo_course_catalog?: Array<{
    id: string;
    name: string;
    instructor: string;
    credits: number;
    schedule: string;
    room: string;
    progress: string;
  }>;
  semester_memory?: {
    evidence: Json[];
    evidence_summary: {
      verified_count: number;
      inferred_count: number;
      quality: string;
      mastery_basis: string;
    };
    calendar_events: Json[];
    plan_blocks: Json[];
    focus: {
      active?: Json | null;
      today_seconds: number;
      week_seconds: number;
      month_seconds: number;
      recent: Json[];
    };
    questions: Json[];
    trends: {
      has_sufficient_evidence: boolean;
      evidence_by_course: Record<string, number>;
      repeated_error_patterns: Record<string, number>;
      open_question_count: number;
      planned_minutes: number;
      actual_focus_minutes: number;
    };
  };
};

const fmt = (
  value?: unknown,
  options?: Intl.DateTimeFormatOptions,
  timeZone?: string,
) =>
  value
    ? new Intl.DateTimeFormat(dateTimeLocale(), {
        ...(options || {
          month: "short",
          day: "numeric",
          hour: "2-digit",
          minute: "2-digit",
        }),
        ...(timeZone ? { timeZone } : {}),
      }).format(new Date(String(value)))
    : localeCopy(canvasPreferredLocale(), "未安排", "Not scheduled");

const zonedParts = (value: unknown, timeZone?: string) => {
  const parts = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
    ...(timeZone ? { timeZone } : {}),
  }).formatToParts(new Date(String(value)));
  return Object.fromEntries(parts.map((part) => [part.type, part.value]));
};

export const zonedDateKey = (value: unknown, timeZone?: string) => {
  const parts = zonedParts(value, timeZone);
  return `${parts.year}-${parts.month}-${parts.day}`;
};

export const zonedHour = (value: unknown, timeZone?: string) =>
  Number(zonedParts(value, timeZone).hour);

const addCalendarDays = (dateKey: string, amount: number) => {
  const date = new Date(`${dateKey}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
};

const wallTimeAfter = (dateKey: string, hour: number, duration: number) => {
  const date = new Date(`${dateKey}T${String(hour).padStart(2, "0")}:00:00Z`);
  date.setTime(date.getTime() + duration);
  return date.toISOString().slice(0, 16);
};
const percent = (value?: unknown) => `${Math.round(Number(value || 0) * 100)}%`;
const minutes = (seconds?: unknown) =>
  `${Math.round(Number(seconds || 0) / 60)} ${localeCopy(canvasPreferredLocale(), "分钟", "min")}`;
const inputTime = (date: Date) =>
  new Date(date.getTime() - date.getTimezoneOffset() * 60_000)
    .toISOString()
    .slice(0, 16);

export function currentRoute(pathname = window.location.pathname) {
  const path = pathname;
  const learn = path.match(/^\/memury\/learn\/([^/]+)$/);
  if (learn)
    return { name: "learn", assignmentId: decodeURIComponent(learn[1]) };
  if (path === "/memury/risks") return { name: "risks" };
  if (path === "/memury/plan") return { name: "plan" };
  if (path === "/memury/memory") return { name: "memory" };
  return { name: "home" };
}

const LEGACY_ASSIGNMENT_ALIASES: Record<string, string> = {
  "mech-force": "ME250-HW4",
};

export function resolveAssignment(
  assignments: Assignment[],
  assignmentId?: string,
) {
  const resolvedId =
    LEGACY_ASSIGNMENT_ALIASES[assignmentId || ""] || assignmentId;
  return assignments.find((item) => {
    const demoId = (item as Assignment & { demo_assignment_id?: string })
      .demo_assignment_id;
    return String(item.id) === resolvedId || demoId === resolvedId;
  });
}

function Shell({
  children,
  state,
  busy,
  sync,
}: {
  children: React.ReactNode;
  state: ProductState;
  busy: boolean;
  sync: () => void;
}) {
  const route = currentRoute().name;
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const inCourse = route === "learn";
  const nativeCanvas =
    typeof document !== "undefined" &&
    Boolean(document.querySelector(".ic-app-header, #application"));
  return (
    <main
      className={`memury-product-shell${inCourse ? " is-course-view" : ""}${
        nativeCanvas ? " is-native-canvas" : ""
      }`}
    >
      <aside className="canvas-global-nav" aria-label={copy("Canvas 全局导航", "Canvas global navigation")}>
        <a className="canvas-logo" href="/memury" aria-label={copy("Canvas 首页", "Canvas home")}>
          C
        </a>
        <a href="/memury" aria-label={copy("账户", "Account")}>
          <span aria-hidden="true">○</span>
          <small>{copy("账户", "Account")}</small>
        </a>
        <a href="/memury" aria-label={copy("控制面板", "Dashboard")}>
          <span aria-hidden="true">▦</span>
          <small>{copy("控制面板", "Dashboard")}</small>
        </a>
        <a href="/memury" aria-current={inCourse ? "page" : undefined}>
          <span aria-hidden="true">▤</span>
          <small>{copy("课程", "Courses")}</small>
        </a>
        <a href="/memury/plan">
          <span aria-hidden="true">□</span>
          <small>{copy("日历", "Calendar")}</small>
        </a>
        <a href="/memury/memory">
          <span aria-hidden="true">?</span>
          <small>{copy("帮助", "Help")}</small>
        </a>
      </aside>

      <div className="canvas-app-frame">
        <header className="canvas-topbar">
          <button type="button" aria-label={copy("展开导航", "Open navigation")}>☰</button>
          <div>
            <strong>{inCourse ? copy("工程力学基础", "Engineering Mechanics") : copy("控制面板", "Dashboard")}</strong>
            {inCourse && <span>ME 250 · {copy("2026 秋", "Fall 2026")}</span>}
          </div>
          <nav aria-label={copy("Canvas 工具", "Canvas tools")}>
            <button type="button" aria-label={copy("历史记录", "History")}>◷</button>
            <button type="button" aria-label={copy("收件箱", "Inbox")}>✉</button>
            <span className="canvas-avatar" aria-label={copy("学生账户", "Student account")}>SZ</span>
          </nav>
        </header>

        <div className="canvas-body">
          {inCourse && (
            <aside className="canvas-course-nav" aria-label={copy("课程导航", "Course navigation")}>
              <a href="#course-home">{copy("主页", "Home")}</a>
              <a href="#announcements">{copy("公告", "Announcements")}</a>
              <a className="is-active" href="#assignments" aria-current="page">
                {copy("作业", "Assignments")}
              </a>
              <a href="#discussions">{copy("讨论", "Discussions")}</a>
              <a href="#grades">{copy("成绩", "Grades")}</a>
              <a href="#people">{copy("人员", "People")}</a>
              <a href="#modules">{copy("模块", "Modules")}</a>
              <a className="is-memury" href="#memury-assist">
                <span>M</span> Memury
              </a>
            </aside>
          )}

          <section className="canvas-content">
            {!inCourse && (
              <>
                <header className="memury-product-nav">
                  <a
                    className="memury-wordmark"
                    href="/memury"
                    aria-label={copy("Memury 首页", "Memury home")}
                  >
                    <span>M</span>Memury
                  </a>
                  <nav aria-label={copy("Memury 主导航", "Memury navigation")}>
                    {[
                      ["home", copy("今天", "Today"), "/memury"],
                      ["risks", copy("风险", "Risks"), "/memury/risks"],
                      ["plan", copy("计划", "Plan"), "/memury/plan"],
                      ["memory", copy("学期脉搏", "Semester"), "/memury/memory"],
                    ].map(([key, label, href]) => (
                      <a
                        key={key}
                        href={href}
                        aria-current={route === key ? "page" : undefined}
                      >
                        {label}
                      </a>
                    ))}
                  </nav>
                  <button
                    className="memury-quiet-button"
                    disabled={busy}
                    onClick={sync}
                  >
                    {copy("同步 Canvas", "Sync Canvas")}
                  </button>
                </header>
                <div className="memury-term-context">
                  <span>{copy("2026 秋季学期", "Fall 2026")}</span>
                  <span>·</span>
                  <span>
                    {state.academic_snapshot?.course_count || 0} {copy("门课程", "courses")}
                  </span>
                  <span>·</span>
                  <span>
                    {copy("上次同步", "Last synced")}{" "}
                    {fmt(state.last_synced_at, undefined, state.time_zone)}
                  </span>
                </div>
              </>
            )}
            {children}
            <footer>
              {copy(
                "Memury 读取 Canvas 中的学习事实，不修改正式成绩。",
                "Memury reads learning facts from Canvas and never changes official grades.",
              )}
            </footer>
          </section>
        </div>
      </div>
    </main>
  );
}

function Provenance({ kind }: { kind?: unknown }) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) => localeCopy(locale, chinese, english);
  const value = String(kind || "Inferred");
  const label =
    value === "Official" || value === "canvas"
      ? copy("Canvas 正式证据", "Official Canvas evidence")
      : value === "Simulated" || value === "demo"
        ? "Demo Evidence"
        : copy("Memury 推断", "Memury inference");
  return (
    <span
      className={`memury-provenance memury-provenance--${value.toLowerCase()}`}
    >
      {label}
    </span>
  );
}

function OptionalValidation({
  state,
  mutate,
}: {
  state: ProductState;
  mutate: (fn: () => Promise<ProductState>) => void;
}) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const [answer, setAnswer] = useState("");
  const session = state.learning_session || {};
  const diagnostic = state.diagnostic;
  if (state.phase === "overview") return null;

  return (
    <section className="memury-validation" aria-live="polite">
      <div className="memury-validation-progress" aria-label={copy("补充验证进度", "Optional validation progress")}>
        {["recall", "verify", "repair", "transfer", "complete"].map(
          (phase, index) => (
            <span
              key={phase}
              className={state.phase === phase ? "is-current" : ""}
            >
              {String(index + 1).padStart(2, "0")}
            </span>
          ),
        )}
      </div>
      {state.phase === "recall" && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            if (answer.trim())
              mutate(() =>
                sendAction({ event: "answer_recall", student_answer: answer }),
              );
          }}
        >
          <p className="memury-kicker">OPTIONAL RECALL</p>
          <h2>{copy("用自己的话做一次补充验证", "Add a quick check in your own words")}</h2>
          <p>{String(session.recall_question || copy("请解释你的判断和理由。", "Explain your answer and reasoning."))}</p>
          <label>
            {copy("你的回答", "Your answer")}
            <textarea
              value={answer}
              onChange={(event) => setAnswer(event.target.value)}
              placeholder={copy("说明判断与理由", "Explain your answer and reasoning")}
              required
            />
          </label>
          <button type="submit">{copy("提交补充验证", "Submit check")}</button>
        </form>
      )}
      {state.phase === "verify" && (
        <div>
          <p className="memury-kicker">DIAGNOSE</p>
          <h2>{copy("先验证候选错因", "Check the possible misconception first")}</h2>
          <p>{diagnostic?.diagnosis_summary}</p>
          <blockquote>
            {diagnostic?.verification_question || copy("请解释你的判断依据。", "Explain the evidence for your answer.")}
          </blockquote>
          <button
            onClick={() =>
              mutate(() => sendAction({ event: "answer_verification" }))
            }
          >
            {copy("已完成验证", "Check complete")}
          </button>
        </div>
      )}
      {state.phase === "repair" && (
        <div>
          <p className="memury-kicker">REPAIR</p>
          <h2>{copy("只补强已验证的薄弱点", "Focus only on the verified gap")}</h2>
          <p>{state.verified_hypothesis}</p>
          {(diagnostic?.hint || session.active_hint) && (
            <blockquote>
              {String(session.active_hint || diagnostic?.hint)}
            </blockquote>
          )}
          <div className="memury-inline-actions">
            <button
              onClick={() =>
                mutate(() => sendAction({ event: "request_hint" }))
              }
            >
              {copy("下一条渐进提示", "Next hint")}
            </button>
            <button
              onClick={() =>
                mutate(() => sendAction({ event: "start_transfer" }))
              }
            >
              {copy("进入迁移验证", "Start transfer check")}
            </button>
          </div>
        </div>
      )}
      {state.phase === "transfer" && (
        <div>
          <p className="memury-kicker">TRANSFER</p>
          <h2>{copy("换一个情境检验迁移", "Test the idea in a new situation")}</h2>
          <p>{diagnostic?.transfer_question}</p>
          <div className="memury-inline-actions">
            <button
              onClick={() =>
                mutate(() =>
                  sendAction({ event: "answer_transfer", correct: false }),
                )
              }
            >
              {copy("需要继续修复", "I need more help")}
            </button>
            <button
              onClick={() =>
                mutate(() =>
                  sendAction({ event: "answer_transfer", correct: true }),
                )
              }
            >
              {copy("已完成迁移", "Transfer complete")}
            </button>
          </div>
        </div>
      )}
      {state.phase === "complete" && (
        <div>
          <p className="memury-kicker">EVIDENCE ACCEPTED</p>
          <h2>{copy("验证已完成，状态与计划已重新计算", "Validation complete; status and plan updated")}</h2>
          <p>{state.concept.reason}</p>
          <a className="memury-primary-link" href="/memury">
            {copy("返回首页查看变化 →", "Return home to view changes →")}
          </a>
        </div>
      )}
    </section>
  );
}

function Home({ state }: { state: ProductState }) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) => localeCopy(locale, chinese, english);
  const action = state.next_action;
  const memory = state.semester_memory;
  const target = state.assignments.find(
    (item) => String(item.id) === action?.assignment_id,
  );
  const pattern = memory?.evidence.find(
    (item) =>
      String(item.assignment_id) === String(action?.assignment_id) &&
      item.error_pattern,
  );
  const actionLabel = pattern
    ? copy(`查看「${action?.title}」的错误模式`, `Review the error pattern in “${action?.title}”`)
    : copy(
        `查看「${action?.title || "当前任务"}」的学习证据`,
        `Review evidence for “${action?.title || "current task"}”`,
      );
  const plan = memory?.plan_blocks || [];
  return (
    <>
      <section
        className="memury-hero memury-enter"
        aria-labelledby="today-heading"
      >
        <div className="memury-hero-copy">
          <p className="memury-kicker">NEXT BEST ACTION</p>
          <h1 id="today-heading">{copy("把最重要的事，放进现在。", "Put the most important thing into now.")}</h1>
          <p className="memury-hero-lead">
            {action?.why ||
              copy(
                "同步 Canvas 后，Memury 会根据真实作业、反馈与时间约束给出唯一行动。",
                "After Canvas syncs, Memury recommends one action from real assignments, feedback, and time constraints.",
              )}
          </p>
          <div className="memury-action-meta">
            <span>{action?.course}</span>
            <span>{action?.estimated_minutes || 0} {copy("分钟", "min")}</span>
            <span>{copy("风险", "Risk")} {percent(action?.priority)}</span>
          </div>
          {action && (
            <a
              className="memury-primary-link"
              href={`/memury/learn/${encodeURIComponent(action.assignment_id)}`}
            >
              {actionLabel}
              <span aria-hidden="true">→</span>
            </a>
          )}
        </div>
        <div className="memury-hero-evidence">
          <span className="memury-orbit-label">{copy("判断依据", "Why this action")}</span>
          {(action?.evidence || []).slice(0, 3).map((item) => (
            <div key={`${item.type}-${item.id}`}>
              <Provenance kind={item.official_or_inferred} />
              <p>{item.label}</p>
            </div>
          ))}
          {!action?.evidence?.length && <p>{copy("证据不足；同步后不会虚构掌握度。", "Not enough evidence; Memury will not invent mastery after sync.")}</p>}
        </div>
      </section>
      <section
        className="memury-time-river memury-enter"
        aria-labelledby="river-heading"
      >
        <div className="memury-section-heading">
          <p className="memury-kicker">FROM NOW</p>
          <h2 id="river-heading">{copy("今天到本周", "Today through this week")}</h2>
          <a href="/memury/plan">{copy("打开完整周计划 →", "Open weekly plan →")}</a>
        </div>
        <div className="memury-river-track">
          <div className="memury-now-marker">
            <span>{copy("现在", "Now")}</span>
          </div>
          {plan.slice(0, 4).map((block, index) => (
            <a
              key={String(block.id)}
              className="memury-river-block"
              style={{ "--order": index } as React.CSSProperties}
              href="/memury/plan"
            >
              <time>{fmt(block.starts_at, undefined, state.time_zone)}</time>
              <strong>{String(block.title)}</strong>
              <small>{String(block.reason)}</small>
            </a>
          ))}
          {!plan.length && (
            <div className="memury-empty-inline">
              {copy(
                "还没有可执行时间块。打开计划，让 Memury 避开课程与个人日程进行编排。",
                "No actionable study block yet. Open Plan so Memury can work around classes and personal events.",
              )}
            </div>
          )}
        </div>
      </section>
      <section
        className="memury-course-band memury-enter"
        aria-labelledby="course-band-heading"
      >
        <div className="memury-section-heading">
          <div>
            <p className="memury-kicker">SEMESTER COURSES</p>
            <h2 id="course-band-heading">{copy("本学期课程", "Courses this term")}</h2>
          </div>
          <span>
            {state.demo_course_catalog?.length || state.courses?.length || 0} {copy("门", "courses")}
          </span>
        </div>
        <div className="memury-course-rail">
          {(state.demo_course_catalog || []).map((course) => (
            <article key={course.id}>
              <span>
                Demo Course · {course.id} · {course.credits} {copy("学分", "credits")}
              </span>
              <h3>{course.name}</h3>
              <p>{course.instructor}</p>
              <dl>
                <div>
                  <dt>{copy("课表", "Schedule")}</dt>
                  <dd>{course.schedule}</dd>
                </div>
                <div>
                  <dt>{copy("教室", "Room")}</dt>
                  <dd>{course.room}</dd>
                </div>
                <div>
                  <dt>{copy("进度", "Progress")}</dt>
                  <dd>{course.progress}</dd>
                </div>
              </dl>
            </article>
          ))}
        </div>
      </section>
      <div className="memury-home-lower memury-enter">
        <section className="memury-risk-stream" aria-labelledby="risk-preview">
          <div className="memury-section-heading">
            <div>
              <p className="memury-kicker">EVIDENCE, NOT SCORES</p>
              <h2 id="risk-preview">{copy("风险脉络", "Risk trail")}</h2>
            </div>
            <a href="/memury/risks">{copy("追溯全部风险 →", "Trace all risks →")}</a>
          </div>
          {(state.risks || []).slice(0, 3).map((risk) => (
            <a
              className="memury-risk-line"
              href={`/memury/learn/${encodeURIComponent(risk.id)}`}
              key={`${risk.type}-${risk.id}`}
            >
              <span className="memury-risk-level">{percent(risk.risk)}</span>
              <div>
                <strong>
                  {risk.course} · {risk.title}
                </strong>
                <p>{risk.reasons.join(locale === "zh-CN" ? "；" : "; ")}</p>
              </div>
              <span aria-hidden="true">↗</span>
            </a>
          ))}
        </section>
        <aside className="memury-pulse-rail" aria-label={copy("长期状态", "Long-term status")}>
          <p className="memury-kicker">SEMESTER PULSE</p>
          <h2>{copy("持续状态", "Ongoing status")}</h2>
          <dl>
            <div>
              <dt>{copy("本周专注", "Focus this week")}</dt>
              <dd>{minutes(memory?.focus.week_seconds)}</dd>
            </div>
            <div>
              <dt>{copy("未解决疑点", "Open questions")}</dt>
              <dd>{memory?.trends.open_question_count || 0}</dd>
            </div>
            <div>
              <dt>{copy("已验证 Evidence", "Verified evidence")}</dt>
              <dd>{memory?.evidence_summary.verified_count || 0}</dd>
            </div>
          </dl>
          <a href="/memury/memory">{copy("查看 Learning Memory →", "Open Learning Memory →")}</a>
        </aside>
      </div>
      {target && (
        <p className="memury-source-note">
          {copy("当前主行动来自", "The current main action comes from")} <Provenance kind={target.official_or_inferred} />
          {copy("；任何 AI 练习只作为后续可选验证。", "; AI-generated practice remains an optional follow-up check.")}
        </p>
      )}
    </>
  );
}

function LearningWorkspace({
  state,
  assignmentId,
  mutate,
}: {
  state: ProductState;
  assignmentId?: string;
  mutate: (fn: () => Promise<ProductState>) => void;
}) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const assignment = resolveAssignment(state.assignments, assignmentId);
  const [workspaceView, setWorkspaceView] = useState<"evidence" | "graph">(
    "evidence",
  );
  const [learningMode, setLearningMode] = useState<LearningMode>("review");
  const [workspaceOpen, setWorkspaceOpen] = useState(false);
  const [highlightEvidenceId, setHighlightEvidenceId] = useState<string | null>(
    null,
  );
  const evidence = (state.semester_memory?.evidence || []).filter(
    (item) =>
      String(item.assignment_id) === String(assignment?.id) ||
      String(item.course_id) === String(assignment?.course_id),
  );
  const verified = evidence.filter((item) => item.verified);
  const teacherEvidence = evidence.find(
    (item) => String(item.official_or_inferred) === "Official",
  );
  const primaryRiskReason =
    assignment?.risk_reasons?.[0] ||
    copy(
      "这项作业仍有一个待确认的知识点。",
      "This assignment still has one concept to clarify.",
    );
  const documentExcerpt = copy(
    "对给定的受力情境绘制自由体图，标明每个力的方向、大小与作用对象。选择正确的研究对象，标注所有外力，并解释哪些力可以构成平衡。",
    "Draw a free-body diagram for the given force scenario. Label each force’s direction, magnitude, and object. Choose the correct object, include every external force, and explain which forces can be in equilibrium.",
  );
  const recommendedMode = evidence.length ? "review" : "direct";
  const chooseMode = useCallback(
    (mode: LearningMode) => {
      setLearningMode(mode);
      setWorkspaceView(workspaceViewForLearningMode(mode));
      if (typeof window !== "undefined")
        window.localStorage.setItem(
          `memury-learning-mode:${assignment?.id || assignmentId}`,
          mode,
        );
    },
    [assignment?.id, assignmentId],
  );
  useEffect(() => {
    if (typeof window === "undefined") return;
    const stored = window.localStorage.getItem(
      `memury-learning-mode:${assignment?.id || assignmentId}`,
    );
    if (stored === "direct" || stored === "review" || stored === "continuous")
      chooseMode(stored);
  }, [assignment?.id, assignmentId, chooseMode]);
  useEffect(() => {
    if (!workspaceOpen) return;
    window.setTimeout(() => {
      document
        .getElementById("memury-workspace")
        ?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 0);
  }, [workspaceOpen]);
  const openAnchoredEvidence = (evidenceId: string) => {
    setHighlightEvidenceId(evidenceId);
    setWorkspaceView("evidence");
    setWorkspaceOpen(true);
    window.setTimeout(() => {
      document
        .getElementById(`memury-evidence-${evidenceId}`)
        ?.scrollIntoView({ behavior: "smooth", block: "center" });
    }, 0);
  };
  const openQGraph = () => {
    setLearningMode("continuous");
    setWorkspaceView("graph");
    setWorkspaceOpen(true);
  };
  if (!assignment)
    return (
      <PageIntro
        eyebrow="LEARNING WORKSPACE"
        title={copy("找不到这项作业", "Assignment not found")}
        summary={copy(
          "该 URL 没有匹配当前 Canvas 或 Demo 数据。",
          "This URL does not match the current Canvas or demo data.",
        )}
      >
        <a href="/memury">{copy("返回今天", "Back to Today")}</a>
      </PageIntro>
    );
  return (
    <>
      <nav className="canvas-breadcrumbs" aria-label={copy("面包屑导航", "Breadcrumbs")}>
        <a href="#course-home">{assignment.course_name}</a>
        <span>/</span>
        <a href="#assignments">{copy("作业", "Assignments")}</a>
        <span>/</span>
        <span>{assignment.title}</span>
      </nav>

      <header className="canvas-assignment-header memury-enter">
        <div>
          <h1>{assignment.title}</h1>
          <p>
            {copy("截止", "Due")} {fmt(assignment.due_at, undefined, state.time_zone)} · 10 {copy("分", "points")} · {copy("一次提交", "one submission")}
          </p>
        </div>
        <div className="canvas-assignment-actions">
          <span className={assignment.submitted ? "is-submitted" : ""}>
            {assignment.submitted ? copy("✓ 已提交", "✓ Submitted") : copy("尚未提交", "Not submitted")}
          </span>
          {assignment.source_url && (
            <a href={assignment.source_url}>{copy("在 Canvas 中打开", "Open in Canvas")}</a>
          )}
        </div>
      </header>

      <div className="canvas-assignment-tabs" role="tablist" aria-label={copy("作业视图", "Assignment views")}>
        <button type="button" role="tab" aria-selected="true">
          {copy("作业说明", "Instructions")}
        </button>
        <button type="button" role="tab" aria-selected="false">
          {copy("教师反馈", "Instructor feedback")} <b>{verified.length || 1}</b>
        </button>
        <button
          type="button"
          className="is-memury"
          role="tab"
          aria-selected="false"
          onClick={openQGraph}
        >
          <span>Q</span> {copy("用 Q Graph 打开", "Open with Q Graph")}
        </button>
      </div>

      <div className="memury-canvas-assignment-layout">
        <article className="canvas-assignment-document" id="canvas-source">
          <header className="memury-document-header">
            <div>
              <span>{copy("当前文档", "Current document")}</span>
              <h2>{copy("作业要求", "Assignment instructions")}</h2>
            </div>
            <button type="button" className="memury-open-qgraph" onClick={openQGraph}>
              <span aria-hidden="true">Q</span>
              {copy("用 Q Graph 打开", "Open with Q Graph")}
            </button>
          </header>
          <p>{documentExcerpt}</p>
          <ol>
            <li>{copy("选择正确的研究对象并单独画出。", "Choose and isolate the correct object.")}</li>
            <li>{copy("标注所有外力，不把作用在其他物体上的力画进来。", "Label every external force; exclude forces acting on other objects.")}</li>
            <li>{copy("使用 2–3 句话解释哪些力可以构成平衡。", "Use 2–3 sentences to explain which forces can be in equilibrium.")}</li>
          </ol>
          <section className="canvas-submission-card">
            <div>
              <span>{copy("你的提交", "Your submission")}</span>
              <strong>{copy("受力分析_v2.pdf", "force-analysis_v2.pdf")}</strong>
              <small>{copy("提交于 8月15日 22:41", "Submitted Aug 15 at 10:41 PM")}</small>
            </div>
            <span className="canvas-score">
              <strong>
                {(assignment as Assignment & { score?: number }).score ?? "—"}
              </strong>
              / 10
            </span>
          </section>
          <section className="canvas-teacher-feedback">
            <div className="canvas-feedback-avatar">LW</div>
            <div>
              <span>{copy("教师评论", "Instructor comment")}</span>
              <p>
                {String(
                  teacherEvidence?.summary ||
                    copy(
                      "请先确定每个力分别作用在哪个物体上。",
                      "First identify which object each force acts on.",
                    ),
                )}
              </p>
            </div>
          </section>
        </article>

        <aside className="memury-assist-panel" id="memury-assist">
          <header>
            <div className="memury-assist-brand">
              <span>M</span>
              <div>
                <strong>Memury</strong>
                <small>{copy("Canvas 学习助手", "Canvas learning assistant")}</small>
              </div>
            </div>
            <button type="button" disabled={false}>···</button>
          </header>
          <p className="memury-recommendation-label">{copy("根据这份作业的建议", "Suggestion for this assignment")}</p>
          <h2>{copy("先修正“作用对象”，再做一道迁移题", "Clarify the object first, then test the idea in a new case")}</h2>
          <p className="memury-recommendation-reason">{primaryRiskReason}</p>
          <div className="memury-source-chip">
            <Provenance kind={assignment.official_or_inferred} />
            <span>{verified.length} {copy("条可信依据", "trusted sources")}</span>
          </div>
          <div className="memury-mini-plan" aria-label={copy("建议学习计划", "Suggested study plan")}>
            <div>
              <span>{copy("3 分钟", "3 min")}</span>
              <strong>{copy("核对反馈", "Review feedback")}</strong>
            </div>
            <i aria-hidden="true" />
            <div>
              <span>{copy("5 分钟", "5 min")}</span>
              <strong>{copy("修正理解", "Clarify the idea")}</strong>
            </div>
            <i aria-hidden="true" />
            <div>
              <span>{copy("4 分钟", "4 min")}</span>
              <strong>{copy("迁移检验", "Transfer check")}</strong>
            </div>
          </div>
          <button
            type="button"
            className="memury-start-button"
            onClick={() => {
              chooseMode(recommendedMode);
              setWorkspaceOpen(true);
            }}
          >
            {copy("开始 12 分钟修正", "Start a 12-minute review")} <span aria-hidden="true">→</span>
          </button>
          <p className="memury-assist-note">
            {copy(
              "不会改动 Canvas 成绩；只有完成迁移检验才会更新学习记忆。",
              "Canvas grades are never changed; Learning Memory updates only after a completed transfer check.",
            )}
          </p>
        </aside>
      </div>

      {workspaceOpen && (
      <section className="memury-embedded-workspace" id="memury-workspace">
        <header className="memury-embedded-header">
          <div>
            <span className="memury-embedded-eyebrow">MEMURY · {copy("当前作业", "CURRENT ASSIGNMENT")}</span>
            <h2>
              {workspaceView === "graph"
                ? copy("与 Q Graph 继续聊", "Continue in Q Graph")
                : copy("从反馈开始修正", "Review from feedback")}
            </h2>
          </div>
          <div className="memury-compact-modes" aria-label={copy("学习方式", "Study mode")}>
            <button
              type="button"
              className={learningMode === "direct" ? "is-active" : ""}
              aria-pressed={learningMode === "direct"}
              onClick={() => chooseMode("direct")}
            >
              {copy("直接学习", "Study")}
            </button>
            <button
              type="button"
              className={learningMode === "review" ? "is-active" : ""}
              aria-pressed={learningMode === "review"}
              onClick={() => chooseMode("review")}
            >
              {copy("根据反馈复习", "Review feedback")}
              {recommendedMode === "review" && <b>{copy("建议", "Suggested")}</b>}
            </button>
            <button
              type="button"
              className={learningMode === "continuous" ? "is-active" : ""}
              aria-pressed={learningMode === "continuous"}
              onClick={() => chooseMode("continuous")}
            >
              Q Graph
            </button>
            <button
              type="button"
              className="memury-collapse-workspace"
              onClick={() => setWorkspaceOpen(false)}
            >
              {copy("收起", "Close")}
            </button>
          </div>
        </header>

        <div className="memury-workspace-switch" role="tablist" aria-label={copy("学习内容", "Learning content")}>
          <button
            type="button"
            role="tab"
            aria-selected={workspaceView === "evidence"}
            onClick={() => setWorkspaceView("evidence")}
          >
            {copy("学习建议", "Study guidance")}
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={workspaceView === "graph"}
            onClick={() => setWorkspaceView("graph")}
          >
            Q Graph <small>{copy("文档对话", "Document chat")}</small>
          </button>
        </div>

        {workspaceView === "graph" ? (
          <LearningGraph
            assignmentId={String(assignment.id)}
            assignmentTitle={assignment.title}
            documentTitle={assignment.title}
            documentExcerpt={documentExcerpt}
            onOpenEvidence={openAnchoredEvidence}
          />
        ) : (
          <div className="memury-learning-layout memury-enter" role="tabpanel">
            <section className="memury-evidence-ledger">
              <div className="memury-section-heading">
                <div>
                  <p className="memury-kicker">FROM CANVAS</p>
                  <h2>{copy("用到的依据", "Evidence used")}</h2>
                </div>
                <span>{verified.length} {copy("条已确认", "verified")}</span>
              </div>
              <div className="memury-assignment-facts">
                <div>
                  <span>{copy("提交", "Submission")}</span>
                  <strong>{assignment.submitted ? copy("已提交", "Submitted") : copy("未提交", "Not submitted")}</strong>
                </div>
                <div>
                  <span>{copy("得分", "Score")}</span>
                  <strong>
                    {(assignment as Assignment & { score?: number }).score ??
                      copy("待评分", "Pending")}
                  </strong>
                </div>
                <div>
                  <span>{copy("建议用时", "Suggested time")}</span>
                  <strong>{copy("12 分钟", "12 min")}</strong>
                </div>
              </div>
              {evidence.map((item) => (
                <article
                  id={`memury-evidence-${String(item.id)}`}
                  className={`memury-evidence-item${
                    highlightEvidenceId === String(item.id)
                      ? " is-highlighted"
                      : ""
                  }`}
                  key={String(item.id)}
                >
                  <div>
                    <Provenance kind={item.official_or_inferred} />
                    <span>{item.verified ? copy("已确认", "Verified") : copy("待验证的推测", "Unverified inference")}</span>
                  </div>
                  <h3>{String(item.title)}</h3>
                  <p>{String(item.summary || copy("没有更多正文", "No additional details"))}</p>
                  {Boolean(item.error_pattern) && (
                    <p className="memury-pattern">
                      {copy("需修正", "Needs review")} · {String(item.error_pattern)}
                    </p>
                  )}
                </article>
              ))}
              {!evidence.length && (
                <div className="memury-insufficient">
                  <strong>{copy("还没有足够依据", "Not enough evidence yet")}</strong>
                  <p>{copy("Canvas 尚未提供题目级错题或教师反馈。", "Canvas has not provided item-level errors or instructor feedback yet.")}</p>
                </div>
              )}
            </section>
            <aside className="memury-next-step-card">
              <span>{copy("接下来做什么", "What to do next")}</span>
              <h3>{copy("先确认力作用在谁身上", "First identify which object each force acts on")}</h3>
              <ol>
                <li>{copy("回看老师的批注", "Review the instructor comment")}</li>
                <li>{copy("在自由体图上重新标注对象", "Relabel the object in the free-body diagram")}</li>
                <li>{copy("换一个情境再判断一次", "Test the idea in a new situation")}</li>
              </ol>
              <button
                type="button"
                onClick={() => {
                  setLearningMode("continuous");
                  setWorkspaceView("graph");
                }}
              >
                {copy("用 Q Graph 打开 →", "Open in Q Graph →")}
              </button>
            </aside>
          </div>
        )}
      </section>
      )}
      <OptionalValidation state={state} mutate={mutate} />
    </>
  );
}

function Risks({ state }: { state: ProductState }) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const evidence = state.semester_memory?.evidence || [];
  return (
    <>
      <PageIntro
        eyebrow="RISK CENTER"
        title={copy("风险不是一个颜色，而是一条可追溯的证据链。", "Risk is a traceable evidence trail, not just a color.")}
        summary={copy("按截止、权重、提交状态、重复错误和时间冲突排序；证据不足时明确保留不确定性。", "Prioritized by deadlines, weight, submission state, recurring errors, and schedule conflicts. Uncertainty stays visible when evidence is limited.")}
      >
        <span>{state.risks?.length || 0} {copy("个观察项", "observations")}</span>
      </PageIntro>
      <section className="memury-risk-center memury-enter">
        {(state.risks || []).map((risk, index) => {
          const linked = evidence.filter(
            (item) =>
              String(item.assignment_id) === risk.id ||
              String(item.course_id) === String(risk.course_id),
          );
          return (
            <details
              className="memury-risk-case"
              key={`${risk.type}-${risk.id}`}
              open={index === 0}
            >
              <summary>
                <span className="memury-risk-rank">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <div>
                  <small>{risk.course}</small>
                  <h2>{risk.title}</h2>
                </div>
                <strong>{percent(risk.risk)}</strong>
              </summary>
              <div className="memury-risk-detail">
                <div>
                  <h3>{copy("形成风险的证据", "Evidence behind this risk")}</h3>
                  <ul>
                    {risk.reasons.map((reason) => (
                      <li key={reason}>{reason}</li>
                    ))}
                  </ul>
                  {linked.length ? (
                    linked.slice(0, 3).map((item) => (
                      <p key={String(item.id)}>
                        <Provenance kind={item.official_or_inferred} />{" "}
                        {String(item.title)}
                      </p>
                    ))
                  ) : (
                    <p className="memury-insufficient">
                      {copy("证据不足：当前只有截止与状态信号。", "Limited evidence: only deadline and status signals are available.")}
                    </p>
                  )}
                </div>
                <dl>
                  <div>
                    <dt>{copy("截止", "Due")}</dt>
                    <dd>
                      {fmt(
                        risk.due_at || risk.starts_at,
                        undefined,
                        state.time_zone,
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt>{copy("预计用时", "Estimated time")}</dt>
                    <dd>{risk.estimated_minutes} {copy("分钟", "min")}</dd>
                  </div>
                  <div>
                    <dt>{copy("推断置信", "Confidence")}</dt>
                    <dd>
                      {percent((risk.source.confidence as number) || 0.5)}
                    </dd>
                  </div>
                </dl>
                <a
                  className="memury-primary-link"
                  href={`/memury/learn/${encodeURIComponent(risk.id)}`}
                >
                  {copy("查看作业与 Evidence →", "View assignment and evidence →")}
                </a>
              </div>
            </details>
          );
        })}
      </section>
    </>
  );
}

function EventForm({
  state,
  mutate,
}: {
  state: ProductState;
  mutate: (fn: () => Promise<ProductState>) => void;
}) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const start = useMemo(() => {
    return `${state.today?.date || inputTime(new Date()).slice(0, 10)}T19:00`;
  }, [state.today?.date]);
  const end = useMemo(() => {
    return `${state.today?.date || inputTime(new Date()).slice(0, 10)}T21:00`;
  }, [state.today?.date]);
  const [form, setForm] = useState({
    title: "",
    starts_at: start,
    ends_at: end,
    availability: "busy",
  });
  const [validationError, setValidationError] = useState<string | null>(null);
  return (
    <form
      className="memury-event-form"
      onSubmit={(event) => {
        event.preventDefault();
        if (new Date(form.ends_at) <= new Date(form.starts_at)) {
          setValidationError(copy("结束时间必须晚于开始时间", "End time must be later than start time"));
          return;
        }
        setValidationError(null);
        mutate(() => createCalendarEvent(form));
      }}
    >
      <h2>{copy("加入个人时间", "Add personal time")}</h2>
      <label>
        {copy("事件名称", "Event name")}
        <input
          value={form.title}
          onChange={(e) => setForm({ ...form, title: e.target.value })}
          required
        />
      </label>
      <div>
        <label>
          {copy("开始", "Start")}
          <input
            type="datetime-local"
            value={form.starts_at}
            onChange={(e) => setForm({ ...form, starts_at: e.target.value })}
            required
          />
        </label>
        <label>
          {copy("结束", "End")}
          <input
            type="datetime-local"
            value={form.ends_at}
            onChange={(e) => setForm({ ...form, ends_at: e.target.value })}
            required
          />
        </label>
      </div>
      <div>
        <label>
          {copy("占用方式", "Availability")}
          <select
            value={form.availability}
            onChange={(e) => setForm({ ...form, availability: e.target.value })}
          >
            <option value="busy">{copy("不可占用", "Busy")}</option>
            <option value="flexible">{copy("可调整", "Flexible")}</option>
          </select>
        </label>
      </div>
      <button type="submit">{copy("保存并重新规划", "Save and replan")}</button>
      {validationError && <p role="alert">{validationError}</p>}
      <p>{state.semester_memory?.calendar_events.length || 0} {copy("个日程已保存", "events saved")}</p>
    </form>
  );
}

function Plan({
  state,
  mutate,
}: {
  state: ProductState;
  mutate: (fn: () => Promise<ProductState>) => void;
}) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const memory = state.semester_memory;
  const firstDate =
    state.today?.date || zonedDateKey(new Date(), state.time_zone);
  const days = Array.from({ length: 7 }, (_, index) =>
    addCalendarDays(firstDate, index),
  );
  const move = (id: string, day: string, hour: number) => {
    const block = memory?.plan_blocks.find((item) => String(item.id) === id);
    const duration = block
      ? new Date(String(block.ends_at)).getTime() -
        new Date(String(block.starts_at)).getTime()
      : 30 * 60_000;
    mutate(() =>
      updatePlanBlock(id, {
        starts_at: `${day}T${String(hour).padStart(2, "0")}:00`,
        ends_at: wallTimeAfter(day, hour, duration),
        locked: true,
      }),
    );
  };
  return (
    <>
      <PageIntro
        eyebrow="WEEKLY ORCHESTRATION"
        title={copy("让课程、DDL 与个人生活共享同一条时间轴。", "Put classes, deadlines, and life on one timeline.")}
        summary={copy("自动计划避开固定课程和个人事件；拖动后自动锁定，后续重排不会覆盖。", "Automatic planning works around fixed classes and personal events. Dragged blocks lock in place and remain unchanged during replanning.")}
      >
        <button
          className="memury-primary-button"
          onClick={() => mutate(replan)}
        >
          {copy("根据最新约束重新规划", "Replan with current constraints")}
        </button>
        {state.planning_status && (
          <p role="status">
            {state.planning_status.status === "planned"
              ? copy(`已生成 ${state.planning_status.generated_count} 个学习块`, `${state.planning_status.generated_count} study blocks created`)
              : copy("截止前没有可用时间，请调整个人占用后重试", "No time is available before the deadline. Adjust personal events and try again.")}
          </p>
        )}
      </PageIntro>
      <div className="memury-plan-layout memury-enter">
        <EventForm state={state} mutate={mutate} />
        <section className="memury-calendar" aria-label={copy("周计划时间轴", "Weekly plan timeline")}>
          <div className="memury-calendar-head">
            <span />
            {days.map((day) => (
              <div key={day}>
                <strong>
                  {fmt(`${day}T12:00:00Z`, { weekday: "short" }, "UTC")}
                </strong>
                <span>
                  {Number(day.slice(5, 7))}/{Number(day.slice(8, 10))}
                </span>
              </div>
            ))}
          </div>
          <div className="memury-calendar-body">
            {[9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21].map((hour) => (
              <React.Fragment key={hour}>
                <time>{hour}:00</time>
                {days.map((day) => (
                  <div
                    className="memury-time-cell"
                    key={`${day}-${hour}`}
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={(e) =>
                      move(
                        e.dataTransfer.getData("text/memury-block"),
                        day,
                        hour,
                      )
                    }
                  >
                    {(memory?.calendar_events || [])
                      .filter(
                        (item) =>
                          zonedDateKey(item.starts_at, state.time_zone) ===
                            day &&
                          zonedHour(item.starts_at, state.time_zone) === hour,
                      )
                      .map((item) => (
                        <article
                          className="memury-calendar-event"
                          key={String(item.id)}
                        >
                          <strong>{String(item.title)}</strong>
                          <small>
                            {String(item.availability) === "busy"
                              ? copy("不可占用", "Busy")
                              : copy("可调整", "Flexible")}
                          </small>
                          {String(item.source_kind) === "personal" && (
                            <>
                              <button
                                aria-label={copy(
                                  `将 ${String(item.title)} 延后一小时`,
                                  `Move ${String(item.title)} one hour later`,
                                )}
                                onClick={() => {
                                  const startsAt = new Date(
                                    String(item.starts_at),
                                  );
                                  const endsAt = new Date(String(item.ends_at));
                                  mutate(() =>
                                    updateCalendarEvent(String(item.id), {
                                      starts_at: new Date(
                                        startsAt.getTime() + 3_600_000,
                                      ).toISOString(),
                                      ends_at: new Date(
                                        endsAt.getTime() + 3_600_000,
                                      ).toISOString(),
                                    }),
                                  );
                                }}
                              >
                                +1h
                              </button>
                              <button
                                aria-label={copy(`删除 ${String(item.title)}`, `Delete ${String(item.title)}`)}
                                onClick={() =>
                                  mutate(() =>
                                    deleteCalendarEvent(String(item.id)),
                                  )
                                }
                              >
                                ×
                              </button>
                            </>
                          )}
                        </article>
                      ))}
                    {(memory?.plan_blocks || [])
                      .filter(
                        (item) =>
                          zonedDateKey(item.starts_at, state.time_zone) ===
                            day &&
                          zonedHour(item.starts_at, state.time_zone) === hour,
                      )
                      .map((item) => (
                        <article
                          draggable
                          className={`memury-plan-block ${
                            item.locked ? "is-locked" : ""
                          }`}
                          key={String(item.id)}
                          onDragStart={(e) =>
                            e.dataTransfer.setData(
                              "text/memury-block",
                              String(item.id),
                            )
                          }
                        >
                          <strong>{String(item.title)}</strong>
                          <small>
                            {fmt(
                              item.starts_at,
                              {
                                hour: "2-digit",
                                minute: "2-digit",
                              },
                              state.time_zone,
                            )}{" "}
                            · {String(item.reason)}
                          </small>
                          <div>
                            <button
                              onClick={() =>
                                mutate(() =>
                                  updatePlanBlock(String(item.id), {
                                    locked: !item.locked,
                                  }),
                                )
                              }
                            >
                              {item.locked ? copy("解锁", "Unlock") : copy("锁定", "Lock")}
                            </button>
                            <button
                              onClick={() =>
                                mutate(() =>
                                  updatePlanBlock(String(item.id), {
                                    status: "completed",
                                  }),
                                )
                              }
                            >
                              {copy("完成", "Complete")}
                            </button>
                          </div>
                        </article>
                      ))}
                  </div>
                ))}
              </React.Fragment>
            ))}
          </div>
        </section>
      </div>
      {!memory?.plan_blocks.length && (
        <div className="memury-insufficient" role="status">
          <strong>{copy("当前没有可安排的学习块", "No study blocks can be scheduled")}</strong>
          <p>
            {state.planning_status?.unscheduled[0]?.reason ||
              copy("同步 Canvas 后重新规划；若仍为空，请检查截止时间与个人占用。", "Sync Canvas and replan. If this remains empty, check deadlines and personal events.")}
          </p>
        </div>
      )}
      <p className="memury-plan-help">
        {copy(
          "拖动学习块到新的小时格会吸附并锁定。若与不可占用事件冲突，重新规划会把未锁定块移到下一可用窗口。",
          "Drag a study block to another hour to snap and lock it. Replanning moves unlocked blocks to the next available window when conflicts occur.",
        )}
      </p>
    </>
  );
}

function Memory({
  state,
  mutate,
}: {
  state: ProductState;
  mutate: (fn: () => Promise<ProductState>) => void;
}) {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const memory = state.semester_memory;
  const focus = memory?.focus;
  const [question, setQuestion] = useState("");
  return (
    <>
      <PageIntro
        eyebrow="LEARNING MEMORY"
        title={copy("不是一次分数，而是一整个学期的学习状态。", "A semester of learning state, not a single score.")}
        summary={copy("专注、疑点、Evidence 质量与负荷变化都保留来源；证据不足时不绘制精确趋势。", "Focus, open questions, evidence quality, and workload changes keep their sources. Precise trends remain hidden until evidence is sufficient.")}
      >
        <span>{memory?.evidence_summary.mastery_basis}</span>
      </PageIntro>
      <div className="memury-memory-grid memury-enter">
        <section className="memury-focus-console">
          <p className="memury-kicker">FOCUS</p>
          <h2>
            {focus?.active
              ? `${minutes(focus.active.active_seconds)} · ${String(
                  focus.active.status,
                )}`
              : copy("准备一次有边界的专注", "Start a focused session with clear boundaries")}
          </h2>
          <div>
            {!focus?.active && (
              <button onClick={() => mutate(() => focusCommand("start"))}>
                {copy("开始专注", "Start focus")}
              </button>
            )}
            {focus?.active?.status === "active" && (
              <button onClick={() => mutate(() => focusCommand("pause"))}>
                {copy("暂停", "Pause")}
              </button>
            )}
            {focus?.active?.status === "paused" && (
              <button onClick={() => mutate(() => focusCommand("resume"))}>
                {copy("继续", "Resume")}
              </button>
            )}
            {focus?.active && (
              <button onClick={() => mutate(() => focusCommand("finish"))}>
                {copy("结束并保存", "Finish and save")}
              </button>
            )}
          </div>
          <dl>
            <div>
              <dt>{copy("今天", "Today")}</dt>
              <dd>{minutes(focus?.today_seconds)}</dd>
            </div>
            <div>
              <dt>{copy("本周", "This week")}</dt>
              <dd>{minutes(focus?.week_seconds)}</dd>
            </div>
            <div>
              <dt>{copy("本月", "This month")}</dt>
              <dd>{minutes(focus?.month_seconds)}</dd>
            </div>
          </dl>
          <p>
            {copy("本周计划", "Planned this week")} {memory?.trends.planned_minutes || 0} {copy("分钟", "min")} · {copy("实际专注", "Actual focus")} {memory?.trends.actual_focus_minutes || 0} {copy("分钟", "min")}
          </p>
        </section>
        <section className="memury-question-log">
          <p className="memury-kicker">OPEN LOOPS</p>
          <h2>{copy("学期疑点", "Open questions this term")}</h2>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (question.trim())
                mutate(() =>
                  createQuestion({ content: question, source_kind: "manual" }),
                );
              setQuestion("");
            }}
          >
            <label>
              {copy("记录一个待追踪疑点", "Record a question to revisit")}
              <textarea
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
                placeholder={copy("例如：为什么同一受力图在不同参考系下会变化？", "For example: Why does the same force diagram change across reference frames?")}
                required
              />
            </label>
            <button>{copy("加入疑点记录", "Add question")}</button>
          </form>
          {(memory?.questions || []).map((item) => (
            <article key={String(item.id)}>
              <span>{String(item.status)}</span>
              <p>{String(item.content)}</p>
              <small>
                {String(item.source_kind)} ·{" "}
                {fmt(item.created_at, undefined, state.time_zone)}
              </small>
              {item.status !== "resolved" && (
                <button
                  onClick={() =>
                    mutate(() =>
                      updateQuestion(String(item.id), {
                        status: "resolved",
                        resolution_note: copy("已通过课程材料与作业反馈复核", "Reviewed with course materials and assignment feedback"),
                      }),
                    )
                  }
                >
                  {copy("标记已解决", "Mark resolved")}
                </button>
              )}
            </article>
          ))}
        </section>
        <section className="memury-trend-space">
          <p className="memury-kicker">SEMESTER SIGNALS</p>
          <h2>{copy("长期趋势", "Long-term trends")}</h2>
          {memory?.trends.has_sufficient_evidence ? (
            <>
              <div className="memury-signal-bars">
                {Object.entries(memory.trends.repeated_error_patterns).map(
                  ([name, count]) => (
                    <div key={name}>
                      <span>{name}</span>
                      <i style={{ width: `${Math.min(100, count * 25)}%` }} />
                      <strong>{count}</strong>
                    </div>
                  ),
                )}
              </div>
            </>
          ) : (
            <div className="memury-insufficient">
              <strong>{copy("还不能画出可信曲线", "Not enough evidence for a reliable trend")}</strong>
              <p>
                {copy(
                  "至少需要 3 条已验证 Evidence。当前只展示计数与来源，不制造精确趋势。",
                  "At least three verified evidence items are required. For now, Memury shows counts and sources without inventing a precise trend.",
                )}
              </p>
            </div>
          )}
        </section>
      </div>
    </>
  );
}

function PageIntro({
  eyebrow,
  title,
  summary,
  children,
}: {
  eyebrow: string;
  title: string;
  summary: string;
  children?: React.ReactNode;
}) {
  return (
    <header className="memury-page-intro memury-enter">
      <p className="memury-kicker">{eyebrow}</p>
      <h1>{title}</h1>
      <p>{summary}</p>
      <div>{children}</div>
    </header>
  );
}

export function ProductApp() {
  const locale = canvasPreferredLocale();
  const copy = (chinese: string, english: string) =>
    localeCopy(locale, chinese, english);
  const [state, setState] = useState<ProductState | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const route = useMemo(currentRoute, []);
  const mutate = useCallback(
    async (fn: () => Promise<ProductState>) => {
      if (busy) return;
      setBusy(true);
      setError(null);
      try {
        setState(await fn());
      } catch (reason) {
        setError(reason instanceof Error ? reason.message : String(reason));
      } finally {
        setBusy(false);
      }
    },
    [busy],
  );
  useEffect(() => {
    getState(
      route.name === "learn"
        ? { type: "assignment", assignment_id: route.assignmentId }
        : { type: "dashboard" },
    )
      .then(setState)
      .catch((reason) => setError(String(reason)));
  }, [route.assignmentId, route.name]);
  if (!state)
    return (
      <main className="memury-product-shell">
        <div className="memury-loading-orb" />
        <p>{error || copy("正在整理学习证据与时间约束…", "Organizing learning evidence and time constraints…")}</p>
      </main>
    );
  const body =
    route.name === "learn" ? (
      <LearningWorkspace
        state={state}
        assignmentId={route.assignmentId}
        mutate={mutate}
      />
    ) : route.name === "risks" ? (
      <Risks state={state} />
    ) : route.name === "plan" ? (
      <Plan state={state} mutate={mutate} />
    ) : route.name === "memory" ? (
      <Memory state={state} mutate={mutate} />
    ) : (
      <Home state={state} />
    );
  return (
    <Shell state={state} busy={busy} sync={() => mutate(syncState)}>
      {error && (
        <div className="memury-toast" role="alert">
          {error}
        </div>
      )}
      {busy && (
        <div className="memury-progress" role="status">
          {copy("正在更新…", "Updating…")}
        </div>
      )}
      {body}
    </Shell>
  );
}
