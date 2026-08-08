/*
 * Copyright (C) 2026 - present Instructure, Inc.
 */

import React from 'react'
import {fireEvent, render, screen, within} from '@testing-library/react'
import {vi} from 'vitest'
import {CourseIntelligenceView, MemuryAssistant, MemuryToday} from '../surfaces'
import type {MemuryState} from '../types'

const state: MemuryState = {
  demo_mode: true,
  phase: 'overview',
  last_synced_at: '2026-08-08T09:00:00Z',
  assignments: [
    {
      id: 'mech-force',
      course_id: 'demo-course-mechanics',
      course_name: '工程力学基础',
      title: '受力分析作业 2',
      due_at: '2026-08-09T09:00:00Z',
      submitted: false,
      risk: 0.82,
      risk_reasons: ['作业将在 24 小时内截止', '对应知识点掌握度偏低'],
      estimated_minutes: 25,
      source_platform: 'Demo Canvas data',
      source_object_id: 'mech-force',
      last_synced_at: '2026-08-08T09:00:00Z',
      official_or_inferred: 'Simulated',
      confidence: 1,
    },
  ],
  study_blocks: [
    {
      id: 'block-recall',
      stage: 'recall',
      title: 'Recall：回忆关键区别',
      starts_at: '2026-08-08T10:00:00Z',
      duration_minutes: 10,
      status: 'planned',
      today_status: 'current',
      course_name: '工程力学基础',
      concept: '平衡力与作用力—反作用力的区别',
      source_platform: 'Memury',
      source_object_id: 'block-recall',
      last_synced_at: '2026-08-08T09:00:00Z',
      official_or_inferred: 'Inferred',
      confidence: 0.86,
    },
  ],
  concept: {
    name: '平衡力与作用力—反作用力的区别',
    mastery: 0.42,
    confidence: 0.76,
    misconception: '把不同物体上的力当作同一物体上的平衡力',
  },
  evidence: [],
  decision_logs: [],
  learning_session: {},
  next_action: {
    assignment_id: 'mech-force',
    title: '受力分析作业 2',
    course: '工程力学基础',
    course_id: 'demo-course-mechanics',
    priority: 0.82,
    reasons: ['作业将在 24 小时内截止', '对应知识点掌握度偏低'],
    why: '作业将在 24 小时内截止；对应知识点掌握度偏低',
    reason: '作业将在 24 小时内截止；对应知识点掌握度偏低',
    estimated_minutes: 25,
    confidence: 0.91,
    source: {
      type: 'risk_engine',
      id: 'mech-force',
      platform: 'Demo Canvas data',
      official_or_inferred: 'Simulated',
    },
    evidence: [
      {
        type: 'assignment',
        id: 'mech-force',
        label: '受力分析作业 2',
        source: 'Demo Canvas data',
        official_or_inferred: 'Simulated',
      },
    ],
    generated_at: '2026-08-08T09:00:00Z',
  },
  academic_snapshot: {
    course_count: 1,
    incomplete_assignment_count: 1,
    due_soon_count: 1,
    overdue_count: 0,
    upcoming_exam_count: 1,
    overall_risk: 0.82,
    weekly_estimated_minutes: 25,
  },
  today: {
    date: '2026-08-08',
    study_blocks: [],
    total_minutes: 10,
    completed_minutes: 0,
    has_overdue: false,
    has_due_soon: true,
    has_schedule_conflict: false,
  },
  courses: [
    {
      id: 'demo-course-mechanics',
      name: '工程力学基础',
      source: {source_platform: 'Demo Canvas data'},
      official_or_inferred: 'Simulated',
      risk: 0.82,
      risk_reasons: ['对应知识点掌握度偏低'],
      assignment_count: 1,
      incomplete_count: 1,
      estimated_minutes: 25,
      upcoming_exam: {title: '工程力学基础模拟考试', starts_at: '2026-08-11T09:00:00Z'},
      weak_concepts: [
        {
          id: 'force-concept',
          name: '平衡力与作用力—反作用力的区别',
          mastery: 0.42,
          misconception: '需要区分受力物体',
        },
      ],
      recent_evidence: [],
      next_action: {
        assignment_id: 'mech-force',
        title: '受力分析作业 2',
        course: '工程力学基础',
        course_id: 'demo-course-mechanics',
        priority: 0.82,
        reasons: ['对应知识点掌握度偏低'],
        why: '对应知识点掌握度偏低',
        estimated_minutes: 25,
      },
      study_blocks: [],
    },
  ],
  learner_state: {
    weak_concepts: [
      {id: 'force-concept', name: '平衡力与作用力—反作用力的区别', mastery: 0.42},
    ],
    mastery_change: {},
    completed_sessions: 1,
    recent_evidence: [],
  },
  current_context: {
    type: 'course',
    course_id: 'demo-course-mechanics',
    course_name: '工程力学基础',
    relationship_to_plan: '当前推荐行动',
  },
}

