// @ts-check
const { defineConfig, devices } = require('@playwright/test')

const port = process.env.PLAYWRIGHT_PORT || process.env.PORT || '4455'
const baseURL = `http://localhost:${port}`

module.exports = defineConfig({
  testDir: './tests',
  fullyParallel: false,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    ...devices['Desktop Chrome'],
  },
  webServer: {
    cwd: '..',
    command: `env MIX_ENV=e2e PORT=${port} mix phx.server`,
    url: `${baseURL}/test-assets/cart.js`,
    stdout: 'pipe',
    stderr: 'pipe',
    reuseExistingServer: false,
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5000 },
  },
})
