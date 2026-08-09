/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 */

import React from 'react'
import {Alert} from '@instructure/ui-alerts'
import {Badge} from '@instructure/ui-badge'
import {Button} from '@instructure/ui-buttons'
import {Heading} from '@instructure/ui-heading'
import {Spinner} from '@instructure/ui-spinner'
import {Text} from '@instructure/ui-text'
import {View} from '@instructure/ui-view'
import {useScope as createI18nScope} from '@canvas/i18n'
import type {CourseIntelligence, MemuryContext, MemuryState, RecommendationEvidence} from './types'

const I18n = createI18nScope('memury')

function sourceLabel(value: string | undefined) {
  const labels: Record<string, string> = {
    Official: I18n.t('Canvas 正式数据'),
    Simulated: I18n.t('模拟数据'),
    Inferred: I18n.t('Memury 推断'),
    'User override': I18n.t('用户调整'),
    'Learner State': I18n.t('Learner State'),
  }
  return labels[value || ''] || value || I18n.t('未知来源')
}

function SourceBadge({value}: {value?: string}) {
  return <Badge count={1} formatOutput={() => sourceLabel(value)} standalone />
}

function formatDate(value?: string) {
  if (!value) return I18n.t('未安排')
  const date = new Date(value)
  return Number.isNaN(date.valueOf()) ? I18n.t('未安排') : date.toLocaleString()
}

function AcademicSnapshot({state}: {state: MemuryState}) {
  const snapshot = state.academic_snapshot
  if (!snapshot) return null
  const values = [
    [I18n.t('课程'), snapshot.course_count],
    [I18n.t('未完成任务'), snapshot.incomplete_assignment_count],
    [I18n.t('临近截止'), snapshot.due_soon_count],
    [I18n.t('逾期'), snapshot.overdue_count],
    [I18n.t('临近考试'), snapshot.upcoming_exam_count],
    [I18n.t('本周预计负载'), `${snapshot.weekly_estimated_minutes} ${I18n.t('分钟')}`],
  ]
  return (
    <View as="section" id="academic-snapshot" className="memury-section memury-snapshot" margin="medium 0">
      <Heading level="h2">{I18n.t('Academic Snapshot')}</Heading>
      <View as="div" display="flex">
        {values.map(([label, value]) => (
          <View key={String(label)} className="memury-stat" borderWidth="small" borderRadius="small" padding="small" minWidth="130px">
            <Text size="small">{label}</Text>
            <br />
            <Text size="large" weight="bold">{value}</Text>
          </View>
        ))}
      </View>
      <Text size="small">
        {I18n.t('总体风险')} {Math.round(snapshot.overall_risk * 100)}%
      </Text>
    </View>
  )
}

function EvidenceDetails({evidence}: {evidence?: RecommendationEvidence[]}) {
  if (!evidence?.length) return null
  return (
    <details>
      <summary>{I18n.t('为什么推荐？查看依据')}</summary>
      <View as="ul" margin="small 0">
        {evidence.map(item => (
          <li key={`${item.type}-${item.id}`}>
            <Text size="small">
              {item.label} · {sourceLabel(item.source)} · {sourceLabel(item.official_or_inferred)}
            </Text>
          </li>
        ))}
      </View>
    </details>
  )
}

function RecommendationCard({
  state,
  busy,
  act,
  sourceType = 'next_best_action',
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
  sourceType?: string
}) {
  const action = state.next_action
  if (!action) return <Alert variant="info">{I18n.t('当前没有待安排的学习行动。')}</Alert>

  return (
    <View as="section" id="next-best-action" className="memury-card memury-card--featured memury-next-action" padding="medium" borderWidth="small" borderRadius="medium" margin="medium 0">
      <Text size="small">{I18n.t('由风险、截止时间和 Learner State 共同计算')}</Text>
      <Heading level="h2">{I18n.t('下一最佳学习行动')}</Heading>
      <Text size="small">Next Best Action</Text>
      <Text size="large" weight="bold">
        {action.course} · {action.title}
      </Text>
      <Text as="p">{action.reason || action.why}</Text>
      <Text>
        {I18n.t('预计 %{minutes} 分钟 · 风险 %{risk} · 置信度 %{confidence}%', {
          minutes: action.estimated_minutes,
          risk: Math.round(action.priority * 100),
          confidence: Math.round((action.confidence ?? 0.5) * 100),
        })}
      </Text>
      <EvidenceDetails evidence={action.evidence} />
      <Button
        color="primary"
        margin="small 0 0"
        disabled={busy}
        onClick={() =>
          act({
            event: 'start_study_block',
            assignment_id: action.assignment_id,
            source_type: sourceType,
            source_id: action.assignment_id,
            course_id: action.course_id,
            concept_id: state.learner_state?.weak_concepts[0]?.id,
            trigger_reason: action.reason || action.why,
            originating_study_block: state.today?.study_blocks.find(block => block.status === 'planned')?.id,
          })
        }
      >
        {I18n.t('开始学习')}
      </Button>
    </View>
  )
}

