# Changelog

## 0.2.0-dev

- Add a store launch state — `:off`, `:preview`, `:live` — as the `:visibility`
  config key, with `BrandoShopify.visibility/1`, `BrandoShopify.live?/1` and
  `BrandoShopify.Plug.Visibility` to enforce it. A store is filled with products
  long before it opens; `:preview` lets the people doing that work see it on the
  real site while everyone else is redirected or 404'd. The key takes the same
  literal/function/MFA sources as secrets, so the state can live in a CMS and be
  flipped without a deploy. Defaults to `:live`, so existing stores are
  unaffected. Sync is deliberately not gated — the catalog stays warm while the
  store is closed.
- Fix webhook sync workers silently dropping changes. Product, collection, and
  inventory uniqueness relied on Oban's default `states`, which include
  `:completed`, so one finished sync suppressed every later change to the same
  resource for the whole period — 24 hours for products and collections. All
  three now dedupe against `:incomplete` states only, with a 30 second window,
  and the webhook handler logs debounced inserts instead of discarding them
  without trace.
- Replace the legacy REST-era scaffold with versioned Admin and Storefront
  GraphQL clients targeting Shopify `2026-07`.
- Add local base and configured country/language product projections, including
  translations, contextual prices/availability, optional selling plans, and
  per-variant allocations.
- Add normalized inventory items and location levels, inventory webhook workers,
  and explicit freshness helpers.
- Add two-phase streamed product/inventory Bulk Operation imports,
  transactional incremental sync, tombstones, and reconciliation.
- Add verified/idempotent webhook handling with Oban workers.
- Add a session-backed Cart API and optional accessible cart custom element,
  including selling-plan line selection.
- Add multi-store/runtime-secret configuration and GraphQL telemetry.
- Add a store-level injectable HTTP boundary, deterministic Brando Playwright
  integration suite, and opt-in live development-store contract.
- Normalize webhook timestamps to microsecond precision and log handler
  failures without disclosing request secrets.
- Harden the cart UI against host image styles and document the dedicated JSON
  pipeline and CSRF meta-tag requirements.
- Document architecture, Brando integration, Shopify setup, platform research,
  ownership boundaries, and upgrade strategy.
