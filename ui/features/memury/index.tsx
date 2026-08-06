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

import React, {useCallback, useEffect, useState} from 'react'
import {createRoot} from 'react-dom/client'
import {Alert} from '@instructure/ui-alerts'
import {Badge} from '@instructure/ui-badge'
import {Button} from '@instructure/ui-buttons'
import {Heading} from '@instructure/ui-heading'
import {ProgressBar} from '@instructure/ui-progress'
import {Spinner} from '@instructure/ui-spinner'
import {Table} from '@instructure/ui-table'
import {Text} from '@instructure/ui-text'
import {View} from '@instructure/ui-view'
import {useScope as createI18nScope} from '@canvas/i18n'
import {getState, resetState, sendAction, syncState} from './api'
import type {Assignment, MemuryState, StudyBlock} from './types'

const I18n = createI18nScope('memury')

function Source({kind}: {kind: string}) {
  const labels: Record<string, string> = {
    Official: I18n.t('正式'),
    Inferred: I18n.t('推断'),
    Simulated: I18n.t('模拟'),
    'User override': I18n.t('用户调整'),
  }
  return <Badge count={1} formatOutput={() => labels[kind] || kind} standalone />
}

function RiskLabel({assignment}: {assignment: Assignment}) {
  const level =
    assignment.risk >= 0.7
      ? I18n.t('高风险')
      : assignment.risk >= 0.45
        ? I18n.t('中风险')
        : I18n.t('低风险')
  return (
    <Text weight="bold">
      {level} · {Math.round(assignment.risk * 100)}
    </Text>
  )
}

function NextAction({
  state,
  busy,
  act,
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
}) {
  const action = state.next_action
  if (!action)
    return <Alert variant="info">{I18n.t('当前没有待安排的学习行动。同步 Canvas 后再试。')}</Alert>

  return (
    <View as="section" padding="medium" borderWidth="small" borderRadius="medium" margin="medium 0">
      <Text size="small">{I18n.t('唯一推荐')}</Text>
      <Heading level="h2">{I18n.t('下一最佳学习行动')}</Heading>
      <Text size="large" weight="bold">
        {action.course} · {action.title}
      </Text>
      <View as="ul" margin="small 0">
        {action.reasons.map(reason => (
          <li key={reason}>
            <Text>{reason}</Text>
          </li>
        ))}
      </View>
      <Text>
        {I18n.t('预计 %{minutes} 分钟完成 Recall → Repair → Transfer。', {
          minutes: action.estimated_minutes,
        })}
      </Text>
      <br />
      <Button
        color="primary"
        margin="small 0 0"
        disabled={busy}
        onClick={() => act({event: 'start_study_block', assignment_id: action.assignment_id})}
      >
        {I18n.t('开始三段式学习')}
      </Button>
    </View>
  )
}

