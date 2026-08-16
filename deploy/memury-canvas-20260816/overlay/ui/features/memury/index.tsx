/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import React, {useCallback, useEffect, useRef, useState} from 'react'
import {createRoot} from 'react-dom/client'
import {ScreenReaderContent} from '@instructure/ui-a11y-content'
import {Alert} from '@instructure/ui-alerts'
import {Badge} from '@instructure/ui-badge'
import {Button} from '@instructure/ui-buttons'
import {Heading} from '@instructure/ui-heading'
import {ProgressBar} from '@instructure/ui-progress'
import {Spinner} from '@instructure/ui-spinner'
import {TextArea} from '@instructure/ui-text-area'
import {Text} from '@instructure/ui-text'
import {View} from '@instructure/ui-view'
import {useScope as createI18nScope} from '@canvas/i18n'
import {getState, resetState, sendAction, syncState} from './api'
import {
  CourseDirectory,
  MemuryContextSurface,
  MemuryToday,
} from './surfaces'
import type {MemuryContext, MemuryState} from './types'
import {ProductApp} from './product_app'
import './theme'
import './memury.css'

const I18n = createI18nScope('memury')

function Source({kind}: {kind: string}) {
  const labels: Record<string, string> = {
    ai: I18n.t('智能诊断'),
    rule_fallback: I18n.t('规则回退'),
    Official: I18n.t('正式'),
    Inferred: I18n.t('推断'),
    Simulated: I18n.t('模拟'),
    'User override': I18n.t('用户调整'),
  }
  return <Badge count={1} formatOutput={() => labels[kind] || kind} standalone />
}

function DiagnosisPanel({
  diagnostic,
}: {
  diagnostic: NonNullable<MemuryState['diagnostic']>
}) {
  const answerJudgmentLabels: Record<string, string> = {
    correct: I18n.t('正确'),
    incorrect: I18n.t('需补强'),
    uncertain: I18n.t('证据不足'),
  }
  return (
    <View
      as="section"
      className="memury-card memury-diagnosis"
      padding="small"
      borderWidth="small"
      borderRadius="small"
      margin="small 0"
    >
      <Text size="small">
        {I18n.t('诊断来源')}{' '}
        <Source kind={diagnostic.source === 'ai' ? 'ai' : 'rule_fallback'} />
      </Text>
      <Heading level="h3">{I18n.t('错因诊断')}</Heading>
      <Text weight="bold">{diagnostic.diagnosis_summary}</Text>
      <br />
      <Text size="small">
        {I18n.t('置信度')} {Math.round(diagnostic.confidence * 100)}% ·{' '}
        {answerJudgmentLabels[diagnostic.answer_judgment] || diagnostic.answer_judgment}
      </Text>
      <View as="ul" margin="small 0 0">
        {diagnostic.evidence.map(item => (
          <li key={item}>
            <Text size="small">{item}</Text>
          </li>
        ))}
      </View>
    </View>
  )
}