function TodayPlan({
  state,
  busy,
  act,
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
}) {
  const blocks = state.today?.study_blocks?.length ? state.today.study_blocks : state.study_blocks
  return (
    <View as="section" id="today-plan" className="memury-plan memury-section" margin="large 0">
      <Heading level="h2">{I18n.t('Today Plan')}</Heading>
      <Text size="small">
        {I18n.t('%{completed} / %{total} 分钟已完成', {
          completed: state.today?.completed_minutes || 0,
          total: state.today?.total_minutes ?? blocks.reduce((sum, block) => sum + block.duration_minutes, 0),
        })}
      </Text>
      <div className="memury-study-list" role="list" aria-label={I18n.t('今日 Study Blocks')}>
        {blocks.map(block => (
          <article className="memury-study-row" role="listitem" key={block.id}>
            <div className="memury-study-row__body">
              <div className="memury-study-row__heading">
                <h3>{block.title}</h3>
                <span className="memury-status-pill">{block.today_status || block.status}</span>
              </div>
              <p className="memury-study-row__concept">{block.course_name} · {block.concept}</p>
              <p className="memury-study-row__time">
                {block.duration_minutes} {I18n.t('分钟')} · {formatDate(block.starts_at)}
              </p>
            </div>
            <div className="memury-study-row__actions">
                <Button
                  className="memury-secondary-action"
                  size="small"
                  disabled={busy || block.status === 'completed' || block.status === 'skipped'}
                  onClick={() => act({event: 'complete_block', block_id: block.id})}
                >
                  {I18n.t('完成')}
                </Button>
                <Button
                  className="memury-secondary-action"
                  size="small"
                  disabled={busy || block.status === 'completed' || block.status === 'skipped'}
                  onClick={() =>
                    act({
                      event: 'reschedule_block',
                      block_id: block.id,
                      starts_at: new Date(new Date(block.starts_at).getTime() + 86_400_000).toISOString(),
                      duration_minutes: block.duration_minutes,
                    })
                  }
                >
                  {I18n.t('暂缓一天')}
                </Button>
            </div>
          </article>
        ))}
      </div>
      {(state.today?.has_overdue || state.today?.has_due_soon || state.today?.has_schedule_conflict) && (
        <Alert variant="warning">
          {[state.today?.has_overdue && I18n.t('存在逾期任务'), state.today?.has_due_soon && I18n.t('存在临近截止任务'), state.today?.has_schedule_conflict && I18n.t('Study Block 存在时间冲突')]
            .filter(Boolean)
            .join(' · ')}
        </Alert>
      )}
    </View>
  )
}

function UpcomingExam({state}: {state: MemuryState}) {
  const exam = state.risks?.find(item => item.type === 'exam')
  if (!exam) return null
  const startsAt = exam.starts_at ? new Date(exam.starts_at) : null
  const hours = startsAt && !Number.isNaN(startsAt.valueOf()) ? Math.max(0, Math.ceil((startsAt.getTime() - Date.now()) / 3_600_000)) : null
  return (
    <View as="section" id="upcoming-exam" className="memury-card memury-card--warning" padding="small" borderWidth="small" borderRadius="small" margin="medium 0">
      <Text weight="bold">{I18n.t('最近考试：%{title}', {title: exam.title})}</Text>
      <br />
      <Text size="small">
        {hours === null ? formatDate(exam.starts_at) : I18n.t('倒计时约 %{hours} 小时', {hours})} · {sourceLabel(String(exam.source.official_or_inferred))}
      </Text>
    </View>
  )
}

