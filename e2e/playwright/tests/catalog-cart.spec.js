import { createHmac } from 'node:crypto'
import { test, expect } from '../test-support/setup'

const PRODUCT_ID = 'gid://shopify/Product/1001'
const VARIANT_ID = 'gid://shopify/ProductVariant/2001'
const PRODUCT_PATH = '/shopify-e2e/products/brando-field-boot'
const WEBHOOK_SECRET = 'brando-e2e-webhook-secret'

async function resetShopify(page) {
  const response = await page.request.post('/__shopify/reset')
  expect(response.ok(), await response.text()).toBe(true)
}

async function mockState(page) {
  const response = await page.request.get('/__shopify/state')
  expect(response.ok()).toBe(true)
  return response.json()
}

async function deliverProductWebhook(
  page,
  { id, signature = 'valid', topic = 'products/update', payload = {} },
) {
  const body = JSON.stringify({ admin_graphql_api_id: PRODUCT_ID, ...payload })
  const hmac = createHmac('sha256', WEBHOOK_SECRET).update(body).digest('base64')

  return page.request.post('/shopify/webhooks', {
    data: body,
    headers: {
      'content-type': 'application/json',
      'x-shopify-api-version': '2026-07',
      'x-shopify-hmac-sha256': signature === 'valid' ? hmac : 'invalid',
      'x-shopify-shop-domain': 'brando-e2e.myshopify.com',
      'x-shopify-topic': topic,
      'x-shopify-triggered-at': '2026-07-31T10:30:00Z',
      'x-shopify-webhook-id': id,
    },
  })
}

