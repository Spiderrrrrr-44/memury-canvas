/*
 * Copyright (C) 2026 - present Instructure, Inc.
 */

import {vi} from 'vitest'
import doFetchApi from '@canvas/do-fetch-api-effect'
import {continueLearningGraph, getLearningGraph, getState} from '../api'

vi.mock('@canvas/do-fetch-api-effect', () => ({default: vi.fn()}))

describe('Memury API context', () => {
  it('passes explicit Canvas context IDs to the shared state endpoint', async () => {
    vi.mocked(doFetchApi).mockResolvedValue({
      json: {phase: 'overview'},
    } as never)

    await getState({type: 'assignment', course_id: '42', assignment_id: '99'})

    expect(vi.mocked(doFetchApi)).toHaveBeenCalledWith({
      path: '/memury/state?context_type=assignment&course_id=42&assignment_id=99',
    })
  })

  it('loads a user-scoped graph for the selected Assignment', async () => {
    vi.mocked(doFetchApi).mockResolvedValue({json: {nodes: [], edges: []}} as never)

    await getLearningGraph('assignment 42')

    expect(vi.mocked(doFetchApi)).toHaveBeenCalledWith({
      path: '/memury/learning_graph?assignment_id=assignment%2042',
    })
  })

  it('creates a persistent branch through the graph command endpoint', async () => {
    vi.mocked(doFetchApi).mockResolvedValue({json: {nodes: [], edges: []}} as never)

    await continueLearningGraph({
      assignmentId: '42',
      parentNodeId: 'step-9',
      question: 'Why does this relationship hold?',
      requestId: 'request-1234',
    })

    expect(vi.mocked(doFetchApi)).toHaveBeenCalledWith({
      path: '/memury/learning_graph/branches',
      method: 'POST',
      body: {
        assignment_id: '42',
        parent_node_id: 'step-9',
        question: 'Why does this relationship hold?',
        request_id: 'request-1234',
      },
    })
  })
})
