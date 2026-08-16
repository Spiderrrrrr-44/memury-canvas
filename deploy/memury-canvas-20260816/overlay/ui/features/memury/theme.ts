/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 */

export type MemuryTheme = 'canvas'

export function applyTheme(): MemuryTheme {
  if (typeof document !== 'undefined') {
    document.documentElement.removeAttribute('data-memury-theme')
    document.body?.classList.remove('memury-ui-surface')
  }
  return 'canvas'
}

export function initializeTheme(): MemuryTheme {
  return applyTheme()
}

initializeTheme()
