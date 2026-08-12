/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */
import {describe, expect, it} from 'vitest'
import {currentRoute} from '../product_app'

describe('Memury product routes', () => {
  it('restores three distinct product pages from directly visited URLs', () => {
    expect(currentRoute('/memury/learn/assignment-42')).toEqual({
      name: 'learn',
      assignmentId: 'assignment-42',
    })
    expect(currentRoute('/memury/risks')).toEqual({name: 'risks'})
    expect(currentRoute('/memury/plan')).toEqual({name: 'plan'})
  })

  it('keeps Learning Memory separate from the three primary routes', () => {
    expect(currentRoute('/memury/memory')).toEqual({name: 'memory'})
    expect(currentRoute('/memury')).toEqual({name: 'home'})
  })
})