describe('Memury integrated surfaces', () => {
  it('renders Memury Today from the public state and starts the recommended block with provenance', () => {
    const act = vi.fn()
    render(<MemuryToday state={state} busy={false} act={act} />)

    expect(screen.getByText('Memury Today')).toBeVisible()
    expect(screen.getByText('Academic Snapshot')).toBeVisible()
    expect(screen.getByText('下一最佳学习行动')).toBeVisible()
    expect(screen.getByText('为什么推荐？查看依据')).toBeVisible()
    const snapshot = screen.getByText('Academic Snapshot').closest('section')
    expect(snapshot).not.toBeNull()
    expect(within(snapshot as HTMLElement).getByText('课程')).toBeVisible()
    expect(within(snapshot as HTMLElement).getAllByText('1').length).toBeGreaterThan(0)
    expect(screen.getByText(/当前薄弱概念：平衡力与作用力/)).toBeVisible()

    fireEvent.click(screen.getByRole('button', {name: '开始学习'}))
    expect(act).toHaveBeenCalledWith(
      expect.objectContaining({
        event: 'start_study_block',
        assignment_id: 'mech-force',
        source_type: 'dashboard',
        course_id: 'demo-course-mechanics',
      }),
    )
  })

  it('renders Course Intelligence and starts a weak-concept block through the existing action API', () => {
    const act = vi.fn()
    render(<CourseIntelligenceView state={state} busy={false} act={act} courseId="demo-course-mechanics" />)

    expect(screen.getByText(/Course Intelligence：工程力学基础/)).toBeVisible()
    expect(screen.getByText('模拟数据')).toBeVisible()
    expect(screen.getByText('开始针对该概念学习')).toBeVisible()
    fireEvent.click(screen.getByText('开始针对该概念学习'))

    expect(act).toHaveBeenCalledWith(
      expect.objectContaining({
        event: 'start_study_block',
        source_type: 'course_weak_concept',
        source_id: 'force-concept',
        concept_id: 'force-concept',
      }),
    )
  })

  it('uses the public Today Plan to submit complete and reschedule operations', () => {
    const act = vi.fn()
    render(<MemuryToday state={state} busy={false} act={act} />)

    fireEvent.click(screen.getByRole('button', {name: '完成'}))
    expect(act).toHaveBeenCalledWith({event: 'complete_block', block_id: 'block-recall'})

    fireEvent.click(screen.getByRole('button', {name: '暂缓一天'}))
    expect(act).toHaveBeenCalledWith(
      expect.objectContaining({event: 'reschedule_block', block_id: 'block-recall', duration_minutes: 10}),
    )
  })

  it('offers a real course next-step action when a course has no weak-concept card', () => {
    const act = vi.fn()
    const programming = {
      ...state.courses![0],
      id: 'demo-course-programming',
      name: '程序设计实践',
      weak_concepts: [],
      next_action: {...state.next_action!, course: '程序设计实践', course_id: 'demo-course-programming'},
    }
    render(<CourseIntelligenceView state={{...state, courses: [programming]}} busy={false} act={act} courseId="demo-course-programming" />)

    fireEvent.click(screen.getByRole('button', {name: '开始课程下一步'}))
    expect(act).toHaveBeenCalledWith(
      expect.objectContaining({
        event: 'start_study_block',
        source_type: 'course',
        course_id: 'demo-course-programming',
      }),
    )
  })

  it('identifies an assignment context and offers only executable actions', () => {
    const act = vi.fn()
    render(
      <MemuryAssistant
        state={state}
        context={{type: 'assignment', course_id: 'demo-course-mechanics', assignment_id: 'mech-force'}}
        busy={false}
        act={act}
      />,
    )

    expect(screen.getByText('Memury 当前知道你在哪里：工程力学基础')).toBeVisible()
    expect(screen.getByRole('button', {name: '开始相关学习'})).toBeEnabled()
    expect(screen.getByText('打开完整 Memury 计划')).toHaveAttribute('href', '/memury')
    expect(act).not.toHaveBeenCalled()
  })
})