function RiskQueue({state, assignmentId}: {state: MemuryState; assignmentId?: string}) {
  const risks = state.risks?.filter(item => !assignmentId || item.id === assignmentId).slice(0, 6)
  if (!risks?.length) return null
  return (
    <View as="section" id="risk-queue" className="memury-risk-queue memury-section" margin="large 0">
      <Heading level="h2">{I18n.t('Risk Queue')}</Heading>
      {risks.map(item => (
        <article key={`${item.type}-${item.id}`} className="memury-risk-row">
          <div className="memury-risk-row__header">
            <div className="memury-risk-row__identity">
              <span className="memury-risk-row__course">{item.course}</span>
              <h3>{item.title}</h3>
            </div>
            <span className="memury-risk-score" aria-label={I18n.t('风险 %{risk}%', {risk: Math.round(item.risk * 100)})}>
              {Math.round(item.risk * 100)}%
            </span>
          </div>
          <div className="memury-risk-row__meta">
            <span className="memury-status-pill">{item.status}</span>
            <span>{item.estimated_minutes} {I18n.t('分钟')}</span>
          </div>
          <ul className="memury-risk-row__reasons">
            {item.reasons.map(reason => <li key={reason}>{reason}</li>)}
          </ul>
        </article>
      ))}
    </View>
  )
}

function LearnerStateSnapshot({state}: {state: MemuryState}) {
  const learnerState = state.learner_state
  if (!learnerState) return null
  const weak = learnerState.weak_concepts[0]
  return (
    <View as="section" id="learner-state" className="memury-learner-state memury-section" margin="large 0">
      <Heading level="h2">{I18n.t('Learner State Snapshot')}</Heading>
      {weak && (
        <Text>
          {I18n.t('当前薄弱概念：%{concept} · 掌握度 %{mastery}%', {
            concept: String(weak.name),
            mastery: Math.round(Number(weak.mastery) * 100),
          })}
        </Text>
      )}
      <br />
      <Text size="small">{I18n.t('已完成学习 session：%{count}', {count: learnerState.completed_sessions})}</Text>
      {learnerState.recent_evidence[0] && (
        <Text as="p" size="small">{I18n.t('最近证据：%{title}', {title: String(learnerState.recent_evidence[0].title)})}</Text>
      )}
    </View>
  )
}

function AgentActivity({state}: {state: MemuryState}) {
  if (!state.agent_activity?.length) return null
  return (
    <View as="section" id="agent-activity" className="memury-agent-activity memury-section" margin="large 0">
      <Heading level="h2">{I18n.t('Recent Changes / Agent Activity')}</Heading>
      {state.agent_activity.slice(0, 4).map((item, index) => (
        <Alert key={`${String(item.at)}-${index}`} variant="info" margin="small 0">
          {String(item.reason || item.change)} · {sourceLabel(String(item.source))}
        </Alert>
      ))}
    </View>
  )
}

export function MemuryToday({
  state,
  busy,
  act,
  showFullPlanLink = true,
  sourceType = 'dashboard',
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
  showFullPlanLink?: boolean
  sourceType?: string
}) {
  return (
    <View as="section" id="memury-today" className="memury-surface memury-today" padding="medium" borderWidth="small" borderRadius="medium" margin="medium 0">
      <Heading level="h2">{I18n.t('Memury Today')}</Heading>
      <Text>{I18n.t('Memury 根据课程任务、截止时间、考试和 Learner State 帮你决定现在先做什么。')}</Text>
      <RecommendationCard state={state} busy={busy} act={act} sourceType={sourceType} />
      <AcademicSnapshot state={state} />
      <UpcomingExam state={state} />
      <TodayPlan state={state} busy={busy} act={act} />
      <RiskQueue state={state} />
      <LearnerStateSnapshot state={state} />
      <AgentActivity state={state} />
      {showFullPlanLink && <a href="/memury">{I18n.t('查看完整计划')}</a>}
      {!showFullPlanLink && <a href="/memury#courses">{I18n.t('查看 Course Intelligence')}</a>}
    </View>
  )
}

function courseAssignments(state: MemuryState, course: CourseIntelligence) {
  return state.assignments.filter(item => item.course_id?.toString() === course.id)
}

