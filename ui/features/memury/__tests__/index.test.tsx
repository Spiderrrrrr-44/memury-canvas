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

import React from 'react'
import {fireEvent, render, screen, waitFor} from '@testing-library/react'
import {vi} from 'vitest'
import {MemuryApp} from '../index'
import * as api from '../api'
import type {MemuryState} from '../types'

vi.mock('../api', () => ({
  getState: vi.fn(),
  resetState: vi.fn(),
  sendAction: vi.fn(),
  syncState: vi.fn(),
}))

const baseState: MemuryState = {
  demo_mode: true,
  phase: 'recall',
  last_synced_at: '2026-08-07T00:00:00Z',
  assignments: [],
  study_blocks: [],
  concept: {
    name: '平衡力与作用力—反作用力的区别',
    mastery: 0.42,
    confidence: 0.76,
    misconception: '把作用在不同物体上的作用力与反作用力当作平衡力',
  },
  evidence: [],
  decision_logs: [],
  learning_session: {
    recall_question: '一本书静止在桌面上。桌面对书的支持力与书对桌面的压力是一对平衡力吗？',
  },
  next_action: null,
}

const completeState: MemuryState = {
  ...baseState,
  phase: 'complete',
  assignments: [
    {
      id: 'mech-force',
      course_name: '工程力学基础',
      title: '受力分析作业 2',
      due_at: '2026-08-08T00:00:00Z',
      risk: 0.31,
      risk_reasons: ['已完成本轮补强，风险已显著下降'],
      source_platform: 'Canvas',
      source_object_id: 'canvas-101',
      last_synced_at: '2026-08-07T00:00:00Z',
      official_or_inferred: 'Official',
      confidence: 1,
      estimated_minutes: 25,
    },
    {
      id: 'mech-dynamics',
      course_name: '工程力学基础',
      title: '动力学补强',
      due_at: '2026-08-09T00:00:00Z',
      risk: 0.68,
      risk_reasons: ['下一风险点已上升为首要任务'],
      source_platform: 'Canvas',
      source_object_id: 'canvas-102',
      last_synced_at: '2026-08-07T00:00:00Z',
      official_or_inferred: 'Official',
      confidence: 1,
      estimated_minutes: 20,
    },
  ],
  study_blocks: [
    {
      id: 'transfer-block',
      stage: 'transfer',
      title: 'Transfer',
      starts_at: '2026-08-07T01:00:00Z',
      duration_minutes: 20,
      status: 'completed',
      course_name: '工程力学基础',
      concept: '平衡力与作用力—反作用力的区别',
      source_platform: 'Memury',
      source_object_id: 'transfer-block',
      last_synced_at: '2026-08-07T00:00:00Z',
      official_or_inferred: 'Simulated',
      confidence: 1,
    },
  ],
  concept: {
    ...baseState.concept,
    mastery: 0.53,
    previous_mastery: 0.42,
    reason: '完成验证题与迁移题后，概念掌握度提升',
  },
  evidence: [
    {
      title: 'Transfer 迁移题答对',
      source: 'Memury learning session',
      observed_at: '2026-08-07T00:05:00Z',
    },
  ],
  decision_logs: [
    {
      at: '2026-08-07T00:05:00Z',
      reason: 'Transfer 阶段验证通过',
      change: '已完成当前补强，准备重排计划',
    },
  ],
  learning_session: {
    ...baseState.learning_session,
    target_assignment_id: 'mech-force',
    recall_correct: false,
    hypothesis_verified: true,
    used_hint: true,
    hint_level: 2,
    transfer_correct: true,
    completed_at: '2026-08-07T00:05:00Z',
  },
  next_action: {
    assignment_id: 'mech-dynamics',
    title: '动力学补强',
    course: '工程力学基础',
    priority: 0.68,
    reasons: ['下一风险点已上升为首要任务'],
    why: '下一风险点已上升为首要任务',
    estimated_minutes: 20,
  },
}

