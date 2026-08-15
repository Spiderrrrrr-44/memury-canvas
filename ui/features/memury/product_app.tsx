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
import "./product.css";

type Json = Record<string, unknown>;
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
  timeZone?: string
) =>
  value
    ? new Intl.DateTimeFormat(
        "zh-CN",
        {
          ...(options || {
            month: "short",
            day: "numeric",
            hour: "2-digit",
            minute: "2-digit",
          }),
          ...(timeZone ? { timeZone } : {}),
        }
      ).format(new Date(String(value)))
    : "未安排";

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
  `${Math.round(Number(seconds || 0) / 60)} 分钟`;
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
  assignmentId?: string
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
  return (
    <main className="memury-product-shell">
      <div className="memury-ambient" aria-hidden="true" />
      <header className="memury-product-nav">
        <a className="memury-wordmark" href="/memury" aria-label="Memury 首页">
          <span>M</span>Memury
        </a>
        <nav aria-label="Memury 主导航">
          {[
            ["home", "今天", "/memury"],
            ["risks", "风险", "/memury/risks"],
            ["plan", "计划", "/memury/plan"],
            ["memory", "学期脉搏", "/memury/memory"],
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
        <button className="memury-quiet-button" disabled={busy} onClick={sync}>
          同步 Canvas
        </button>
      </header>
      <div className="memury-term-context">
        <span>2026 秋季学期</span>
        <span>·</span>
        <span>{state.academic_snapshot?.course_count || 0} 门课程</span>
        <span>·</span>
          <span>上次同步 {fmt(state.last_synced_at, undefined, state.time_zone)}</span>
      </div>
      {children}
      <footer>Memury 只读取学习证据并提供安排，不修改 Canvas 正式成绩。</footer>
    </main>
  );
}

function Provenance({ kind }: { kind?: unknown }) {
  const value = String(kind || "Inferred");
  const label =
    value === "Official" || value === "canvas"
      ? "Canvas 正式证据"
      : value === "Simulated" || value === "demo"
      ? "Demo Evidence"
      : "Memury 推断";
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
  const [answer, setAnswer] = useState("");
  const session = state.learning_session || {};
  const diagnostic = state.diagnostic;
  if (state.phase === "overview") return null;

  return (
    <section className="memury-validation" aria-live="polite">
      <div className="memury-validation-progress" aria-label="补充验证进度">
        {["recall", "verify", "repair", "transfer", "complete"].map(
          (phase, index) => (
            <span
              key={phase}
              className={state.phase === phase ? "is-current" : ""}
            >
              {String(index + 1).padStart(2, "0")}
            </span>
          )
        )}
      </div>
      {state.phase === "recall" && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            if (answer.trim())
              mutate(() =>
                sendAction({ event: "answer_recall", student_answer: answer })
              );
          }}
        >
          <p className="memury-kicker">OPTIONAL RECALL</p>
          <h2>用自己的话做一次补充验证</h2>
          <p>{String(session.recall_question || "请解释你的判断和理由。")}</p>
          <label>
            你的回答
            <textarea
              value={answer}
              onChange={(event) => setAnswer(event.target.value)}
              placeholder="说明判断与理由"
              required
            />
          </label>
          <button type="submit">提交补充验证</button>
        </form>
      )}
      {state.phase === "verify" && (
        <div>
          <p className="memury-kicker">DIAGNOSE</p>
          <h2>先验证候选错因</h2>
          <p>{diagnostic?.diagnosis_summary}</p>
          <blockquote>
            {diagnostic?.verification_question || "请解释你的判断依据。"}
          </blockquote>
          <button
            onClick={() =>
              mutate(() => sendAction({ event: "answer_verification" }))
            }
          >
            已完成验证
          </button>
        </div>
      )}
      {state.phase === "repair" && (
        <div>
          <p className="memury-kicker">REPAIR</p>
          <h2>只补强已验证的薄弱点</h2>
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
              下一条渐进提示
            </button>
            <button
              onClick={() =>
                mutate(() => sendAction({ event: "start_transfer" }))
              }
            >
              进入迁移验证
            </button>
          </div>
        </div>
      )}
      {state.phase === "transfer" && (
        <div>
          <p className="memury-kicker">TRANSFER</p>
          <h2>换一个情境检验迁移</h2>
          <p>{diagnostic?.transfer_question}</p>
          <div className="memury-inline-actions">
            <button
              onClick={() =>
                mutate(() =>
                  sendAction({ event: "answer_transfer", correct: false })
                )
              }
            >
              需要继续修复
            </button>
            <button
              onClick={() =>
                mutate(() =>
                  sendAction({ event: "answer_transfer", correct: true })
                )
              }
            >
              已完成迁移
            </button>
          </div>
        </div>
      )}
      {state.phase === "complete" && (
        <div>
          <p className="memury-kicker">EVIDENCE ACCEPTED</p>
          <h2>验证已完成，状态与计划已重新计算</h2>
          <p>{state.concept.reason}</p>
          <a className="memury-primary-link" href="/memury">
            返回首页查看变化 →
          </a>
        </div>
      )}
    </section>
  );
}

