import React, {useEffect, useState} from 'react'
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
import {getState, sendAction, syncState} from './api'
import type {MemuryState, StudyBlock} from './types'

const I18n = createI18nScope('memury')

function Source({kind}: {kind: string}) {
  return <Badge count={kind === 'Official' ? I18n.t('正式') : kind === 'Inferred' ? I18n.t('推断') : I18n.t('用户调整')} standalone />
}

function Calendar({state, update}: {state: MemuryState; update: (value: MemuryState) => void}) {
  const act = async (event: string, block: StudyBlock) => update(await sendAction({event, block_id: block.id}))
  const reschedule = async (block: StudyBlock) => update(await sendAction({event: 'reschedule_block', block_id: block.id, starts_at: new Date(new Date(block.starts_at).getTime() + 86_400_000).toISOString(), duration_minutes: block.duration_minutes}))
  return <View as="section" margin="large 0"><Heading level="h2">{I18n.t('本周可执行学习日历')}</Heading>
    <Table caption={I18n.t('Memury 学习块')} margin="small 0">
      <Table.Head><Table.Row><Table.ColHeader id="time">{I18n.t('时间')}</Table.ColHeader><Table.ColHeader id="task">{I18n.t('学习块')}</Table.ColHeader><Table.ColHeader id="source">{I18n.t('来源')}</Table.ColHeader><Table.ColHeader id="action">{I18n.t('操作')}</Table.ColHeader></Table.Row></Table.Head>
      <Table.Body>{state.study_blocks.map(block => <Table.Row key={block.id}>
        <Table.Cell>{new Date(block.starts_at).toLocaleString()} · {block.duration_minutes} {I18n.t('分钟')}</Table.Cell>
        <Table.Cell><Text weight="bold">{block.title}</Text><br/><Text size="small">{block.course_name} · {block.status}</Text></Table.Cell>
        <Table.Cell><Source kind={block.official_or_inferred}/></Table.Cell>
        <Table.Cell><Button size="small" onClick={() => act('complete_block', block)}>{I18n.t('完成')}</Button>{' '}<Button size="small" onClick={() => act('skip_block', block)}>{I18n.t('跳过')}</Button>{' '}<Button size="small" onClick={() => reschedule(block)}>{I18n.t('顺延一天')}</Button></Table.Cell>
      </Table.Row>)}</Table.Body>
    </Table>
  </View>
}

function LearningLoop({state, update}: {state: MemuryState; update: (value: MemuryState) => void}) {
  if (state.phase === 'overview') return <Button color="primary" onClick={async () => update(await sendAction({event: 'answer_diagnostic'}))}>{I18n.t('开始诊断：选择“这两个力互相平衡”')}</Button>
  if (state.phase === 'verify') return <View as="section" padding="medium" background="secondary"><Heading level="h3">{I18n.t('候选错因（尚未定论）')}</Heading><Text>{state.hypotheses?.map(h => `${h.name} ${Math.round(h.confidence * 100)}%`).join('；')}</Text><Heading level="h4" margin="medium 0 small">{I18n.t('最小验证问题')}</Heading><Text>{I18n.t('桌上的书受到桌面的支持力；与这个支持力构成作用力—反作用力的是哪一个力？')}</Text><br/><Button color="primary" margin="small 0" onClick={async () => update(await sendAction({event: 'answer_verification'}))}>{I18n.t('选择：书对桌面的压力')}</Button></View>
  if (state.phase === 'intervention') return <View as="section" padding="medium" background="secondary"><Heading level="h3">{I18n.t('已验证错因')}</Heading><Text>{state.verified_hypothesis}</Text><Heading level="h4" margin="medium 0 small">{I18n.t('课程依据：第 2 章「受力分析」')}</Heading><Text>{I18n.t('先标出每个力作用在哪个物体上：平衡力作用于同一物体；作用力与反作用力作用于两个不同物体。')}</Text><br/><Button margin="small 0" onClick={async () => update(await sendAction({event: 'request_hint'}))}>{I18n.t('再给一级提示')} ({state.hint_level || 0}/4)</Button>{' '}<Button color="primary" onClick={async () => update(await sendAction({event: 'answer_transfer', correct: true}))}>{I18n.t('完成电梯情境迁移题')}</Button></View>
  return <Alert variant="success" margin="medium 0">{state.concept.reason}：{state.concept.previous_mastery} → {state.concept.mastery}。{I18n.t('剩余学习块已按新证据重排。')}</Alert>
}

