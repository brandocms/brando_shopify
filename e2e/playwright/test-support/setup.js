import { test as baseTest, expect } from '@playwright/test'

const port = process.env.PLAYWRIGHT_PORT || process.env.PORT || '4455'
const baseURL = `http://localhost:${port}`

export const test = baseTest.extend({
  page: async ({ browser }, use) => {
    const response = await fetch(`${baseURL}/sandbox`, { method: 'POST' })
    expect(response.ok).toBe(true)
    const userAgent = await response.text()

    const context = await browser.newContext({ baseURL, userAgent })
    const page = await context.newPage()

    try {
      await use(page)
    } finally {
      await context.close()
      await fetch(`${baseURL}/sandbox`, {
        method: 'DELETE',
        headers: { 'user-agent': userAgent },
      })
    }
  },
})

export { expect }
