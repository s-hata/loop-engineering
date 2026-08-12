import { fileURLToPath } from 'node:url'

import type { ConfigOptions } from '@nuxt/test-utils/playwright'
import { defineConfig, devices } from '@playwright/test'

export default defineConfig<ConfigOptions>({
  testDir: './tests/e2e',
  fullyParallel: true,
  reporter: 'list',
  use: {
    trace: 'on-first-retry',
    nuxt: {
      rootDir: fileURLToPath(new URL('.', import.meta.url)),
    },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
})
