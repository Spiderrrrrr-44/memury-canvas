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

export interface Provenance {
  source_platform: string
  source_object_id: string
  source_url?: string | null
  last_synced_at: string
  official_or_inferred: 'Official' | 'Inferred' | 'User override' | 'Simulated'
  confidence: number
}

export interface Assignment extends Provenance {
  id: string | number
  course_id?: string | number
  course_name: string
  title: string
  due_at: string
  submitted?: boolean
  risk: number
  risk_reasons: string[]
  estimated_minutes?: number
}

export interface StudyBlock extends Provenance {
  id: string
  stage: 'recall' | 'repair' | 'transfer'
  title: string
  starts_at: string
  duration_minutes: number
  status: 'planned' | 'active' | 'completed' | 'skipped'
  course_name: string
  concept: string
  course_id?: string | number
  today_status?: 'completed' | 'current' | 'upcoming'
  source_type?: string
  source_id?: string
  trigger_reason?: string
}

export interface LearningSession {
  target_assignment_id?: string
  recall_question?: string
  recall_correct?: boolean
  hypothesis_verified?: boolean
  used_hint?: boolean
  hint_level?: number
  active_hint?: string
  transfer_correct?: boolean
  completed_at?: string
  source_type?: string
  source_id?: string
  course_id?: string | number
  concept_id?: string
  trigger_reason?: string
  originating_study_block?: string
}

export interface MemuryContext {
  type: 'dashboard' | 'course' | 'assignment' | 'page' | 'module' | 'session'
  course_id?: string
  assignment_id?: string
  page_id?: string
  module_id?: string
}

export interface RecommendationEvidence {
  type: string
  id: string
  label: string
  source: string
  official_or_inferred: string
}

export interface RecommendationSource {
  type: string
  id: string
  platform: string
  official_or_inferred: string
}

export interface CourseIntelligence {
  id: string
  name: string
  source: Record<string, unknown>
  official_or_inferred: string
  risk: number
  risk_reasons: string[]
  assignment_count: number
  incomplete_count: number
  estimated_minutes: number
  upcoming_exam?: Record<string, unknown> | null
  weak_concepts: Array<Record<string, unknown>>
  recent_evidence: Array<Record<string, unknown>>
  next_action?: MemuryState['next_action'] | null
  study_blocks: StudyBlock[]
}

export interface MemuryState {
  demo_mode: boolean
  phase: 'overview' | 'recall' | 'verify' | 'repair' | 'transfer' | 'complete'
  last_synced_at: string
  assignments: Assignment[]
  study_blocks: StudyBlock[]
  sis_events?: Array<Record<string, unknown>>
  sync_summary?: {courses: number; assignments: number}
  concept: {
    name: string
    mastery: number
    previous_mastery?: number
    reason?: string
    confidence: number
    misconception: string
  }
  diagnostic?: {
    source: 'ai' | 'rule_fallback'
    diagnosis_summary: string
    answer_judgment: 'correct' | 'incorrect' | 'uncertain'
    misconception_type:
      | 'conceptual'
      | 'procedural'
      | 'calculation'
      | 'incomplete'
      | 'guessing'
      | 'insufficient_evidence'
    evidence: string[]
    confidence: number
    verification_question: string
    hint: string
    transfer_question: string
    learner_state_suggestion: {
      skill: string
      suggested_status: string
      reason: string
    }
  }
  diagnostic_meta?: {
    fallback_reason?: string
    compatibility_note?: string
    latency_ms?: number
  }
  evidence: Array<{title: string; source: string; observed_at: string}>
  decision_logs: Array<{at: string; reason: string; change: string}>
  hypotheses?: Array<{name: string; confidence: number}>
  verified_hypothesis?: string
  learning_session: LearningSession
  next_action: null | {
    assignment_id: string
    title: string
    course: string
    priority: number
    reasons: string[]
    why: string
    estimated_minutes: number
    course_id?: string
    reason?: string
    confidence?: number
    source?: RecommendationSource
    evidence?: RecommendationEvidence[]
    generated_at?: string
  }
  today?: {
    date: string
    study_blocks: StudyBlock[]
    total_minutes: number
    completed_minutes: number
    has_overdue: boolean
    has_due_soon: boolean
    has_schedule_conflict: boolean
  }
  academic_snapshot?: {
    course_count: number
    incomplete_assignment_count: number
    due_soon_count: number
    overdue_count: number
    upcoming_exam_count: number
    overall_risk: number
    weekly_estimated_minutes: number
  }
  risks?: Array<{
    type: string
    id: string
    course_id?: string
    course: string
    title: string
    due_at?: string
    starts_at?: string
    status: string
    risk: number
    reasons: string[]
    estimated_minutes: number
    source: Record<string, unknown>
  }>
  courses?: CourseIntelligence[]
  learner_state?: {
    weak_concepts: Array<Record<string, unknown>>
    mastery_change: Record<string, unknown>
    recent_activity_at?: string
    completed_sessions: number
    recent_evidence: Array<Record<string, unknown>>
  }
  recent_evidence?: Array<Record<string, unknown>>
  agent_activity?: Array<Record<string, unknown>>
  current_context?: {
    type: string
    course_id?: string
    course_name?: string
    assignment_id?: string
    assignment_title?: string
    relationship_to_plan?: string
  }
  provenance?: {
    generated_at: string
    state_source: string
    official_or_inferred: string
  }
}
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