function AcademicTimeline({state}: {state: MemuryState}) {
  return <View as="section" margin="large 0"><Heading level="h2">{I18n.t('学业时间线与任务风险')}</Heading>
    {state.assignments.map(item => <View as="div" key={item.id} padding="small 0" borderWidth="0 0 small 0"><Text weight="bold">{item.course_name} · {item.title}</Text><br/><Text size="small">DDL {new Date(item.due_at).toLocaleString()} · {I18n.t('风险')} {Math.round(item.risk * 100)}% · {item.source_platform}</Text> <Source kind={item.official_or_inferred}/></View>)}
    {state.sis_events?.map((event, index) => <View as="div" key={index} padding="small 0"><Text weight="bold">{String(event.title)}</Text><br/><Text size="small">{new Date(String(event.starts_at)).toLocaleString()} · {String(event.location)} · {String(event.source_platform)} · {I18n.t('只读')}</Text></View>)}
  </View>
}

function App() {
  const [state, setState] = useState<MemuryState | null>(null)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => { getState().then(setState).catch(reason => setError(String(reason))) }, [])
  if (error) return <Alert variant="error">{error}</Alert>
  if (!state) return <Spinner renderTitle={I18n.t('正在加载 Memury')}/>
  return <View as="main" maxWidth="1100px" margin="0 auto" padding="large">
    <Heading level="h1">{I18n.t('Memury 学脉')}</Heading><Text>{I18n.t('目标感知自适应学习 Agent · 非 Instructure 官方功能')}</Text>
    {state.demo_mode && <Alert variant="info" margin="medium 0">{I18n.t('当前为可靠 Demo 模式：模拟 SIS 与预置题目均有明确标注，不是在线模型生成。')}</Alert>}
    <View as="section" padding="medium" borderWidth="small" borderRadius="medium"><Heading level="h2">{I18n.t('下一最佳学习行动')}</Heading><Text size="large" weight="bold">{state.next_action.course} · {state.next_action.title}</Text><br/><Text>{state.next_action.why}</Text><br/><Button color="primary" margin="small 0" onClick={async () => setState(await syncState())}>{I18n.t('立即同步并重新规划')}</Button><Text size="small"> {I18n.t('上次同步：')} {new Date(state.last_synced_at).toLocaleString()}</Text></View>
    <View as="section" margin="large 0"><Heading level="h2">{I18n.t('概念掌握状态')}</Heading><Text>{state.concept.name} · {Math.round(state.concept.confidence * 100)}% {I18n.t('判断置信度')}</Text><ProgressBar screenReaderLabel={I18n.t('概念掌握度')} valueNow={state.concept.mastery * 100}/></View>
    <AcademicTimeline state={state}/><Calendar state={state} update={setState}/><View as="section" margin="large 0"><Heading level="h2">{I18n.t('主动诊断与迁移验证')}</Heading><LearningLoop state={state} update={setState}/></View>
    <View as="section" margin="large 0"><Heading level="h2">{I18n.t('证据与决策日志')}</Heading>{state.evidence.map((item, index) => <View as="div" key={index} padding="small 0"><Text weight="bold">{item.title}</Text><br/><Text size="small">{item.source} · {new Date(item.observed_at).toLocaleString()}</Text></View>)}{state.decision_logs.map((log, index) => <Alert key={index} variant="info" margin="small 0">{log.change}：{log.reason}</Alert>)}</View>
    <Alert variant="warning">{I18n.t('Memury 仅提供辅助学习建议，不修改 Canvas 正式成绩，也不替代教师或学校评价。')}</Alert>
  </View>
}

const root = document.getElementById('memury-root')
if (root) createRoot(root).render(<App />)
