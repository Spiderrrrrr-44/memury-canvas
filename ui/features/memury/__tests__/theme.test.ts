/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 */

import {beforeEach, describe, expect, it} from 'vitest'
import {initializeTheme} from '../theme'

describe('Memury dark theme', () => {
  beforeEach(() => {
    document.documentElement.removeAttribute('data-theme')
    document.documentElement.removeAttribute('data-memury-theme')
    document.documentElement.style.colorScheme = ''
    document.body.classList.remove('memury-ui-surface')
  })

  it('always applies the product dark theme to the document', () => {
    expect(initializeTheme()).toBe('dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(document.documentElement.dataset.memuryTheme).toBe('dark')
    expect(document.documentElement.style.colorScheme).toBe('dark')
    expect(document.body).toHaveClass('memury-ui-surface')
  })
})
