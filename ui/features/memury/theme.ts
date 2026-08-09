/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 */

export type MemuryTheme = 'dark'

export function applyTheme(): MemuryTheme {
  if (typeof document === 'undefined') return 'dark'
  const root = document.documentElement
  root.dataset.theme = 'dark'
  root.dataset.memuryTheme = 'dark'
  root.style.colorScheme = 'dark'
  document.body?.classList.add('memury-ui-surface')
  return 'dark'
}

export function initializeTheme(): MemuryTheme {
  return applyTheme()
}

initializeTheme()