const refreshedOverviewState: MemuryState = {
  ...completeState,
  phase: 'overview',
  assignments: [
    completeState.assignments[1],
    completeState.assignments[0],
  ],
  study_blocks: [
    completeState.study_blocks[0],
    {
      id: 'next-recall-block',
      stage: 'recall',
      title: 'Recall',
      starts_at: '2026-08-08T01:00:00Z',
      duration_minutes: 15,
      status: 'planned',
      course_name: '工程力学基础',
      concept: '动力学基础',
      source_platform: 'Memury',
      source_object_id: 'next-recall-block',
      last_synced_at: '2026-08-07T00:00:00Z',
      official_or_inferred: 'Simulated',
      confidence: 1,
    },
  ],
  next_action: {
    assignment_id: 'mech-dynamics',
    title: '动力学补强',
    course: '工程力学基础',
    priority: 0.68,
    reasons: ['迁移题完成后，系统已重排到新的首要风险任务'],
    why: '迁移题完成后，系统已重排到新的首要风险任务',
    estimated_minutes: 20,
  },
}

describe('MemuryApp', () => {
  beforeEach(() => {
    vi.mocked(api.getState).mockReset()
    vi.mocked(api.resetState).mockReset()
    vi.mocked(api.sendAction).mockReset()
    vi.mocked(api.syncState).mockReset()
  })

  it('submits a free-form answer and renders the AI diagnosis', async () => {
    vi.mocked(api.getState).mockResolvedValue(baseState)
    vi.mocked(api.sendAction).mockResolvedValue({
      ...baseState,
      phase: 'verify',
      diagnostic: {
        source: 'ai',
        diagnosis_summary: '学生把不同物体上的力误当作同一物体上的平衡力。',
        answer_judgment: 'incorrect',
        misconception_type: 'conceptual',
        evidence: ['把支持力和压力混为一谈'],
        confidence: 0.84,
        verification_question: '请说明为什么这两个力不能算作平衡力。',
        hint: '先分清作用对象，再判断是否在同一个物体上。',
        transfer_question: '如果换成电梯里的人与地面相互作用，这个判断会怎么变？',
        learner_state_suggestion: {
          skill: '平衡力与作用力—反作用力的区别',
          suggested_status: 'review_needed',
          reason: '概念证据不足，先做最小验证再迁移。',
        },
      },
      hypotheses: [
        {name: 'conceptual', confidence: 0.84},
        {name: '读题错误', confidence: 0.11},
        {name: '计算失误', confidence: 0.05},
      ],
    })

    render(<MemuryApp />)

    fireEvent.change(await screen.findByPlaceholderText('请输入你的判断和理由'), {
      target: {value: '我觉得它们是平衡力，因为方向相反。'},
    })
    fireEvent.click(screen.getByText('提交回答'))

    await waitFor(() => {
      expect(vi.mocked(api.sendAction)).toHaveBeenCalledWith(
        expect.objectContaining({
          event: 'answer_recall',
          student_answer: '我觉得它们是平衡力，因为方向相反。',
        }),
      )
    })

    expect(await screen.findByText('学生把不同物体上的力误当作同一物体上的平衡力。')).toBeVisible()
    expect(screen.getByText('智能诊断')).toBeVisible()
    expect(screen.getByText(/验证问题：/)).toBeVisible()
  })

  it('renders rule fallback diagnostics without exposing raw errors', async () => {
    vi.mocked(api.getState).mockResolvedValue({
      ...baseState,
      phase: 'verify',
      diagnostic: {
        source: 'rule_fallback',
        diagnosis_summary: '当前回答证据不足，暂时只能判断为 guessing。',
        answer_judgment: 'uncertain',
        misconception_type: 'guessing',
        evidence: ['回答过短，缺少可验证依据'],
        confidence: 0.31,
        verification_question: '请再补充一步判断理由。',
        hint: '先分清力的作用对象。',
        transfer_question: '换个场景再判断一次。',
        learner_state_suggestion: {
          skill: '平衡力与作用力—反作用力的区别',
          suggested_status: 'needs_evidence',
          reason: '先补充最小证据，再进入迁移。',
        },
      },
      diagnostic_meta: {
        fallback_reason: 'AI diagnosis disabled',
      },
    })

    render(<MemuryApp />)

    expect(await screen.findByText('规则回退')).toBeVisible()
    expect(screen.getByText('当前回答证据不足，暂时只能判断为 guessing。')).toBeVisible()
    expect(screen.getByText(/置信度/)).toBeVisible()
    expect(screen.getByText(/验证问题：/)).toBeVisible()
  })

  it('returns to the overview with freshly fetched state after completing a loop', async () => {
    vi.mocked(api.getState)
      .mockResolvedValueOnce(completeState)
      .mockResolvedValueOnce(refreshedOverviewState)
    vi.mocked(api.sendAction).mockResolvedValue(completeState)

    render(<MemuryApp />)

    expect(await screen.findByText('返回首页查看新计划')).toBeVisible()

    fireEvent.click(screen.getByText('返回首页查看新计划'))

    await waitFor(() => {
      expect(vi.mocked(api.sendAction)).toHaveBeenCalledWith({event: 'return_home'})
    })

    await waitFor(() => {
      expect(vi.mocked(api.getState)).toHaveBeenCalledTimes(2)
    })

    await screen.findByText('下一最佳学习行动')
    expect(screen.queryByText('返回首页查看新计划')).not.toBeInTheDocument()
    expect(screen.getAllByText(/工程力学基础\s*·\s*动力学补强/).length).toBeGreaterThan(0)
    expect(screen.getByText('迁移题完成后，系统已重排到新的首要风险任务')).toBeVisible()
    expect(screen.getByText('当前掌握度 53%')).toBeVisible()
    expect(vi.mocked(api.syncState)).not.toHaveBeenCalled()
    expect(vi.mocked(api.resetState)).not.toHaveBeenCalled()
  })

  it('prevents duplicate return-home submissions while a refresh is in flight', async () => {
    let resolveReturnHome: (value: MemuryState) => void = () => {}
    const returnHomeRequest = new Promise<MemuryState>(resolve => {
      resolveReturnHome = resolve
    })

    vi.mocked(api.getState)
      .mockResolvedValueOnce(completeState)
      .mockResolvedValueOnce(refreshedOverviewState)
    vi.mocked(api.sendAction).mockReturnValue(returnHomeRequest)

    render(<MemuryApp />)

    const button = await screen.findByText('返回首页查看新计划')
    fireEvent.click(button)
    fireEvent.click(button)

    expect(await screen.findByText('正在更新学习状态…')).toBeVisible()
    expect(vi.mocked(api.sendAction)).toHaveBeenCalledTimes(1)

    resolveReturnHome(completeState)

    await screen.findByText('下一最佳学习行动')
    expect(vi.mocked(api.getState)).toHaveBeenCalledTimes(2)
  })

  it('shows a recoverable error instead of faking success when the overview refresh fails', async () => {
    vi.mocked(api.getState)
      .mockResolvedValueOnce(completeState)
      .mockRejectedValueOnce(new Error('state refresh failed'))
    vi.mocked(api.sendAction).mockResolvedValue(completeState)

    render(<MemuryApp />)

    fireEvent.click(await screen.findByText('返回首页查看新计划'))

    expect(await screen.findByText('操作失败：state refresh failed')).toBeVisible()
    expect(screen.getByText('返回首页查看新计划')).toBeVisible()
    expect(screen.queryByText('下一最佳学习行动')).not.toBeInTheDocument()
    expect(vi.mocked(api.sendAction)).toHaveBeenCalledTimes(1)
    expect(vi.mocked(api.getState)).toHaveBeenCalledTimes(2)
  })
})
