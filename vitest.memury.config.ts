import {defineConfig} from 'vitest/config'
import {resolve} from 'path'

export default defineConfig({
  resolve: {
    alias: {
      '@canvas/do-fetch-api-effect': resolve(
        __dirname,
        'ui/features/memury/__tests__/do_fetch_api_stub.ts',
      ),
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: resolve(__dirname, 'ui/features/memury/__tests__/setup.ts'),
    restoreMocks: true,
  },
})