test.describe('Brando Shopify integration', () => {
  test.skip(
    process.env.SHOPIFY_E2E_LIVE === '1',
    'The deterministic suite uses the local Shopify transport',
  )

  test.beforeEach(async ({ page }) => {
    await resetShopify(page)
  })

  test('renders the complete local projection without a Shopify request', async ({ page }) => {
    await page.goto(PRODUCT_PATH)

    await expect(page.locator('main')).toHaveAttribute('data-catalog-source', 'local')
    await expect(page.locator('main')).toHaveAttribute('data-catalog-context', 'norway')
    await expect(page.locator('[data-product-title]')).toHaveText('Brando feltstøvel')
    await expect(page.locator('[data-product-vendor]')).toHaveText('Brando Goods')
    await expect(page.locator('[data-product-sku]')).toHaveText('BRANDO-BOOT-42')
    await expect(page.locator('[data-product-inventory]')).toHaveText('12')
    await expect(page.locator('[data-selling-plan]')).toHaveText('Monthly delivery')
    await expect(page.locator('[data-product-description]')).toContainText(
      'En lokalt synkronisert markedsvisning',
    )

    expect((await mockState(page)).request_count).toBe(0)

    const mutation = await page.request.patch('/__shopify/product', {
      data: { title: 'Remote title not synchronized yet' },
    })
    expect(mutation.ok()).toBe(true)

    await page.reload()
    await expect(page.locator('[data-product-title]')).toHaveText('Brando feltstøvel')
    expect((await mockState(page)).request_count).toBe(0)
  })

  test('verifies, deduplicates, and synchronizes product webhooks', async ({ page }) => {
    await page.request.patch('/__shopify/product', {
      data: {
        title: 'Brando Field Boot — webhook edition',
        price: '1399.00',
        context_title: 'Brando feltstøvel — webhook-utgave',
        context_price: '1599.00',
      },
    })

    const rejected = await deliverProductWebhook(page, {
      id: 'webhook-invalid-signature',
      signature: 'invalid',
    })
    expect(rejected.status()).toBe(401)

    await page.goto(PRODUCT_PATH)
    await expect(page.locator('[data-product-title]')).toHaveText('Brando feltstøvel')

    const accepted = await deliverProductWebhook(page, { id: 'webhook-product-update-1' })
    expect(accepted.status(), await accepted.text()).toBe(200)
    expect(await accepted.json()).toMatchObject({ accepted: true, result: 'ok' })

    await page.reload()
    await expect(page.locator('[data-product-title]')).toHaveText(
      'Brando feltstøvel — webhook-utgave',
    )
    await expect(page.locator('[data-product-price]')).toContainText('1599.00')

    const duplicate = await deliverProductWebhook(page, { id: 'webhook-product-update-1' })
    expect(duplicate.status()).toBe(200)
    expect(await duplicate.json()).toMatchObject({ accepted: true, result: 'duplicate' })

    const state = await mockState(page)
    expect(state.requests.BrandoShopifyProduct).toBe(1)
    expect(state.requests.StorefrontProductContextById).toBe(1)
  })

  test('tombstones deleted products without calling Shopify', async ({ page }) => {
    const deleted = await deliverProductWebhook(page, {
      id: 'webhook-product-delete-1',
      topic: 'products/delete',
    })

    expect(deleted.status(), await deleted.text()).toBe(200)
    expect(await deleted.json()).toMatchObject({ accepted: true, result: 'ok' })

    const productPage = await page.goto(PRODUCT_PATH)
    expect(productPage.status()).toBe(404)
    expect((await mockState(page)).request_count).toBe(0)
  })

  test('synchronizes location inventory and contextual availability from inventory webhooks', async ({
    page,
  }) => {
    await page.goto(PRODUCT_PATH)
    await expect(page.locator('[data-product-inventory]')).toHaveText('12')

    const mutation = await page.request.patch('/__shopify/product', {
      data: { inventory: 3 },
    })
    expect(mutation.ok()).toBe(true)

    await page.reload()
    await expect(page.locator('[data-product-inventory]')).toHaveText('12')
    expect((await mockState(page)).request_count).toBe(0)

    const accepted = await deliverProductWebhook(page, {
      id: 'webhook-inventory-level-update-1',
      topic: 'inventory_levels/update',
      payload: { inventory_item_id: 4001, location_id: 5001, available: 3 },
    })

    expect(accepted.status(), await accepted.text()).toBe(200)
    expect(await accepted.json()).toMatchObject({ accepted: true, result: 'ok' })

    await page.reload()
    await expect(page.locator('[data-product-inventory]')).toHaveText('3')

    const state = await mockState(page)
    expect(state.requests.BrandoShopifyProduct).toBe(1)
    expect(state.requests.StorefrontProductContextById).toBe(1)
  })

  test('creates, restores, updates, and removes a cart without exposing its ID', async ({ page }) => {
    await page.goto(PRODUCT_PATH)
    await page.getByRole('button', { name: 'Add to cart' }).click()

    const cart = page.locator('brando-shopify-cart')
    await expect(cart).toHaveAttribute('open', '')
    await expect(cart.getByText('Brando Field Boot')).toBeVisible()
    await expect(cart.locator('.brando-cart__quantity-value')).toHaveText('1')

    await cart.getByRole('button', { name: 'Increase quantity' }).click()
    await expect(cart.locator('.brando-cart__quantity-value')).toHaveText('2')

    const publicResponse = await page.request.get('/shopify/cart')
    const publicBody = await publicResponse.text()
    const publicCart = JSON.parse(publicBody).cart

    expect(publicResponse.status()).toBe(200)
    expect(publicBody).not.toContain('gid://shopify/Cart/')
    expect(publicBody).not.toContain('never-expose-this')
    expect(publicCart.id).toBeUndefined()
    expect(publicCart.checkoutUrl).toBeUndefined()
    expect(publicCart.totalQuantity).toBe(2)

    await page.reload()
    await page.getByRole('button', { name: 'Open cart' }).click()
    await expect(cart.locator('.brando-cart__quantity-value')).toHaveText('2')

    await cart.getByRole('button', { name: 'Remove item' }).click()
    await expect(cart.getByText('Your cart is empty.')).toBeVisible()
  })

  test('hands off to a fresh checkout URL only when checkout is clicked', async ({ page }) => {
    await page.goto(PRODUCT_PATH)
    await page.getByRole('button', { name: 'Add to cart' }).click()

    await Promise.all([
      page.waitForURL('**/__shopify/checkout'),
      page.locator('brando-shopify-cart').getByRole('button', { name: 'Checkout' }).click(),
    ])

    await expect(page.getByRole('heading', { name: 'Shopify test checkout' })).toBeVisible()
    await expect(page.getByText('No payment is attempted.')).toBeVisible()
  })

  test('passes synchronized selling-plan selections through the server cart', async ({ page }) => {
    await page.goto(PRODUCT_PATH)

    await page.locator('brando-shopify-cart').evaluate(
      (cart, { variantId }) =>
        cart.add(variantId, 1, [], {
          sellingPlanId: 'gid://shopify/SellingPlan/6001',
        }),
      { variantId: VARIANT_ID },
    )

    const response = await page.request.get('/shopify/cart')
    const { cart } = await response.json()

    expect(cart.lines.nodes[0].sellingPlanAllocation.sellingPlan).toMatchObject({
      id: 'gid://shopify/SellingPlan/6001',
      name: 'Monthly delivery',
    })
  })
})
