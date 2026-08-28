# Cart UI and customization

`<brando-shopify-cart>` is an optional, framework-free custom element. It talks
only to the same-origin `BrandoShopify.Plug.Cart`; Storefront credentials and
Shopify's secret-bearing cart ID remain on the server.

This document describes the public browser contract in
`assets/js/cart.js` and the default styles in `assets/css/cart.css`.

## Setup

Import the JavaScript and default stylesheet through the host application's
asset entrypoints:

```js
import "../../deps/brando_shopify/assets/js/cart.js";
import "../../deps/brando_shopify/assets/css/cart.css";
```

Render Brando's CSRF component in the document head and mount the element:

```heex
<head>
  <.csrf_meta_tag />
</head>
<body>
  <button type="button" data-open-cart>Cart (<span data-cart-count>0</span>)</button>
  <brando-shopify-cart endpoint="/shopify/cart"></brando-shopify-cart>
</body>
```

```js
const cart = document.querySelector("brando-shopify-cart");

document.querySelector("[data-open-cart]").addEventListener("click", () => {
  cart.open();
});
```

The endpoint must be same-origin because the component sends the browser session
cookie and the `x-csrf-token` header. Mount the Cart Plug behind a session and
CSRF-protected JSON pipeline as shown in the main README.

## Attributes

Set behavioral attributes declaratively on the element.

| Attribute | Default | Behavior |
|---|---:|---|
| `endpoint` | `/shopify/cart` | Base URL for all cart requests; a trailing slash is removed |
| `open` | absent | Controls visibility and emits `cart:open` or `cart:close` when changed |
| `manual` | absent | When present at connection time, skips the automatic initial `refresh()` |
| `headless` | absent | Suppresses the default renderer; state, requests, and events continue normally |
| `aria-label` | `Shopping cart` | Accessible label applied to the element's `region` role |

The element reflects closed state through the standard `hidden` property. Use
`open()`, `close()`, or `toggle()` instead of manipulating `hidden` directly.

## State

`cart.state()` returns a new snapshot with this shape:

```js
{
  cart,       // sanitized Storefront cart, or null
  count,      // cart.totalQuantity, or 0
  loading,    // true while the active request is running
  error,      // Error with status and payload when a request fails, or null
  warnings,   // Storefront mutation warnings
  open        // whether the open attribute is present
}
```

The current values are also available as `cart.cart`, `cart.loading`,
`cart.error`, and `cart.warnings`. `cart.count` is a read-only convenience
getter. Browser-visible cart objects never contain the complete Shopify cart ID
or `checkoutUrl`.

## Methods

Mutation requests are queued, so rapid calls execute in the order they were
made. Request methods return promises.

| Method | Result |
|---|---|
| `open()` | Adds `open` |
| `close()` | Removes `open` |
| `toggle(force?)` | Toggles `open`, or sets it from a boolean |
| `refresh()` | Loads the session's current cart |
| `add(merchandiseId, quantity = 1, attributes = [], options = {})` | Creates a cart and adds a variant; `options.sellingPlanId` selects a selling plan |
| `update(lineId, quantity, options = {})` | Updates quantity plus optional CartLineUpdateInput fields; quantities at or below zero remove the line |
| `remove(lineId)` | Removes one cart line |
| `discounts(codes)` | Replaces discount codes; accepts one string or an array |
| `buyer(buyerIdentity)` | Replaces the Storefront buyer identity object |
| `checkout()` | Fetches a fresh checkout URL, emits `cart:checkout`, then navigates to Shopify |
| `state()` | Returns the state snapshot described above |

Examples:

```js
await cart.add("gid://shopify/ProductVariant/123", 2, [
  { key: "Engraving", value: "Brando" },
]);

await cart.update("gid://shopify/CartLine/456", 3);
await cart.add(variantId, 1, [], { sellingPlanId });
await cart.discounts(["SUMMER", "MEMBER"]);
await cart.buyer({ countryCode: "NO", email: "buyer@example.com" });
```

Line IDs come from `state.cart.lines.nodes`. They are safe public Cart Line IDs,
not the secret-bearing cart ID stored by the server.

## Events

All events bubble from the custom element.

| Event | `event.detail` | Emitted when |
|---|---|---|
| `cart:change` | `{ cart, warnings }` | A refresh or mutation succeeds |
| `cart:error` | `{ error }` | A refresh or mutation returns a non-success response |
| `cart:open` | none | `open` is added |
| `cart:close` | none | `open` is removed |
| `cart:checkout` | `{ checkoutUrl }` | A fresh checkout URL is received, immediately before navigation |

```js
cart.addEventListener("cart:change", ({ detail: { cart } }) => {
  document.querySelector("[data-cart-count]").textContent =
    cart?.totalQuantity || 0;
});

cart.addEventListener("cart:error", ({ detail: { error } }) => {
  console.error(error.message, error.status, error.payload);
});
```

## Translating the default renderer

Every string the default renderer shows comes from `element.labels`, so a
non-English shop does not need a custom renderer. Override what you need; the
rest fall back to English.

```js
cart.labels = { title: "Handlekurv", checkout: "Til kassen" }
```

Gettext runs on the server and this renderer runs in the browser, so the package
bridges the two with a JSON attribute. `BrandoShopify.Cart.Labels.to_json/0`
produces the map in the current Gettext locale:

```heex
<brando-shopify-cart
  endpoint="/shopify/cart"
  labels={BrandoShopify.Cart.Labels.to_json()}
>
</brando-shopify-cart>
```

Translations live in the `cart` domain under the package's `priv/gettext`;
Norwegian Bokmål ships with it. Set the locale for **this backend** — Brando's
`put_locale` plug only sets it for the host application's own Gettext backend:

```elixir
# single-language site
config :brando_shopify, BrandoShopify.Gettext, default_locale: "nb"
```

A multilingual host should mirror the request locale onto
`BrandoShopify.Gettext` in a plug instead.

The full key set is in `DEFAULT_LABELS`, exported from `cart.js`. One key is
absent on purpose: `defaultVariant` is not UI copy but Shopify's own name for
the single variant of an option-less product, matched so the cart can hide it.
Translating it would stop the match working.

## Styling the default renderer

The stylesheet defines these variables on `:root`:

| Variable | Default |
|---|---|
| `--brando-cart-width` | `min(32rem, 100vw)` |
| `--brando-cart-bg` | `#fff` |
| `--brando-cart-fg` | `#151515` |
| `--brando-cart-muted` | `#707070` |
| `--brando-cart-border` | `#e7e7e7` |
| `--brando-cart-accent` | `#151515` |
| `--brando-cart-accent-fg` | `#fff` |
| `--brando-cart-radius` | `0` |
| `--brando-cart-shadow` | `-1rem 0 3rem rgb(0 0 0 / 12%)` |
| `--brando-cart-gap` | `1.25rem` |

Override them globally, on a storefront wrapper, or directly on the element:

```css
brando-shopify-cart {
  --brando-cart-width: min(40rem, 100vw);
  --brando-cart-bg: var(--color-surface);
  --brando-cart-fg: var(--color-text);
  --brando-cart-accent: var(--color-action);
  --brando-cart-radius: 0.75rem;
}
```

The renderer uses light DOM rather than a shadow root. The following class names
are stable styling hooks:

```text
brando-cart__panel       brando-cart__header       brando-cart__title
brando-cart__close       brando-cart__error        brando-cart__empty
brando-cart__lines       brando-cart__line         brando-cart__image
brando-cart__details     brando-cart__product      brando-cart__variant
brando-cart__quantity    brando-cart__quantity-value
brando-cart__remove      brando-cart__line-total   brando-cart__footer
brando-cart__total       brando-cart__total-amount brando-cart__checkout
```

Structural nodes also carry `part` attributes with these values:

```text
panel header close error empty lines line quantity footer checkout
```

Because there is no shadow root, select them as light-DOM attributes rather
than with `::part()`:

```css
brando-shopify-cart [part~="line"] {
  border-block-end: 1px solid var(--color-border);
}

brando-shopify-cart [part~="checkout"] {
  min-height: 3.5rem;
}
```

## Custom renderer

Assign `renderer` to replace the default DOM while retaining the request,
session, state, queueing, and event behavior:

```js
const cart = document.querySelector("brando-shopify-cart");

cart.renderer = (element, state, actions) => {
  const panel = document.createElement("section");
  panel.className = "my-cart";
  panel.setAttribute("aria-busy", String(state.loading));

  const heading = document.createElement("h2");
  heading.textContent = `Basket (${state.count})`;

  const close = document.createElement("button");
  close.type = "button";
  close.textContent = "Close";
  close.addEventListener("click", actions.close);

  const status = document.createElement("p");
  status.textContent = state.error
    ? state.error.message
    : state.cart
      ? `${state.cart.totalQuantity} items`
      : "Your basket is empty";

  panel.append(heading, close, status);
  element.replaceChildren(panel);
};

cart.refresh();
```

The renderer is called when the element connects, before a cart request, and
after that request settles. It must therefore be idempotent. Its arguments are:

1. `element` — the `<brando-shopify-cart>` instance;
2. `state` — the snapshot returned by `element.state()`; and
3. `actions` — `update(id, quantity)`, `remove(id)`, `checkout()`, and `close()`.

Call other operations, such as `add()` or `discounts()`, directly on `element`.
Use DOM APIs or otherwise escape remote product data when producing HTML.

## Headless mode

With `headless`, the element performs requests and owns state but never creates
cart markup. This is useful for a framework-owned or otherwise external UI:

```html
<brando-shopify-cart id="cart-state" headless manual></brando-shopify-cart>
```

```js
const cart = document.querySelector("#cart-state");
const count = document.querySelector("[data-cart-count]");

cart.addEventListener("cart:change", ({ detail }) => {
  count.textContent = detail.cart?.totalQuantity || 0;
});

await cart.refresh();
```

Omit `manual` when the state owner should refresh automatically as soon as the
element connects.

## Error and checkout behavior

Non-success refresh and mutation responses reject with an `Error` whose
`message`, numeric `status`, and parsed `payload` are available to the caller
and in `cart:error`. The default renderer shows the message in an element with
`role="alert"`. A checkout failure rejects the `checkout()` promise and does
not emit `cart:checkout` or navigate away.

`checkout()` deliberately asks the server for a fresh URL only when invoked.
After emitting `cart:checkout`, it navigates the current window to Shopify.
Shopify checkout is not embedded in the Brando page.
