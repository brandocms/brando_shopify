import { test, expect } from '../test-support/setup'

test.describe('Brando Shopify live development-store contract', () => {
  test.skip(
    process.env.SHOPIFY_E2E_LIVE !== '1',
    'Set SHOPIFY_E2E_LIVE=1 and development-store credentials to run this contract',
  )

  test('syncs through Admin GraphQL and creates a cart through Storefront GraphQL', async ({
    page,
  }) => {
    const syncResponse = await page.request.post('/__shopify/live/sync')
    expect(syncResponse.ok(), await syncResponse.text()).toBe(true)
    const { product } = await syncResponse.json()

    await page.goto(`/shopify-e2e/products/${product.handle}`)
    await expect(page.locator('[data-product-title]')).toHaveText(product.title)

    const addButton = page.getByRole('button', { name: 'Add to cart' })
    await expect(addButton).toHaveAttribute('data-merchandise-id', /ProductVariant/)
    await addButton.click()

    const cart = page.locator('brando-shopify-cart')
    await expect(cart.locator('.brando-cart__quantity-value')).toHaveText('1')

    const csrf = await page.locator('meta[name="csrf-token"]').getAttribute('content')
    const checkoutResponse = await page.request.post('/shopify/cart/checkout', {
      headers: { 'x-csrf-token': csrf },
    })
    expect(checkoutResponse.ok(), await checkoutResponse.text()).toBe(true)

    const { checkoutUrl } = await checkoutResponse.json()
    expect(new URL(checkoutUrl).protocol).toBe('https:')
  })
})