function LearningFlow({
  state,
  busy,
  act,
  returnHome,
  draftAnswer,
  setDraftAnswer,
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
  returnHome: () => void
  draftAnswer: string
  setDraftAnswer: (value: string) => void
}) {
  const session = state.learning_session || {}

  if (state.phase === 'recall')
    return (
      <View
        as="section"
        className="memury-surface memury-learning-stage memury-learning-stage--recall"
        padding="medium"
        margin="large 0"
      >
        <Heading level="h2">{I18n.t('1 · Recall：先用自己的话回答')}</Heading>
        <Text>{session.recall_question || I18n.t('一本书静止在桌面上。')}</Text>
        <TextArea
          label={<ScreenReaderContent>{I18n.t('学生回答')}</ScreenReaderContent>}
          placeholder={I18n.t('请输入你的判断和理由')}
          autoGrow={false}
          resize="vertical"
          inline={false}
          value={draftAnswer}
          onChange={event => setDraftAnswer(event.target.value)}
          disabled={busy}
          height="120px"
          margin="small 0"
        />
        <Button
          color="primary"
          disabled={busy || draftAnswer.trim().length === 0}
          onClick={() => act({event: 'answer_recall', student_answer: draftAnswer})}
        >
          {I18n.t('提交回答')}
        </Button>
      </View>
    )

  if (state.phase === 'verify')
    return (
      <View
        as="section"
        className="memury-surface memury-learning-stage memury-learning-stage--diagnose"
        padding="medium"
        margin="large 0"
      >
        <Heading level="h2">{I18n.t('2 · Diagnose：先确认错因')}</Heading>
        {state.diagnostic ? (
          <DiagnosisPanel diagnostic={state.diagnostic} />
        ) : (
          <Alert variant="info">{I18n.t('当前没有可展示的智能诊断。')}</Alert>
        )}
        <Text weight="bold">
          {I18n.t('验证问题：%{question}', {
            question: state.diagnostic?.verification_question || I18n.t('请解释你的判断理由。'),
          })}
        </Text>
        {state.hypotheses?.length ? (
          <>
            <Heading level="h3">{I18n.t('候选错因')}</Heading>
            <View as="ul">
              {state.hypotheses.map(item => (
                <li key={item.name}>
                  <Text size="small">
                    {item.name} · {Math.round(item.confidence * 100)}%
                  </Text>
                </li>
              ))}
            </View>
          </>
        ) : null}
        <Button color="primary" margin="small 0" disabled={busy} onClick={() => act({event: 'answer_verification'})}>
          {I18n.t('已完成验证')}
        </Button>
      </View>
    )

  if (state.phase === 'repair')
    return (
      <View
        as="section"
        className="memury-surface memury-learning-stage memury-learning-stage--repair"
        padding="medium"
        margin="large 0"
      >
        <Heading level="h2">{I18n.t('3 · Repair：针对已验证错因补强')}</Heading>
        {state.diagnostic ? <DiagnosisPanel diagnostic={state.diagnostic} /> : null}
        <Text weight="bold">{state.verified_hypothesis}</Text>
        <br />
        <Text>{I18n.t('课程依据：第 2 章「受力分析」')}</Text>
        {state.diagnostic?.hint && (
          <Alert variant="info" margin="small 0">
            {state.diagnostic.hint}
          </Alert>
        )}
        {session.active_hint && (
          <Alert variant="info" margin="small 0">
            {I18n.t('第 %{level} 级提示：%{hint}', {
              level: session.hint_level,
              hint: session.active_hint,
            })}
          </Alert>
        )}
        <Text weight="bold">
          {I18n.t('迁移题：%{question}', {
            question:
              state.diagnostic?.transfer_question ||
              I18n.t('换一个情境，说明支持力和重力是不是一对平衡力。'),
          })}
        </Text>
        <Button
          className="memury-secondary-action"
          margin="small 0"
          disabled={busy || session.hint_level === 4}
          onClick={() => act({event: 'request_hint'})}
        >
          {I18n.t('获取下一条渐进提示')} ({session.hint_level || 0}/4)
        </Button>{' '}
        <Button color="primary" disabled={busy} onClick={() => act({event: 'start_transfer'})}>
          {I18n.t('进入 Transfer')}
        </Button>
      </View>
    )

  if (state.phase === 'transfer')
    return (
      <View
        as="section"
        className="memury-surface memury-learning-stage memury-learning-stage--transfer"
        padding="medium"
        margin="large 0"
      >
        <Heading level="h2">{I18n.t('4 · Transfer：换一个情境验证迁移')}</Heading>
        <Text>
          {state.diagnostic?.transfer_question ||
            I18n.t('电梯加速上升时，人受到的支持力大于重力。支持力与重力是一对作用力—反作用力吗？')}
        </Text>
        <br />
        <Button
          className="memury-secondary-action"
          margin="small 0"
          disabled={busy}
          onClick={() => act({event: 'answer_transfer', correct: false})}
        >
          {I18n.t('是，因为方向相反')}
        </Button>{' '}
        <Button
          color="primary"
          disabled={busy}
          onClick={() => act({event: 'answer_transfer', correct: true})}
        >
          {I18n.t('不是，它们都作用在人身上')}
        </Button>
      </View>
    )

  if (state.phase === 'complete')
    return (
      <View
        as="section"
        className="memury-surface memury-learning-stage memury-learning-stage--complete"
        margin="large 0"
      >
        <Alert variant="success">
          {state.concept.reason}：{state.concept.previous_mastery} → {state.concept.mastery}。
          {I18n.t('目标风险已下降，计划已重排。')}
        </Alert>
        <Button color="primary" margin="small 0" disabled={busy} onClick={returnHome}>
          {I18n.t('返回首页查看新计划')}
        </Button>
      </View>
    )

  return null
}