export function CourseIntelligenceView({
  state,
  busy,
  act,
  courseId,
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
  courseId?: string
}) {
  const courses = state.courses || []
  const course = courseId ? courses.find(item => item.id === courseId) : courses[0]
  if (!course) return <Alert variant="info">{I18n.t('当前状态中没有课程数据，请先同步 Canvas。')}</Alert>
  const assignments = courseAssignments(state, course)
  return (
    <View as="section" id="course-intelligence" className="memury-course memury-section" margin="medium 0">
      <Heading level="h2">{I18n.t('Course Intelligence：%{course}', {course: course.name})}</Heading>
      <Text>
        {I18n.t('课程风险 %{risk}% · 未完成 %{count} 项 · 预计负载 %{minutes} 分钟', {
          risk: Math.round(course.risk * 100),
          count: course.incomplete_count,
          minutes: course.estimated_minutes,
        })}
      </Text>{' '}
      <SourceBadge value={course.official_or_inferred} />
      {course.upcoming_exam && (
        <Alert variant="warning" margin="small 0">
          {I18n.t('最近考试：%{title} · %{time}', {
            title: String(course.upcoming_exam.title),
            time: formatDate(String(course.upcoming_exam.starts_at)),
          })}
        </Alert>
      )}
      <Heading level="h3">{I18n.t('课程任务与风险')}</Heading>
      {assignments.map(item => (
        <View as="article" key={String(item.id)} className="memury-course-assignment" padding="small 0">
          <Text weight="bold">{item.title}</Text> · <Text>{item.submitted ? I18n.t('已提交') : I18n.t('未完成')}</Text>
          <br />
          <Text size="small">{item.risk_reasons.join('；')} · {formatDate(item.due_at)}</Text>
          {item.source_url && (
            <>
              {' · '}
              <a href={item.source_url}>{I18n.t('打开 Canvas 作业')}</a>
            </>
          )}
        </View>
      ))}
      {course.next_action && (
        <Button
          color="primary"
          size="small"
          disabled={busy}
          onClick={() =>
            act({
              event: 'start_study_block',
              assignment_id: course.next_action?.assignment_id,
              source_type: 'course',
              source_id: course.id,
              course_id: course.id,
              concept_id: String(course.weak_concepts[0]?.id || ''),
              trigger_reason: `课程 ${course.name} 的下一最佳行动`,
              originating_study_block: course.study_blocks.find(block => block.status === 'planned')?.id,
            })
          }
        >
          {I18n.t('开始课程下一步')}
        </Button>
      )}
      <Heading level="h3">{I18n.t('薄弱概念与学习证据')}</Heading>
      {course.weak_concepts.map(concept => (
        <View as="article" key={String(concept.id)} className="memury-concept-card" padding="small" borderWidth="small" borderRadius="small">
          <Text weight="bold">{String(concept.name)}</Text> · {Math.round(Number(concept.mastery) * 100)}%
          <br />
          <Text size="small">{String(concept.misconception || I18n.t('需要更多证据'))}</Text>
          <br />
          <Button
            color="primary"
            size="small"
            disabled={busy || !course.next_action}
            onClick={() =>
              course.next_action &&
              act({
                event: 'start_study_block',
                assignment_id: course.next_action.assignment_id,
                source_type: 'course_weak_concept',
                source_id: String(concept.id),
                course_id: course.id,
                concept_id: String(concept.id),
                trigger_reason: `课程 ${course.name} 的薄弱概念需要巩固`,
                originating_study_block: course.study_blocks.find(block => block.status === 'planned')?.id,
              })
            }
          >
            {I18n.t('开始针对该概念学习')}
          </Button>
        </View>
      ))}
      {course.recent_evidence.map((item, index) => (
        <Text as="p" size="small" key={`${String(item.observed_at)}-${index}`}>
          {String(item.title)} · {String(item.source)}
        </Text>
      ))}
      <Heading level="h3">{I18n.t('对应 Study Blocks')}</Heading>
      {course.study_blocks.map(block => (
        <Text as="p" size="small" key={block.id}>
          {block.title} · {block.duration_minutes} {I18n.t('分钟')} · {block.status}
        </Text>
      ))}
    </View>
  )
}

export function CourseDirectory({
  state,
  busy,
  act,
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
}) {
  if (!state.courses?.length) return null
  return (
    <View as="section" id="courses" className="memury-course-directory memury-section" margin="large 0">
      <Heading level="h2">{I18n.t('Courses')}</Heading>
      {state.courses.map(course => (
        <View as="article" key={course.id} className="memury-card" padding="small 0" borderWidth="small" borderRadius="small" margin="small 0">
          <CourseIntelligenceView state={state} busy={busy} act={act} courseId={course.id} />
        </View>
      ))}
    </View>
  )
}