function Home({ state }: { state: ProductState }) {
  const action = state.next_action;
  const memory = state.semester_memory;
  const target = state.assignments.find(
    (item) => String(item.id) === action?.assignment_id
  );
  const pattern = memory?.evidence.find(
    (item) =>
      String(item.assignment_id) === String(action?.assignment_id) &&
      item.error_pattern
  );
  const actionLabel = pattern
    ? `查看「${action?.title}」的错误模式`
    : `查看「${action?.title || "当前任务"}」的学习证据`;
  const plan = memory?.plan_blocks || [];
  return (
    <>
      <section
        className="memury-hero memury-enter"
        aria-labelledby="today-heading"
      >
        <div className="memury-hero-copy">
          <p className="memury-kicker">NEXT BEST ACTION</p>
          <h1 id="today-heading">把最重要的事，放进现在。</h1>
          <p className="memury-hero-lead">
            {action?.why ||
              "同步 Canvas 后，Memury 会根据真实作业、反馈与时间约束给出唯一行动。"}
          </p>
          <div className="memury-action-meta">
            <span>{action?.course}</span>
            <span>{action?.estimated_minutes || 0} 分钟</span>
            <span>风险 {percent(action?.priority)}</span>
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
          <span className="memury-orbit-label">判断依据</span>
          {(action?.evidence || []).slice(0, 3).map((item) => (
            <div key={`${item.type}-${item.id}`}>
              <Provenance kind={item.official_or_inferred} />
              <p>{item.label}</p>
            </div>
          ))}
          {!action?.evidence?.length && <p>证据不足；同步后不会虚构掌握度。</p>}
        </div>
      </section>
      <section
        className="memury-time-river memury-enter"
        aria-labelledby="river-heading"
      >
        <div className="memury-section-heading">
          <p className="memury-kicker">FROM NOW</p>
          <h2 id="river-heading">今天到本周</h2>
          <a href="/memury/plan">打开完整周计划 →</a>
        </div>
        <div className="memury-river-track">
          <div className="memury-now-marker">
            <span>现在</span>
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
              还没有可执行时间块。打开计划，让 Memury
              避开课程与个人日程进行编排。
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
            <h2 id="course-band-heading">本学期课程</h2>
          </div>
          <span>
            {state.demo_course_catalog?.length || state.courses?.length || 0} 门
          </span>
        </div>
        <div className="memury-course-rail">
          {(state.demo_course_catalog || []).map((course) => (
            <article key={course.id}>
              <span>
                Demo Course · {course.id} · {course.credits} 学分
              </span>
              <h3>{course.name}</h3>
              <p>{course.instructor}</p>
              <dl>
                <div>
                  <dt>课表</dt>
                  <dd>{course.schedule}</dd>
                </div>
                <div>
                  <dt>教室</dt>
                  <dd>{course.room}</dd>
                </div>
                <div>
                  <dt>进度</dt>
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
              <h2 id="risk-preview">风险脉络</h2>
            </div>
            <a href="/memury/risks">追溯全部风险 →</a>
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
                <p>{risk.reasons.join("；")}</p>
              </div>
              <span aria-hidden="true">↗</span>
            </a>
          ))}
        </section>
        <aside className="memury-pulse-rail" aria-label="长期状态">
          <p className="memury-kicker">SEMESTER PULSE</p>
          <h2>持续状态</h2>
          <dl>
            <div>
              <dt>本周专注</dt>
              <dd>{minutes(memory?.focus.week_seconds)}</dd>
            </div>
            <div>
              <dt>未解决疑点</dt>
              <dd>{memory?.trends.open_question_count || 0}</dd>
            </div>
            <div>
              <dt>已验证 Evidence</dt>
              <dd>{memory?.evidence_summary.verified_count || 0}</dd>
            </div>
          </dl>
          <a href="/memury/memory">查看 Learning Memory →</a>
        </aside>
      </div>
      {target && (
        <p className="memury-source-note">
          当前主行动来自 <Provenance kind={target.official_or_inferred} />
          ，任何 AI 练习只作为后续可选验证。
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
  const assignment = resolveAssignment(state.assignments, assignmentId);
  const evidence = (state.semester_memory?.evidence || []).filter(
    (item) =>
      String(item.assignment_id) === String(assignment?.id) ||
      String(item.course_id) === String(assignment?.course_id)
  );
  const verified = evidence.filter((item) => item.verified);
  if (!assignment)
    return (
      <PageIntro
        eyebrow="LEARNING WORKSPACE"
        title="找不到这项作业"
        summary="该 URL 没有匹配当前 Canvas 或 Demo 数据。"
      >
        <a href="/memury">返回今天</a>
      </PageIntro>
    );
  return (
    <>
      <PageIntro
        eyebrow="CANVAS EVIDENCE WORKSPACE"
        title={assignment.title}
        summary={`${assignment.course_name} · ${
          assignment.submitted ? "已提交" : "未提交"
          } · 截止 ${fmt(assignment.due_at, undefined, state.time_zone)}`}
      >
        <Provenance kind={assignment.official_or_inferred} />
        {assignment.source_url && (
          <a href={assignment.source_url}>在 Canvas 中打开 ↗</a>
        )}
      </PageIntro>
      <div className="memury-learning-layout memury-enter">
        <section className="memury-evidence-ledger">
          <div className="memury-section-heading">
            <div>
              <p className="memury-kicker">OBSERVED EVIDENCE</p>
              <h2>作业证据链</h2>
            </div>
            <span>{verified.length} 条已验证</span>
          </div>
          <div className="memury-assignment-facts">
            <div>
              <span>提交状态</span>
              <strong>{assignment.submitted ? "已提交" : "尚未提交"}</strong>
            </div>
            <div>
              <span>得分</span>
              <strong>
                {(assignment as Assignment & { score?: number }).score ??
                  "待评分"}
              </strong>
            </div>
            <div>
              <span>风险</span>
              <strong>{percent(assignment.risk)}</strong>
            </div>
            <div>
              <span>预计用时</span>
              <strong>{assignment.estimated_minutes || 30} 分钟</strong>
            </div>
          </div>
          {evidence.map((item) => (
            <article className="memury-evidence-item" key={String(item.id)}>
              <div>
                <Provenance kind={item.official_or_inferred} />
                <span>{item.verified ? "已验证" : "未验证，不更新状态"}</span>
              </div>
              <h3>{String(item.title)}</h3>
              <p>{String(item.summary || "没有更多正文")}</p>
              {Boolean(item.error_pattern) && (
                <p className="memury-pattern">
                  重复模式 · {String(item.error_pattern)}
                </p>
              )}
            </article>
          ))}
          {!evidence.length && (
            <div className="memury-insufficient">
              <strong>证据不足</strong>
              <p>
                Canvas 尚未提供题目级错题或教师反馈。Memury
                不会据此生成精确掌握结论。
              </p>
            </div>
          )}
        </section>
        <aside className="memury-learning-aside">
          <p className="memury-kicker">WHY NOW</p>
          <h2>为什么现在处理</h2>
          <ul>
            {assignment.risk_reasons.map((reason) => (
              <li key={reason}>{reason}</li>
            ))}
          </ul>
          <p>建议先回到课程模块核对概念与教师反馈，再决定是否使用补充验证。</p>
          <a href="/memury/plan">查看已安排时间 →</a>
          <div className="memury-optional-practice">
            <span>可选验证</span>
            <h3>针对性练习与迁移</h3>
            <p>
              只有在真实薄弱点已被 Evidence 支持后，才启动 Recall → Diagnose →
              Repair → Transfer。
            </p>
            <button
              onClick={() =>
                mutate(() =>
                  sendAction({
                    event: "start_study_block",
                    assignment_id: assignment.id,
                    source_type: "assignment_evidence",
                    source_id: assignment.id,
                  })
                )
              }
            >
              启动可选验证
            </button>
          </div>
        </aside>
      </div>
      <OptionalValidation state={state} mutate={mutate} />
    </>
  );
}

function Risks({ state }: { state: ProductState }) {
  const evidence = state.semester_memory?.evidence || [];
  return (
    <>
      <PageIntro
        eyebrow="RISK CENTER"
        title="风险不是一个颜色，而是一条可追溯的证据链。"
        summary="按截止、权重、提交状态、重复错误和时间冲突排序；证据不足时明确保留不确定性。"
      >
        <span>{state.risks?.length || 0} 个观察项</span>
      </PageIntro>
      <section className="memury-risk-center memury-enter">
        {(state.risks || []).map((risk, index) => {
          const linked = evidence.filter(
            (item) =>
              String(item.assignment_id) === risk.id ||
              String(item.course_id) === String(risk.course_id)
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
                  <h3>形成风险的证据</h3>
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
                      证据不足：当前只有截止与状态信号。
                    </p>
                  )}
                </div>
                <dl>
                  <div>
                    <dt>截止</dt>
                    <dd>{fmt(risk.due_at || risk.starts_at, undefined, state.time_zone)}</dd>
                  </div>
                  <div>
                    <dt>预计用时</dt>
                    <dd>{risk.estimated_minutes} 分钟</dd>
                  </div>
                  <div>
                    <dt>推断置信</dt>
                    <dd>
                      {percent((risk.source.confidence as number) || 0.5)}
                    </dd>
                  </div>
                </dl>
                <a
                  className="memury-primary-link"
                  href={`/memury/learn/${encodeURIComponent(risk.id)}`}
                >
                  查看作业与 Evidence →
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
          setValidationError("结束时间必须晚于开始时间");
          return;
        }
        setValidationError(null);
        mutate(() => createCalendarEvent(form));
      }}
    >
      <h2>加入个人时间</h2>
      <label>
        事件名称
        <input
          value={form.title}
          onChange={(e) => setForm({ ...form, title: e.target.value })}
          required
        />
      </label>
      <div>
        <label>
          开始
          <input
            type="datetime-local"
            value={form.starts_at}
            onChange={(e) => setForm({ ...form, starts_at: e.target.value })}
            required
          />
        </label>
        <label>
          结束
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
          占用方式
          <select
            value={form.availability}
            onChange={(e) => setForm({ ...form, availability: e.target.value })}
          >
            <option value="busy">不可占用</option>
            <option value="flexible">可调整</option>
          </select>
        </label>
      </div>
      <button type="submit">保存并重新规划</button>
      {validationError && <p role="alert">{validationError}</p>}
      <p>{state.semester_memory?.calendar_events.length || 0} 个日程已持久化</p>
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
  const memory = state.semester_memory;
  const firstDate = state.today?.date || zonedDateKey(new Date(), state.time_zone);
  const days = Array.from({ length: 7 }, (_, index) => addCalendarDays(firstDate, index));
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
      })
    );
  };
  return (
    <>
      <PageIntro
        eyebrow="WEEKLY ORCHESTRATION"
        title="让课程、DDL 与个人生活共享同一条时间轴。"
        summary="自动计划避开固定课程和个人事件；拖动后自动锁定，后续重排不会覆盖。"
      >
        <button
          className="memury-primary-button"
          onClick={() => mutate(replan)}
        >
          根据最新约束重新规划
        </button>
        {state.planning_status && (
          <p role="status">
            {state.planning_status.status === "planned"
              ? `已生成 ${state.planning_status.generated_count} 个学习块`
              : "截止前没有可用时间，请调整个人占用后重试"}
          </p>
        )}
      </PageIntro>
      <div className="memury-plan-layout memury-enter">
        <EventForm state={state} mutate={mutate} />
        <section className="memury-calendar" aria-label="周计划时间轴">
          <div className="memury-calendar-head">
            <span />
            {days.map((day) => (
              <div key={day}>
                <strong>{fmt(`${day}T12:00:00Z`, { weekday: "short" }, "UTC")}</strong>
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
                        hour
                      )
                    }
                  >
                    {(memory?.calendar_events || [])
                      .filter(
                        (item) =>
                          zonedDateKey(item.starts_at, state.time_zone) === day &&
                          zonedHour(item.starts_at, state.time_zone) === hour
                      )
                      .map((item) => (
                        <article
                          className="memury-calendar-event"
                          key={String(item.id)}
                        >
                          <strong>{String(item.title)}</strong>
                          <small>
                            {String(item.availability) === "busy"
                              ? "不可占用"
                              : "可调整"}
                          </small>
                          {String(item.source_kind) === "personal" && (
                            <>
                              <button
                                aria-label={`将 ${String(
                                  item.title
                                )} 延后一小时`}
                                onClick={() => {
                                  const startsAt = new Date(
                                    String(item.starts_at)
                                  );
                                  const endsAt = new Date(String(item.ends_at));
                                  mutate(() =>
                                    updateCalendarEvent(String(item.id), {
                                      starts_at: new Date(
                                        startsAt.getTime() + 3_600_000
                                      ).toISOString(),
                                      ends_at: new Date(
                                        endsAt.getTime() + 3_600_000
                                      ).toISOString(),
                                    })
                                  );
                                }}
                              >
                                +1h
                              </button>
                              <button
                                aria-label={`删除 ${String(item.title)}`}
                                onClick={() =>
                                  mutate(() =>
                                    deleteCalendarEvent(String(item.id))
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
                          zonedDateKey(item.starts_at, state.time_zone) === day &&
                          zonedHour(item.starts_at, state.time_zone) === hour
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
                              String(item.id)
                            )
                          }
                        >
                          <strong>{String(item.title)}</strong>
                          <small>
                            {fmt(item.starts_at, {
                              hour: "2-digit",
                              minute: "2-digit",
                            }, state.time_zone)}{" "}
                            · {String(item.reason)}
                          </small>
                          <div>
                            <button
                              onClick={() =>
                                mutate(() =>
                                  updatePlanBlock(String(item.id), {
                                    locked: !item.locked,
                                  })
                                )
                              }
                            >
                              {item.locked ? "解锁" : "锁定"}
                            </button>
                            <button
                              onClick={() =>
                                mutate(() =>
                                  updatePlanBlock(String(item.id), {
                                    status: "completed",
                                  })
                                )
                              }
                            >
                              完成
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
          <strong>当前没有可安排的学习块</strong>
          <p>
            {state.planning_status?.unscheduled[0]?.reason ||
              "同步 Canvas 后重新规划；若仍为空，请检查截止时间与个人占用。"}
          </p>
        </div>
      )}
      <p className="memury-plan-help">
        拖动学习块到新的小时格会吸附并锁定。若与不可占用事件冲突，重新规划会把未锁定块移到下一可用窗口。
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
  const memory = state.semester_memory;
  const focus = memory?.focus;
  const [question, setQuestion] = useState("");
  return (
    <>
      <PageIntro
        eyebrow="LEARNING MEMORY"
        title="不是一次分数，而是一整个学期的学习状态。"
        summary="专注、疑点、Evidence 质量与负荷变化都保留来源；证据不足时不绘制精确趋势。"
      >
        <span>{memory?.evidence_summary.mastery_basis}</span>
      </PageIntro>
      <div className="memury-memory-grid memury-enter">
        <section className="memury-focus-console">
          <p className="memury-kicker">FOCUS</p>
          <h2>
            {focus?.active
              ? `${minutes(focus.active.active_seconds)} · ${String(
                  focus.active.status
                )}`
              : "准备一次有边界的专注"}
          </h2>
          <div>
            {!focus?.active && (
              <button onClick={() => mutate(() => focusCommand("start"))}>
                开始专注
              </button>
            )}
            {focus?.active?.status === "active" && (
              <button onClick={() => mutate(() => focusCommand("pause"))}>
                暂停
              </button>
            )}
            {focus?.active?.status === "paused" && (
              <button onClick={() => mutate(() => focusCommand("resume"))}>
                继续
              </button>
            )}
            {focus?.active && (
              <button onClick={() => mutate(() => focusCommand("finish"))}>
                结束并保存
              </button>
            )}
          </div>
          <dl>
            <div>
              <dt>今天</dt>
              <dd>{minutes(focus?.today_seconds)}</dd>
            </div>
            <div>
              <dt>本周</dt>
              <dd>{minutes(focus?.week_seconds)}</dd>
            </div>
            <div>
              <dt>本月</dt>
              <dd>{minutes(focus?.month_seconds)}</dd>
            </div>
          </dl>
          <p>
            本周计划 {memory?.trends.planned_minutes || 0} 分钟 · 实际专注{" "}
            {memory?.trends.actual_focus_minutes || 0} 分钟
          </p>
        </section>
        <section className="memury-question-log">
          <p className="memury-kicker">OPEN LOOPS</p>
          <h2>学期疑点</h2>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (question.trim())
                mutate(() =>
                  createQuestion({ content: question, source_kind: "manual" })
                );
              setQuestion("");
            }}
          >
            <label>
              记录一个待追踪疑点
              <textarea
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
                placeholder="例如：为什么同一受力图在不同参考系下会变化？"
                required
              />
            </label>
            <button>加入疑点记录</button>
          </form>
          {(memory?.questions || []).map((item) => (
            <article key={String(item.id)}>
              <span>{String(item.status)}</span>
              <p>{String(item.content)}</p>
              <small>
                      {String(item.source_kind)} · {fmt(item.created_at, undefined, state.time_zone)}
              </small>
              {item.status !== "resolved" && (
                <button
                  onClick={() =>
                    mutate(() =>
                      updateQuestion(String(item.id), {
                        status: "resolved",
                        resolution_note: "已通过课程材料与作业反馈复核",
                      })
                    )
                  }
                >
                  标记已解决
                </button>
              )}
            </article>
          ))}
        </section>
        <section className="memury-trend-space">
          <p className="memury-kicker">SEMESTER SIGNALS</p>
          <h2>长期趋势</h2>
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
                  )
                )}
              </div>
            </>
          ) : (
            <div className="memury-insufficient">
              <strong>还不能画出可信曲线</strong>
              <p>
                至少需要 3 条已验证
                Evidence。当前只展示计数与来源，不制造精确趋势。
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
    [busy]
  );
  useEffect(() => {
    getState(
      route.name === "learn"
        ? { type: "assignment", assignment_id: route.assignmentId }
        : { type: "dashboard" }
    )
      .then(setState)
      .catch((reason) => setError(String(reason)));
  }, [route.assignmentId, route.name]);
  if (!state)
    return (
      <main className="memury-product-shell">
        <div className="memury-loading-orb" />
        <p>{error || "正在整理学习证据与时间约束…"}</p>
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
          正在更新…
        </div>
      )}
      {body}
    </Shell>
  );
}
