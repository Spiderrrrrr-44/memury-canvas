/*
 * Copyright (C) 2026 - present Instructure, Inc.
 */

import {vi} from 'vitest'
import doFetchApi from '@canvas/do-fetch-api-effect'
import {getState} from '../api'

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
})