export function MemuryAssistant({
  state,
  context,
  busy,
  act,
}: {
  state: MemuryState
  context: MemuryContext
  busy: boolean
  act: (body: Record<string, unknown>) => void
}) {
  const current = state.current_context
  const action = state.next_action
  const startRelatedLearning = () => {
    if (!action) return
    act({
      event: 'start_study_block',
      assignment_id: action.assignment_id,
      source_type: 'assistant',
      source_id: context.assignment_id || context.course_id || action.assignment_id,
      course_id: context.course_id || action.course_id,
      concept_id: state.learner_state?.weak_concepts[0]?.id,
      trigger_reason: `根据当前 ${context.type} 页面上下文启动学习`,
    })
  }
  const contextLabel =
    current?.assignment_title ||
    current?.course_name ||
    (context.type === 'assignment'
      ? I18n.t('作业 %{id}', {id: context.assignment_id})
      : context.type === 'course'
        ? I18n.t('课程 %{id}', {id: context.course_id})
        : I18n.t('Canvas Dashboard'))
  return (
    <View as="aside" id="memury-assistant" className="memury-card memury-assistant" padding="medium" borderWidth="small" borderRadius="medium" margin="medium 0">
      <Heading level="h2">{I18n.t('Memury Assistant')}</Heading>
      <Text weight="bold">{I18n.t('Memury 当前知道你在哪里：%{context}', {context: contextLabel})}</Text>
      <Text as="p" size="small">
        {current?.relationship_to_plan || I18n.t('当前页面已与统一学习计划关联。')}
      </Text>
      {action && (
        <Text as="p" size="small">
          {I18n.t('下一行动：%{title} · %{minutes} 分钟', {title: action.title, minutes: action.estimated_minutes})}
        </Text>
      )}
      <Button color="primary" disabled={busy || !action} onClick={startRelatedLearning}>
        {I18n.t('开始相关学习')}
      </Button>{' '}
      <a href="/memury">{I18n.t('打开完整 Memury 计划')}</a>
      {context.type === 'dashboard' && <p><a href="/memury#risk-queue">{I18n.t('查看本周风险')}</a></p>}
      {context.type === 'course' && <p><a href="#course-intelligence">{I18n.t('查看课程风险')}</a></p>}
      {context.type === 'assignment' && action && (
        <View as="div" margin="small 0">
          <EvidenceDetails evidence={action.evidence} />
        </View>
      )}
    </View>
  )
}

export function MemuryContextSurface({context}: {context: MemuryContext}) {
  const [state, setState] = React.useState<MemuryState | null>(null)
  const [busy, setBusy] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)
  const inFlight = React.useRef(false)

  React.useEffect(() => {
    let mounted = true
    import('./api').then(({getState}) => getState(context)).then(value => mounted && setState(value)).catch(reason => mounted && setError(String(reason)))
    return () => {
      mounted = false
    }
  }, [context])

  const act = React.useCallback((body: Record<string, unknown>) => {
    if (inFlight.current) return
    inFlight.current = true
    setBusy(true)
    setError(null)
    void import('./api')
      .then(({sendAction, getState}) =>
        sendAction(body).then(value => {
          if (body.event === 'start_study_block') {
            window.location.href = '/memury'
            return value
          }
          return getState(context)
        }),
      )
      .then(value => setState(value))
      .catch(reason => setError(reason instanceof Error ? reason.message : String(reason)))
      .finally(() => {
        inFlight.current = false
        setBusy(false)
      })
  }, [context])

  if (error && !state)
    return (
      <div className="memury-context-shell memury-error">
        <Alert variant="error">{I18n.t('Memury 加载失败：%{error}', {error})}</Alert>
      </div>
    )
  if (!state)
    return (
      <div className="memury-context-shell memury-loading">
        <Spinner renderTitle={I18n.t('正在加载 Memury 上下文')} />
      </div>
    )

  return (
    <View
      as="section"
      id="memury-context-surface"
      className="memury-context-shell memury-context-surface"
      maxWidth="960px"
      padding="medium"
    >
      <div className="memury-context-toolbar">
        <div className="memury-context-toolbar__copy">
          <p className="memury-eyebrow">Memury / context-aware learning</p>
          <h1>{I18n.t('把当前 Canvas 页面接入学习计划')}</h1>
          <p className="memury-context-toolbar__summary">{I18n.t('在不打断当前任务的前提下，查看风险、证据与下一步行动。')}</p>
        </div>
      </div>
      <MemuryAssistant state={state} context={context} busy={busy} act={act} />
      {error && <Alert variant="error">{I18n.t('操作失败：%{error}', {error})}</Alert>}
      {context.type === 'course' && <CourseIntelligenceView state={state} busy={busy} act={act} courseId={context.course_id} />}
      {context.type === 'dashboard' && <MemuryToday state={state} busy={busy} act={act} showFullPlanLink={false} />}
      {context.type === 'assignment' && (
        <View as="section" margin="medium 0">
          <Heading level="h2">{I18n.t('当前作业在学习计划中的位置')}</Heading>
          <RiskQueue state={state} assignmentId={context.assignment_id} />
        </View>
      )}
    </View>
  )
}
