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

import doFetchApi from '@canvas/do-fetch-api-effect'
import type {LearningGraphState, MemuryContext, MemuryState} from './types'

export async function getState(context?: MemuryContext): Promise<MemuryState> {
  const query = context
    ? Object.entries(context)
        .filter(([, value]) => value)
        .map(([key, value]) =>
          `${encodeURIComponent(key === 'type' ? 'context_type' : key)}=${encodeURIComponent(value)}`,
        )
        .join('&')
    : ''
  const {json} = await doFetchApi<MemuryState>({
    path: query ? `/memury/state?${query}` : '/memury/state',
  })
  if (!json) throw new Error('Memury returned no state')
  return json
}

export async function syncState(): Promise<MemuryState> {
  const {json} = await doFetchApi<MemuryState>({path: '/memury/sync', method: 'POST'})
  if (!json) throw new Error('Memury sync returned no state')
  return json
}

export async function resetState(): Promise<MemuryState> {
  const {json} = await doFetchApi<MemuryState>({path: '/memury/reset', method: 'POST'})
  if (!json) throw new Error('Memury reset returned no state')
  return json
}

export async function sendAction(body: Record<string, unknown>): Promise<MemuryState> {
  const {json} = await doFetchApi<MemuryState>({path: '/memury/action', method: 'PATCH', body})
  if (!json) throw new Error('Memury action returned no state')
  return json
}

export async function getLearningGraph(assignmentId: string): Promise<LearningGraphState> {
  const {json} = await doFetchApi<LearningGraphState>({
    path: `/memury/learning_graph?assignment_id=${encodeURIComponent(assignmentId)}`,
  })
  if (!json) throw new Error('Memury returned no learning graph')
  return json
}

export async function continueLearningGraph({
  assignmentId,
  parentNodeId,
  question,
  requestId,
  documentTitle,
  documentExcerpt,
  locale,
}: {
  assignmentId: string
  parentNodeId: string
  question: string
  requestId: string
  documentTitle?: string
  documentExcerpt?: string
  locale?: string
}): Promise<LearningGraphState> {
  const {json} = await doFetchApi<LearningGraphState>({
    path: '/memury/learning_graph/branches',
    method: 'POST',
    body: {
      assignment_id: assignmentId,
      parent_node_id: parentNodeId,
      question,
      request_id: requestId,
      document_title: documentTitle,
      document_excerpt: documentExcerpt,
      locale,
    },
  })
  if (!json) throw new Error('Memury returned no updated learning graph')
  return json
}

export async function selectLearningGraphNode({
  assignmentId,
  nodeId,
}: {
  assignmentId: string
  nodeId: string
}): Promise<LearningGraphState> {
  const {json} = await doFetchApi<LearningGraphState>({
    path: '/memury/learning_graph/current',
    method: 'PATCH',
    body: {
      assignment_id: assignmentId,
      node_id: nodeId,
    },
  })
  if (!json) throw new Error('Memury returned no selected learning node')
  return json
}
