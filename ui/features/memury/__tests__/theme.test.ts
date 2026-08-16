/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 */

import {beforeEach, describe, expect, it} from 'vitest'
import {initializeTheme} from '../theme'

describe('Memury Canvas theme', () => {
  beforeEach(() => {
    document.documentElement.removeAttribute('data-theme')
    document.documentElement.removeAttribute('data-memury-theme')
    document.documentElement.style.colorScheme = ''
    document.body.classList.remove('memury-ui-surface')
  })

  it('inherits Canvas without changing the global document theme', () => {
    expect(initializeTheme()).toBe('canvas')
    expect(document.documentElement.dataset.memuryTheme).toBeUndefined()
    expect(document.body).not.toHaveClass('memury-ui-surface')
  })
})
