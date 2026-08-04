export interface Provenance {
  source_platform: string
  source_object_id: string
  source_url?: string | null
  last_synced_at: string
  official_or_inferred: 'Official' | 'Inferred' | 'User override'
  confidence: number
}

export interface Assignment extends Provenance {
  id: string
  course_name: string
  title: string
  due_at: string
  risk: number
}

export interface StudyBlock extends Provenance {
  id: string
  title: string
  starts_at: string
  duration_minutes: number
  status: string
  course_name: string
  concept: string
}

export interface MemuryState {
  demo_mode: boolean
  phase: 'overview' | 'verify' | 'intervention' | 'complete'
  last_synced_at: string
  assignments: Assignment[]
  study_blocks: StudyBlock[]
  sis_events?: Array<Record<string, unknown>>
  concept: {name: string; mastery: number; previous_mastery?: number; reason?: string; confidence: number; misconception: string}
  evidence: Array<{title: string; source: string; observed_at: string}>
  decision_logs: Array<{at: string; reason: string; change: string}>
  hypotheses?: Array<{name: string; confidence: number}>
  verified_hypothesis?: string
  hint_level?: number
  next_action: {title: string; course: string; priority: number; why: string}
}
