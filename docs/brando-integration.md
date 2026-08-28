# Brando integration

## Keep ownership explicit

Shopify owns commerce data. Brando owns presentation and editorial content.
Avoid adding editor controls that mutate synchronized columns because the next
webhook will replace them.

A typical project Blueprint relates its editorial overlay to the local product:

```elixir
defmodule MyApp.Shop.ProductPage do
  use Brando.Blueprint,
    application: "Shop",
    domain: "Product pages",
    schema: "product_pages",
    singular: "product page",
    plural: "product pages"

  # Add the project's normal attributes/blocks, then relate the row to
  # BrandoShopify.Catalog.Product through product_id.
end
```

The exact relation declaration depends on the Brando version and project
conventions. The important contract is that the foreign key targets the local
`shopify_products.id`, while Shopify's GID remains the durable remote identity.

## Controller or LiveView

Load once while preparing the page:

```elixir
def show(conn, %{"handle" => handle}) do
  product =
    BrandoShopify.Catalog.get_product_by_handle(handle,
      preload: [:variants, :collections]
    )

  render(conn, :show, product: product)
end
```

Every field rendered afterward is local. There is no hidden Storefront request.
For a configured country/language view, query its local projection instead:

```elixir
BrandoShopify.Catalog.get_contextual_product_by_handle(handle, :norway,
  preload: [variants: [inventory_item: :levels], collections: []]
)
```

This is still Ecto-only. It returns `nil` when the exact context is unavailable
instead of falling back to a potentially wrong price or publication state.
Direct `Storefront` helpers are reserved for deliberately live, buyer-specific
work outside ordinary template rendering.

## Product references in blocks

Store a stable reference rather than copying the full product into block data:

```elixir
reference = BrandoShopify.Catalog.reference(product)

# %{
#   "type" => "shopify_product",
#   "id" => "gid://shopify/Product/...",
#   "handle" => "...",
#   "title" => "...",
#   "image" => "..."
# }
```

At render time, batch the reference IDs and query the local table. The title and
image in the reference are useful editor previews, while the ID resolves the
fresh synchronized row. A deleted product remains tombstoned, allowing the
editor to show a clear “no longer available” state instead of losing the
reference.

## Product picker

`Catalog.list_products/1` is intended as the base for a Brando datasource or
picker:

```elixir
BrandoShopify.Catalog.list_products(
  search: search_term,
  limit: 50,
  preload: [:variants]
)
```

It searches title, handle, and vendor locally. Projects can layer tags,
collection filters, pagination, or their normal Brando selection component on
top without involving Shopify while an editor types.

## Caching

The database projection is already a resilient cache with explicit freshness
timestamps. Page/cache keys can include `product.remote_updated_at` or
`product.synced_at`. Webhook workers can broadcast or invalidate project caches
after `Sync.Persister` completes if the host application needs immediate static
page regeneration.

Do not cache the full Shopify cart ID, checkout URL, or customer-specific live
Storefront response in public page caches.

## Variant add-to-cart

Render the local variant GID:

```heex
<button
  type="button"
  phx-hook="AddShopifyVariant"
  data-variant-id={@variant.shopify_id}
>
  Add to cart
</button>
```

The hook can call:

```js
document
  .querySelector("brando-shopify-cart")
  .add(el.dataset.variantId, 1)
  .then(() => document.querySelector("brando-shopify-cart").open());
```

Shopify validates availability and calculates the actual contextual price when
the line is added. A stale local inventory snapshot can therefore affect
presentation but cannot bypass Shopify's commerce rules.


## Storefront components

`BrandoShopify.Components.Catalog` renders the synced catalogue. Every component
works with no slots at all, and every part of it is replaceable without giving up
the rest.

```elixir
import BrandoShopify.Components.Catalog
```

```heex
<.product_grid products={@products} href={&~p"/shop/#{&1.handle}"} />
```

### Slots receive presented data

This is the point of them. A slot that took the raw `%Product{}` would push the
same JSON-shaped work — digging through `featured_media`, matching
`selected_options`, formatting Decimals — into every template that overrides
anything. So slots get derived values instead:

```heex
<.product_card product={@product} href={@href}>
  <:badge :let={p}><span :if={p.sold_out?}>Utsolgt</span></:badge>
  <:info :let={p}>{p.price.formatted} — {p.product.title}</:info>
</.product_card>
```

`%{product:, href:, image:, price:, sold_out?:, on_sale?:, option_groups:}`.

The same values are available on their own through
`BrandoShopify.Catalog.Present`, for a renderer that wants none of this markup.

### Components

| Component | Slots |
|---|---|
| `product_grid/1` | `:card` (whole card), `:empty` |
| `product_card/1` | `:media`, `:badge`, `:info`, `:footer` |
| `product_image/1` | `:empty` |
| `price/1` | — |
| `variant_picker/1` | `:option` (one option group) |

`product_grid` deliberately does **not** forward slots to `product_card`. Want a
badge on cards in a grid? Use `:card` and render `<.product_card>` yourself. It
is a line more, and it keeps the grid from having to know the card's shape.

### Routes and money stay yours

The package cannot know your URLs, so `href` takes a string or a function of the
product. Without one, cards render as `<article>` rather than as links with
nowhere to go.

Prices format per currency by default. Override per call with `format`, or once:

```elixir
config :brando_shopify, :money_formatter, {MyApp.Money, :format, []}
```

### Several options

A product with Size *and* Colour has combinations, not values, and which
combination is selected is only known in the browser. `variant_picker/1`
therefore renders the controls **and** the full variant table on
`data-variants`:

```js
const variants = JSON.parse(el.dataset.variants)
const match = variants.find(v => names.every(n => v.options[n] === selection[n]))
```

`available?` on an option value means it appears in at least one purchasable
variant — not that it is purchasable given the other selections. The server
cannot know that, and claiming otherwise would put a lie in the API.
