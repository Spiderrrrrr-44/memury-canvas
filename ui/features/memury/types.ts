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
}

export interface LearningSession {
  target_assignment_id?: string
  recall_correct?: boolean
  hypothesis_verified?: boolean
  used_hint?: boolean
  hint_level?: number
  active_hint?: string
  transfer_correct?: boolean
  completed_at?: string
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
