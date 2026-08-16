/* Copyright (C) 2026 - present Instructure, Inc. AGPLv3 */
import {afterEach, describe, expect, it} from 'vitest'
import {canvasPreferredLocale, normalizeMemuryLocale} from '../locale'

describe('Memury locale preference', () => {
  afterEach(() => {
    delete (window as Window & {ENV?: {LOCALE?: string}}).ENV
    document.documentElement.lang = ''
  })

  it('prefers the Canvas user locale over the browser locale', () => {
    ;(window as Window & {ENV?: {LOCALE?: string}}).ENV = {LOCALE: 'zh-Hans'}
    document.documentElement.lang = 'en'
    expect(canvasPreferredLocale()).toBe('zh-CN')
  })

  it('uses English for Canvas English and unsupported locales', () => {
    expect(normalizeMemuryLocale('en-AU')).toBe('en')
    expect(normalizeMemuryLocale('fr-FR')).toBe('en')
  })
})