function RiskList({assignments}: {assignments: Assignment[]}) {
  if (assignments.length === 0)
    return <Alert variant="info">{I18n.t('尚无任务。请先同步 Canvas。')}</Alert>

  return (
    <View as="section" margin="large 0">
      <Heading level="h2">{I18n.t('课程风险排序')}</Heading>
      <Table caption={I18n.t('按风险从高到低排列的课程任务')} margin="small 0">
        <Table.Head>
          <Table.Row>
            <Table.ColHeader id="risk">{I18n.t('风险')}</Table.ColHeader>
            <Table.ColHeader id="task">{I18n.t('任务')}</Table.ColHeader>
            <Table.ColHeader id="reason">{I18n.t('为什么')}</Table.ColHeader>
            <Table.ColHeader id="source">{I18n.t('来源')}</Table.ColHeader>
          </Table.Row>
        </Table.Head>
        <Table.Body>
          {assignments.map(item => (
            <Table.Row key={`${item.source_platform}-${item.id}`}>
              <Table.Cell>
                <RiskLabel assignment={item} />
              </Table.Cell>
              <Table.Cell>
                <Text weight="bold">
                  {item.course_name} · {item.title}
                </Text>
                <br />
                <Text size="small">DDL {new Date(item.due_at).toLocaleString()}</Text>
              </Table.Cell>
              <Table.Cell>
                <View as="ul" margin="0">
                  {item.risk_reasons.map(reason => (
                    <li key={reason}>
                      <Text size="small">{reason}</Text>
                    </li>
                  ))}
                </View>
              </Table.Cell>
              <Table.Cell>
                <Text size="small">{item.source_platform}</Text>
                <br />
                <Source kind={item.official_or_inferred} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table.Body>
      </Table>
    </View>
  )
}

function StudyCalendar({
  state,
  busy,
  act,
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
}) {
  const defer = (block: StudyBlock) =>
    act({
      event: 'reschedule_block',
      block_id: block.id,
      starts_at: new Date(new Date(block.starts_at).getTime() + 86_400_000).toISOString(),
      duration_minutes: block.duration_minutes,
    })

  return (
    <View as="section" margin="large 0">
      <Heading level="h2">{I18n.t('三段式 Study Block')}</Heading>
      <Table caption={I18n.t('Recall、Repair 和 Transfer 学习块')} margin="small 0">
        <Table.Head>
          <Table.Row>
            <Table.ColHeader id="stage">{I18n.t('阶段')}</Table.ColHeader>
            <Table.ColHeader id="time">{I18n.t('计划')}</Table.ColHeader>
            <Table.ColHeader id="status">{I18n.t('状态')}</Table.ColHeader>
            <Table.ColHeader id="action">{I18n.t('操作')}</Table.ColHeader>
          </Table.Row>
        </Table.Head>
        <Table.Body>
          {state.study_blocks.map(block => (
            <Table.Row key={block.id}>
              <Table.Cell>
                <Text weight="bold">{block.title}</Text>
              </Table.Cell>
              <Table.Cell>
                {new Date(block.starts_at).toLocaleString()} · {block.duration_minutes}{' '}
                {I18n.t('分钟')}
              </Table.Cell>
              <Table.Cell>
                {block.status} · <Source kind={block.official_or_inferred} />
              </Table.Cell>
              <Table.Cell>
                <Button
                  size="small"
                  disabled={busy || block.status === 'completed'}
                  onClick={() => defer(block)}
                >
                  {I18n.t('顺延一天')}
                </Button>
              </Table.Cell>
            </Table.Row>
          ))}
        </Table.Body>
      </Table>
    </View>
  )
}

function LearningFlow({
  state,
  busy,
  act,
}: {
  state: MemuryState
  busy: boolean
  act: (body: Record<string, unknown>) => void
}) {
  const session = state.learning_session || {}
  if (state.phase === 'recall')
    return (
      <View as="section" padding="medium" background="secondary" margin="large 0">
        <Heading level="h2">{I18n.t('1 · Recall：先回忆，不看答案')}</Heading>
        <Text>
          {I18n.t('一本书静止在桌面上。桌面对书的支持力与书对桌面的压力是一对平衡力吗？')}
        </Text>
        <br />
        <Button
          margin="small 0"
          disabled={busy}
          onClick={() => act({event: 'answer_recall', correct: false})}
        >
          {I18n.t('是，它们大小相等方向相反')}
        </Button>{' '}
        <Button
          color="primary"
          disabled={busy}
          onClick={() => act({event: 'answer_recall', correct: true})}
        >
          {I18n.t('不是，它们作用在不同物体上')}
        </Button>
      </View>
    )

  if (state.phase === 'verify')
    return (
      <View as="section" padding="medium" background="secondary" margin="large 0">
        <Heading level="h2">{I18n.t('2 · Repair：先验证错因')}</Heading>
        <Heading level="h3">{I18n.t('候选错因（尚未定论）')}</Heading>
        <View as="ul">
          {state.hypotheses?.map(item => (
            <li key={item.name}>
              {item.name} · {Math.round(item.confidence * 100)}%
            </li>
          ))}
        </View>
        <Text>{I18n.t('最小验证题：与桌面对书的支持力构成作用力—反作用力的是哪一个力？')}</Text>
        <br />
        <Button
          color="primary"
          margin="small 0"
          disabled={busy}
          onClick={() => act({event: 'answer_verification'})}
        >
          {I18n.t('书对桌面的压力')}
        </Button>
      </View>
    )

  if (state.phase === 'repair')
    return (
      <View as="section" padding="medium" background="secondary" margin="large 0">
        <Heading level="h2">{I18n.t('2 · Repair：针对已验证错因补强')}</Heading>
        <Text weight="bold">{state.verified_hypothesis}</Text>
        <br />
        <Text>{I18n.t('课程依据：第 2 章「受力分析」')}</Text>
        {session.active_hint && (
          <Alert variant="info" margin="small 0">
            {I18n.t('第 %{level} 级提示：%{hint}', {
              level: session.hint_level,
              hint: session.active_hint,
            })}
          </Alert>
        )}
        <Button
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
      <View as="section" padding="medium" background="secondary" margin="large 0">
        <Heading level="h2">{I18n.t('3 · Transfer：换一个情境验证迁移')}</Heading>
        <Text>
          {I18n.t('电梯加速上升时，人受到的支持力大于重力。支持力与重力是一对作用力—反作用力吗？')}
        </Text>
        <br />
        <Button
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
      <View as="section" margin="large 0">
        <Alert variant="success">
          {state.concept.reason}：{state.concept.previous_mastery} → {state.concept.mastery}。
          {I18n.t('目标风险已下降，计划已重排。')}
        </Alert>
        <Button
          color="primary"
          margin="small 0"
          disabled={busy}
          onClick={() => act({event: 'return_home'})}
        >
          {I18n.t('返回首页查看新计划')}
        </Button>
      </View>
    )

  return null
}

function SisTimeline({events}: {events: Array<Record<string, unknown>>}) {
  return (
    <View as="section" margin="large 0">
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

function App() {
  const [state, setState] = useState<MemuryState | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    getState()
      .then(value => active && setState(value))
      .catch(reason => active && setError(String(reason)))
    return () => {
      active = false
    }
  }, [])

  const perform = useCallback(async (request: () => Promise<MemuryState>) => {
    setBusy(true)
    setError(null)
    try {
      setState(await request())
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setBusy(false)
    }
  }, [])

  const act = useCallback(
    (body: Record<string, unknown>) => {
      void perform(() => sendAction(body))
    },
    [perform],
  )
  if (error && !state)
    return <Alert variant="error">{I18n.t('Memury 加载失败：%{error}', {error})}</Alert>
  if (!state) return <Spinner renderTitle={I18n.t('正在加载 Memury')} />

  return (
    <View as="main" maxWidth="1100px" margin="0 auto" padding="large">
      <Heading level="h1">{I18n.t('Memury')}</Heading>
      <Text>{I18n.t('理解全局 → 选择行动 → 诊断学习 → 更新计划')}</Text>
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
      <Button color="primary" disabled={busy} onClick={() => void perform(syncState)}>
        {I18n.t('同步 Canvas 并重新规划')}
      </Button>{' '}
      <Button disabled={busy} onClick={() => void perform(resetState)}>
        {I18n.t('重置 Demo')}
      </Button>
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
          <NextAction state={state} busy={busy} act={act} />
          <View as="section" margin="large 0">
            <Heading level="h2">{I18n.t('概念掌握状态')}</Heading>
            <Text>
              {state.concept.name} · {Math.round(state.concept.confidence * 100)}%{' '}
              {I18n.t('判断置信度')}
            </Text>
            <ProgressBar
              screenReaderLabel={I18n.t('概念掌握度')}
              valueNow={state.concept.mastery * 100}
            />
          </View>
          <RiskList assignments={state.assignments} />
          <SisTimeline events={state.sis_events || []} />
          <StudyCalendar state={state} busy={busy} act={act} />
        </>
      )}
      <LearningFlow state={state} busy={busy} act={act} />
      <View as="section" margin="large 0">
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

const root = document.getElementById('memury-root')
if (root) createRoot(root).render(<App />)
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