function SisTimeline({events}: {events: Array<Record<string, unknown>>}) {
  return (
    <View as="section" className="memury-section memury-timeline" margin="large 0">
      <Heading level="h2">{I18n.t('Demo SIS 课表与考试')}</Heading>
      {events.length === 0 ? (
        <Alert variant="info">{I18n.t('同步后显示模拟 SIS 事件。')}</Alert>
      ) : (
        events.map((event, index) => (
          <View as="div" key={index} padding="small 0">
            <Text weight="bold">{String(event.title)}</Text>
            <br />
            <Text size="small">
              {new Date(String(event.starts_at)).toLocaleString()} · {String(event.location)} ·{' '}
              {String(event.source_platform)} · {I18n.t('只读')}
            </Text>
          </View>
        ))
      )}
    </View>
  )
}

export function MemuryApp() {
  const [state, setState] = useState<MemuryState | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [draftAnswer, setDraftAnswer] = useState('')
  const requestInFlightRef = useRef(false)

  useEffect(() => {
    let active = true
    getState()
      .then(value => active && setState(value))
      .catch(reason => active && setError(String(reason)))
    return () => {
      active = false
    }
  }, [])

  useEffect(() => {
    if (state?.phase === 'recall') setDraftAnswer('')
  }, [state?.phase])

  const perform = useCallback(async (request: () => Promise<MemuryState>) => {
    if (requestInFlightRef.current) return

    requestInFlightRef.current = true
    setBusy(true)
    setError(null)
    try {
      setState(await request())
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      requestInFlightRef.current = false
      setBusy(false)
    }
  }, [])

  const act = useCallback(
    (body: Record<string, unknown>) => {
      void perform(() => sendAction(body))
    },
    [perform],
  )
  const returnHome = useCallback(() => {
    void perform(async () => {
      await sendAction({event: 'return_home'})
      return getState()
    })
  }, [perform])

  if (error && !state)
    return <div className="memury-shell memury-error"><Alert variant="error">{I18n.t('Memury 加载失败：%{error}', {error})}</Alert></div>
  if (!state) return <div className="memury-shell memury-loading"><Spinner renderTitle={I18n.t('正在加载 Memury')} /></div>

  return (
    <View as="main" className="memury-shell" maxWidth="1100px" margin="0 auto" padding="large">
      <header className="memury-page-header">
        <div className="memury-page-header__copy">
          <p className="memury-eyebrow">Memury / adaptive learning copilot</p>
          <h1>{I18n.t('Memury')}</h1>
          <p className="memury-page-header__summary">{I18n.t('理解全局 → 选择行动 → 诊断学习 → 更新计划')}</p>
        </div>
        <div className="memury-toolbar" aria-label={I18n.t('Memury 工具栏')}>
          <Button
            className="memury-primary-action"
            color="primary"
            disabled={busy}
            onClick={() => void perform(syncState)}
          >
            {I18n.t('同步 Canvas 并重新规划')}
          </Button>
          <Button className="memury-secondary-action" disabled={busy} onClick={() => void perform(resetState)}>
            {I18n.t('重置 Demo')}
          </Button>
        </div>
      </header>
      {state.demo_mode && (
        <Alert variant="info" margin="medium 0">
          {I18n.t('可靠 Demo 模式：模拟 SIS 和预置题目均明确标注，不依赖外部 API Key。')}
        </Alert>
      )}
      {error && (
        <Alert variant="error" margin="medium 0">
          {I18n.t('操作失败：%{error}', {error})}
        </Alert>
      )}
      {busy && (
        <Alert variant="info" margin="small 0">
          {I18n.t('正在更新学习状态…')}
        </Alert>
      )}
      <Text size="small">
        {' '}
        {I18n.t('上次同步：')} {new Date(state.last_synced_at).toLocaleString()}
      </Text>
      {state.sync_summary && (
        <Text as="p" size="small">
          {I18n.t(
            '本次读取 Canvas：%{courses} 门课程，%{assignments} 项作业。',
            state.sync_summary,
          )}
        </Text>
      )}
      {state.phase === 'overview' && (
        <>
          <MemuryToday state={state} busy={busy} act={act} showFullPlanLink={false} />
          <View as="section" className="memury-surface memury-section" margin="large 0">
            <Heading level="h2">{I18n.t('概念掌握状态')}</Heading>
            <Text>
              {state.concept.name} · {Math.round(state.concept.confidence * 100)}%{' '}
              {I18n.t('判断置信度')}
            </Text>
            <br />
            <Text>{I18n.t('当前掌握度 %{mastery}%', {mastery: Math.round(state.concept.mastery * 100)})}</Text>
            <ProgressBar
              screenReaderLabel={I18n.t('概念掌握度')}
              valueNow={state.concept.mastery * 100}
            />
          </View>
          <SisTimeline events={state.sis_events || []} />
          <CourseDirectory state={state} busy={busy} act={act} />
        </>
      )}
      <LearningFlow
        state={state}
        busy={busy}
        act={act}
        returnHome={returnHome}
        draftAnswer={draftAnswer}
        setDraftAnswer={setDraftAnswer}
      />
      <View as="section" className="memury-section memury-evidence" margin="large 0">
        <Heading level="h2">{I18n.t('最近证据与决策')}</Heading>
        {state.evidence
          .slice(-4)
          .reverse()
          .map((item, index) => (
            <View as="div" key={`${item.observed_at}-${index}`} padding="small 0">
              <Text weight="bold">{item.title}</Text>
              <br />
              <Text size="small">
                {item.source} · {new Date(item.observed_at).toLocaleString()}
              </Text>
            </View>
          ))}
        {state.decision_logs.slice(-2).map((log, index) => (
          <Alert key={`${log.at}-${index}`} variant="info" margin="small 0">
            {log.change}：{log.reason}
          </Alert>
        ))}
      </View>
      <Alert variant="warning">
        {I18n.t('Memury 仅提供辅助学习建议，不修改 Canvas 正式成绩，也不替代教师或学校评价。')}
      </Alert>
    </View>
  )
}

function contextFromRoot(root: HTMLElement): MemuryContext {
  const type = root.dataset.contextType
  const supportedTypes: MemuryContext['type'][] = ['dashboard', 'course', 'assignment', 'page', 'module', 'session']
  return {
    type: supportedTypes.includes(type as MemuryContext['type']) ? (type as MemuryContext['type']) : 'dashboard',
    course_id: root.dataset.courseId,
    assignment_id: root.dataset.assignmentId,
    page_id: root.dataset.pageId,
    module_id: root.dataset.moduleId,
  }
}

const root = document.getElementById('memury-root')
const dashboardRoot = document.getElementById('memury-dashboard-root')
const contextRoot = document.getElementById('memury-context-root')
if (root) createRoot(root).render(<ProductApp />)
else if (dashboardRoot) createRoot(dashboardRoot).render(<MemuryContextSurface context={contextFromRoot(dashboardRoot)} />)
else if (contextRoot) createRoot(contextRoot).render(<MemuryContextSurface context={contextFromRoot(contextRoot)} />)
/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */
